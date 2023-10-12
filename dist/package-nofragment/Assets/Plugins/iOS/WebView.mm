/*
 * Copyright (C) 2011 Keijiro Takahashi
 * Copyright (C) 2012 GREE, Inc.
 *
 * This software is provided 'as-is', without any express or implied
 * warranty.  In no event will the authors be held liable for any damages
 * arising from the use of this software.
 *
 * Permission is granted to anyone to use this software for any purpose,
 * including commercial applications, and to alter it and redistribute it
 * freely, subject to the following restrictions:
 *
 * 1. The origin of this software must not be misrepresented; you must not
 *    claim that you wrote the original software. If you use this software
 *    in a product, an acknowledgment in the product documentation would be
 *    appreciated but is not required.
 * 2. Altered source versions must be plainly marked as such, and must not be
 *    misrepresented as being the original software.
 * 3. This notice may not be removed or altered from any source distribution.
 */

#if !(__IPHONE_OS_VERSION_MIN_REQUIRED < __IPHONE_9_0)

#import <UIKit/UIKit.h>
#import <WebKit/WebKit.h>

// NOTE: we need extern without "C" before unity 4.5
//extern UIViewController *UnityGetGLViewController();
extern "C" UIViewController *UnityGetGLViewController();
extern "C" void UnitySendMessage(const char *, const char *, const char *);

// cf. https://stackoverflow.com/questions/26383031/wkwebview-causes-my-view-controller-to-leak/33365424#33365424
@interface WeakScriptMessageDelegate : NSObject<WKScriptMessageHandler>

@property (nonatomic, weak) id<WKScriptMessageHandler> scriptDelegate;

- (instancetype)initWithDelegate:(id<WKScriptMessageHandler>)scriptDelegate;

@end

@implementation WeakScriptMessageDelegate

- (instancetype)initWithDelegate:(id<WKScriptMessageHandler>)scriptDelegate
{
    self = [super init];
    if (self) {
        _scriptDelegate = scriptDelegate;
    }
    return self;
}

- (void)userContentController:(WKUserContentController *)userContentController didReceiveScriptMessage:(WKScriptMessage *)message
{
    [self.scriptDelegate userContentController:userContentController didReceiveScriptMessage:message];
}

@end

@protocol WebViewProtocol <NSObject>
@property (nonatomic, getter=isOpaque) BOOL opaque;
@property (nullable, nonatomic, copy) UIColor *backgroundColor UI_APPEARANCE_SELECTOR;
@property (nonatomic, getter=isHidden) BOOL hidden;
@property (nonatomic) CGRect frame;
@property (nullable, nonatomic, weak) id <WKNavigationDelegate> navigationDelegate;
@property (nullable, nonatomic, weak) id <WKUIDelegate> UIDelegate;
@property (nullable, nonatomic, readonly, copy) NSURL *URL;
- (void)load:(NSURLRequest *)request;
- (void)loadHTML:(NSString *)html baseURL:(NSURL *)baseUrl;
- (void)evaluateJavaScript:(NSString *)javaScriptString completionHandler:(void (^ __nullable)(__nullable id, NSError * __nullable error))completionHandler;
@property (nonatomic, readonly) BOOL canGoBack;
@property (nonatomic, readonly) BOOL canGoForward;
- (void)goBack;
- (void)goForward;
- (void)reload;
- (void)stopLoading;
- (void)setScrollbarsVisibility:(BOOL)visibility;
- (void)setScrollBounce:(BOOL)enable;
@end

@interface WKWebView(WebViewProtocolConformed) <WebViewProtocol>
@end

@implementation WKWebView(WebViewProtocolConformed)

- (void)load:(NSURLRequest *)request
{
    WKWebView *webView = (WKWebView *)self;
    NSURL *url = [request URL];
    if ([url.absoluteString hasPrefix:@"file:"]) {
        NSURL *top = [NSURL URLWithString:[[url absoluteString] stringByDeletingLastPathComponent]];
        [webView loadFileURL:url allowingReadAccessToURL:top];
    } else {
        [webView loadRequest:request];
    }
}

- (NSURLRequest *)constructionCustomHeader:(NSURLRequest *)originalRequest with:(NSDictionary *)headerDictionary
{
    NSMutableURLRequest *convertedRequest = originalRequest.mutableCopy;
    for (NSString *key in [headerDictionary allKeys]) {
        [convertedRequest setValue:headerDictionary[key] forHTTPHeaderField:key];
    }
    return (NSURLRequest *)[convertedRequest copy];
}

- (void)loadHTML:(NSString *)html baseURL:(NSURL *)baseUrl
{
    WKWebView *webView = (WKWebView *)self;
    [webView loadHTMLString:html baseURL:baseUrl];
}

- (void)setScrollbarsVisibility:(BOOL)visibility
{
    WKWebView *webView = (WKWebView *)self;
    webView.scrollView.showsHorizontalScrollIndicator = visibility;
    webView.scrollView.showsVerticalScrollIndicator = visibility;
}

- (void)setScrollBounce:(BOOL)enable
{
    WKWebView *webView = (WKWebView *)self;
    webView.scrollView.bounces = enable;
}

@end

@interface CWebViewPlugin : NSObject<WKUIDelegate, WKNavigationDelegate, WKScriptMessageHandler>
{
    UIView <WebViewProtocol> *webView;
    NSString *gameObjectName;
    NSMutableDictionary *customRequestHeader;
    BOOL alertDialogEnabled;
    NSRegularExpression *allowRegex;
    NSRegularExpression *denyRegex;
    NSRegularExpression *hookRegex;
    NSString *basicAuthUserName;
    NSString *basicAuthPassword;
}
@end

@implementation CWebViewPlugin

static WKProcessPool *_sharedProcessPool;
static NSMutableArray *_instances = [[NSMutableArray alloc] init];

