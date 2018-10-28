#import "FlutterWebviewPlugin.h"
#import "FlutterWebviewPluginUtils.h"

static NSString *const CHANNEL_NAME = @"flutter_webview_plugin";

@interface FlutterWebviewPlugin() <WKNavigationDelegate, UIScrollViewDelegate, WKUIDelegate>
@property (nonatomic, strong) NSURL *currentUrl;
@property (nonatomic, assign) BOOL enableAppScheme;
@property (nonatomic, assign) BOOL enableZoom;
@property (nonatomic, strong) NSMutableDictionary *additionalHttpHeaders;
@property (nonatomic, strong) NSMutableDictionary *interceptUrls;
@end

@implementation FlutterWebviewPlugin
+ (void)registerWithRegistrar:(NSObject<FlutterPluginRegistrar>*)registrar {
    channel = [FlutterMethodChannel
               methodChannelWithName:CHANNEL_NAME
               binaryMessenger:[registrar messenger]];
    
    UIViewController *viewController = (UIViewController *)registrar.messenger;
    FlutterWebviewPlugin* instance = [[FlutterWebviewPlugin alloc] initWithViewController:viewController];
    
    [registrar addMethodCallDelegate:instance channel:channel];
    [registrar publish:instance];
}

- (instancetype)initWithViewController:(UIViewController *)viewController {
    self = [super init];
    if (self) {
        self.viewController = viewController;
        _additionalHttpHeaders = [[NSMutableDictionary alloc] init];
        _interceptUrls = [[NSMutableDictionary alloc]init];
    }
    return self;
}


#pragma mark - delegate
- (void)handleMethodCall:(FlutterMethodCall*)call result:(FlutterResult)result {
    if ([@"launch" isEqualToString:call.method]) {
        if (!self.webview)
            [self initWebview:call];
        else
            [self navigate:call];
        result(nil);
    } else if ([@"close" isEqualToString:call.method]) {
        [self closeWebViewWithNoti:(id) call.arguments];
        result(nil);
    } else if ([@"eval" isEqualToString:call.method]) {
        [self evalJavascript:call completionHandler:^(NSString * response) {
            result(response);
        }];
    } else if ([@"resize" isEqualToString:call.method]) {
        [self resize:call];
        result(nil);
    } else if ([@"reloadUrl" isEqualToString:call.method]) {
        [self reloadUrl:call];
        result(nil);	
    } else if ([@"show" isEqualToString:call.method]) {
        [self show];
        result(nil);
    } else if ([@"hide" isEqualToString:call.method]) {
        [self hide];
        result(nil);
    } else if ([@"stopLoading" isEqualToString:call.method]) {
        [self stopLoading];
        result(nil);
    } else {
        result(FlutterMethodNotImplemented);
    }
}

- (void)initWebview:(FlutterMethodCall*)call {
    NSNumber *clearCache = call.arguments[@"clearCache"];
    NSNumber *clearCookies = call.arguments[@"clearCookies"];
    NSNumber *hidden = call.arguments[@"hidden"];
    NSDictionary *rect = call.arguments[@"rect"];
    _enableAppScheme = [call.arguments[@"enableAppScheme"] boolValue];
    NSString *userAgent = call.arguments[@"userAgent"];
    NSNumber *withZoom = call.arguments[@"withZoom"];
    NSNumber *scrollBar = call.arguments[@"scrollBar"];
    NSNumber *javascript = call.arguments[@"withJavascript"];
    
    if (clearCache != (id)[NSNull null] && [clearCache boolValue]) {
        [[NSURLCache sharedURLCache] removeAllCachedResponses];
    }
    
    if (clearCookies != (id)[NSNull null] && [clearCookies boolValue]) {
        [[NSURLSession sharedSession] resetWithCompletionHandler:^{
        }];
    }
    
    if (userAgent != (id)[NSNull null]) {
        [[NSUserDefaults standardUserDefaults] registerDefaults:@{@"UserAgent": userAgent}];
    }
    
    
    CGRect rc;
    if (rect != nil) {
        rc = [self parseRect:rect];
    } else {
        rc = self.viewController.view.bounds;
    }
    self.webview = [[WKWebView alloc] initWithFrame:rc configuration:[WKWebViewConfiguration new]];
    self.webview.navigationDelegate = self;
    self.webview.UIDelegate = self;
    self.webview.scrollView.delegate = self;
    self.webview.hidden = [hidden boolValue];
    self.webview.scrollView.showsHorizontalScrollIndicator = [scrollBar boolValue];
    self.webview.scrollView.showsVerticalScrollIndicator = [scrollBar boolValue];
    
    if ([javascript isKindOfClass:[NSNumber class]]) {
        self.webview.configuration.preferences.javaScriptEnabled = [javascript boolValue];
    }
    if ([userAgent isKindOfClass:[NSString class]]) {
        if (@available(iOS 9.0, *)) {
            self.webview.customUserAgent = userAgent;
        }
    }



    [self.webview  addObserver:self forKeyPath:@"title" options:NSKeyValueObservingOptionNew context:NULL];
    _enableZoom = [withZoom boolValue];
    [self.viewController.view addSubview:self.webview];
    [self navigate:call];
}

