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

#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>
#import <WebKit/WebKit.h>
#import <Carbon/Carbon.h>
#import <CoreGraphics/CGContext.h>
#import <Metal/Metal.h>
#import <OpenGL/gl.h>
#import <unistd.h>
#include <unordered_map>

static BOOL s_inEditor;
static BOOL s_useMetal;

@interface CWebViewPlugin : NSObject<WKUIDelegate, WKNavigationDelegate, WKScriptMessageHandler>
{
    NSWindow *window;
    NSWindowController *windowController;
    WKWebView *webView;
    NSString *gameObject;
    NSBitmapImageRep *bitmap;
    void *textureId;
    BOOL needsDisplay;
    NSMutableDictionary *customRequestHeader;
    NSMutableArray *messages;
    NSRegularExpression *allowRegex;
    NSRegularExpression *denyRegex;
    NSRegularExpression *hookRegex;
    BOOL inRendering;
}
@end

@implementation CWebViewPlugin

static WKProcessPool *_sharedProcessPool;
static std::unordered_map<int, int> _nskey2cgkey{
    { NSUpArrowFunctionKey,          126 },
    { NSDownArrowFunctionKey,        125 },
    { NSLeftArrowFunctionKey,        123 },
    { NSRightArrowFunctionKey,       124 },
    { NSF1FunctionKey,                 0 },
    { NSF2FunctionKey,                 0 },
    { NSF3FunctionKey,                 0 },
    { NSF4FunctionKey,                 0 },
    { NSF5FunctionKey,                 0 },
    { NSF6FunctionKey,                 0 },
    { NSF7FunctionKey,                 0 },
    { NSF8FunctionKey,                 0 },
    { NSF9FunctionKey,                 0 },
    { NSF10FunctionKey,                0 },
    { NSF11FunctionKey,                0 },
    { NSF12FunctionKey,                0 },
    { NSF13FunctionKey,                0 },
    { NSF14FunctionKey,                0 },
    { NSF15FunctionKey,                0 },
    { NSF16FunctionKey,                0 },
    { NSF17FunctionKey,                0 },
    { NSF18FunctionKey,                0 },
    { NSF19FunctionKey,                0 },
    { NSF20FunctionKey,                0 },
    { NSF21FunctionKey,                0 },
    { NSF22FunctionKey,                0 },
    { NSF23FunctionKey,                0 },
    { NSF24FunctionKey,                0 },
    { NSF25FunctionKey,                0 },
    { NSF26FunctionKey,                0 },
    { NSF27FunctionKey,                0 },
    { NSF28FunctionKey,                0 },
    { NSF29FunctionKey,                0 },
    { NSF30FunctionKey,                0 },
    { NSF31FunctionKey,                0 },
    { NSF32FunctionKey,                0 },
    { NSF33FunctionKey,                0 },
    { NSF34FunctionKey,                0 },
    { NSF35FunctionKey,                0 },
    { NSInsertFunctionKey,             0 },
    { NSDeleteFunctionKey,             0 },
    { NSHomeFunctionKey,               0 },
    { NSBeginFunctionKey,              0 },
    { NSEndFunctionKey,                0 },
    { NSPageUpFunctionKey,             0 },
    { NSPageDownFunctionKey,           0 },
    { NSPrintScreenFunctionKey,        0 },
    { NSScrollLockFunctionKey,         0 },
    { NSPauseFunctionKey,              0 },
    { NSSysReqFunctionKey,             0 },
    { NSBreakFunctionKey,              0 },
    { NSResetFunctionKey,              0 },
    { NSStopFunctionKey,               0 },
    { NSMenuFunctionKey,               0 },
    { NSUserFunctionKey,               0 },
    { NSSystemFunctionKey,             0 },
    { NSPrintFunctionKey,              0 },
    { NSClearLineFunctionKey,          0 },
    { NSClearDisplayFunctionKey,       0 },
    { NSInsertLineFunctionKey,         0 },
    { NSDeleteLineFunctionKey,         0 },
    { NSInsertCharFunctionKey,         0 },
    { NSDeleteCharFunctionKey,         0 },
    { NSPrevFunctionKey,               0 },
    { NSNextFunctionKey,               0 },
    { NSSelectFunctionKey,             0 },
    { NSExecuteFunctionKey,            0 },
    { NSUndoFunctionKey,               0 },
    { NSRedoFunctionKey,               0 },
    { NSFindFunctionKey,               0 },
    { NSHelpFunctionKey,               0 },
    { NSModeSwitchFunctionKey,         0 },
};