- (id)initWithGameObjectName:(const char *)gameObjectName_ transparent:(BOOL)transparent zoom:(BOOL)zoom ua:(const char *)ua enableWKWebView:(BOOL)enableWKWebView contentMode:(WKContentMode)contentMode allowsLinkPreview:(BOOL)allowsLinkPreview allowsBackForwardNavigationGestures:(BOOL)allowsBackForwardNavigationGestures radius:(int)radius
{
    self = [super init];

    gameObjectName = [NSString stringWithUTF8String:gameObjectName_];
    customRequestHeader = [[NSMutableDictionary alloc] init];
    alertDialogEnabled = true;
    allowRegex = nil;
    denyRegex = nil;
    hookRegex = nil;
    basicAuthUserName = nil;
    basicAuthPassword = nil;
    UIView *view = UnityGetGLViewController().view;
    if (enableWKWebView && [WKWebView class]) {
        if (_sharedProcessPool == NULL) {
            _sharedProcessPool = [[WKProcessPool alloc] init];
        }
        WKWebViewConfiguration *configuration = [[WKWebViewConfiguration alloc] init];
        WKUserContentController *controller = [[WKUserContentController alloc] init];
        [controller addScriptMessageHandler:[[WeakScriptMessageDelegate alloc] initWithDelegate:self] name:@"unityControl"];
        [controller addScriptMessageHandler:[[WeakScriptMessageDelegate alloc] initWithDelegate:self] name:@"saveDataURL"];
        NSString *str = @"\
window.Unity = { \
    call: function(msg) { \
        window.webkit.messageHandlers.unityControl.postMessage(msg); \
    }, \
    saveDataURL: function(fileName, dataURL) { \
        window.webkit.messageHandlers.saveDataURL.postMessage(fileName + '\t' + dataURL); \
    } \
}; \
";
        if (!zoom) {
          str = [str stringByAppendingString:@"\
(function() { \
    var meta = document.querySelector('meta[name=viewport]'); \
    if (meta == null) { \
        meta = document.createElement('meta'); \
        meta.name = 'viewport'; \
    } \
    meta.content += ((meta.content.length > 0) ? ',' : '') + 'user-scalable=no'; \
    var head = document.getElementsByTagName('head')[0]; \
    head.appendChild(meta); \
})(); \
"
            ];
        }
        WKUserScript *script
            = [[WKUserScript alloc] initWithSource:str injectionTime:WKUserScriptInjectionTimeAtDocumentEnd forMainFrameOnly:YES];
        [controller addUserScript:script];
        configuration.userContentController = controller;
        configuration.allowsInlineMediaPlayback = true;
        if (@available(iOS 10.0, *)) {
            configuration.mediaTypesRequiringUserActionForPlayback = WKAudiovisualMediaTypeNone;
        } else {
            if (@available(iOS 9.0, *)) {
                configuration.requiresUserActionForMediaPlayback = NO;
            } else {
                configuration.mediaPlaybackRequiresUserAction = NO;
            }
        }
        configuration.websiteDataStore = [WKWebsiteDataStore defaultDataStore];
        configuration.processPool = _sharedProcessPool;
        if (@available(iOS 13.0, *)) {
            configuration.defaultWebpagePreferences.preferredContentMode = contentMode;
        }
#if UNITYWEBVIEW_IOS_ALLOW_FILE_URLS
        // cf. https://stackoverflow.com/questions/35554814/wkwebview-xmlhttprequest-with-file-url/44365081#44365081
        try {
            [configuration.preferences setValue:@TRUE forKey:@"allowFileAccessFromFileURLs"];
        }
        catch (NSException *ex) {
        }
        try {
            [configuration setValue:@TRUE forKey:@"allowUniversalAccessFromFileURLs"];
        }
        catch (NSException *ex) {
        }
#endif
        WKWebView *wkwebView = [[WKWebView alloc] initWithFrame:view.frame configuration:configuration];
#if UNITYWEBVIEW_DEVELOPMENT
        NSOperatingSystemVersion version = { 16, 4, 0 };
        if ([[NSProcessInfo processInfo] isOperatingSystemAtLeastVersion:version]) {
            wkwebView.inspectable = true;
        }
#endif
        wkwebView.allowsLinkPreview = allowsLinkPreview;
        wkwebView.allowsBackForwardNavigationGestures = allowsBackForwardNavigationGestures;
        webView = wkwebView;
        webView.UIDelegate = self;
        webView.navigationDelegate = self;
        if (radius > 0) {
            webView.layer.cornerRadius = radius;
            webView.layer.masksToBounds = YES;
        }
        if (ua != NULL && strcmp(ua, "") != 0) {
            ((WKWebView *)webView).customUserAgent = [[NSString alloc] initWithUTF8String:ua];
        }
        // cf. https://rick38yip.medium.com/wkwebview-weird-spacing-issue-in-ios-13-54a4fc686f72
        // cf. https://stackoverflow.com/questions/44390971/automaticallyadjustsscrollviewinsets-was-deprecated-in-ios-11-0
        if (@available(iOS 11.0, *)) {
            ((WKWebView *)webView).scrollView.contentInsetAdjustmentBehavior = UIScrollViewContentInsetAdjustmentNever;
        } else {
            //UnityGetGLViewController().automaticallyAdjustsScrollViewInsets = false;
        }
    } else {
        webView = nil;
        return self;
    }
    if (transparent) {
        webView.opaque = NO;
        webView.backgroundColor = [UIColor clearColor];
    }
    webView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    webView.hidden = YES;

    [webView addObserver:self forKeyPath: @"loading" options: NSKeyValueObservingOptionNew context:nil];

    [view addSubview:webView];

    return self;
}

- (void)dispose
{
    if (webView != nil) {
        UIView <WebViewProtocol> *webView0 = webView;
        webView = nil;
        if ([webView0 isKindOfClass:[WKWebView class]]) {
            webView0.UIDelegate = nil;
            webView0.navigationDelegate = nil;
            [((WKWebView *)webView0).configuration.userContentController removeScriptMessageHandlerForName:@"saveDataURL"];
            [((WKWebView *)webView0).configuration.userContentController removeScriptMessageHandlerForName:@"unityControl"];
        }
        [webView0 stopLoading];
        [webView0 removeFromSuperview];
        [webView0 removeObserver:self forKeyPath:@"loading"];
    }
    basicAuthPassword = nil;
    basicAuthUserName = nil;
    hookRegex = nil;
    denyRegex = nil;
    allowRegex = nil;
    customRequestHeader = nil;
    gameObjectName = nil;
}

+ (void)resetSharedProcessPool
{
    // cf. https://stackoverflow.com/questions/33156567/getting-all-cookies-from-wkwebview/49744695#49744695
    _sharedProcessPool = [[WKProcessPool alloc] init];
    [_instances enumerateObjectsUsingBlock:^(CWebViewPlugin *obj, NSUInteger idx, BOOL *stop) {
        if ([obj->webView isKindOfClass:[WKWebView class]]) {
            WKWebView *webView = (WKWebView *)obj->webView;
            webView.configuration.processPool = _sharedProcessPool;
        }
    }];
}

