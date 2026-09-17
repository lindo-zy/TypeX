#import "DXAIEngine.h"
#import "common.h"
#import "DXShared.h"

// SSE 流式客户端。所有引擎统一 OpenAI 兼容协议：
//   请求  POST {endpoint}/chat/completions  {model, messages, stream}
//   流式  data: {choices:[{delta:{content}}]} 行，data: [DONE] 结束
//   非流式 响应体 {choices:[{message:{content}}]}
// Gemini 走其 OpenAI 兼容端点，协议同上。
@interface DXAIStreamSink : NSObject <NSURLSessionDataDelegate>
@property (nonatomic, copy) void (^onDelta)(NSString *piece);
@property (nonatomic, copy) void (^onFinish)(NSString *fullText, NSError *error);
@property (nonatomic, assign) BOOL wantsStream;
@property (nonatomic, strong) NSMutableData *lineBuffer;   // SSE 跨 chunk 行缓冲
@property (nonatomic, strong) NSMutableData *rawBody;      // 非流式响应 / 错误体
@property (nonatomic, strong) NSMutableString *fullText;
@property (nonatomic, assign) NSInteger httpStatus;
@property (nonatomic, assign) BOOL streamBroken;           // 流中途出现 [DONE]/错误
@property (nonatomic, strong) NSURLSession *session;
@property (nonatomic, strong) NSURLSessionDataTask *task;
- (void)consumeData:(NSData *)data;
- (void)finishWithError:(NSError *)error;
@end

@implementation DXAIEngineInfo
@end

@implementation DXAIStreamSink

- (instancetype)init {
    if ((self = [super init])) {
        self.lineBuffer = [NSMutableData data];
        self.rawBody = [NSMutableData data];
        self.fullText = [NSMutableString string];
    }
    return self;
}

- (void)appendText:(NSString *)piece {
    if (piece.length == 0) return;
    [self.fullText appendString:piece];
    if (self.onDelta) self.onDelta(piece);
}