- (id)initWithGameObject:(const char *)gameObject_ transparent:(BOOL)transparent width:(int)width height:(int)height ua:(const char *)ua separated:(BOOL)separated
{
    self = [super init];
    @synchronized(self) {
        if (_sharedProcessPool == NULL) {
            _sharedProcessPool = [[WKProcessPool alloc] init];
        }
    }
    messages = [[NSMutableArray alloc] init];
    customRequestHeader = [[NSMutableDictionary alloc] init];
    allowRegex = nil;
    denyRegex = nil;
    hookRegex = nil;
    WKWebViewConfiguration *configuration = [[WKWebViewConfiguration alloc] init];
    WKUserContentController *controller = [[WKUserContentController alloc] init];
    WKPreferences *preferences = [[WKPreferences alloc] init];
    preferences.javaScriptEnabled = true;
    preferences.plugInsEnabled = true;
    [controller addScriptMessageHandler:self name:@"unityControl"];
    configuration.userContentController = controller;
    configuration.processPool = _sharedProcessPool;
    // configuration.preferences = preferences;
    NSRect frame = NSMakeRect(0, 0, width, height);
    webView = [[WKWebView alloc] initWithFrame:frame
                                 configuration:configuration];
    [[[webView configuration] preferences] setValue:@YES forKey:@"developerExtrasEnabled"];
    webView.UIDelegate = self;
    webView.navigationDelegate = self;
    webView.hidden = YES;
    if (transparent) {
        [webView setValue:@NO forKey:@"drawsBackground"];
    }
    // webView.translatesAutoresizingMaskIntoConstraints = NO;
    [webView setAutoresizingMask:(NSViewWidthSizable|NSViewHeightSizable)];
    // [webView setFrameLoadDelegate:(id)self];
    // [webView setPolicyDelegate:(id)self];
    webView.UIDelegate = self;
    webView.navigationDelegate = self;
    gameObject = [NSString stringWithUTF8String:gameObject_];
    if (ua != NULL && strcmp(ua, "") != 0) {
        [webView setCustomUserAgent:[NSString stringWithUTF8String:ua]];
    }
    if (separated) {
        window = [[NSWindow alloc] initWithContentRect:frame
                                             styleMask:NSWindowStyleMaskTitled|NSWindowStyleMaskClosable|NSWindowStyleMaskResizable
                                               backing:NSBackingStoreBuffered
                                                 defer:NO];
        [window setContentView:webView];
        [window orderFront:NSApp];
        windowController = [[NSWindowController alloc] initWithWindow:window];
    }
    return self;
}

- (void)dispose
{
    @synchronized(self) {
        if (webView != nil) {
            // [webView setFrameLoadDelegate:nil];
            // [webView setPolicyDelegate:nil];
            webView.UIDelegate = nil;
            webView.navigationDelegate = nil;
            [webView stopLoading:nil];
            webView = nil;
        }
        if (window != nil) {
            [window close];
        }
        gameObject = nil;
        bitmap = nil;
        window = nil;
        windowController = nil;
        hookRegex = nil;
        denyRegex = nil;
        allowRegex = nil;
        customRequestHeader = nil;
        messages = nil;
    }
}

- (void)webView:(WKWebView *)webView didFailProvisionalNavigation:(WKNavigation *)navigation withError:(NSError *)error
{
    [self addMessage:[NSString stringWithFormat:@"E%@",[error description]]];
}

- (void)webView:(WKWebView *)webView didFailNavigation:(WKNavigation *)navigation withError:(NSError *)error
{
    [self addMessage:[NSString stringWithFormat:@"E%@",[error description]]];
}

- (void)webView:(WKWebView*)wkWebView didCommitNavigation:(null_unspecified WKNavigation *)navigation
{
    [self addMessage:[NSString stringWithFormat:@"L%s","Unknown URL"]];
}