+ (void)clearCookies
{
    [CWebViewPlugin resetSharedProcessPool];

    // cf. https://dev.classmethod.jp/smartphone/remove-webview-cookies/
    NSString *libraryPath = NSSearchPathForDirectoriesInDomains(NSLibraryDirectory, NSUserDomainMask, YES).firstObject;
    NSString *cookiesPath = [libraryPath stringByAppendingPathComponent:@"Cookies"];
    NSString *webKitPath = [libraryPath stringByAppendingPathComponent:@"WebKit"];
    [[NSFileManager defaultManager] removeItemAtPath:cookiesPath error:nil];
    [[NSFileManager defaultManager] removeItemAtPath:webKitPath error:nil];

    NSHTTPCookieStorage *cookieStorage = [NSHTTPCookieStorage sharedHTTPCookieStorage];
    if (cookieStorage == nil) {
        // cf. https://stackoverflow.com/questions/33876295/nshttpcookiestorage-sharedhttpcookiestorage-comes-up-empty-in-10-11
        cookieStorage = [NSHTTPCookieStorage sharedCookieStorageForGroupContainerIdentifier:@"Cookies"];
    }
    [[cookieStorage cookies] enumerateObjectsUsingBlock:^(NSHTTPCookie *cookie, NSUInteger idx, BOOL *stop) {
        [cookieStorage deleteCookie:cookie];
    }];

    NSOperatingSystemVersion version = { 9, 0, 0 };
    if ([[NSProcessInfo processInfo] isOperatingSystemAtLeastVersion:version]) {
        // cf. https://stackoverflow.com/questions/46465070/how-to-delete-cookies-from-wkhttpcookiestore/47928399#47928399
        NSSet *websiteDataTypes = [WKWebsiteDataStore allWebsiteDataTypes];
        NSDate *date = [NSDate dateWithTimeIntervalSince1970:0];
        [[WKWebsiteDataStore defaultDataStore] removeDataOfTypes:websiteDataTypes
                                                   modifiedSince:date
                                               completionHandler:^{}];
    }
}

+ saveCookies
{
    [CWebViewPlugin resetSharedProcessPool];
}

- (void)getCookies:(const char *)url
{
    NSOperatingSystemVersion version = { 9, 0, 0 };
    if ([[NSProcessInfo processInfo] isOperatingSystemAtLeastVersion:version]) {
        NSURL *nsurl = [NSURL URLWithString:[[NSString alloc] initWithUTF8String:url]];
        WKHTTPCookieStore *cookieStore = WKWebsiteDataStore.defaultDataStore.httpCookieStore;
        [cookieStore
            getAllCookies:^(NSArray<NSHTTPCookie *> *array) {
                NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
                formatter.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
                [formatter setDateFormat:@"EEE, dd MMM yyyy HH:mm:ss zzz"];
                NSMutableString *result = [NSMutableString string];
                [array enumerateObjectsUsingBlock:^(NSHTTPCookie *cookie, NSUInteger idx, BOOL *stop) {
                        if ([cookie.domain isEqualToString:nsurl.host]) {
                            [result appendString:[NSString stringWithFormat:@"%@=%@", cookie.name, cookie.value]];
                            if ([cookie.domain length] > 0) {
                                [result appendString:[NSString stringWithFormat:@"; "]];
                                [result appendString:[NSString stringWithFormat:@"Domain=%@", cookie.domain]];
                            }
                            if ([cookie.path length] > 0) {
                                [result appendString:[NSString stringWithFormat:@"; "]];
                                [result appendString:[NSString stringWithFormat:@"Path=%@", cookie.path]];
                            }
                            if (cookie.expiresDate != nil) {
                                [result appendString:[NSString stringWithFormat:@"; "]];
                                [result appendString:[NSString stringWithFormat:@"Expires=%@", [formatter stringFromDate:cookie.expiresDate]]];
                            }
                            [result appendString:[NSString stringWithFormat:@"; "]];
                            [result appendString:[NSString stringWithFormat:@"Version=%zd", cookie.version]];
                            [result appendString:[NSString stringWithFormat:@"\n"]];
                        }
                    }];
                UnitySendMessage([gameObjectName UTF8String], "CallOnCookies", [result UTF8String]);
            }];
    } else {
        [CWebViewPlugin resetSharedProcessPool];
        NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
        formatter.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
        [formatter setDateFormat:@"EEE, dd MMM yyyy HH:mm:ss zzz"];
        NSMutableString *result = [NSMutableString string];
        NSHTTPCookieStorage *cookieStorage = [NSHTTPCookieStorage sharedHTTPCookieStorage];
        if (cookieStorage == nil) {
            // cf. https://stackoverflow.com/questions/33876295/nshttpcookiestorage-sharedhttpcookiestorage-comes-up-empty-in-10-11
            cookieStorage = [NSHTTPCookieStorage sharedCookieStorageForGroupContainerIdentifier:@"Cookies"];
        }
        [[cookieStorage cookiesForURL:[NSURL URLWithString:[[NSString alloc] initWithUTF8String:url]]]
            enumerateObjectsUsingBlock:^(NSHTTPCookie *cookie, NSUInteger idx, BOOL *stop) {
                [result appendString:[NSString stringWithFormat:@"%@=%@", cookie.name, cookie.value]];
                if ([cookie.domain length] > 0) {
                    [result appendString:[NSString stringWithFormat:@"; "]];
                    [result appendString:[NSString stringWithFormat:@"Domain=%@", cookie.domain]];
                }
                if ([cookie.path length] > 0) {
                    [result appendString:[NSString stringWithFormat:@"; "]];
                    [result appendString:[NSString stringWithFormat:@"Path=%@", cookie.path]];
                }
                if (cookie.expiresDate != nil) {
                    [result appendString:[NSString stringWithFormat:@"; "]];
                    [result appendString:[NSString stringWithFormat:@"Expires=%@", [formatter stringFromDate:cookie.expiresDate]]];
                }
                [result appendString:[NSString stringWithFormat:@"; "]];
                [result appendString:[NSString stringWithFormat:@"Version=%zd", cookie.version]];
                [result appendString:[NSString stringWithFormat:@"\n"]];
            }];
        UnitySendMessage([gameObjectName UTF8String], "CallOnCookies", [result UTF8String]);
    }
}