- (void) scrollViewDidScroll:(UIScrollView *)scrollView {
    id xDirection = @{@"xDirection": @(scrollView.contentOffset.x) };
    [channel invokeMethod:@"onScrollXChanged" arguments:xDirection];

    id yDirection = @{@"yDirection": @(scrollView.contentOffset.y) };
    [channel invokeMethod:@"onScrollYChanged" arguments:yDirection];
}

- (void)navigate:(FlutterMethodCall*)call {
    if (self.webview != nil) {
            NSString *url = call.arguments[@"url"];
            NSNumber *withLocalUrl = call.arguments[@"withLocalUrl"];
            if ( [withLocalUrl boolValue]) {
                NSURL *htmlUrl = [NSURL fileURLWithPath:url isDirectory:false];
                if (@available(iOS 9.0, *)) {
                    [self.webview loadFileURL:htmlUrl allowingReadAccessToURL:htmlUrl];
                } else {
                    @throw @"not available on version earlier than ios 9.0";
                }
            } else {
                NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:url]];
                NSDictionary *headers = call.arguments[@"headers"];
                
                if (headers != nil) {
                    [request setAllHTTPHeaderFields:headers];
                }
                
                [self.webview loadRequest:request];
            }
        }
}

- (void)evalJavascript:(FlutterMethodCall*)call
     completionHandler:(void (^_Nullable)(NSString * response))completionHandler {
    if (self.webview != nil) {
        NSString *code = call.arguments[@"code"];
        [self.webview evaluateJavaScript:code
                       completionHandler:^(id _Nullable response, NSError * _Nullable error) {
                           completionHandler([NSString stringWithFormat:@"%@", response]);
                       }];
    } else {
        completionHandler(nil);
    }
}

- (void)resize:(FlutterMethodCall*)call {
    if (self.webview != nil) {
        NSDictionary *rect = call.arguments[@"rect"];
        CGRect rc = [self parseRect:rect];
        self.webview.frame = rc;
    }
}

- (void)closeWebView {
    if (self.webview != nil) {
        [self.webview stopLoading];
        [self.webview removeFromSuperview];
        self.webview.navigationDelegate = nil;
        self.webview = nil;

        // manually trigger onDestroy
        [channel invokeMethod:@"onDestroy" arguments:nil];
    }
}

- (void)reloadUrl:(FlutterMethodCall*)call {
    if (self.webview != nil) {
		NSString *url = call.arguments[@"url"];
		NSURLRequest *request = [NSURLRequest requestWithURL:[NSURL URLWithString:url]];
        [self.webview loadRequest:request];
    }
}
- (void)show {
    if (self.webview != nil) {
        self.webview.hidden = false;
    }
}

- (void)hide {
    if (self.webview != nil) {
        self.webview.hidden = true;
    }
}
- (void)stopLoading {
    if (self.webview != nil) {
        [self.webview stopLoading];
    }
}

#pragma mark -- WkWebView Delegate
- (void)webView:(WKWebView *)webView decidePolicyForNavigationAction:(WKNavigationAction *)navigationAction
decisionHandler:(void (^)(WKNavigationActionPolicy))decisionHandler {
    [self stringByEvaluatingJavaScriptFromString:nil];
    //==============
    id data = @{@"url": navigationAction.request.URL.absoluteString,
                @"type": @"shouldStart",
                @"navigationType": [NSNumber numberWithInt:navigationAction.navigationType]};
    [channel invokeMethod:@"onState" arguments:data];
    if (navigationAction.navigationType == WKNavigationTypeBackForward) {
        [channel invokeMethod:@"onBackPressed" arguments:nil];
    } else {
        id data = @{@"url": navigationAction.request.URL.absoluteString};
        [channel invokeMethod:@"onUrlChanged" arguments:data];
    }

    NSURLRequest *request = navigationAction.request;
    NSDictionary *requestHeaders = request.allHTTPHeaderFields;
    if (requestHeaders[@"Authorization"]) {
        decisionHandler(WKNavigationActionPolicyAllow);
    } else {
        if ([navigationAction.request.URL.absoluteString containsString:@"hexindai"]) {
              request = [self addCommonHeaderToRequest:request.mutableCopy];
             [webView loadRequest:request];
        }
        decisionHandler(WKNavigationActionPolicyAllow);
    }
}


