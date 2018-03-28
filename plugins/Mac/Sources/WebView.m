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
#import <OpenGL/gl.h>
#import <unistd.h>

static BOOL inEditor;

typedef void * ManagedCallback(const char*);

@interface CWebViewPlugin : NSObject
{
    WebView *webView;
    NSString *gameObject;
    NSBitmapImageRep *bitmap;
    int textureId;
    BOOL needsDisplay;
    NSMutableDictionary *customRequestHeader;
    ManagedCallback* onError;
    ManagedCallback* onLoaded;
    ManagedCallback* onFromJS;
}
@end

@implementation CWebViewPlugin

- (id)initWithGameObject:(const char *)gameObject_ transparent:(BOOL)transparent width:(int)width height:(int)height ua:(const char *)ua
{
    self = [super init];

    customRequestHeader = [[NSMutableDictionary alloc] init];
    webView = [[WebView alloc] initWithFrame:NSMakeRect(0, 0, width, height)];
    webView.hidden = YES;
    if (transparent) {
        [webView setDrawsBackground:NO];
    }
    [webView setAutoresizingMask:(NSViewWidthSizable|NSViewHeightSizable)];
    [webView setFrameLoadDelegate:(id)self];
    [webView setPolicyDelegate:(id)self];
    gameObject = [[NSString stringWithUTF8String:gameObject_] retain];
    if (ua != NULL && strcmp(ua, "") != 0) {
        [webView setCustomUserAgent:[NSString stringWithUTF8String:ua]];
    }
    onError = NULL;
    onLoaded = NULL;
    onFromJS = NULL;
    return self;
}

- (void)dealloc
{
    @synchronized(self) {
        if (webView != nil) {
            [webView setFrameLoadDelegate:nil];
            [webView setPolicyDelegate:nil];
            [webView stopLoading:nil];
            [webView release];
            webView = nil;
        }
        if (gameObject != nil) {
            [gameObject release];
            gameObject = nil;
        }
        if (bitmap != nil) {
            [bitmap release];
            bitmap = nil;
        }
    }
    [super dealloc];
}

- (void)webView:(WebView *)sender didFailProvisionalLoadWithError:(NSError *)error forFrame:(WebFrame *)frame
{
    if (onError != NULL)
        onError([[error description] UTF8String]);
}

- (void)webView:(WebView *)sender didFinishLoadForFrame:(WebFrame *)frame
{
    if (onLoaded != NULL)
        onLoaded([[[[[frame dataSource] request] URL] absoluteString] UTF8String]);
}

- (void)webView:(WebView *)sender decidePolicyForNavigationAction:(NSDictionary *)actionInformation request:(NSURLRequest *)request frame:(WebFrame *)frame decisionListener:(id<WebPolicyDecisionListener>)listener
{
    NSString *url = [[request URL] absoluteString];
    if ([url hasPrefix:@"unity:"]) {
        if (onFromJS != NULL)
            onFromJS([[url substringFromIndex:6] UTF8String]);
        [listener ignore];
    } else {
        if ([customRequestHeader count] > 0) {
            bool isCustomized = YES;

            // Check for additional custom header.
            for (NSString *key in [customRequestHeader allKeys])
            {
                if (![[[request allHTTPHeaderFields] objectForKey:key] isEqualToString:[customRequestHeader objectForKey:key]]) {
                    isCustomized = NO;
                    break;
                }
            }

            // If the custom header is not attached, give it and make a request again.
            if (!isCustomized) {
                [listener ignore];
                [frame loadRequest:[self constructionCustomHeader:request]];
                return;
            }
        }

        [listener use];
    }
}