- (void)webView:(WKWebView *)wkWebView decidePolicyForNavigationAction:(WKNavigationAction *)navigationAction decisionHandler:(void (^)(WKNavigationActionPolicy))decisionHandler
{
    if (webView == nil) {
        decisionHandler(WKNavigationActionPolicyCancel);
        return;
    }
    NSString *url = [[navigationAction.request URL] absoluteString];
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
        [[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:url]];
        decisionHandler(WKNavigationActionPolicyCancel);
    } else if ([url hasPrefix:@"unity:"]) {
        [self addMessage:[NSString stringWithFormat:@"J%@",[url substringFromIndex:6]]];
        decisionHandler(WKNavigationActionPolicyCancel);
    } else if (hookRegex != nil && [hookRegex firstMatchInString:url options:0 range:NSMakeRange(0, url.length)]) {
        [self addMessage:[NSString stringWithFormat:@"H%@",url]];
        decisionHandler(WKNavigationActionPolicyCancel);
    } else if (navigationAction.navigationType == WKNavigationTypeLinkActivated
               && (!navigationAction.targetFrame || !navigationAction.targetFrame.isMainFrame)) {
        // cf. for target="_blank", cf. http://qiita.com/ShingoFukuyama/items/b3a1441025a36ab7659c
        [webView loadRequest:navigationAction.request];
        decisionHandler(WKNavigationActionPolicyCancel);
    } else {
        if ([customRequestHeader count] > 0) {
            bool isCustomized = YES;

            // Check for additional custom header.
            for (NSString *key in [customRequestHeader allKeys])
            {
                if (![[[navigationAction.request allHTTPHeaderFields] objectForKey:key] isEqualToString:[customRequestHeader objectForKey:key]]) {
                    isCustomized = NO;
                    break;
                }
            }

            // If the custom header is not attached, give it and make a request again.
            if (!isCustomized) {
                decisionHandler(WKNavigationActionPolicyCancel);
                [webView loadRequest:[self constructionCustomHeader:navigationAction.request]];
                return;
            }
        }
        [self addMessage:[NSString stringWithFormat:@"S%@",url]];
        decisionHandler(WKNavigationActionPolicyAllow);
    }
}

- (void)userContentController:(WKUserContentController *)userContentController
      didReceiveScriptMessage:(WKScriptMessage *)message {

    // Log out the message received
    NSLog(@"Received event %@", message.body);
    [self addMessage:[NSString stringWithFormat:@"J%@",message.body]];

    /*
    // Then pull something from the device using the message body
    NSString *version = [[UIDevice currentDevice] valueForKey:message.body];

    // Execute some JavaScript using the result?
    NSString *exec_template = @"set_headline(\"received: %@\");";
    NSString *exec = [NSString stringWithFormat:exec_template, version];
    [webView evaluateJavaScript:exec completionHandler:nil];
    */
}

- (void)addMessage:(NSString*)msg
{
    @synchronized(messages)
    {
        [messages addObject:msg];
    }
}

- (NSString *)getMessage
{
    NSString *ret = nil;
    @synchronized(messages)
    {
        if ([messages count] > 0) {
            ret = [messages[0] copy];
            [messages removeObjectAtIndex:0];
        }
    }
    return ret;
}

- (void)setRect:(int)width height:(int)height
{
    if (webView == nil)
        return;
    NSRect frame;
    frame.size.width = width;
    frame.size.height = height;
    frame.origin.x = 0;
    frame.origin.y = 0;
    webView.frame = frame;
    if (bitmap != nil) {
        bitmap = nil;
    }
    if (window != nil) {
        frame.origin = window.frame.origin;
        [window setFrame:frame display:YES];
    }
}

- (void)setVisibility:(BOOL)visibility
{
    if (webView == nil)
        return;
    webView.hidden = visibility ? NO : YES;
}

- (NSURLRequest *)constructionCustomHeader:(NSURLRequest *)originalRequest
{
    NSMutableURLRequest *convertedRequest = originalRequest.mutableCopy;
    for (NSString *key in [customRequestHeader allKeys]) {
        [convertedRequest setValue:customRequestHeader[key] forHTTPHeaderField:key];
    }
    return convertedRequest;
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

    if ([nsurl.absoluteString hasPrefix:@"file:"]) {
        NSURL *top = [NSURL URLWithString:[[nsurl absoluteString] stringByDeletingLastPathComponent]];
        [webView loadFileURL:nsurl allowingReadAccessToURL:top];
    } else {
        [webView loadRequest:request];
    }
}

