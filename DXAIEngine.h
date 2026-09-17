#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

// AI 问答偏好键（com.lindo.typex 域）。Settings 端写入权威域+共享快照，键盘
// 进程面板经 DXPrefsManager 快照读取。带引擎后缀的键按引擎标识拼接。
#define DXAIPrefEngine           @"aiEngine"
#define DXAIPrefKeyPrefix        @"aiKey_"
#define DXAIPrefModelsPrefix     @"aiModels_"
#define DXAIPrefSelectedPrefix   @"aiSelectedModel_"
#define DXAIPrefCustomEndpoint   @"aiCustomEndpoint"
#define DXAIPrefCustomName       @"aiCustomName"
#define DXAIPrefPersona          @"aiPersona"
#define DXAIPrefStream           @"aiStreamBOOL"
#define DXAIPrefTheme            @"aiTheme"
#define DXAIPrefBall             @"aiBallBOOL"
#define DXAIPrefBallHalf         @"aiBallHalfBOOL"
#define DXAIPrefBallPos          @"aiBallPos"

// 一个 OpenAI 兼容引擎的静态预设。请求统一走 {baseURL}/chat/completions，
// 模型抓取统一走 {baseURL}/models（含 Gemini 的 OpenAI 兼容端点）。
@interface DXAIEngineInfo : NSObject
@property (nonatomic, copy) NSString *identifier;    // qwen / openai / ... / custom
@property (nonatomic, copy) NSString *displayName;   // 通义千问 / DeepSeek / ...
@property (nonatomic, copy) NSString *baseURL;       // 预设端点（custom 引擎读偏好）
@property (nonatomic, copy) NSString *defaultModels; // 逗号分隔默认模型（custom 为空）
@property (nonatomic, copy) NSString *keysURL;       // 获取 API Key 的网页
@end

// 一次对话请求的句柄：面板的"停止"按钮据此取消流式任务。
@interface DXAIChatRequest : NSObject
- (void)cancel;
@end

@interface DXAIEngine : NSObject
+ (NSArray<DXAIEngineInfo *> *)allEngines;
+ (DXAIEngineInfo *)currentEngine;
+ (DXAIEngineInfo *)engineForIdentifier:(NSString *)identifier;

// 配置读取：偏好值缺失时回退引擎预设（模型回退 defaultModels，选中模型回退首个）。
+ (NSString *)apiKeyForEngine:(DXAIEngineInfo *)engine;
+ (NSString *)endpointForEngine:(DXAIEngineInfo *)engine;
+ (NSArray<NSString *> *)modelsForEngine:(DXAIEngineInfo *)engine;
+ (NSString *)selectedModelForEngine:(DXAIEngineInfo *)engine;
+ (void)setSelectedModelForEngine:(DXAIEngineInfo *)engine model:(NSString *)model;

// 面板行为偏好。
+ (BOOL)streamEnabled;
+ (NSString *)personaPrompt;
+ (NSInteger)themeStyle; // 0 跟随系统 / 1 浅色 / 2 深色
+ (BOOL)ballEnabled;
+ (BOOL)ballHalfHide;
+ (NSString *)ballStoredPosition;
+ (void)setBallStoredPosition:(NSString *)position;

// 发送一轮对话。messages 为请求形状：{role, content}，content 是字符串或
// OpenAI 视觉 parts 数组。stream 时 onDelta 增量回调，onDone 在结束/失败时
// 恰好调用一次（fullText 为累计全文，失败时为已收到的部分）。返回的句柄
// 可 cancel（onDone 会以 code=-999 结束）。
+ (DXAIChatRequest *)sendChatWithMessages:(NSArray<NSDictionary *> *)messages
                      engine:(DXAIEngineInfo *)engine
                       onDelta:(void (^)(NSString *piece))onDelta
                      onDone:(void (^)(NSString *fullText, NSError *error))onDone;

// 拉取引擎可用模型列表（{endpoint}/models → data[].id）。
+ (void)fetchModelsForEngine:(DXAIEngineInfo *)engine
                  completion:(void (^)(NSArray<NSString *> *models, NSError *error))completion;
@end