- (void)webView:(WKWebView *)webView didStartProvisionalNavigation:(WKNavigation *)navigation {
    [channel invokeMethod:@"onState" arguments:@{@"type": @"startLoad", @"url": webView.URL.absoluteString}];
    if ([self.navigationDelegate respondsToSelector:@selector(webView:didStartProvisionalNavigation:)]) {
        [self.navigationDelegate webView:webView didStartProvisionalNavigation:navigation];
    }
}

- (void)webView:(WKWebView *)webView didFinishNavigation:(WKNavigation *)navigation {
    [channel invokeMethod:@"onState" arguments:@{@"type": @"finishLoad", @"url": webView.URL.absoluteString}];
    if ([self.navigationDelegate respondsToSelector:@selector(webView:didFinishNavigation:)]) {
        [self.navigationDelegate webView:webView didFinishNavigation:navigation];
    }
}

- (void)webView:(WKWebView *)webView didFailNavigation:(WKNavigation *)navigation withError:(NSError *)error {
    id data = [FlutterError errorWithCode:[NSString stringWithFormat:@"%ld", error.code]
                                  message:error.localizedDescription
                                  details:error.localizedFailureReason];
    [channel invokeMethod:@"onError" arguments:data];
    if ([self.navigationDelegate respondsToSelector:@selector(webView:didFailNavigation:withError:)]) {
        [self.navigationDelegate webView:webView didFailNavigation:navigation withError:error];
    }
}

- (void)webView:(WKWebView *)webView didFailProvisionalNavigation:(WKNavigation *)navigation withError:(NSError *)error {
    if ([self.navigationDelegate respondsToSelector:@selector(webView:didFailProvisionalNavigation:withError:)]) {
        [self.navigationDelegate webView:webView didFailProvisionalNavigation:navigation withError:error];
    }
}

- (void)webView:(WKWebView *)webView didReceiveAuthenticationChallenge:(NSURLAuthenticationChallenge *)challenge completionHandler:(void (^)(NSURLSessionAuthChallengeDisposition, NSURLCredential * _Nullable))completionHandler {
    if ([self.navigationDelegate respondsToSelector:@selector(webView:didReceiveAuthenticationChallenge:completionHandler:)]) {
        [self.navigationDelegate webView:webView didReceiveAuthenticationChallenge:challenge completionHandler:completionHandler];
    } else {
        completionHandler(NSURLSessionAuthChallengePerformDefaultHandling, nil);
    }
}

- (void)webView:(WKWebView *)webView decidePolicyForNavigationResponse:(WKNavigationResponse *)navigationResponse decisionHandler:(void (^)(WKNavigationResponsePolicy))decisionHandler {
    if ([navigationResponse.response isKindOfClass:[NSHTTPURLResponse class]]) {
        NSHTTPURLResponse * response = (NSHTTPURLResponse *)navigationResponse.response;

        [channel invokeMethod:@"onHttpError" arguments:@{@"code": [NSString stringWithFormat:@"%ld", response.statusCode], @"url": webView.URL.absoluteString}];
    }
    decisionHandler(WKNavigationResponsePolicyAllow);
}

//scrollView 代理事件
- (void)scrollViewWillBeginDragging:(UIScrollView *)scrollView {
    if (scrollView.pinchGestureRecognizer.isEnabled != _enableZoom) {
        scrollView.pinchGestureRecognizer.enabled = _enableZoom;
    }
}




#pragma mark - WKUIDelegate
- (nullable WKWebView *)webView:(WKWebView *)webView createWebViewWithConfiguration:(WKWebViewConfiguration *)configuration forNavigationAction:(WKNavigationAction *)navigationAction windowFeatures:(WKWindowFeatures *)windowFeatures {
    if (!navigationAction.targetFrame || !navigationAction.targetFrame.isMainFrame) {
        [webView loadRequest:navigationAction.request];
    }
    return nil;
}

- (void)webView:(WKWebView *)webView runJavaScriptConfirmPanelWithMessage:(NSString *)message initiatedByFrame:(WKFrameInfo *)frame completionHandler:(void (^)(BOOL result))completionHandler {
    UIAlertController *alertController = [UIAlertController alertControllerWithTitle:@"提示"
                                                                             message:message
                                                                      preferredStyle:UIAlertControllerStyleAlert];
    [alertController addAction:[UIAlertAction actionWithTitle:@"确定"
                                                        style:UIAlertActionStyleDefault
                                                      handler:^(UIAlertAction *action) {
                                                          kBlockSafeRun(completionHandler, YES);
                                                      }]];
    [alertController addAction:[UIAlertAction actionWithTitle:@"取消"
                                                        style:UIAlertActionStyleCancel
                                                      handler:^(UIAlertAction *action) {
                                                          kBlockSafeRun(completionHandler, NO);
                                                      }]];
    [self.viewController presentViewController:alertController animated:YES completion:nil];
}