- (void)userContentController:(WKUserContentController *)userContentController
      didReceiveScriptMessage:(WKScriptMessage *)message {

    // Log out the message received
    //NSLog(@"Received event %@", message.body);
    if ([message.name isEqualToString:@"unityControl"]) {
        UnitySendMessage([gameObjectName UTF8String], "CallFromJS", [[NSString stringWithFormat:@"%@", message.body] UTF8String]);
    } else if ([message.name isEqualToString:@"saveDataURL"]) {
        NSRange range = [message.body rangeOfString:@"\t"];
        if (range.location == NSNotFound) {
            return;
        }
        NSString *fileName = [[message.body substringWithRange:NSMakeRange(0, range.location)] lastPathComponent];
        NSString *dataURL = [message.body substringFromIndex:(range.location + 1)];
        range = [dataURL rangeOfString:@"data:"];
        if (range.location != 0) {
            return;
        }
        NSString *tmp = [dataURL substringFromIndex:[@"data:" length]];
        range = [tmp rangeOfString:@";"];
        if (range.location == NSNotFound) {
            return;
        }
        NSString *base64data = [tmp substringFromIndex:(range.location + 1 + [@"base64," length])];
        NSString *type = [tmp substringWithRange:NSMakeRange(0, range.location)];
        NSData *data = [[NSData alloc] initWithBase64EncodedString:base64data options:0];
        NSString *path = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES)[0];
        path = [path stringByAppendingString:@"/Downloads"];
        BOOL isDir;
        NSError *err = nil;
        if ([[NSFileManager defaultManager] fileExistsAtPath:path isDirectory:&isDir]) {
            if (!isDir) {
                return;
            }
        } else {
            [[NSFileManager defaultManager] createDirectoryAtPath:path withIntermediateDirectories:YES attributes:nil error:&err];
            if (err != nil) {
                return;
            }
        }
        NSString *prefix  = [path stringByAppendingString:@"/"];
        path = [prefix stringByAppendingString:fileName];
        int count = 0;
        while ([[NSFileManager defaultManager] fileExistsAtPath:path]) {
            count++;
            NSString *name = [fileName stringByDeletingPathExtension];
            NSString *ext = [fileName pathExtension];
            if (ext.length == 0) {
                path = [NSString stringWithFormat:@"%@%@ (%d)", prefix, name, count];
            } else {
                path = [NSString stringWithFormat:@"%@%@ (%d).%@", prefix, name, count, ext];
            }
        }
        [data writeToFile:path atomically:YES];
    }

    /*
    // Then pull something from the device using the message body
    NSString *version = [[UIDevice currentDevice] valueForKey:message.body];

    // Execute some JavaScript using the result?
    NSString *exec_template = @"set_headline(\"received: %@\");";
    NSString *exec = [NSString stringWithFormat:exec_template, version];
    [webView evaluateJavaScript:exec completionHandler:nil];
    */
}

- (void)observeValueForKeyPath:(NSString *)keyPath
                      ofObject:(id)object
                        change:(NSDictionary *)change
                       context:(void *)context {
    if (webView == nil)
        return;

    if ([keyPath isEqualToString:@"loading"] && [[change objectForKey:NSKeyValueChangeNewKey] intValue] == 0
        && [webView URL] != nil) {
        UnitySendMessage(
                         [gameObjectName UTF8String],
                         "CallOnLoaded",
                         [[[webView URL] absoluteString] UTF8String]);

    }
}

- (void)webViewWebContentProcessDidTerminate:(WKWebView *)webView
{
    UnitySendMessage([gameObjectName UTF8String], "CallOnError", "webViewWebContentProcessDidTerminate");
}

- (void)webView:(WKWebView *)webView didFailProvisionalNavigation:(WKNavigation *)navigation withError:(NSError *)error
{
    UnitySendMessage([gameObjectName UTF8String], "CallOnError", [[error description] UTF8String]);
}

- (void)webView:(WKWebView *)webView didFailNavigation:(WKNavigation *)navigation withError:(NSError *)error
{
    UnitySendMessage([gameObjectName UTF8String], "CallOnError", [[error description] UTF8String]);
}

- (WKWebView *)webView:(WKWebView *)wkWebView createWebViewWithConfiguration:(WKWebViewConfiguration *)configuration forNavigationAction:(WKNavigationAction *)navigationAction windowFeatures:(WKWindowFeatures *)windowFeatures
{
    // cf. for target="_blank", cf. http://qiita.com/ShingoFukuyama/items/b3a1441025a36ab7659c
    if (!navigationAction.targetFrame.isMainFrame) {
        [wkWebView loadRequest:navigationAction.request];
    }
    return nil;
}

- (void)webView:(WKWebView *)wkWebView decidePolicyForNavigationAction:(WKNavigationAction *)navigationAction decisionHandler:(void (^)(WKNavigationActionPolicy))decisionHandler
{
    if (webView == nil) {
        decisionHandler(WKNavigationActionPolicyCancel);
        return;
    }
    NSURL *nsurl = [navigationAction.request URL];
    NSString *url = [nsurl absoluteString];
    BOOL pass = YES;
    if (allowRegex != nil && [allowRegex firstMatchInString:url options:0 range:NSMakeRange(0, url.length)]) {
         pass = YES;
    } else if (denyRegex != nil && [denyRegex firstMatchInString:url options:0 range:NSMakeRange(0, url.length)]) {
         pass = NO;
    }
    if (!pass) {
        decisionHandler(WKNavigationActionPolicyCancel);
        return;
    }
    if ([url rangeOfString:@"//itunes.apple.com/"].location != NSNotFound) {
        [[UIApplication sharedApplication] openURL:nsurl];
        decisionHandler(WKNavigationActionPolicyCancel);
        return;
    } else if ([url hasPrefix:@"unity:"]) {
        UnitySendMessage([gameObjectName UTF8String], "CallFromJS", [[url substringFromIndex:6] UTF8String]);
        decisionHandler(WKNavigationActionPolicyCancel);
        return;
    } else if (hookRegex != nil && [hookRegex firstMatchInString:url options:0 range:NSMakeRange(0, url.length)]) {
        UnitySendMessage([gameObjectName UTF8String], "CallOnHooked", [url UTF8String]);
        decisionHandler(WKNavigationActionPolicyCancel);
        return;
    } else if (![url hasPrefix:@"about:blank"]  // for loadHTML(), cf. #365
               && ![url hasPrefix:@"about:srcdoc"] // for iframe srcdoc attribute
               && ![url hasPrefix:@"file:"]
               && ![url hasPrefix:@"http:"]
               && ![url hasPrefix:@"https:"]) {
        if([[UIApplication sharedApplication] canOpenURL:nsurl]) {
            [[UIApplication sharedApplication] openURL:nsurl];
        }
        decisionHandler(WKNavigationActionPolicyCancel);
        return;
    } else if (navigationAction.navigationType == WKNavigationTypeLinkActivated
               && (!navigationAction.targetFrame || !navigationAction.targetFrame.isMainFrame)) {
        // cf. for target="_blank", cf. http://qiita.com/ShingoFukuyama/items/b3a1441025a36ab7659c
        [webView load:navigationAction.request];
        decisionHandler(WKNavigationActionPolicyCancel);
        return;
    } else {
        if (navigationAction.targetFrame != nil && navigationAction.targetFrame.isMainFrame) {
            // If the custom header is not attached, give it and make a request again.
            if (![self isSetupedCustomHeader:[navigationAction request]]) {
                NSLog(@"navi ... %@", navigationAction);
                [wkWebView loadRequest:[self constructionCustomHeader:navigationAction.request]];
                decisionHandler(WKNavigationActionPolicyCancel);
                return;
            }
        }
    }
    UnitySendMessage([gameObjectName UTF8String], "CallOnStarted", [url UTF8String]);
    decisionHandler(WKNavigationActionPolicyAllow);
}