- (void)loadHTML:(const char *)html baseURL:(const char *)baseUrl
{
    if (webView == nil)
        return;
    NSString *htmlStr = [NSString stringWithUTF8String:html];
    NSString *baseStr = [NSString stringWithUTF8String:baseUrl];
    NSURL *baseNSUrl = [NSURL URLWithString:baseStr];
    [webView loadHTMLString:htmlStr baseURL:baseNSUrl];
}

- (void)evaluateJS:(const char *)js
{
    if (webView == nil)
        return;
    NSString *jsStr = [NSString stringWithUTF8String:js];
    [webView evaluateJavaScript:jsStr completionHandler:nil];
}

- (int)progress
{
    if (webView == nil)
        return 0;
    return (int)([webView estimatedProgress] * 100);
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

- (void)sendMouseEvent:(int)x y:(int)y deltaY:(float)deltaY mouseState:(int)mouseState
{
    if (webView == nil)
        return;
    NSView *view = webView;
    NSGraphicsContext *context = [NSGraphicsContext currentContext];
    dispatch_async(
        dispatch_get_main_queue(),
        ^{
            NSEvent *event;
            switch (mouseState) {
            case 1:
                event = [NSEvent mouseEventWithType:NSEventTypeLeftMouseDown
                                           location:NSMakePoint(x, y) modifierFlags:0
                                          timestamp:GetCurrentEventTime() windowNumber:0
                                            context:context eventNumber:0 clickCount:1 pressure:1];
                [view mouseDown:event];
                break;
            case 2:
                event = [NSEvent mouseEventWithType:NSEventTypeLeftMouseDragged
                                           location:NSMakePoint(x, y) modifierFlags:0
                                          timestamp:GetCurrentEventTime() windowNumber:0
                                            context:context eventNumber:0 clickCount:0 pressure:1];
                [view mouseDragged:event];
                break;
            case 3:
                event = [NSEvent mouseEventWithType:NSEventTypeLeftMouseUp
                                           location:NSMakePoint(x, y) modifierFlags:0
                                          timestamp:GetCurrentEventTime() windowNumber:0
                                            context:context eventNumber:0 clickCount:0 pressure:0];
                [view mouseUp:event];
                break;
            default:
                break;
            }
            {
                CGEventRef cgEvent = CGEventCreateScrollWheelEvent(NULL, kCGScrollEventUnitLine, 1, deltaY * 3, 0);
                NSEvent *scrollEvent = [NSEvent eventWithCGEvent:cgEvent];
                CFRelease(cgEvent);
                [view scrollWheel:scrollEvent];
            }
        });
}

- (void)sendKeyEvent:(int)x y:(int)y keyChars:(char *)keyChars keyCode:(unsigned short)keyCode keyState:(int)keyState
{
    if (webView == nil)
        return;
    NSView *view = webView;
    NSGraphicsContext *context = [NSGraphicsContext currentContext];
    NSString *characters = [NSString stringWithUTF8String:keyChars];
    CGKeyCode cgKeyCode = 0;
    if (0xf700 <= keyCode && keyCode <= 0xf8ff
        && _nskey2cgkey.find(keyCode) != _nskey2cgkey.end())
        cgKeyCode = _nskey2cgkey.at(keyCode);
    dispatch_async(
        dispatch_get_main_queue(),
        ^{
            NSEvent *event;
            switch (keyState) {
            case 1:
                if (cgKeyCode == 0 || CGEventSourceKeyState(kCGEventSourceStateCombinedSessionState, cgKeyCode)) {
                    event = [NSEvent keyEventWithType:NSEventTypeKeyDown
                                             location:NSMakePoint(x, y) modifierFlags:0
                                            timestamp:GetCurrentEventTime() windowNumber:0
                                              context:context
                                           characters:characters
                                     charactersIgnoringModifiers:characters
                                            isARepeat:NO keyCode:0];
                    [view keyDown:event];
                }
                break;
            case 2:
                if (cgKeyCode == 0 || CGEventSourceKeyState(kCGEventSourceStateCombinedSessionState, cgKeyCode)) {
                    event = [NSEvent keyEventWithType:NSEventTypeKeyDown
                                             location:NSMakePoint(x, y) modifierFlags:0
                                            timestamp:GetCurrentEventTime() windowNumber:0
                                              context:context
                                           characters:characters
                                     charactersIgnoringModifiers:characters
                                            isARepeat:YES keyCode:0];
                    [view keyDown:event];
                }
                break;
            case 3:
                if (cgKeyCode == 0 || !CGEventSourceKeyState(kCGEventSourceStateCombinedSessionState, cgKeyCode)) {
                    event = [NSEvent keyEventWithType:NSEventTypeKeyUp
                                             location:NSMakePoint(x, y) modifierFlags:0
                                            timestamp:GetCurrentEventTime() windowNumber:0
                                              context:context
                                           characters:characters
                                     charactersIgnoringModifiers:characters
                                            isARepeat:NO keyCode:0];
                    [view keyUp:event];
                }
                break;
            default:
                break;
            }
        });
}

- (void)update:(BOOL)refreshBitmap
{
    if (webView == nil)
        return;
    @synchronized(self) {
        if (inRendering)
            return;
        if (refreshBitmap) {
            // [webView cacheDisplayInRect:webView.frame toBitmapImageRep:bitmap];
            NSRect rect = webView.frame;
            if (bitmap == nil) {
                bitmap
                    = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:nil
                                                              pixelsWide:rect.size.width
                                                              pixelsHigh:rect.size.height
                                                           bitsPerSample:8
                                                         samplesPerPixel:4
                                                                hasAlpha:YES
                                                                isPlanar:NO
                                                          colorSpaceName:NSCalibratedRGBColorSpace
                                                            bitmapFormat:0
                                                             bytesPerRow:(4 * rect.size.width)
                                                            bitsPerPixel:32];
                // bitmap = [webView bitmapImageRepForCachingDisplayInRect:webView.frame];
            }
            inRendering = YES;
            if (window != nil) {
                memset([bitmap bitmapData], 128, [bitmap bytesPerRow] * [bitmap pixelsHigh]);
                inRendering = NO;
            } else {
                NSBitmapImageRep *bmpRep = bitmap;
                // memset([bitmap bitmapData], 0, [bitmap bytesPerRow] * [bitmap pixelsHigh]);
                // [webView cacheDisplayInRect:webView.frame toBitmapImageRep:bitmap];
                WKWebView *wkv = webView;
                WKSnapshotConfiguration *cfg = [WKSnapshotConfiguration new];
                //cfg.snapshotWidth = [NSNumber numberWithLong:[bitmap pixelsWide]];
                //cfg.rect = webView.frame;
                [wkv takeSnapshotWithConfiguration:cfg
                                 completionHandler:^(NSImage *nsImg, NSError *err) {
                    if (err == nil) {
                        NSGraphicsContext *ctx = [NSGraphicsContext graphicsContextWithBitmapImageRep:bmpRep];
                        [NSGraphicsContext saveGraphicsState];
                        [NSGraphicsContext setCurrentContext:ctx];
                        [nsImg drawAtPoint:CGPointZero
                                  fromRect:CGRectMake(0, 0, [bmpRep pixelsWide], [bmpRep pixelsHigh])
                                 operation:NSCompositingOperationCopy
                                  fraction:1.0];
                        [[NSGraphicsContext currentContext] flushGraphics];
                        [NSGraphicsContext restoreGraphicsState];
                    }
                    self->inRendering = NO;
                }];
            }
        }
        needsDisplay = refreshBitmap;
    }
}