// 解析一条 SSE data 载荷；返回 YES 表示会话应结束（[DONE] 或已报错）。
- (BOOL)consumeSSEPayload:(NSString *)payload {
    NSString *trimmed = [payload stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (trimmed.length == 0) return NO;
    if ([trimmed isEqualToString:@"[DONE]"]) return YES;

    NSData *json = [trimmed dataUsingEncoding:NSUTF8StringEncoding];
    id object = json ? [NSJSONSerialization JSONObjectWithData:json options:0 error:nil] : nil;
    if (![object isKindOfClass:[NSDictionary class]]) return NO;

    // HTTP 层成功但业务报错（部分端点在流里吐 {"error":...}）。
    NSDictionary *errorBody = [object[@"error"] isKindOfClass:[NSDictionary class]] ? object[@"error"] : nil;
    if (errorBody) {
        NSString *message = [errorBody[@"message"] isKindOfClass:[NSString class]] ? errorBody[@"message"] : @"server error";
        if (!self.streamBroken) {
            self.streamBroken = YES;
            [self finishWithError:[NSError errorWithDomain:@"DXAIChat" code:-3
                                                  userInfo:@{NSLocalizedDescriptionKey: message}]];
        }
        return YES;
    }

    NSArray *choices = [object[@"choices"] isKindOfClass:[NSArray class]] ? object[@"choices"] : nil;
    NSDictionary *first = [choices.firstObject isKindOfClass:[NSDictionary class]] ? choices.firstObject : nil;
    NSDictionary *delta = [first[@"delta"] isKindOfClass:[NSDictionary class]] ? first[@"delta"] : nil;
    id piece = delta[@"content"] ?: first[@"text"]; // text: 老 completions 形态兜底
    if ([piece isKindOfClass:[NSString class]]) [self appendText:piece];
    return NO;
}

- (void)consumeData:(NSData *)data {
    if (!data.length) return;
    if (self.wantsStream && self.httpStatus >= 200 && self.httpStatus < 300 && !self.streamBroken) {
        [self.lineBuffer appendData:data];
        // SSE 事件以单个 \n 分行；缓冲区尾可能留半行，只消费完整行。
        static NSData *newline;
        static dispatch_once_t onceToken;
        dispatch_once(&onceToken, ^{ newline = [@"\n" dataUsingEncoding:NSUTF8StringEncoding]; });
        NSRange range;
        while ((range = [self.lineBuffer rangeOfData:newline options:0 range:NSMakeRange(0, self.lineBuffer.length)]).location != NSNotFound) {
            NSData *lineData = [self.lineBuffer subdataWithRange:NSMakeRange(0, range.location)];
            [self.lineBuffer replaceBytesInRange:NSMakeRange(0, range.location + newline.length) withBytes:"" length:0];
            NSString *line = [[NSString alloc] initWithData:lineData encoding:NSUTF8StringEncoding];
            if (!line) continue;
            line = [line stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
            if (line.length == 0 || [line hasPrefix:@":"]) continue;         // 注释/心跳
            if ([line hasPrefix:@"data:"]) {
                if ([self consumeSSEPayload:[line substringFromIndex:5]]) return;
            }
        }
        return;
    }
    [self.rawBody appendData:data];
}

- (void)finishWithError:(NSError *)error {
    if (self.onFinish) {
        void (^onFinish)(NSString *, NSError *) = self.onFinish;
        self.onFinish = nil; // 恰好一次
        onFinish(self.fullText, error);
    }
}

// 响应体终判：流式已产出内容则成功收尾；否则解析非流式 JSON 或错误体。
- (void)finalizeAfterStatus {
    if (self.httpStatus < 200 || self.httpStatus >= 300) {
        NSString *body = [[NSString alloc] initWithData:self.rawBody encoding:NSUTF8StringEncoding];
        NSString *message = nil;
        id object = body ? [NSJSONSerialization JSONObjectWithData:[body dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil] : nil;
        if ([object isKindOfClass:[NSDictionary class]]) {
            id err = object[@"error"];
            if ([err isKindOfClass:[NSString class]]) message = err;
            else if ([err isKindOfClass:[NSDictionary class]] && [err[@"message"] isKindOfClass:[NSString class]]) message = err[@"message"];
        }
        if (message.length == 0) message = [body length] > 0 ? [body substringToIndex:MIN(200, body.length)] : [NSString stringWithFormat:@"HTTP %ld", (long)self.httpStatus];
        [self finishWithError:[NSError errorWithDomain:@"DXAIChat" code:self.httpStatus
                                              userInfo:@{NSLocalizedDescriptionKey: message}]];
        return;
    }
    if (self.fullText.length > 0) {
        [self finishWithError:nil];
        return;
    }
    // 非流式：整包解析 message.content。
    id object = [NSJSONSerialization JSONObjectWithData:self.rawBody options:0 error:nil];
    if ([object isKindOfClass:[NSDictionary class]]) {
        NSArray *choices = [object[@"choices"] isKindOfClass:[NSArray class]] ? object[@"choices"] : nil;
        NSDictionary *first = [choices.firstObject isKindOfClass:[NSDictionary class]] ? choices.firstObject : nil;
        NSDictionary *message = [first[@"message"] isKindOfClass:[NSDictionary class]] ? first[@"message"] : nil;
        id content = message[@"content"] ?: first[@"text"];
        if ([content isKindOfClass:[NSString class]]) [self appendText:content];
    }
    if (self.fullText.length == 0) {
        [self finishWithError:[NSError errorWithDomain:@"DXAIChat" code:-2
                                              userInfo:@{NSLocalizedDescriptionKey: @"empty response"}]];
        return;
    }
    [self finishWithError:nil];
}

- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)dataTask
    didReceiveResponse:(NSURLResponse *)response
     completionHandler:(void (^)(NSURLSessionResponseDisposition))completionHandler {
    self.httpStatus = [(NSHTTPURLResponse *)response statusCode];
    completionHandler(NSURLSessionResponseAllow);
}

- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)dataTask
        didReceiveData:(NSData *)data {
    [self consumeData:data];
}

- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task
    didCompleteWithError:(NSError *)error {
    if (error && error.code != NSURLErrorCancelled) {
        [self finishWithError:error];
        return;
    }
    [self finalizeAfterStatus];
}

@end

@interface DXAIChatRequest ()
@property (nonatomic, strong) DXAIStreamSink *sink;
@end

@implementation DXAIChatRequest
- (void)cancel {
    [self.sink.task cancel];
    // 立即收尾：didCompleteWithError 仍会到，但 finish 恰好一次的守卫保证
    // onDone 只被调用一次（cancel 的错误码 -999）。
    [self.sink finishWithError:[NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorCancelled userInfo:nil]];
}
@end

@implementation DXAIEngine

#pragma mark - 引擎预设

+ (NSArray<DXAIEngineInfo *> *)allEngines {
    static NSArray *engines;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        engines = @[[self engineWithID:@"qwen" name:@"通义千问"
                              baseURL:@"https://dashscope.aliyuncs.com/compatible-mode/v1"
                              models:@"qwen3.8-flash, qwen3-vl-flash"
                             keysURL:@"https://bailian.console.aliyun.com/?apiKey=1#/api-key"],
                    [self engineWithID:@"deepseek" name:@"DeepSeek"
                              baseURL:@"https://api.deepseek.com/v1"
                              models:@"deepseek-chat, deepseek-reasoner"
                             keysURL:@"https://platform.deepseek.com/api_keys"],
                    [self engineWithID:@"openai" name:@"OpenAI"
                              baseURL:@"https://api.openai.com/v1"
                              models:@"gpt-4o-mini, gpt-4o"
                             keysURL:@"https://platform.openai.com/api-keys"],
                    [self engineWithID:@"siliconflow" name:@"硅基流动"
                              baseURL:@"https://api.siliconflow.cn/v1"
                              models:@"deepseek-ai/DeepSeek-V3, Qwen/Qwen2.5-7B-Instruct"
                             keysURL:@"https://cloud.siliconflow.cn/account/ak"],
                    [self engineWithID:@"doubao" name:@"豆包"
                              baseURL:@"https://ark.cn-beijing.volces.com/api/v3"
                              models:@""
                             keysURL:@"https://console.volcengine.com/ark/region:ark-cn-beijing/apiKey"],
                    [self engineWithID:@"zhipu" name:@"智谱"
                              baseURL:@"https://open.bigmodel.cn/api/paas/v4"
                              models:@"glm-4-flash, glm-4-plus"
                             keysURL:@"https://open.bigmodel.cn/usercenter/apikeys"],
                    [self engineWithID:@"gemini" name:@"Gemini"
                              baseURL:@"https://generativelanguage.googleapis.com/v1beta/openai"
                              models:@"gemini-2.0-flash, gemini-1.5-flash"
                             keysURL:@"https://aistudio.google.com/apikey"],
                    [self engineWithID:@"custom" name:@"自定义"
                              baseURL:@""
                              models:@""
                             keysURL:@""]];
    });
    return engines;
}