- (void)setHandler:(ManagedCallback)error loaded:(ManagedCallback)loaded fromjs:(ManagedCallback)fromjs
{
    if (webView == nil)
        return;
    onError = error;
    onLoaded = loaded;
    onFromJS = fromjs;
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
        [bitmap release];
        bitmap = nil;
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

- (void)loadURL:(const char *)url
{
    if (webView == nil)
        return;
    NSString *urlStr = [NSString stringWithUTF8String:url];
    NSURL *nsurl = [NSURL URLWithString:urlStr];
    NSURLRequest *request = [self constructionCustomHeader:[NSMutableURLRequest requestWithURL:nsurl]];
    [[webView mainFrame] loadRequest:request];
}

- (void)loadHTML:(const char *)html baseURL:(const char *)baseUrl
{
    if (webView == nil)
        return;
    NSString *htmlStr = [NSString stringWithUTF8String:html];
    NSString *baseStr = [NSString stringWithUTF8String:baseUrl];
    NSURL *baseNSUrl = [NSURL URLWithString:baseStr];
    [[webView mainFrame] loadHTMLString:htmlStr baseURL:baseNSUrl];
}

- (void)evaluateJS:(const char *)js
{
    if (webView == nil)
        return;
    NSString *jsStr = [NSString stringWithUTF8String:js];
    [webView stringByEvaluatingJavaScriptFromString:jsStr];
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

- (void)update:(int)x y:(int)y deltaY:(float)deltaY buttonDown:(BOOL)buttonDown buttonPress:(BOOL)buttonPress buttonRelease:(BOOL)buttonRelease keyPress:(BOOL)keyPress keyCode:(unsigned short)keyCode keyChars:(const char*)keyChars refreshBitmap:(BOOL)refreshBitmap
{
    if (webView == nil)
        return;

    NSView *view = [[[webView mainFrame] frameView] documentView];
    NSGraphicsContext *context = [NSGraphicsContext currentContext];
    NSEvent *event;
    NSString *characters;

    if (buttonDown) {
        if (buttonPress) {
            event = [NSEvent mouseEventWithType:NSLeftMouseDown
                location:NSMakePoint(x, y) modifierFlags:nil
                timestamp:GetCurrentEventTime() windowNumber:0
                context:context eventNumber:nil clickCount:1 pressure:1];
            [view mouseDown:event];
        } else {
            event = [NSEvent mouseEventWithType:NSLeftMouseDragged
                location:NSMakePoint(x, y) modifierFlags:nil
                timestamp:GetCurrentEventTime() windowNumber:0
                context:context eventNumber:nil clickCount:0 pressure:1];
            [view mouseDragged:event];
        }
    } else if (buttonRelease) {
        event = [NSEvent mouseEventWithType:NSLeftMouseUp
            location:NSMakePoint(x, y) modifierFlags:nil
            timestamp:GetCurrentEventTime() windowNumber:0
            context:context eventNumber:nil clickCount:0 pressure:0];
        [view mouseUp:event];
    }

    if (keyPress) {
        characters = [NSString stringWithUTF8String:keyChars];
        event = [NSEvent keyEventWithType:NSKeyDown
            location:NSMakePoint(x, y) modifierFlags:nil
            timestamp:GetCurrentEventTime() windowNumber:0
            context:context
            characters:characters
            charactersIgnoringModifiers:characters
            isARepeat:NO keyCode:(unsigned short)keyCode];
        [view keyDown:event];
    }

    if (deltaY != 0) {
        CGEventRef cgEvent = CGEventCreateScrollWheelEvent(NULL,
            kCGScrollEventUnitLine, 1, deltaY * 3, 0);
        NSEvent *scrollEvent = [NSEvent eventWithCGEvent:cgEvent];
        CFRelease(cgEvent);
        [view scrollWheel:scrollEvent];
    }

    @synchronized(self) {
        if (refreshBitmap) {
            if (bitmap == nil) {
                bitmap = [[webView bitmapImageRepForCachingDisplayInRect:webView.frame] retain];
            }
            memset([bitmap bitmapData], 0, [bitmap bytesPerRow] * [bitmap pixelsHigh]);
            [webView cacheDisplayInRect:webView.frame toBitmapImageRep:bitmap];
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

- (void)setTextureId:(int)tId
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

        int samplesPerPixel = (int)[bitmap samplesPerPixel];
        int rowLength = 0;
        int unpackAlign = 0;
        glGetIntegerv(GL_UNPACK_ROW_LENGTH, &rowLength);
        glGetIntegerv(GL_UNPACK_ALIGNMENT, &unpackAlign);
        glPixelStorei(GL_UNPACK_ROW_LENGTH, (GLint)[bitmap bytesPerRow] / samplesPerPixel);
        glPixelStorei(GL_UNPACK_ALIGNMENT, 1);
        glBindTexture(GL_TEXTURE_2D, textureId);
        if (![bitmap isPlanar] && (samplesPerPixel == 3 || samplesPerPixel == 4)) {
            glTexSubImage2D(
                GL_TEXTURE_2D,
                0,
                0,
                0,
                (GLsizei)[bitmap pixelsWide],
                (GLsizei)[bitmap pixelsHigh],
                samplesPerPixel == 4 ? GL_RGBA : GL_RGB,
                GL_UNSIGNED_BYTE,
                [bitmap bitmapData]);
        }
        glPixelStorei(GL_UNPACK_ROW_LENGTH, rowLength);
        glPixelStorei(GL_UNPACK_ALIGNMENT, unpackAlign);
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
const char *_CWebViewPlugin_GetAppPath();
void *_CWebViewPlugin_Init(
    const char *gameObject, BOOL transparent, int width, int height, const char *ua, BOOL ineditor);
void _CWebViewPlugin_SetHandler(void *instance, ManagedCallback error, ManagedCallback loaded, ManagedCallback fromjs);
void _CWebViewPlugin_Destroy(void *instance);
void _CWebViewPlugin_SetRect(void *instance, int width, int height);
void _CWebViewPlugin_SetVisibility(void *instance, BOOL visibility);
void _CWebViewPlugin_LoadURL(void *instance, const char *url);
void _CWebViewPlugin_LoadHTML(void *instance, const char *html, const char *baseUrl);
void _CWebViewPlugin_EvaluateJS(void *instance, const char *url);
int _CWebViewPlugin_Progress(void *instance);
BOOL _CWebViewPlugin_CanGoBack(void *instance);
BOOL _CWebViewPlugin_CanGoForward(void *instance);
void _CWebViewPlugin_GoBack(void *instance);
void _CWebViewPlugin_GoForward(void *instance);
void _CWebViewPlugin_Update(void *instance, int x, int y, float deltaY,
    BOOL buttonDown, BOOL buttonPress, BOOL buttonRelease,
    BOOL keyPress, unsigned char keyCode, const char *keyChars, BOOL refreshBitmap);
int _CWebViewPlugin_BitmapWidth(void *instance);
int _CWebViewPlugin_BitmapHeight(void *instance);
void _CWebViewPlugin_SetTextureId(void *instance, int textureId);
void _CWebViewPlugin_SetCurrentInstance(void *instance);
void UnityRenderEvent(int eventId);
UnityRenderEventFunc GetRenderEventFunc();
void _CWebViewPlugin_AddCustomHeader(void *instance, const char *headerKey, const char *headerValue);
void _CWebViewPlugin_RemoveCustomHeader(void *instance, const char *headerKey);
void _CWebViewPlugin_ClearCustomHeader(void *instance);
const char *_CWebViewPlugin_GetCustomHeaderValue(void *instance, const char *headerKey);
#ifdef __cplusplus
}
#endif

const char *_CWebViewPlugin_GetAppPath()
{
    const char *s = [[[[NSBundle mainBundle] bundleURL] absoluteString] UTF8String];
    char *r = (char *)malloc(strlen(s) + 1);
    strcpy(r, s);
    return r;
}

static NSMutableSet *pool;

void *_CWebViewPlugin_Init(
    const char *gameObject, BOOL transparent, int width, int height, const char *ua, BOOL ineditor)
{
    if (pool == 0)
        pool = [[NSMutableSet alloc] init];

    inEditor = ineditor;
    id instance = [[CWebViewPlugin alloc] initWithGameObject:gameObject transparent:transparent width:width height:height ua:ua];
    [pool addObject:[NSValue valueWithPointer:instance]];
    return (void *)instance;
}

void _CWebViewPlugin_SetHandler(void* instance, ManagedCallback error, ManagedCallback loaded, ManagedCallback fromjs)
{
    CWebViewPlugin *webViewPlugin = (__bridge CWebViewPlugin *)instance;
    [webViewPlugin setHandler:error loaded:loaded fromjs:fromjs];
}

void _CWebViewPlugin_Destroy(void *instance)
{
    CWebViewPlugin *webViewPlugin = (CWebViewPlugin *)instance;
    [webViewPlugin release];
    [pool removeObject:[NSValue valueWithPointer:instance]];
}

void _CWebViewPlugin_SetRect(void *instance, int width, int height)
{
    CWebViewPlugin *webViewPlugin = (CWebViewPlugin *)instance;
    [webViewPlugin setRect:width height:height];
}

void _CWebViewPlugin_SetVisibility(void *instance, BOOL visibility)
{
    CWebViewPlugin *webViewPlugin = (CWebViewPlugin *)instance;
    [webViewPlugin setVisibility:visibility];
}

void _CWebViewPlugin_LoadURL(void *instance, const char *url)
{
    CWebViewPlugin *webViewPlugin = (CWebViewPlugin *)instance;
    [webViewPlugin loadURL:url];
}

void _CWebViewPlugin_LoadHTML(void *instance, const char *html, const char *baseUrl)
{
    CWebViewPlugin *webViewPlugin = (CWebViewPlugin *)instance;
    [webViewPlugin loadHTML:html baseURL:baseUrl];
}

void _CWebViewPlugin_EvaluateJS(void *instance, const char *js)
{
    CWebViewPlugin *webViewPlugin = (CWebViewPlugin *)instance;
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

void _CWebViewPlugin_Update(void *instance, int x, int y, float deltaY,
    BOOL buttonDown, BOOL buttonPress, BOOL buttonRelease,
    BOOL keyPress, unsigned char keyCode, const char *keyChars, BOOL refreshBitmap)
{
    CWebViewPlugin *webViewPlugin = (CWebViewPlugin *)instance;
    [webViewPlugin update:x y:y deltaY:deltaY buttonDown:buttonDown
        buttonPress:buttonPress buttonRelease:buttonRelease keyPress:keyPress
        keyCode:keyCode keyChars:keyChars refreshBitmap:refreshBitmap];
}

int _CWebViewPlugin_BitmapWidth(void *instance)
{
    CWebViewPlugin *webViewPlugin = (CWebViewPlugin *)instance;
    return [webViewPlugin bitmapWide];
}

int _CWebViewPlugin_BitmapHeight(void *instance)
{
    CWebViewPlugin *webViewPlugin = (CWebViewPlugin *)instance;
    return [webViewPlugin bitmapHigh];
}

void _CWebViewPlugin_SetTextureId(void *instance, int textureId)
{
    CWebViewPlugin *webViewPlugin = (CWebViewPlugin *)instance;
    [webViewPlugin setTextureId:textureId];
}

static void *_instance;

void _CWebViewPlugin_SetCurrentInstance(void *instance)
{
    _instance = instance;
}

void UnityRenderEvent(int eventId)
{
    @autoreleasepool {
        if (_instance == nil) {
            return;
        }
        if ([pool containsObject:[NSValue valueWithPointer:(void *)_instance]]) {
            CWebViewPlugin *webViewPlugin = (CWebViewPlugin *)_instance;
            _instance = nil;
            [webViewPlugin render];
        }
    }
}

UnityRenderEventFunc GetRenderEventFunc()
{
    return UnityRenderEvent;
}

void _CWebViewPlugin_AddCustomHeader(void *instance, const char *headerKey, const char *headerValue)
{
    CWebViewPlugin *webViewPlugin = (CWebViewPlugin *)instance;
    [webViewPlugin addCustomRequestHeader:headerKey value:headerValue];
}

void _CWebViewPlugin_RemoveCustomHeader(void *instance, const char *headerKey)
{
    CWebViewPlugin *webViewPlugin = (CWebViewPlugin *)instance;
    [webViewPlugin removeCustomRequestHeader:headerKey];
}

const char *_CWebViewPlugin_GetCustomHeaderValue(void *instance, const char *headerKey)
{
    CWebViewPlugin *webViewPlugin = (CWebViewPlugin *)instance;
    return [webViewPlugin getCustomRequestHeaderValue:headerKey];
}

void _CWebViewPlugin_ClearCustomHeader(void *instance)
{
    CWebViewPlugin *webViewPlugin = (CWebViewPlugin *)instance;
    [webViewPlugin clearCustomRequestHeader];
}


