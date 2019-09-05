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

#if __IPHONE_OS_VERSION_MIN_REQUIRED < __IPHONE_9_0

#import <UIKit/UIKit.h>
#import <WebKit/WebKit.h>

// NOTE: we need extern without "C" before unity 4.5
//extern UIViewController *UnityGetGLViewController();
extern "C" UIViewController *UnityGetGLViewController();
extern "C" void UnitySendMessage(const char *, const char *, const char *);

@protocol WebViewProtocol <NSObject>
@property (nonatomic, getter=isOpaque) BOOL opaque;
@property (nullable, nonatomic, copy) UIColor *backgroundColor UI_APPEARANCE_SELECTOR;
@property (nonatomic, getter=isHidden) BOOL hidden;
@property (nonatomic) CGRect frame;
@property (nullable, nonatomic, assign) id <UIWebViewDelegate> delegate;
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
- (void)stopLoading;
@end

@interface WKWebView(WebViewProtocolConformed) <WebViewProtocol>
@end

@implementation WKWebView(WebViewProtocolConformed)

@dynamic delegate;

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

@end

@interface UIWebView(WebViewProtocolConformed) <WebViewProtocol>
@end

@implementation UIWebView(WebViewProtocolConformed)

@dynamic navigationDelegate;
@dynamic UIDelegate;

- (NSURL *)URL
{
    return [NSURL URLWithString:[self stringByEvaluatingJavaScriptFromString:@"document.URL"]];
}

- (void)load:(NSURLRequest *)request
{
    UIWebView *webView = (UIWebView *)self;
    [webView loadRequest:request];
}

- (void)loadHTML:(NSString *)html baseURL:(NSURL *)baseUrl
{
    UIWebView *webView = (UIWebView *)self;
    [webView loadHTMLString:html baseURL:baseUrl];
}

- (void)evaluateJavaScript:(NSString *)javaScriptString completionHandler:(void (^ __nullable)(__nullable id, NSError * __nullable error))completionHandler
{
    NSString *result = [self stringByEvaluatingJavaScriptFromString:javaScriptString];
    if (completionHandler) {
        completionHandler(result, nil);
    }
}

@end

@interface CWebViewPlugin : NSObject<UIWebViewDelegate, WKUIDelegate, WKNavigationDelegate, WKScriptMessageHandler>
{
    UIView <WebViewProtocol> *webView;
    NSString *gameObjectName;
    NSMutableDictionary *customRequestHeader;
}
- (void)dispose;
+ (void)clearCookies;
@end

@implementation CWebViewPlugin

static WKProcessPool *_sharedProcessPool;
static NSMutableArray *_instances = [[NSMutableArray alloc] init];

- (id)initWithGameObjectName:(const char *)gameObjectName_ transparent:(BOOL)transparent ua:(const char *)ua enableWKWebView:(BOOL)enableWKWebView
{
    self = [super init];

    gameObjectName = [NSString stringWithUTF8String:gameObjectName_];
    customRequestHeader = [[NSMutableDictionary alloc] init];
    if (ua != NULL && strcmp(ua, "") != 0) {
        [[NSUserDefaults standardUserDefaults]
            registerDefaults:@{ @"UserAgent": [[NSString alloc] initWithUTF8String:ua] }];
    }
    UIView *view = UnityGetGLViewController().view;
    if (enableWKWebView && [WKWebView class]) {
        if (_sharedProcessPool == NULL) {
            _sharedProcessPool = [[WKProcessPool alloc] init];
        }
        WKWebViewConfiguration *configuration = [[WKWebViewConfiguration alloc] init];
        WKUserContentController *controller = [[WKUserContentController alloc] init];
        [controller addScriptMessageHandler:self name:@"unityControl"];
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
        webView = [[WKWebView alloc] initWithFrame:view.frame configuration:configuration];
        webView.UIDelegate = self;
        webView.navigationDelegate = self;
    } else {
        UIWebView *uiwebview = [[UIWebView alloc] initWithFrame:view.frame];
        uiwebview.allowsInlineMediaPlayback = YES;
        uiwebview.mediaPlaybackRequiresUserAction = NO;
        webView = uiwebview;
        webView.delegate = self;
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
    UIView <WebViewProtocol> *webView0 = webView;
    webView = nil;
    if ([webView0 isKindOfClass:[WKWebView class]]) {
        webView0.UIDelegate = nil;
        webView0.navigationDelegate = nil;
    } else {
        webView0.delegate = nil;
    }
    [webView0 stopLoading];
    [webView0 removeFromSuperview];
    [webView0 removeObserver:self forKeyPath:@"loading"];
    customRequestHeader = nil;
    gameObjectName = nil;
}

+ (void)clearCookies
{
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
        NSSet *websiteDataTypes = [WKWebsiteDataStore allWebsiteDataTypes];
        NSDate *date = [NSDate dateWithTimeIntervalSince1970:0];
        [[WKWebsiteDataStore defaultDataStore] removeDataOfTypes:websiteDataTypes
                                                   modifiedSince:date
                                               completionHandler:^{}];
    }
}