+ (DXAIEngineInfo *)engineWithID:(NSString *)identifier name:(NSString *)name
                         baseURL:(NSString *)baseURL models:(NSString *)models keysURL:(NSString *)keysURL {
    DXAIEngineInfo *engine = [[DXAIEngineInfo alloc] init];
    engine.identifier = identifier;
    engine.displayName = name;
    engine.baseURL = baseURL;
    engine.defaultModels = models;
    engine.keysURL = keysURL;
    return engine;
}

+ (DXAIEngineInfo *)engineForIdentifier:(NSString *)identifier {
    for (DXAIEngineInfo *engine in [self allEngines]) {
        if ([engine.identifier isEqualToString:identifier]) return engine;
    }
    return [self allEngines].firstObject;
}

+ (DXAIEngineInfo *)currentEngine {
    // 面板打开在键盘进程，偏好快照可能刚被 Settings 改过而 Darwin 通知尚未
    // 派发；打开路径先 reload 一次再读。
    [[DXPrefsManager sharedInstance] reload];
    NSString *identifier = [DXPrefsManager sharedInstance].prefs[DXAIPrefEngine];
    if (![identifier isKindOfClass:[NSString class]]) identifier = @"qwen";
    return [self engineForIdentifier:identifier];
}

+ (NSString *)prefStringForKey:(NSString *)key {
    id value = [DXPrefsManager sharedInstance].prefs[key];
    return [value isKindOfClass:[NSString class]] ? value : nil;
}