- (void)webView:(WKWebView *)webView decidePolicyForNavigationResponse:(WKNavigationResponse *)navigationResponse decisionHandler:(void (^)(WKNavigationResponsePolicy))decisionHandler {

    if ([navigationResponse.response isKindOfClass:[NSHTTPURLResponse class]]) {

        NSHTTPURLResponse * response = (NSHTTPURLResponse *)navigationResponse.response;
        if (response.statusCode >= 400) {
            UnitySendMessage([gameObjectName UTF8String], "CallOnHttpError", [[NSString stringWithFormat:@"%d", response.statusCode] UTF8String]);
        }

    }
    decisionHandler(WKNavigationResponsePolicyAllow);
}

// alert
- (void)webView:(WKWebView *)webView runJavaScriptAlertPanelWithMessage:(NSString *)message initiatedByFrame:(WKFrameInfo *)frame completionHandler:(void (^)(void))completionHandler
{
    if (!alertDialogEnabled) {
        completionHandler();
        return;
    }
    UIAlertController *alertController = [UIAlertController alertControllerWithTitle:@""
                                                                             message:message
                                                                      preferredStyle:UIAlertControllerStyleAlert];
    [alertController addAction: [UIAlertAction actionWithTitle:@"OK"
                                                         style:UIAlertActionStyleCancel
                                                       handler:^(UIAlertAction *action) {
                                                           completionHandler();
                                                       }]];
    [UnityGetGLViewController() presentViewController:alertController animated:YES completion:^{}];
}

// confirm
- (void)webView:(WKWebView *)webView runJavaScriptConfirmPanelWithMessage:(NSString *)message initiatedByFrame:(WKFrameInfo *)frame completionHandler:(void (^)(BOOL))completionHandler
{
    if (!alertDialogEnabled) {
        completionHandler(NO);
        return;
    }
    UIAlertController *alertController = [UIAlertController alertControllerWithTitle:@""
                                                                             message:message
                                                                      preferredStyle:UIAlertControllerStyleAlert];
    [alertController addAction:[UIAlertAction actionWithTitle:@"OK"
                                                        style:UIAlertActionStyleDefault
                                                      handler:^(UIAlertAction *action) {
                                                          completionHandler(YES);
                                                      }]];
    [alertController addAction:[UIAlertAction actionWithTitle:@"Cancel"
                                                        style:UIAlertActionStyleCancel
                                                      handler:^(UIAlertAction *action) {
                                                          completionHandler(NO);
                                                      }]];
    [UnityGetGLViewController() presentViewController:alertController animated:YES completion:^{}];
}

// prompt
- (void)webView:(WKWebView *)webView runJavaScriptTextInputPanelWithPrompt:(NSString *)prompt defaultText:(NSString *)defaultText initiatedByFrame:(WKFrameInfo *)frame completionHandler:(void (^)(NSString *))completionHandler
{
    if (!alertDialogEnabled) {
        completionHandler(nil);
        return;
    }
    UIAlertController *alertController = [UIAlertController alertControllerWithTitle:@""
                                                                             message:prompt
                                                                      preferredStyle:UIAlertControllerStyleAlert];
    [alertController addTextFieldWithConfigurationHandler:^(UITextField *textField) {
        textField.text = defaultText;
    }];
    [alertController addAction:[UIAlertAction actionWithTitle:@"OK"
                                                        style:UIAlertActionStyleDefault
                                                      handler:^(UIAlertAction *action) {
                                                          NSString *input = ((UITextField *)alertController.textFields.firstObject).text;
                                                          completionHandler(input);
                                                      }]];
    [alertController addAction:[UIAlertAction actionWithTitle:@"Cancel"
                                                        style:UIAlertActionStyleCancel
                                                      handler:^(UIAlertAction *action) {
                                                          completionHandler(nil);
                                                      }]];
    [UnityGetGLViewController() presentViewController:alertController animated:YES completion:^{}];
}

- (void)webView:(WKWebView *)webView didReceiveAuthenticationChallenge:(NSURLAuthenticationChallenge *)challenge completionHandler:(void (^)(NSURLSessionAuthChallengeDisposition, NSURLCredential *))completionHandler
{
    NSURLSessionAuthChallengeDisposition disposition;
    NSURLCredential *credential;
    if (basicAuthUserName && basicAuthPassword && [challenge previousFailureCount] == 0) {
        disposition = NSURLSessionAuthChallengeUseCredential;
        credential = [NSURLCredential credentialWithUser:basicAuthUserName password:basicAuthPassword persistence:NSURLCredentialPersistenceForSession];
    } else {
        disposition = NSURLSessionAuthChallengePerformDefaultHandling;
        credential = nil;
    }
    completionHandler(disposition, credential);
}

