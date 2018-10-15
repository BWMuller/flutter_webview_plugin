//
//  FlutterWebviewPluginUtils.h
//  Pods
//
//  Created by hexindai on 2018/9/28.
//

#ifndef FlutterWebviewPluginUtils_h
#define FlutterWebviewPluginUtils_h

#define JsStr @"var App = {}; (function initialize() { App.getToken = function () { return '%@';};})(); "
//trim string
#define kTrim(str)   [str stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]]
#define kURL(str)  ({ \
NSURL *url = nil; \
NSString *_link = kTrim(str); \
if ([_link rangeOfString:@"%[0-9A-Fa-f]{2}" options:NSRegularExpressionSearch].location != NSNotFound) { \
url = [NSURL URLWithString:_link]; \
} else { \
url = [NSURL URLWithString:[_link stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLQueryAllowedCharacterSet]]]; \
} \
(url); \
})

#define kBlockSafeRun(block, ...)   !block ?: block(__VA_ARGS__)


#endif /* FlutterWebviewPluginUtils_h */