- (void)webView:(WKWebView *)webView runJavaScriptAlertPanelWithMessage:(NSString *)message initiatedByFrame:(WKFrameInfo *)frame completionHandler:(void (^)(void))completionHandler {
    UIAlertController *alertController = [UIAlertController alertControllerWithTitle:@"提示"
                                                                             message:message
                                                                      preferredStyle:UIAlertControllerStyleAlert];
    [alertController addAction:[UIAlertAction actionWithTitle:@"确定"
                                                        style:UIAlertActionStyleDefault
                                                      handler:^(UIAlertAction *action) {
                                                          kBlockSafeRun(completionHandler);
                                                      }]];
    [self.viewController presentViewController:alertController animated:YES completion:nil];
}

- (void)webView:(WKWebView *)webView runJavaScriptTextInputPanelWithPrompt:(NSString *)prompt defaultText:(NSString *)defaultText initiatedByFrame:(WKFrameInfo *)frame completionHandler:(void (^)(NSString * _Nullable))completionHandler {
    UIAlertController *alertController = [UIAlertController alertControllerWithTitle:@"提示"
                                                                             message:prompt
                                                                      preferredStyle:UIAlertControllerStyleAlert];
    [alertController addTextFieldWithConfigurationHandler:^(UITextField * _Nonnull textField) {
        textField.text = defaultText;
    }];
    [alertController addAction:[UIAlertAction actionWithTitle:@"完成"
                                                        style:UIAlertActionStyleDefault
                                                      handler:^(UIAlertAction * _Nonnull action) {
                                                          kBlockSafeRun(completionHandler, alertController.textFields[0].text);
                                                      }]];
    [self.viewController presentViewController:alertController animated:YES completion:nil];
}



#pragma mark - private
- (void)stringByEvaluatingJavaScriptFromString:(NSString *)script{
    if (_additionalHttpHeaders.count > 0) {
        NSString *token= _additionalHttpHeaders[@"hexindai-token"];
        NSString *js = [NSString stringWithFormat:JsStr,token];
        [self.webview evaluateJavaScript:js completionHandler:^(id _Nullable object, NSError * _Nullable error) {
            NSLog(@"AAAAAAAA=======:::::evaluateJavaScript");
        }];
    NSString *jsString = [NSString stringWithFormat:@"localStorage.setItem('token', '%@')", token];
    [self.webview evaluateJavaScript:jsString completionHandler:^(id _Nullable object, NSError * _Nullable error) {
            NSLog(@"BBBBBB=======:::::evaluateJavaScript");
        }];
    }
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context {
        if (object == self.webview) {
             [channel invokeMethod:@"onTitleChanged" arguments:self.webview.title];
        }
}

- (CGRect)parseRect:(NSDictionary *)rect {
    return CGRectMake([[rect valueForKey:@"left"] doubleValue],
                      [[rect valueForKey:@"top"] doubleValue],
                      [[rect valueForKey:@"width"] doubleValue],
                      [[rect valueForKey:@"height"] doubleValue]);
}

- (NSMutableURLRequest *)addCommonHeaderToRequest:(NSMutableURLRequest *)request {
    NSMutableURLRequest *tempRequest = nil;
    if (request) {
        tempRequest = request;
    } else {
        tempRequest = [NSMutableURLRequest new];
    }
    NSArray *allkeys =  _additionalHttpHeaders.allKeys;
    for (NSString *key in allkeys) {
        [tempRequest setValue:_additionalHttpHeaders[key] forHTTPHeaderField:key];
    }
    return tempRequest;
}

- (NSDictionary *)getCommonParams {
     NSString *token= _additionalHttpHeaders[@"hexindai-token"];
    return @{@"token": token ?: @""};
}

- (void)closeWebViewWithNoti:(id)arg {
    NSString *goBack = arg[@"goBack"];
    BOOL canGoBack = [goBack boolValue];
    if (self.webview != nil) {
        if ([self.webview canGoBack] && canGoBack) {
            [self.webview goBack];
        }else{
            [self.webview stopLoading];
            [self.webview removeFromSuperview];
            self.webview.navigationDelegate = nil;
             self.webview = nil;
            // manually trigger onDestroy
            [channel invokeMethod:@"onDestroy" arguments:nil];
        }
    }
}

//字典转json
- (NSString *)dictToJson:(NSDictionary *)dict {
    NSError *parseError = nil;
    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:dict options:NSJSONWritingPrettyPrinted error:&parseError];
    NSString *jsonStr = [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
    return jsonStr;
}

//json转字典
- (NSDictionary *)jsonToDict:(NSString *)json {
    NSData *jsonData = [json dataUsingEncoding:NSUTF8StringEncoding];
    NSError *err;
    NSDictionary *dict = [NSJSONSerialization JSONObjectWithData:jsonData
                                                         options:NSJSONReadingMutableContainers
                                                           error:&err];
    return dict;
}
@end
