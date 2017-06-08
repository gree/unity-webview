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
@end

@implementation CWebViewPlugin


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
        WKWebViewConfiguration *configuration = [[WKWebViewConfiguration alloc] init];
        WKUserContentController *controller = [[WKUserContentController alloc] init];
        [controller addScriptMessageHandler:self name:@"unityControl"];
        configuration.userContentController = controller;
        webView = [[WKWebView alloc] initWithFrame:view.frame configuration:configuration];
        webView.UIDelegate = self;
        webView.navigationDelegate = self;
    } else {
        webView = [[UIWebView alloc] initWithFrame:view.frame];
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
        return YES;
    }
}

- (void)webView:(WKWebView *)wkWebView decidePolicyForNavigationAction:(WKNavigationAction *)navigationAction decisionHandler:(void (^)(WKNavigationActionPolicy))decisionHandler
{
    if (webView == nil) {
        decisionHandler(WKNavigationActionPolicyCancel);
        return;
    }
    NSURL *url = [navigationAction.request URL];
    if ([url.absoluteString rangeOfString:@"//itunes.apple.com/"].location != NSNotFound) {
        [[UIApplication sharedApplication] openURL:url];
        decisionHandler(WKNavigationActionPolicyCancel);
        return;
    } else if ([url.absoluteString hasPrefix:@"unity:"]) {
        UnitySendMessage([gameObjectName UTF8String], "CallFromJS", [[url.absoluteString substringFromIndex:6] UTF8String]);
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
    decisionHandler(WKNavigationActionPolicyAllow);
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

- (void)setMargins:(int)left top:(int)top right:(int)right bottom:(int)bottom
{
    if (webView == nil)
        return;
    UIView *view = UnityGetGLViewController().view;
    CGRect frame = webView.frame;
    CGRect screen = view.bounds;
    CGFloat scale = 1.0f / [self getScale:view];
    frame.size.width = screen.size.width - scale * (left + right) ;
    frame.size.height = screen.size.height - scale * (top + bottom) ;
    frame.origin.x = scale * left ;
    frame.origin.y = scale * top ;
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
        void *instance, int left, int top, int right, int bottom);
    void _CWebViewPlugin_SetVisibility(void *instance, BOOL visibility);
    void _CWebViewPlugin_LoadURL(void *instance, const char *url);
    void _CWebViewPlugin_LoadHTML(void *instance, const char *html, const char *baseUrl);
    void _CWebViewPlugin_EvaluateJS(void *instance, const char *url);
    BOOL _CWebViewPlugin_CanGoBack(void *instance);
    BOOL _CWebViewPlugin_CanGoForward(void *instance);
    void _CWebViewPlugin_GoBack(void *instance);
    void _CWebViewPlugin_GoForward(void *instance);
    void _CWebViewPlugin_AddCustomHeader(void *instance, const char *headerKey, const char *headerValue);
    void _CWebViewPlugin_RemoveCustomHeader(void *instance, const char *headerKey);
    void _CWebViewPlugin_ClearCustomHeader(void *instance);
    const char *_CWebViewPlugin_GetCustomHeaderValue(void *instance, const char *headerKey);
}

void *_CWebViewPlugin_Init(const char *gameObjectName, BOOL transparent, const char *ua, BOOL enableWKWebView)
{
    id instance = [[CWebViewPlugin alloc] initWithGameObjectName:gameObjectName transparent:transparent ua:ua enableWKWebView:enableWKWebView];
    return (__bridge_retained void *)instance;
}

void _CWebViewPlugin_Destroy(void *instance)
{
    CWebViewPlugin *webViewPlugin = (__bridge_transfer CWebViewPlugin *)instance;
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
    void *instance, int left, int top, int right, int bottom)
{
    CWebViewPlugin *webViewPlugin = (__bridge CWebViewPlugin *)instance;
    [webViewPlugin setMargins:left top:top right:right bottom:bottom];
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

const char *_CWebViewPlugin_GetCustomHeaderValue(void *instance, const char *headerKey)
{
    CWebViewPlugin *webViewPlugin = (__bridge CWebViewPlugin *)instance;
    return [webViewPlugin getCustomRequestHeaderValue:headerKey];
}


