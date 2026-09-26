#import <Foundation/Foundation.h>
#import "../DXJavaScriptEngine.h"

static NSArray *cases;
static NSUInteger caseIndex;
static DXJavaScriptEngine *engine;
static NSString *baseURL;
static NSUInteger completed;
static void Next(void);
static void Require(BOOL ok, NSString *message) {
    if (!ok) { NSLog(@"FAIL: %@", message); exit(1); }
}
static void Next(void) {
    [engine cancel]; engine = nil;
    if (caseIndex == cases.count) {
        // Late network callbacks must not produce results or navigation.
        engine = [DXJavaScriptEngine new];
        engine.resultHandler = ^(__unused NSArray *a, __unused NSError *e) { Require(NO, @"cancelled result escaped"); };
        engine.actionHandler = ^(__unused NSDictionary *a) { Require(NO, @"cancelled navigation escaped"); };
        [engine runSource:[NSString stringWithFormat:@"async function main(s){await $http.get({url:'%@/slow'});$url.open('example://late');return s;}", baseURL] input:@"x"];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 50 * NSEC_PER_MSEC), dispatch_get_main_queue(), ^{ [engine cancel]; });
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 1200 * NSEC_PER_MSEC), dispatch_get_main_queue(), ^{
            NSLog(@"PASS: %lu engine cases plus cancellation", (unsigned long)completed); exit(0);
        });
        return;
    }
    NSDictionary *test = cases[caseIndex++];
    engine = [DXJavaScriptEngine new];
    __block BOOL navigated = NO;
    __block NSUInteger calls = 0;
    engine.actionHandler = ^(NSDictionary *action) {
        Require([action[@"content"] isEqual:@"example://search?q=a%26b"], @"scheme argument changed"); navigated = YES;
    };
    engine.resultHandler = ^(NSArray *actions, NSError *error) {
        calls++;
        if ([test[@"chain"] boolValue] && !error && [actions.firstObject[@"type"] isEqual:@"function"]) {
            NSDictionary *action = actions.firstObject;
            [engine callFunction:action[@"content"] arguments:action[@"args"]]; return;
        }
        if ([test[@"error"] boolValue]) Require(error != nil, test[@"name"]);
        else {
            Require(error == nil, [NSString stringWithFormat:@"%@: %@", test[@"name"], error]);
            Require(actions.count == [test[@"count"] unsignedIntegerValue], test[@"name"]);
            if (test[@"text"]) Require([actions.firstObject[@"content"] isEqual:test[@"text"]], test[@"name"]);
            if ([test[@"open"] boolValue]) Require(navigated, @"direct open missing");
        }
        Require(calls <= 18, @"function recursion escaped bound");
        completed++;
        NSLog(@"PASS: %@", test[@"name"]);
        dispatch_async(dispatch_get_main_queue(), ^{ Next(); });
    };
    NSString *source = [test[@"source"] stringByReplacingOccurrencesOfString:@"BASE" withString:baseURL];
    [engine runSource:source input:@"a&b"];
}
int main(int argc, const char *argv[]) {
    @autoreleasepool {
        Require(argc == 2, @"server address required");
        baseURL = [NSString stringWithUTF8String:argv[1]];
        cases = @[
            @{@"name":@"async text", @"source":@"async function main(s){return s.toUpperCase()}", @"count":@1, @"text":@"A&B"},
            @{@"name":@"empty string deletes", @"source":@"async function main(s){return ''}", @"count":@1, @"text":@""},
            @{@"name":@"undefined no insertion", @"source":@"async function main(s){}", @"count":@0},
            @{@"name":@"choices", @"source":@"async function main(s){return ['one','two']}", @"count":@2},
            @{@"name":@"dictionary navigation", @"source":@"async function main(s){return [{type:'url',content:'example://x',title:'Open'},{type:'txt',content:s}]}", @"count":@2},
            @{@"name":@"function args", @"source":@"async function main(s){return {type:'function',content:'next',args:[s,'ok']}} async function next(a,b){return a+b}", @"chain":@YES, @"count":@1, @"text":@"a&bok"},
            @{@"name":@"direct scheme", @"source":@"async function main(s){$url.open('example://search?q='+encodeURIComponent(s));return null}", @"count":@0, @"open":@YES},
            @{@"name":@"GET text", @"source":@"async function main(s){return await $http.get({url:'BASE/text'})}", @"count":@1, @"text":@"hello 中文"},
            @{@"name":@"POST JSON and header", @"source":@"async function main(s){const r=JSON.parse(await $http.post({url:'BASE/echo',headers:{'Content-Type':'application/json','X-Test':'typex'},body:JSON.stringify({text:s})}));return r.method+' '+r.header+' '+JSON.parse(r.body).text}", @"count":@1, @"text":@"POST typex a&b"},
            @{@"name":@"PUT PATCH DELETE", @"source":@"async function main(){let a=[];for(const m of ['put','patch','delete'])a.push(JSON.parse(await $http[m]({url:'BASE/echo'})).method);return a.join(',')}", @"count":@1, @"text":@"PUT,PATCH,DELETE"},
            @{@"name":@"HTTP error catch", @"source":@"async function main(){try{await $http.get({url:'BASE/status'})}catch(e){return e.message}}", @"count":@1, @"text":@"HTTP 503"},
            @{@"name":@"body rejects object", @"source":@"async function main(){return await $http.post({url:'BASE/echo',body:{a:1}})}", @"error":@YES},
            @{@"name":@"binary response", @"source":@"async function main(){return await $http.get({url:'BASE/binary'})}", @"error":@YES},
            @{@"name":@"response size", @"source":@"async function main(){return await $http.get({url:'BASE/large'})}", @"error":@YES},
            @{@"name":@"invalid scheme", @"source":@"async function main(){return await $http.get({url:'file:///etc/hosts'})}", @"error":@YES},
            @{@"name":@"missing main", @"source":@"const x=1", @"error":@YES},
            @{@"name":@"syntax error", @"source":@"async function main( {", @"error":@YES},
            @{@"name":@"promise rejection", @"source":@"async function main(){throw new Error('bad')}", @"error":@YES},
            @{@"name":@"cyclic result", @"source":@"async function main(){let a={};a.a=a;return a}", @"error":@YES},
            @{@"name":@"validate whole array", @"source":@"async function main(){return [{type:'url',content:'example://x'},3]}", @"error":@YES},
            @{@"name":@"legacy eval unsupported", @"source":@"async function main(){return {type:'js',content:'1'}}", @"error":@YES},
            @{@"name":@"infinite top level", @"source":@"while(true){}", @"error":@YES},
            @{@"name":@"infinite main", @"source":@"async function main(){while(true){}}", @"error":@YES},
            @{@"name":@"recursive function result", @"source":@"async function main(){return {type:'function',content:'main'}}", @"chain":@YES, @"error":@YES},
            @{@"name":@"unsettled Promise deadline", @"source":@"async function main(){return new Promise(()=>{})}", @"error":@YES}
        ];
        Next();
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 40 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{ Require(NO, @"suite timed out"); });
        dispatch_main();
    }
}