- (int)bitmapWide
{
    @synchronized(self) {
        return (bitmap == nil) ? 0 : (int)[bitmap pixelsWide];
    }
}

- (int)bitmapHigh
{
    @synchronized(self) {
        return (bitmap == nil) ? 0 : (int)[bitmap pixelsHigh];
    }
}

- (void)setTextureId:(void *)tId
{
    @synchronized(self) {
        textureId = tId;
    }
}

- (void)render
{
    @synchronized(self) {
        if (webView == nil)
            return;
        if (!needsDisplay)
            return;
        if (bitmap == nil)
            return;

        NSInteger w = [bitmap pixelsWide];
        NSInteger h = [bitmap pixelsHigh];
        NSInteger r = w * [bitmap samplesPerPixel];
        void *d = [bitmap bitmapData];
        if (s_useMetal) {
            id<MTLTexture> tex = (__bridge id<MTLTexture>)textureId;
            [tex replaceRegion:MTLRegionMake3D(0, 0, 0, w, h, 1) mipmapLevel:0 withBytes:d bytesPerRow:r];
        } else {
            int rowLength = 0;
            int unpackAlign = 0;
            glGetIntegerv(GL_UNPACK_ROW_LENGTH, &rowLength);
            glGetIntegerv(GL_UNPACK_ALIGNMENT, &unpackAlign);
            glPixelStorei(GL_UNPACK_ROW_LENGTH, (GLint)w);
            glPixelStorei(GL_UNPACK_ALIGNMENT, 1);
            glBindTexture(GL_TEXTURE_2D, (GLuint)(long)textureId);
            glTexSubImage2D(GL_TEXTURE_2D, 0, 0, 0, (GLsizei)w, (GLsizei)h, GL_RGBA, GL_UNSIGNED_BYTE, d);
            glPixelStorei(GL_UNPACK_ROW_LENGTH, rowLength);
            glPixelStorei(GL_UNPACK_ALIGNMENT, unpackAlign);
        }
    }
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

typedef void (*UnityRenderEventFunc)(int eventId);
#ifdef __cplusplus
extern "C" {
#endif
    const char *_CWebViewPlugin_GetAppPath(void);
    void _CWebViewPlugin_InitStatic(BOOL inEditor, BOOL useMetal);
    void *_CWebViewPlugin_Init(
        const char *gameObject, BOOL transparent, int width, int height, const char *ua, BOOL separated);
    void _CWebViewPlugin_Destroy(void *instance);
    void _CWebViewPlugin_SetRect(void *instance, int width, int height);
    void _CWebViewPlugin_SetVisibility(void *instance, BOOL visibility);
    BOOL _CWebViewPlugin_SetURLPattern(void *instance, const char *allowPattern, const char *denyPattern, const char *hookPattern);
    void _CWebViewPlugin_LoadURL(void *instance, const char *url);
    void _CWebViewPlugin_LoadHTML(void *instance, const char *html, const char *baseUrl);
    void _CWebViewPlugin_EvaluateJS(void *instance, const char *url);
    int _CWebViewPlugin_Progress(void *instance);
    BOOL _CWebViewPlugin_CanGoBack(void *instance);
    BOOL _CWebViewPlugin_CanGoForward(void *instance);
    void _CWebViewPlugin_GoBack(void *instance);
    void _CWebViewPlugin_GoForward(void *instance);
    void _CWebViewPlugin_SendMouseEvent(void *instance, int x, int y, float deltaY, int mouseState);
    void _CWebViewPlugin_SendKeyEvent(void *instance, int x, int y, char *keyChars, unsigned short keyCode, int keyState);
    void _CWebViewPlugin_Update(void *instance, BOOL refreshBitmap);
    int _CWebViewPlugin_BitmapWidth(void *instance);
    int _CWebViewPlugin_BitmapHeight(void *instance);
    void _CWebViewPlugin_SetTextureId(void *instance, void *textureId);
    void _CWebViewPlugin_SetCurrentInstance(void *instance);
    void UnityRenderEvent(int eventId);
    UnityRenderEventFunc GetRenderEventFunc(void);
    void _CWebViewPlugin_AddCustomHeader(void *instance, const char *headerKey, const char *headerValue);
    void _CWebViewPlugin_RemoveCustomHeader(void *instance, const char *headerKey);
    void _CWebViewPlugin_ClearCustomHeader(void *instance);
    const char *_CWebViewPlugin_GetCustomHeaderValue(void *instance, const char *headerKey);
    const char *_CWebViewPlugin_GetMessage(void *instance);
#ifdef __cplusplus
}
#endif

const char *_CWebViewPlugin_GetAppPath(void)
{
    const char *s = [[[[NSBundle mainBundle] bundleURL] absoluteString] UTF8String];
    char *r = (char *)malloc(strlen(s) + 1);
    strcpy(r, s);
    return r;
}

static NSMutableSet *pool;

void _CWebViewPlugin_InitStatic(BOOL inEditor, BOOL useMetal)
{
    s_inEditor = inEditor;
    s_useMetal = useMetal;
}

void *_CWebViewPlugin_Init(
    const char *gameObject, BOOL transparent, int width, int height, const char *ua, BOOL separated)
{
    if (pool == 0)
        pool = [[NSMutableSet alloc] init];

    CWebViewPlugin *webViewPlugin = [[CWebViewPlugin alloc] initWithGameObject:gameObject transparent:transparent width:width height:height ua:ua separated:separated];
    [pool addObject:webViewPlugin];
    return (__bridge_retained void *)webViewPlugin;
}

void _CWebViewPlugin_Destroy(void *instance)
{
    _CWebViewPlugin_SetCurrentInstance(NULL);
    CWebViewPlugin *webViewPlugin = (__bridge_transfer CWebViewPlugin *)instance;
    [pool removeObject:webViewPlugin];
    [webViewPlugin dispose];
    webViewPlugin = nil;
}

void _CWebViewPlugin_SetRect(void *instance, int width, int height)
{
    CWebViewPlugin *webViewPlugin = (__bridge CWebViewPlugin *)instance;
    [webViewPlugin setRect:width height:height];
}

void _CWebViewPlugin_SetVisibility(void *instance, BOOL visibility)
{
    CWebViewPlugin *webViewPlugin = (__bridge CWebViewPlugin *)instance;
    [webViewPlugin setVisibility:visibility];
}

BOOL _CWebViewPlugin_SetURLPattern(void *instance, const char *allowPattern, const char *denyPattern, const char *hookPattern)
{
    CWebViewPlugin *webViewPlugin = (__bridge CWebViewPlugin *)instance;
    return [webViewPlugin setURLPattern:allowPattern and:denyPattern and:hookPattern];
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

void _CWebViewPlugin_SendMouseEvent(void *instance, int x, int y, float deltaY, int mouseState)
{
    CWebViewPlugin *webViewPlugin = (__bridge CWebViewPlugin *)instance;
    [webViewPlugin sendMouseEvent:x y:y deltaY:deltaY mouseState:mouseState];
}

void _CWebViewPlugin_SendKeyEvent(void *instance, int x, int y, char *keyChars, unsigned short keyCode, int keyState)
{
    CWebViewPlugin *webViewPlugin = (__bridge CWebViewPlugin *)instance;
    [webViewPlugin sendKeyEvent:x y:y keyChars:keyChars keyCode:keyCode keyState:keyState];
}

void _CWebViewPlugin_Update(void *instance, BOOL refreshBitmap)
{
    CWebViewPlugin *webViewPlugin = (__bridge CWebViewPlugin *)instance;
    [webViewPlugin update:refreshBitmap];
}

int _CWebViewPlugin_BitmapWidth(void *instance)
{
    CWebViewPlugin *webViewPlugin = (__bridge CWebViewPlugin *)instance;
    return [webViewPlugin bitmapWide];
}

int _CWebViewPlugin_BitmapHeight(void *instance)
{
    CWebViewPlugin *webViewPlugin = (__bridge CWebViewPlugin *)instance;
    return [webViewPlugin bitmapHigh];
}

void _CWebViewPlugin_SetTextureId(void *instance, void *textureId)
{
    CWebViewPlugin *webViewPlugin = (__bridge CWebViewPlugin *)instance;
    [webViewPlugin setTextureId:textureId];
}

static void *_instance;

void _CWebViewPlugin_SetCurrentInstance(void *instance)
{
    _instance = instance;
}

void UnityRenderEvent(int eventId)
{
    if (_instance == nil) {
        return;
    }
    CWebViewPlugin *webViewPlugin = (__bridge CWebViewPlugin *)_instance;
    _instance = nil;
    if ([pool containsObject:webViewPlugin]) {
        [webViewPlugin render];
    }
}

UnityRenderEventFunc GetRenderEventFunc(void)
{
    return UnityRenderEvent;
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

const char *_CWebViewPlugin_GetCustomHeaderValue(void *instance, const char *headerKey)
{
    CWebViewPlugin *webViewPlugin = (__bridge CWebViewPlugin *)instance;
    return [webViewPlugin getCustomRequestHeaderValue:headerKey];
}

void _CWebViewPlugin_ClearCustomHeader(void *instance)
{
    CWebViewPlugin *webViewPlugin = (__bridge CWebViewPlugin *)instance;
    [webViewPlugin clearCustomRequestHeader];
}

const char *_CWebViewPlugin_GetMessage(void *instance)
{
    CWebViewPlugin *webViewPlugin = (__bridge CWebViewPlugin *)instance;
    NSString *message = [webViewPlugin getMessage];
    if (message == nil)
        return NULL;
    const char *s = [message UTF8String];
    char *r = (char *)malloc(strlen(s) + 1);
    strcpy(r, s);
    return r;
}