+ (const char *)getCookies:(const char *)url
{
    // cf. https://stackoverflow.com/questions/33156567/getting-all-cookies-from-wkwebview/49744695#49744695
    _sharedProcessPool = [[WKProcessPool alloc] init];
    [_instances enumerateObjectsUsingBlock:^(CWebViewPlugin *obj, NSUInteger idx, BOOL *stop) {
        if ([obj->webView isKindOfClass:[WKWebView class]]) {
            WKWebView *webView = (WKWebView *)obj->webView;
            webView.configuration.processPool = _sharedProcessPool;
        }
    }];
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
    const char *s = [result UTF8String];
    char *r = (char *)malloc(strlen(s) + 1);
    strcpy(r, s);
    return r;
}

- (void)userContentController:(WKUserContentController *)userContentController
      didReceiveScriptMessage:(WKScriptMessage *)message {

    // Log out the message received
    NSLog(@"Received event %@", message.body);
    UnitySendMessage([gameObjectName UTF8String], "CallFromJS",
                     [[NSString stringWithFormat:@"%@", message.body] UTF8String]);

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

- (void)webView:(UIWebView *)uiWebView didFailLoadWithError:(NSError *)error
{
    UnitySendMessage([gameObjectName UTF8String], "CallOnError", [[error description] UTF8String]);
}

- (void)webView:(WKWebView *)webView didFailProvisionalNavigation:(WKNavigation *)navigation withError:(NSError *)error
{
    UnitySendMessage([gameObjectName UTF8String], "CallOnError", [[error description] UTF8String]);
}

- (void)webView:(WKWebView *)webView didFailNavigation:(WKNavigation *)navigation withError:(NSError *)error
{
    UnitySendMessage([gameObjectName UTF8String], "CallOnError", [[error description] UTF8String]);
}

- (void)webViewDidFinishLoad:(UIWebView *)uiWebView {
    if (webView == nil)
        return;
    // cf. http://stackoverflow.com/questions/10996028/uiwebview-when-did-a-page-really-finish-loading/15916853#15916853
    if ([[uiWebView stringByEvaluatingJavaScriptFromString:@"document.readyState"] isEqualToString:@"complete"]
        && [webView URL] != nil) {
        UnitySendMessage(
            [gameObjectName UTF8String],
            "CallOnLoaded",
            [[[webView URL] absoluteString] UTF8String]);
    }
}

- (BOOL)webView:(UIWebView *)uiWebView shouldStartLoadWithRequest:(NSURLRequest *)request navigationType:(UIWebViewNavigationType)navigationType
{
    if (webView == nil)
        return YES;

    NSString *url = [[request URL] absoluteString];
    if ([url hasPrefix:@"unity:"]) {
        UnitySendMessage([gameObjectName UTF8String], "CallFromJS", [[url substringFromIndex:6] UTF8String]);
        return NO;
    } else {
        if (![self isSetupedCustomHeader:request]) {
            [uiWebView loadRequest:[self constructionCustomHeader:request]];
            return NO;
        }
        UnitySendMessage([gameObjectName UTF8String], "CallOnStarted", [url UTF8String]);
        return YES;
    }
}

- (void)webView:(WKWebView *)wkWebView decidePolicyForNavigationAction:(WKNavigationAction *)navigationAction decisionHandler:(void (^)(WKNavigationActionPolicy))decisionHandler
{
    if (webView == nil) {
        decisionHandler(WKNavigationActionPolicyCancel);
        return;
    }
    NSURL *nsurl = [navigationAction.request URL];
    NSString *url = [nsurl absoluteString];
    if ([url rangeOfString:@"//itunes.apple.com/"].location != NSNotFound) {
        [[UIApplication sharedApplication] openURL:nsurl];
        decisionHandler(WKNavigationActionPolicyCancel);
        return;
    } else if ([url hasPrefix:@"unity:"]) {
        UnitySendMessage([gameObjectName UTF8String], "CallFromJS", [[url substringFromIndex:6] UTF8String]);
        decisionHandler(WKNavigationActionPolicyCancel);
        return;
    } else if (![url hasPrefix:@"about:blank"]  // for loadHTML(), cf. #365
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

- (BOOL)isSetupedCustomHeader:(NSURLRequest *)targetRequest
{
    // Check for additional custom header.
    for (NSString *key in [customRequestHeader allKeys])
    {
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

- (void)setFrame:(NSInteger)x positionY:(NSInteger)y width:(NSInteger)width height:(NSInteger)height
{
    if (webView == nil)
        return;
    UIView* view = UnityGetGLViewController().view;
    CGRect frame = webView.frame;
    CGRect screen = view.bounds;
    frame.origin.x = x + ((screen.size.width - width) / 2);
    frame.origin.y = -y + ((screen.size.height - height) / 2);
    frame.size.width = width;
    frame.size.height = height;
    webView.frame = frame;
}

- (void)setMargins:(float)left top:(float)top right:(float)right bottom:(float)bottom relative:(BOOL)relative
{
    if (webView == nil)
        return;
    UIView *view = UnityGetGLViewController().view;
    CGRect frame = webView.frame;
    CGRect screen = view.bounds;
    if (relative) {
        frame.size.width = screen.size.width * (1.0f - left - right);
        frame.size.height = screen.size.height * (1.0f - top - bottom);
        frame.origin.x = screen.size.width * left;
        frame.origin.y = screen.size.height * top;
    } else {
        CGFloat scale = 1.0f / [self getScale:view];
        frame.size.width = screen.size.width - scale * (left + right) ;
        frame.size.height = screen.size.height - scale * (top + bottom) ;
        frame.origin.x = scale * left ;
        frame.origin.y = scale * top ;
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
@end

extern "C" {
    void *_CWebViewPlugin_Init(const char *gameObjectName, BOOL transparent, const char *ua, BOOL enableWKWebView);
    void _CWebViewPlugin_Destroy(void *instance);
    void _CWebViewPlugin_SetFrame(void* instace, int x, int y, int width, int height);
    void _CWebViewPlugin_SetMargins(
        void *instance, float left, float top, float right, float bottom, BOOL relative);
    void _CWebViewPlugin_SetVisibility(void *instance, BOOL visibility);
    void _CWebViewPlugin_LoadURL(void *instance, const char *url);
    void _CWebViewPlugin_LoadHTML(void *instance, const char *html, const char *baseUrl);
    void _CWebViewPlugin_EvaluateJS(void *instance, const char *url);
    int _CWebViewPlugin_Progress(void *instance);
    BOOL _CWebViewPlugin_CanGoBack(void *instance);
    BOOL _CWebViewPlugin_CanGoForward(void *instance);
    void _CWebViewPlugin_GoBack(void *instance);
    void _CWebViewPlugin_GoForward(void *instance);
    void _CWebViewPlugin_AddCustomHeader(void *instance, const char *headerKey, const char *headerValue);
    void _CWebViewPlugin_RemoveCustomHeader(void *instance, const char *headerKey);
    void _CWebViewPlugin_ClearCustomHeader(void *instance);
    void _CWebViewPlugin_ClearCookies();
    const char *_CWebViewPlugin_GetCookies(const char *url);
    const char *_CWebViewPlugin_GetCustomHeaderValue(void *instance, const char *headerKey);
}

void *_CWebViewPlugin_Init(const char *gameObjectName, BOOL transparent, const char *ua, BOOL enableWKWebView)
{
    CWebViewPlugin *webViewPlugin = [[CWebViewPlugin alloc] initWithGameObjectName:gameObjectName transparent:transparent ua:ua enableWKWebView:enableWKWebView];
    [_instances addObject:webViewPlugin];
    return (__bridge_retained void *)webViewPlugin;
}

void _CWebViewPlugin_Destroy(void *instance)
{
    CWebViewPlugin *webViewPlugin = (__bridge_transfer CWebViewPlugin *)instance;
    [_instances removeObject:webViewPlugin];
    [webViewPlugin dispose];
    webViewPlugin = nil;
}

void _CWebViewPlugin_SetFrame(void* instance, int x, int y, int width, int height)
{
    float screenScale = [UIScreen instancesRespondToSelector:@selector(scale)] ? [UIScreen mainScreen].scale : 1.0f;
    CWebViewPlugin* webViewPlugin = (__bridge CWebViewPlugin*)instance;
    if (UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad && screenScale == 2.0f)
        screenScale = 1.0f;
    [webViewPlugin
        setFrame:x / screenScale
        positionY:y / screenScale
        width:width / screenScale
        height:height / screenScale];
}

void _CWebViewPlugin_SetMargins(
    void *instance, float left, float top, float right, float bottom, BOOL relative)
{
    CWebViewPlugin *webViewPlugin = (__bridge CWebViewPlugin *)instance;
    [webViewPlugin setMargins:left top:top right:right bottom:bottom relative:relative];
}

void _CWebViewPlugin_SetVisibility(void *instance, BOOL visibility)
{
    CWebViewPlugin *webViewPlugin = (__bridge CWebViewPlugin *)instance;
    [webViewPlugin setVisibility:visibility];
}

void _CWebViewPlugin_LoadURL(void *instance, const char *url)
{
    CWebViewPlugin *webViewPlugin = (__bridge CWebViewPlugin *)instance;
    [webViewPlugin loadURL:url];
}

void _CWebViewPlugin_LoadHTML(void *instance, const char *html, const char *baseUrl)
{
    CWebViewPlugin *webViewPlugin = (__bridge CWebViewPlugin *)instance;
    [webViewPlugin loadHTML:html baseURL:baseUrl];
}

void _CWebViewPlugin_EvaluateJS(void *instance, const char *js)
{
    CWebViewPlugin *webViewPlugin = (__bridge CWebViewPlugin *)instance;
    [webViewPlugin evaluateJS:js];
}

int _CWebViewPlugin_Progress(void *instance)
{
    CWebViewPlugin *webViewPlugin = (__bridge CWebViewPlugin *)instance;
    return [webViewPlugin progress];
}

BOOL _CWebViewPlugin_CanGoBack(void *instance)
{
    CWebViewPlugin *webViewPlugin = (__bridge CWebViewPlugin *)instance;
    return [webViewPlugin canGoBack];
}

BOOL _CWebViewPlugin_CanGoForward(void *instance)
{
    CWebViewPlugin *webViewPlugin = (__bridge CWebViewPlugin *)instance;
    return [webViewPlugin canGoForward];
}

void _CWebViewPlugin_GoBack(void *instance)
{
    CWebViewPlugin *webViewPlugin = (__bridge CWebViewPlugin *)instance;
    [webViewPlugin goBack];
}

void _CWebViewPlugin_GoForward(void *instance)
{
    CWebViewPlugin *webViewPlugin = (__bridge CWebViewPlugin *)instance;
    [webViewPlugin goForward];
}

void _CWebViewPlugin_AddCustomHeader(void *instance, const char *headerKey, const char *headerValue)
{
    CWebViewPlugin *webViewPlugin = (__bridge CWebViewPlugin *)instance;
    [webViewPlugin addCustomRequestHeader:headerKey value:headerValue];
}

void _CWebViewPlugin_RemoveCustomHeader(void *instance, const char *headerKey)
{
    CWebViewPlugin *webViewPlugin = (__bridge CWebViewPlugin *)instance;
    [webViewPlugin removeCustomRequestHeader:headerKey];
}

void _CWebViewPlugin_ClearCustomHeader(void *instance)
{
    CWebViewPlugin *webViewPlugin = (__bridge CWebViewPlugin *)instance;
    [webViewPlugin clearCustomRequestHeader];
}

void _CWebViewPlugin_ClearCookies()
{
    [CWebViewPlugin clearCookies];
}

const char *_CWebViewPlugin_GetCookies(const char *url)
{
    return [CWebViewPlugin getCookies:url];
}

const char *_CWebViewPlugin_GetCustomHeaderValue(void *instance, const char *headerKey)
{
    CWebViewPlugin *webViewPlugin = (__bridge CWebViewPlugin *)instance;
    return [webViewPlugin getCustomRequestHeaderValue:headerKey];
}

#else // __IPHONE_OS_VERSION_MIN_REQUIRED < __IPHONE_9_0

#import <UIKit/UIKit.h>
#import <WebKit/WebKit.h>

// NOTE: we need extern without "C" before unity 4.5
//extern UIViewController *UnityGetGLViewController();
extern "C" UIViewController *UnityGetGLViewController();
extern "C" void UnitySendMessage(const char *, const char *, const char *);

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
- (void)stopLoading;
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

@end

@interface CWebViewPlugin : NSObject<WKUIDelegate, WKNavigationDelegate, WKScriptMessageHandler>
{
    UIView <WebViewProtocol> *webView;
    NSString *gameObjectName;
    NSMutableDictionary *customRequestHeader;
}
- (void)dispose;
+ (void)clearCookies;
@end

@implementation CWebViewPlugin

static WKProcessPool *_sharedProcessPool;
static NSMutableArray *_instances = [[NSMutableArray alloc] init];

- (id)initWithGameObjectName:(const char *)gameObjectName_ transparent:(BOOL)transparent ua:(const char *)ua enableWKWebView:(BOOL)enableWKWebView
{
    self = [super init];

    gameObjectName = [NSString stringWithUTF8String:gameObjectName_];
    customRequestHeader = [[NSMutableDictionary alloc] init];
    if (ua != NULL && strcmp(ua, "") != 0) {
        [[NSUserDefaults standardUserDefaults]
            registerDefaults:@{ @"UserAgent": [[NSString alloc] initWithUTF8String:ua] }];
    }
    UIView *view = UnityGetGLViewController().view;
    if (enableWKWebView && [WKWebView class]) {
        if (_sharedProcessPool == NULL) {
            _sharedProcessPool = [[WKProcessPool alloc] init];
        }
        WKWebViewConfiguration *configuration = [[WKWebViewConfiguration alloc] init];
        WKUserContentController *controller = [[WKUserContentController alloc] init];
        [controller addScriptMessageHandler:self name:@"unityControl"];
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
        webView = [[WKWebView alloc] initWithFrame:view.frame configuration:configuration];
        webView.UIDelegate = self;
        webView.navigationDelegate = self;
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
        }
        [webView0 stopLoading];
        [webView0 removeFromSuperview];
        [webView0 removeObserver:self forKeyPath:@"loading"];
    }
    customRequestHeader = nil;
    gameObjectName = nil;
}

+ (void)clearCookies
{
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
        NSSet *websiteDataTypes = [WKWebsiteDataStore allWebsiteDataTypes];
        NSDate *date = [NSDate dateWithTimeIntervalSince1970:0];
        [[WKWebsiteDataStore defaultDataStore] removeDataOfTypes:websiteDataTypes
                                                   modifiedSince:date
                                               completionHandler:^{}];
    }
}

+ (const char *)getCookies:(const char *)url
{
    // cf. https://stackoverflow.com/questions/33156567/getting-all-cookies-from-wkwebview/49744695#49744695
    _sharedProcessPool = [[WKProcessPool alloc] init];
    [_instances enumerateObjectsUsingBlock:^(CWebViewPlugin *obj, NSUInteger idx, BOOL *stop) {
        if ([obj->webView isKindOfClass:[WKWebView class]]) {
            WKWebView *webView = (WKWebView *)obj->webView;
            webView.configuration.processPool = _sharedProcessPool;
        }
    }];
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
    const char *s = [result UTF8String];
    char *r = (char *)malloc(strlen(s) + 1);
    strcpy(r, s);
    return r;
}

- (void)userContentController:(WKUserContentController *)userContentController
      didReceiveScriptMessage:(WKScriptMessage *)message {

    // Log out the message received
    NSLog(@"Received event %@", message.body);
    UnitySendMessage([gameObjectName UTF8String], "CallFromJS",
                     [[NSString stringWithFormat:@"%@", message.body] UTF8String]);

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

- (void)webView:(WKWebView *)webView didFailProvisionalNavigation:(WKNavigation *)navigation withError:(NSError *)error
{
    UnitySendMessage([gameObjectName UTF8String], "CallOnError", [[error description] UTF8String]);
}

- (void)webView:(WKWebView *)webView didFailNavigation:(WKNavigation *)navigation withError:(NSError *)error
{
    UnitySendMessage([gameObjectName UTF8String], "CallOnError", [[error description] UTF8String]);
}

- (void)webView:(WKWebView *)wkWebView decidePolicyForNavigationAction:(WKNavigationAction *)navigationAction decisionHandler:(void (^)(WKNavigationActionPolicy))decisionHandler
{
    if (webView == nil) {
        decisionHandler(WKNavigationActionPolicyCancel);
        return;
    }
    NSURL *nsurl = [navigationAction.request URL];
    NSString *url = [nsurl absoluteString];
    if ([url rangeOfString:@"//itunes.apple.com/"].location != NSNotFound) {
        [[UIApplication sharedApplication] openURL:nsurl];
        decisionHandler(WKNavigationActionPolicyCancel);
        return;
    } else if ([url hasPrefix:@"unity:"]) {
        UnitySendMessage([gameObjectName UTF8String], "CallFromJS", [[url substringFromIndex:6] UTF8String]);
        decisionHandler(WKNavigationActionPolicyCancel);
        return;
    } else if (![url hasPrefix:@"about:blank"]  // for loadHTML(), cf. #365
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

- (BOOL)isSetupedCustomHeader:(NSURLRequest *)targetRequest
{
    // Check for additional custom header.
    for (NSString *key in [customRequestHeader allKeys])
    {
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

- (void)setFrame:(NSInteger)x positionY:(NSInteger)y width:(NSInteger)width height:(NSInteger)height
{
    if (webView == nil)
        return;
    UIView* view = UnityGetGLViewController().view;
    CGRect frame = webView.frame;
    CGRect screen = view.bounds;
    frame.origin.x = x + ((screen.size.width - width) / 2);
    frame.origin.y = -y + ((screen.size.height - height) / 2);
    frame.size.width = width;
    frame.size.height = height;
    webView.frame = frame;
}

- (void)setMargins:(float)left top:(float)top right:(float)right bottom:(float)bottom relative:(BOOL)relative
{
    if (webView == nil)
        return;
    UIView *view = UnityGetGLViewController().view;
    CGRect frame = webView.frame;
    CGRect screen = view.bounds;
    if (relative) {
        frame.size.width = screen.size.width * (1.0f - left - right);
        frame.size.height = screen.size.height * (1.0f - top - bottom);
        frame.origin.x = screen.size.width * left;
        frame.origin.y = screen.size.height * top;
    } else {
        CGFloat scale = 1.0f / [self getScale:view];
        frame.size.width = screen.size.width - scale * (left + right) ;
        frame.size.height = screen.size.height - scale * (top + bottom) ;
        frame.origin.x = scale * left ;
        frame.origin.y = scale * top ;
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
@end

extern "C" {
    void *_CWebViewPlugin_Init(const char *gameObjectName, BOOL transparent, const char *ua, BOOL enableWKWebView);
    void _CWebViewPlugin_Destroy(void *instance);
    void _CWebViewPlugin_SetFrame(void* instace, int x, int y, int width, int height);
    void _CWebViewPlugin_SetMargins(
        void *instance, float left, float top, float right, float bottom, BOOL relative);
    void _CWebViewPlugin_SetVisibility(void *instance, BOOL visibility);
    void _CWebViewPlugin_LoadURL(void *instance, const char *url);
    void _CWebViewPlugin_LoadHTML(void *instance, const char *html, const char *baseUrl);
    void _CWebViewPlugin_EvaluateJS(void *instance, const char *url);
    int _CWebViewPlugin_Progress(void *instance);
    BOOL _CWebViewPlugin_CanGoBack(void *instance);
    BOOL _CWebViewPlugin_CanGoForward(void *instance);
    void _CWebViewPlugin_GoBack(void *instance);
    void _CWebViewPlugin_GoForward(void *instance);
    void _CWebViewPlugin_AddCustomHeader(void *instance, const char *headerKey, const char *headerValue);
    void _CWebViewPlugin_RemoveCustomHeader(void *instance, const char *headerKey);
    void _CWebViewPlugin_ClearCustomHeader(void *instance);
    void _CWebViewPlugin_ClearCookies();
    const char *_CWebViewPlugin_GetCookies(const char *url);
    const char *_CWebViewPlugin_GetCustomHeaderValue(void *instance, const char *headerKey);
}

void *_CWebViewPlugin_Init(const char *gameObjectName, BOOL transparent, const char *ua, BOOL enableWKWebView)
{
    if (! (enableWKWebView && [WKWebView class]))
        return nil;
    CWebViewPlugin *webViewPlugin = [[CWebViewPlugin alloc] initWithGameObjectName:gameObjectName transparent:transparent ua:ua enableWKWebView:enableWKWebView];
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

void _CWebViewPlugin_SetFrame(void* instance, int x, int y, int width, int height)
{
    if (instance == NULL)
        return;
    float screenScale = [UIScreen instancesRespondToSelector:@selector(scale)] ? [UIScreen mainScreen].scale : 1.0f;
    CWebViewPlugin* webViewPlugin = (__bridge CWebViewPlugin*)instance;
    if (UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad && screenScale == 2.0f)
        screenScale = 1.0f;
    [webViewPlugin
        setFrame:x / screenScale
        positionY:y / screenScale
        width:width / screenScale
        height:height / screenScale];
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

const char *_CWebViewPlugin_GetCookies(const char *url)
{
    return [CWebViewPlugin getCookies:url];
}

const char *_CWebViewPlugin_GetCustomHeaderValue(void *instance, const char *headerKey)
{
    if (instance == NULL)
        return NULL;
    CWebViewPlugin *webViewPlugin = (__bridge CWebViewPlugin *)instance;
    return [webViewPlugin getCustomRequestHeaderValue:headerKey];
}

#endif // __IPHONE_OS_VERSION_MIN_REQUIRED < __IPHONE_9_0