- (BOOL)isSetupedCustomHeader:(NSURLRequest *)targetRequest
{
    // Check for additional custom header.
    for (NSString *key in [customRequestHeader allKeys]) {
        if (![[[targetRequest allHTTPHeaderFields] objectForKey:key] isEqualToString:[customRequestHeader objectForKey:key]]) {
            return NO;
        }
    }
    return YES;
}

- (NSURLRequest *)constructionCustomHeader:(NSURLRequest *)originalRequest
{
    NSMutableURLRequest *convertedRequest = originalRequest.mutableCopy;
    for (NSString *key in [customRequestHeader allKeys]) {
        [convertedRequest setValue:customRequestHeader[key] forHTTPHeaderField:key];
    }
    return (NSURLRequest *)[convertedRequest copy];
}

- (void)setMargins:(float)left top:(float)top right:(float)right bottom:(float)bottom relative:(BOOL)relative
{
    if (webView == nil)
        return;
    UIView *view = UnityGetGLViewController().view;
    CGRect frame = webView.frame;
    CGRect screen = view.bounds;
    if (relative) {
        frame.size.width = floor(screen.size.width * (1.0f - left - right));
        frame.size.height = floor(screen.size.height * (1.0f - top - bottom));
        frame.origin.x = floor(screen.size.width * left);
        frame.origin.y = floor(screen.size.height * top);
    } else {
        CGFloat scale = 1.0f / [self getScale:view];
        frame.size.width = floor(screen.size.width - scale * (left + right));
        frame.size.height = floor(screen.size.height - scale * (top + bottom));
        frame.origin.x = floor(scale * left);
        frame.origin.y = floor(scale * top);
    }
    webView.frame = frame;
}

- (CGFloat)getScale:(UIView *)view
{
    if ([[[UIDevice currentDevice] systemVersion] floatValue] >= 8.0)
        return view.window.screen.nativeScale;
    return view.contentScaleFactor;
}

- (void)setVisibility:(BOOL)visibility
{
    if (webView == nil)
        return;
    webView.hidden = visibility ? NO : YES;
}

- (void)setInteractionEnabled:(BOOL)enabled
{
    if (webView == nil)
        return;
    webView.userInteractionEnabled = enabled;
}

- (void)setAlertDialogEnabled:(BOOL)enabled
{
    alertDialogEnabled = enabled;
}

- (void)setScrollbarsVisibility:(BOOL)visibility
{
    if (webView == nil)
        return;
    [webView setScrollbarsVisibility:visibility];
}

- (void)setScrollBounceEnabled:(BOOL)enabled
{
    if (webView == nil)
        return;
    [webView setScrollBounce:enabled];
}

- (BOOL)setURLPattern:(const char *)allowPattern and:(const char *)denyPattern and:(const char *)hookPattern
{
    NSError *err = nil;
    NSRegularExpression *allow = nil;
    NSRegularExpression *deny = nil;
    NSRegularExpression *hook = nil;
    if (allowPattern == nil || *allowPattern == '\0') {
        allow = nil;
    } else {
        allow
            = [NSRegularExpression
                regularExpressionWithPattern:[NSString stringWithUTF8String:allowPattern]
                                     options:0
                                       error:&err];
        if (err != nil) {
            return NO;
        }
    }
    if (denyPattern == nil || *denyPattern == '\0') {
        deny = nil;
    } else {
        deny
            = [NSRegularExpression
                regularExpressionWithPattern:[NSString stringWithUTF8String:denyPattern]
                                     options:0
                                       error:&err];
        if (err != nil) {
            return NO;
        }
    }
    if (hookPattern == nil || *hookPattern == '\0') {
        hook = nil;
    } else {
        hook
            = [NSRegularExpression
                regularExpressionWithPattern:[NSString stringWithUTF8String:hookPattern]
                                     options:0
                                       error:&err];
        if (err != nil) {
            return NO;
        }
    }
    allowRegex = allow;
    denyRegex = deny;
    hookRegex = hook;
    return YES;
}

- (void)loadURL:(const char *)url
{
    if (webView == nil)
        return;
    NSString *urlStr = [NSString stringWithUTF8String:url];
    NSURL *nsurl = [NSURL URLWithString:urlStr];
    NSURLRequest *request = [NSURLRequest requestWithURL:nsurl];
    [webView load:request];
}

- (void)loadHTML:(const char *)html baseURL:(const char *)baseUrl
{
    if (webView == nil)
        return;
    NSString *htmlStr = [NSString stringWithUTF8String:html];
    NSString *baseStr = [NSString stringWithUTF8String:baseUrl];
    NSURL *baseNSUrl = [NSURL URLWithString:baseStr];
    [webView loadHTML:htmlStr baseURL:baseNSUrl];
}

- (void)evaluateJS:(const char *)js
{
    if (webView == nil)
        return;
    NSString *jsStr = [NSString stringWithUTF8String:js];
    [webView evaluateJavaScript:jsStr completionHandler:^(NSString *result, NSError *error) {}];
}

- (int)progress
{
    if (webView == nil)
        return 0;
    if ([webView isKindOfClass:[WKWebView class]]) {
        return (int)([(WKWebView *)webView estimatedProgress] * 100);
    } else {
        return 0;
    }
}

- (BOOL)canGoBack
{
    if (webView == nil)
        return false;
    return [webView canGoBack];
}

- (BOOL)canGoForward
{
    if (webView == nil)
        return false;
    return [webView canGoForward];
}

- (void)goBack
{
    if (webView == nil)
        return;
    [webView goBack];
}

- (void)goForward
{
    if (webView == nil)
        return;
    [webView goForward];
}

- (void)reload
{
    if (webView == nil)
        return;
    [webView reload];
}

- (void)addCustomRequestHeader:(const char *)headerKey value:(const char *)headerValue
{
    NSString *keyString = [NSString stringWithUTF8String:headerKey];
    NSString *valueString = [NSString stringWithUTF8String:headerValue];

    [customRequestHeader setObject:valueString forKey:keyString];
}

- (void)removeCustomRequestHeader:(const char *)headerKey
{
    NSString *keyString = [NSString stringWithUTF8String:headerKey];

    if ([[customRequestHeader allKeys]containsObject:keyString]) {
        [customRequestHeader removeObjectForKey:keyString];
    }
}

- (void)clearCustomRequestHeader
{
    [customRequestHeader removeAllObjects];
}