#pragma mark - 配置读取

+ (NSString *)apiKeyForEngine:(DXAIEngineInfo *)engine {
    return [self prefStringForKey:[DXAIPrefKeyPrefix stringByAppendingString:engine.identifier]] ?: @"";
}

+ (NSString *)endpointForEngine:(DXAIEngineInfo *)engine {
    if ([engine.identifier isEqualToString:@"custom"]) {
        NSString *endpoint = [self prefStringForKey:DXAIPrefCustomEndpoint] ?: @"";
        endpoint = [endpoint stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        while ([endpoint hasSuffix:@"/"]) endpoint = [endpoint substringToIndex:endpoint.length - 1];
        return endpoint;
    }
    return engine.baseURL;
}

+ (NSArray<NSString *> *)modelsForEngine:(DXAIEngineInfo *)engine {
    NSString *stored = [self prefStringForKey:[DXAIPrefModelsPrefix stringByAppendingString:engine.identifier]];
    if (stored.length == 0) stored = engine.defaultModels;
    NSMutableArray *models = [NSMutableArray array];
    for (NSString *piece in [stored componentsSeparatedByString:@","]) {
        NSString *model = [piece stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (model.length > 0) [models addObject:model];
    }
    return models;
}

+ (NSString *)selectedModelForEngine:(DXAIEngineInfo *)engine {
    NSString *selected = [self prefStringForKey:[DXAIPrefSelectedPrefix stringByAppendingString:engine.identifier]];
    if (selected.length > 0 && [[self modelsForEngine:engine] containsObject:selected]) return selected;
    return [self modelsForEngine:engine].firstObject ?: @"";
}

+ (void)setSelectedModelForEngine:(DXAIEngineInfo *)engine model:(NSString *)model {
    [[DXPrefsManager sharedInstance] setValue:model
                                       forKey:[DXAIPrefSelectedPrefix stringByAppendingString:engine.identifier]];
}

#pragma mark - 面板行为偏好

+ (BOOL)streamEnabled {
    id value = [DXPrefsManager sharedInstance].prefs[DXAIPrefStream];
    return [value isKindOfClass:[NSNumber class]] ? [value boolValue] : YES;
}

+ (NSString *)personaPrompt {
    return [self prefStringForKey:DXAIPrefPersona] ?: @"";
}

+ (NSInteger)themeStyle {
    id value = [DXPrefsManager sharedInstance].prefs[DXAIPrefTheme];
    return [value isKindOfClass:[NSNumber class]] ? [value integerValue] : 0;
}

+ (BOOL)ballEnabled {
    id value = [DXPrefsManager sharedInstance].prefs[DXAIPrefBall];
    return [value isKindOfClass:[NSNumber class]] ? [value boolValue] : NO;
}

+ (BOOL)ballHalfHide {
    id value = [DXPrefsManager sharedInstance].prefs[DXAIPrefBallHalf];
    return [value isKindOfClass:[NSNumber class]] ? [value boolValue] : YES;
}

+ (NSString *)ballStoredPosition {
    return [self prefStringForKey:DXAIPrefBallPos];
}

+ (void)setBallStoredPosition:(NSString *)position {
    [[DXPrefsManager sharedInstance] setValue:position forKey:DXAIPrefBallPos];
}

#pragma mark - 请求

+ (NSURLSession *)ephemeralSession {
    NSURLSessionConfiguration *configuration = [NSURLSessionConfiguration ephemeralSessionConfiguration];
    configuration.timeoutIntervalForRequest = 90.0;
    configuration.timeoutIntervalForResource = 300.0;
    configuration.URLCache = nil;
    return [NSURLSession sessionWithConfiguration:configuration];
}

+ (DXAIChatRequest *)sendChatWithMessages:(NSArray<NSDictionary *> *)messages
                      engine:(DXAIEngineInfo *)engine
                       onDelta:(void (^)(NSString *piece))onDelta
                      onDone:(void (^)(NSString *fullText, NSError *error))onDone {
    NSString *endpoint = [self endpointForEngine:engine];
    NSString *apiKey = [self apiKeyForEngine:engine];
    NSString *model = [self selectedModelForEngine:engine];
    if (endpoint.length == 0 || model.length == 0) {
        onDone(@"", [NSError errorWithDomain:@"DXAIChat" code:-10
                                    userInfo:@{NSLocalizedDescriptionKey: @"engine endpoint or model missing"}]);
        return nil;
    }

    BOOL stream = [self streamEnabled];
    NSDictionary *payload = @{@"model": model,
                              @"messages": messages ?: @[],
                              @"stream": @(stream)};

    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:[endpoint stringByAppendingString:@"/chat/completions"]]];
    request.HTTPMethod = @"POST";
    [request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    if (apiKey.length > 0) [request setValue:[NSString stringWithFormat:@"Bearer %@", apiKey] forHTTPHeaderField:@"Authorization"];
    request.HTTPBody = [NSJSONSerialization dataWithJSONObject:payload options:0 error:nil];

    DXAIStreamSink *sink = [[DXAIStreamSink alloc] init];
    sink.wantsStream = stream;
    __weak DXAIStreamSink *weakSink = sink;
    sink.onDelta = onDelta;
    sink.onFinish = ^(NSString *fullText, NSError *error) {
        onDone(fullText ?: @"", error);
        // NSURLSession 强持有 delegate 直到 invalidate；显式断开避免每次
        // 对话泄漏一条会话。
        [weakSink.session finishTasksAndInvalidate];
    };
    sink.session = [self ephemeralSession];
    NSURLSessionDataTask *task = [sink.session dataTaskWithRequest:request];
    sink.task = task;
    [task resume];

    DXAIChatRequest *chatRequest = [[DXAIChatRequest alloc] init];
    chatRequest.sink = sink;
    return chatRequest;
}

+ (void)fetchModelsForEngine:(DXAIEngineInfo *)engine
                  completion:(void (^)(NSArray<NSString *> *models, NSError *error))completion {
    NSString *endpoint = [self endpointForEngine:engine];
    if (endpoint.length == 0) {
        completion(@[], [NSError errorWithDomain:@"DXAIChat" code:-10
                                        userInfo:@{NSLocalizedDescriptionKey: @"endpoint missing"}]);
        return;
    }
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:[endpoint stringByAppendingString:@"/models"]]];
    request.HTTPMethod = @"GET";
    request.timeoutInterval = 30.0;
    NSString *apiKey = [self apiKeyForEngine:engine];
    if (apiKey.length > 0) [request setValue:[NSString stringWithFormat:@"Bearer %@", apiKey] forHTTPHeaderField:@"Authorization"];

    [[self ephemeralSession] dataTaskWithRequest:request
                               completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        NSString *body = data ? [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] : nil;
        NSInteger status = [(NSHTTPURLResponse *)response statusCode];
        if (error || status < 200 || status >= 300) {
            NSString *message = [NSString stringWithFormat:@"HTTP %ld%@", (long)status, body.length > 0 ? [NSString stringWithFormat:@" %@", [body substringToIndex:MIN(200, body.length)]] : @""];
            dispatch_async(dispatch_get_main_queue(), ^{
                completion(@[], error ?: [NSError errorWithDomain:@"DXAIChat" code:status userInfo:@{NSLocalizedDescriptionKey: message}]);
            });
            return;
        }
        id object = body ? [NSJSONSerialization JSONObjectWithData:[body dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil] : nil;
        NSArray *items = nil;
        if ([object isKindOfClass:[NSDictionary class]] && [object[@"data"] isKindOfClass:[NSArray class]]) {
            items = object[@"data"]; // OpenAI 形态 {"data":[{"id":...}]}
        } else if ([object isKindOfClass:[NSArray class]]) {
            items = object; // 兼容直接返回 [{"id":...}] 的端点
        }
        NSMutableArray<NSString *> *models = [NSMutableArray array];
        for (id entry in items) {
            NSString *identifier = nil;
            if ([entry isKindOfClass:[NSString class]]) identifier = entry;
            else if ([entry isKindOfClass:[NSDictionary class]] && [entry[@"id"] isKindOfClass:[NSString class]]) identifier = entry[@"id"];
            if (identifier.length > 0) [models addObject:identifier];
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            completion(models, nil);
        });
    }];
}

@end