- (const char *)getCustomRequestHeaderValue:(const char *)headerKey
{
    NSString *keyString = [NSString stringWithUTF8String:headerKey];
    NSString *result = [customRequestHeader objectForKey:keyString];
    if (!result) {
        return NULL;
    }

    const char *s = [result UTF8String];
    char *r = (char *)malloc(strlen(s) + 1);
    strcpy(r, s);
    return r;
}

- (void)setBasicAuthInfo:(const char *)userName password:(const char *)password
{
    basicAuthUserName = [NSString stringWithUTF8String:userName];
    basicAuthPassword = [NSString stringWithUTF8String:password];
}

- (void)clearCache:(BOOL)includeDiskFiles
{
    if (webView == nil)
        return;
    NSMutableSet *types = [NSMutableSet setWithArray:@[WKWebsiteDataTypeMemoryCache]];
    if (includeDiskFiles) {
        [types addObject:WKWebsiteDataTypeDiskCache];
    }
    NSDate *date = [NSDate dateWithTimeIntervalSince1970:0];
    [[WKWebsiteDataStore defaultDataStore] removeDataOfTypes:types modifiedSince:date completionHandler:^{}];
}

- (void)setAllMediaPlaybackSuspended:(BOOL)suspended
{
    NSOperatingSystemVersion version = { 15, 0, 0 };
    if ([[NSProcessInfo processInfo] isOperatingSystemAtLeastVersion:version]) {
        if ([webView isKindOfClass:[WKWebView class]]) {
            [(WKWebView *)webView setAllMediaPlaybackSuspended:suspended completionHandler:nil];
        }
    }
}
@end

extern "C" {
    void *_CWebViewPlugin_Init(const char *gameObjectName, BOOL transparent, BOOL zoom, const char *ua, BOOL enableWKWebView, int contentMode, BOOL allowsLinkPreview, BOOL allowsBackForwardNavigationGestures, int radius);
    void _CWebViewPlugin_Destroy(void *instance);
    void _CWebViewPlugin_SetMargins(
        void *instance, float left, float top, float right, float bottom, BOOL relative);
    void _CWebViewPlugin_SetVisibility(void *instance, BOOL visibility);
    void _CWebViewPlugin_SetInteractionEnabled(void *instance, BOOL enabled);
    void _CWebViewPlugin_SetAlertDialogEnabled(void *instance, BOOL visibility);
    void _CWebViewPlugin_SetScrollbarsVisibility(void *instance, BOOL visibility);
    void _CWebViewPlugin_SetScrollBounceEnabled(void *instance, BOOL enabled);
    BOOL _CWebViewPlugin_SetURLPattern(void *instance, const char *allowPattern, const char *denyPattern, const char *hookPattern);
    void _CWebViewPlugin_LoadURL(void *instance, const char *url);
    void _CWebViewPlugin_LoadHTML(void *instance, const char *html, const char *baseUrl);
    void _CWebViewPlugin_EvaluateJS(void *instance, const char *url);
    int _CWebViewPlugin_Progress(void *instance);
    BOOL _CWebViewPlugin_CanGoBack(void *instance);
    BOOL _CWebViewPlugin_CanGoForward(void *instance);
    void _CWebViewPlugin_GoBack(void *instance);
    void _CWebViewPlugin_GoForward(void *instance);
    void _CWebViewPlugin_Reload(void *instance);
    void _CWebViewPlugin_AddCustomHeader(void *instance, const char *headerKey, const char *headerValue);
    void _CWebViewPlugin_RemoveCustomHeader(void *instance, const char *headerKey);
    void _CWebViewPlugin_ClearCustomHeader(void *instance);
    void _CWebViewPlugin_ClearCookies();
    void _CWebViewPlugin_SaveCookies();
    void _CWebViewPlugin_GetCookies(void *instance, const char *url);
    const char *_CWebViewPlugin_GetCustomHeaderValue(void *instance, const char *headerKey);
    void _CWebViewPlugin_SetBasicAuthInfo(void *instance, const char *userName, const char *password);
    void _CWebViewPlugin_ClearCache(void *instance, BOOL includeDiskFiles);
    void _CWebViewPlugin_SetSuspended(void *instance, BOOL suspended);
}

void *_CWebViewPlugin_Init(const char *gameObjectName, BOOL transparent, BOOL zoom, const char *ua, BOOL enableWKWebView, int contentMode, BOOL allowsLinkPreview, BOOL allowsBackForwardNavigationGestures, int radius)
{
    if (! (enableWKWebView && [WKWebView class]))
        return nil;
    WKContentMode wkContentMode = WKContentModeRecommended;
    switch (contentMode) {
    case 1:
        wkContentMode = WKContentModeMobile;
        break;
    case 2:
        wkContentMode = WKContentModeDesktop;
        break;
    default:
        wkContentMode = WKContentModeRecommended;
        break;
    }
    CWebViewPlugin *webViewPlugin = [[CWebViewPlugin alloc] initWithGameObjectName:gameObjectName transparent:transparent zoom:zoom ua:ua enableWKWebView:enableWKWebView contentMode:wkContentMode allowsLinkPreview:allowsLinkPreview allowsBackForwardNavigationGestures:allowsBackForwardNavigationGestures radius:radius];
    [_instances addObject:webViewPlugin];
    return (__bridge_retained void *)webViewPlugin;
}

void _CWebViewPlugin_Destroy(void *instance)
{
    if (instance == NULL)
        return;
    CWebViewPlugin *webViewPlugin = (__bridge_transfer CWebViewPlugin *)instance;
    [_instances removeObject:webViewPlugin];
    [webViewPlugin dispose];
    webViewPlugin = nil;
}

void _CWebViewPlugin_SetMargins(
    void *instance, float left, float top, float right, float bottom, BOOL relative)
{
    if (instance == NULL)
        return;
    CWebViewPlugin *webViewPlugin = (__bridge CWebViewPlugin *)instance;
    [webViewPlugin setMargins:left top:top right:right bottom:bottom relative:relative];
}

void _CWebViewPlugin_SetVisibility(void *instance, BOOL visibility)
{
    if (instance == NULL)
        return;
    CWebViewPlugin *webViewPlugin = (__bridge CWebViewPlugin *)instance;
    [webViewPlugin setVisibility:visibility];
}

void _CWebViewPlugin_SetInteractionEnabled(void *instance, BOOL enabled)
{
    if (instance == NULL)
        return;
    CWebViewPlugin *webViewPlugin = (__bridge CWebViewPlugin *)instance;
    [webViewPlugin setInteractionEnabled:enabled];
}

void _CWebViewPlugin_SetAlertDialogEnabled(void *instance, BOOL enabled)
{
    if (instance == NULL)
        return;
    CWebViewPlugin *webViewPlugin = (__bridge CWebViewPlugin *)instance;
    [webViewPlugin setAlertDialogEnabled:enabled];
}

void _CWebViewPlugin_SetScrollbarsVisibility(void *instance, BOOL visibility)
{
    if (instance == NULL)
        return;
    CWebViewPlugin *webViewPlugin = (__bridge CWebViewPlugin *)instance;
    [webViewPlugin setScrollbarsVisibility:visibility];
}

void _CWebViewPlugin_SetScrollBounceEnabled(void *instance, BOOL enabled)
{
    if (instance == NULL)
        return;
    CWebViewPlugin *webViewPlugin = (__bridge CWebViewPlugin *)instance;
    [webViewPlugin setScrollBounceEnabled:enabled];
}

BOOL _CWebViewPlugin_SetURLPattern(void *instance, const char *allowPattern, const char *denyPattern, const char *hookPattern)
{
    if (instance == NULL)
        return NO;
    CWebViewPlugin *webViewPlugin = (__bridge CWebViewPlugin *)instance;
    return [webViewPlugin setURLPattern:allowPattern and:denyPattern and:hookPattern];
}

void _CWebViewPlugin_LoadURL(void *instance, const char *url)
{
    if (instance == NULL)
        return;
    CWebViewPlugin *webViewPlugin = (__bridge CWebViewPlugin *)instance;
    [webViewPlugin loadURL:url];
}

void _CWebViewPlugin_LoadHTML(void *instance, const char *html, const char *baseUrl)
{
    if (instance == NULL)
        return;
    CWebViewPlugin *webViewPlugin = (__bridge CWebViewPlugin *)instance;
    [webViewPlugin loadHTML:html baseURL:baseUrl];
}

void _CWebViewPlugin_EvaluateJS(void *instance, const char *js)
{
    if (instance == NULL)
        return;
    CWebViewPlugin *webViewPlugin = (__bridge CWebViewPlugin *)instance;
    [webViewPlugin evaluateJS:js];
}

int _CWebViewPlugin_Progress(void *instance)
{
    if (instance == NULL)
        return 0;
    CWebViewPlugin *webViewPlugin = (__bridge CWebViewPlugin *)instance;
    return [webViewPlugin progress];
}

BOOL _CWebViewPlugin_CanGoBack(void *instance)
{
    if (instance == NULL)
        return false;
    CWebViewPlugin *webViewPlugin = (__bridge CWebViewPlugin *)instance;
    return [webViewPlugin canGoBack];
}

BOOL _CWebViewPlugin_CanGoForward(void *instance)
{
    if (instance == NULL)
        return false;
    CWebViewPlugin *webViewPlugin = (__bridge CWebViewPlugin *)instance;
    return [webViewPlugin canGoForward];
}

void _CWebViewPlugin_GoBack(void *instance)
{
    if (instance == NULL)
        return;
    CWebViewPlugin *webViewPlugin = (__bridge CWebViewPlugin *)instance;
    [webViewPlugin goBack];
}

void _CWebViewPlugin_GoForward(void *instance)
{
    if (instance == NULL)
        return;
    CWebViewPlugin *webViewPlugin = (__bridge CWebViewPlugin *)instance;
    [webViewPlugin goForward];
}

void _CWebViewPlugin_Reload(void *instance)
{
    if (instance == NULL)
        return;
    CWebViewPlugin *webViewPlugin = (__bridge CWebViewPlugin *)instance;
    [webViewPlugin reload];
}

void _CWebViewPlugin_AddCustomHeader(void *instance, const char *headerKey, const char *headerValue)
{
    if (instance == NULL)
        return;
    CWebViewPlugin *webViewPlugin = (__bridge CWebViewPlugin *)instance;
    [webViewPlugin addCustomRequestHeader:headerKey value:headerValue];
}

void _CWebViewPlugin_RemoveCustomHeader(void *instance, const char *headerKey)
{
    if (instance == NULL)
        return;
    CWebViewPlugin *webViewPlugin = (__bridge CWebViewPlugin *)instance;
    [webViewPlugin removeCustomRequestHeader:headerKey];
}

void _CWebViewPlugin_ClearCustomHeader(void *instance)
{
    if (instance == NULL)
        return;
    CWebViewPlugin *webViewPlugin = (__bridge CWebViewPlugin *)instance;
    [webViewPlugin clearCustomRequestHeader];
}

void _CWebViewPlugin_ClearCookies()
{
    [CWebViewPlugin clearCookies];
}

void _CWebViewPlugin_SaveCookies()
{
    [CWebViewPlugin saveCookies];
}

void _CWebViewPlugin_GetCookies(void *instance, const char *url)
{
    CWebViewPlugin *webViewPlugin = (__bridge CWebViewPlugin *)instance;
    [webViewPlugin getCookies:url];
}

const char *_CWebViewPlugin_GetCustomHeaderValue(void *instance, const char *headerKey)
{
    if (instance == NULL)
        return NULL;
    CWebViewPlugin *webViewPlugin = (__bridge CWebViewPlugin *)instance;
    return [webViewPlugin getCustomRequestHeaderValue:headerKey];
}

void _CWebViewPlugin_SetBasicAuthInfo(void *instance, const char *userName, const char *password)
{
    if (instance == NULL)
        return;
    CWebViewPlugin *webViewPlugin = (__bridge CWebViewPlugin *)instance;
    [webViewPlugin setBasicAuthInfo:userName password:password];
}

void _CWebViewPlugin_ClearCache(void *instance, BOOL includeDiskFiles)
{
    if (instance == NULL)
        return;
    CWebViewPlugin *webViewPlugin = (__bridge CWebViewPlugin *)instance;
    [webViewPlugin clearCache:includeDiskFiles];
}

void _CWebViewPlugin_SetSuspended(void *instance, BOOL suspended)
{
    if (instance == NULL)
        return;
    CWebViewPlugin *webViewPlugin = (__bridge CWebViewPlugin *)instance;
    [webViewPlugin setAllMediaPlaybackSuspended:suspended];
}
#endif // !(__IPHONE_OS_VERSION_MIN_REQUIRED < __IPHONE_9_0)
