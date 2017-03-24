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

typedef void *MonoDomain;
typedef void *MonoAssembly;
typedef void *MonoImage;
typedef void *MonoObject;
typedef void *MonoMethodDesc;
typedef void *MonoMethod;
typedef void *MonoString;

extern "C" {
    MonoDomain *mono_domain_get();
    MonoAssembly *mono_domain_assembly_open(
        MonoDomain *domain, const char *assemblyName);
    MonoImage *mono_assembly_get_image(MonoAssembly *assembly);
    MonoMethodDesc *mono_method_desc_new(
        const char *methodString, int useNamespace);
    MonoMethodDesc *mono_method_desc_free(MonoMethodDesc *desc);
    MonoMethod *mono_method_desc_search_in_image(
        MonoMethodDesc *methodDesc, MonoImage *image);
    MonoObject *mono_runtime_invoke(
        MonoMethod *method, void *obj, void **params, MonoObject **exc);
    MonoString *mono_string_new(MonoDomain *domain, const char *text);
}

static BOOL inEditor;
static MonoDomain *monoDomain;
static MonoAssembly *monoAssembly;
static MonoImage *monoImage;
static MonoMethodDesc *monoDesc;
static MonoMethod *monoMethod;

static void UnitySendMessage(
    const char *gameObject, const char *method, const char *message)
{
    if (monoMethod == 0) {
        NSString *assemblyPath;
        if (inEditor) {
            assemblyPath =
                @"Library/ScriptAssemblies/Assembly-CSharp-firstpass.dll";
        } else {
            NSString *dllPath =
                @"Contents/Resources/Data/Managed/Assembly-CSharp-firstpass.dll";
            assemblyPath = [[[NSBundle mainBundle] bundlePath]
                stringByAppendingPathComponent:dllPath];
        }
        monoDomain = mono_domain_get();
        monoDesc = mono_method_desc_new(
            "UnitySendMessageDispatcher:Dispatch(string,string,string)", FALSE);
        
        monoAssembly =
            mono_domain_assembly_open(monoDomain, [assemblyPath UTF8String]);

        if (monoAssembly != 0) {
            monoImage = mono_assembly_get_image(monoAssembly);
            monoMethod = mono_method_desc_search_in_image(monoDesc, monoImage);
        }
        
        
        if (monoMethod == 0) {
            if (inEditor) {
                assemblyPath =
                    @"Library/ScriptAssemblies/Assembly-CSharp.dll";
            } else {
                NSString *dllPath =
                    @"Contents/Resources/Data/Managed/Assembly-CSharp.dll";
                assemblyPath = [[[NSBundle mainBundle] bundlePath]
                                stringByAppendingPathComponent:dllPath];
            }
            monoAssembly =
                mono_domain_assembly_open(monoDomain, [assemblyPath UTF8String]);

            if (monoAssembly != 0) {
                monoImage = mono_assembly_get_image(monoAssembly);
                monoMethod = mono_method_desc_search_in_image(monoDesc, monoImage);
            }
        }
    }
    
    if (monoMethod == 0) {
        return;
    }
    
    void *args[] = {
        mono_string_new(monoDomain, gameObject),
        mono_string_new(monoDomain, method),
        mono_string_new(monoDomain, message),
    };

    mono_runtime_invoke(monoMethod, 0, args, 0);
}

@interface CWebViewPlugin : NSObject
{
    WebView *webView;
    NSString *gameObject;
    NSString *ua;
    NSBitmapImageRep *bitmap;
    int textureId;
    BOOL needsDisplay;
}
@end

@implementation CWebViewPlugin

- (id)initWithGameObject:(const char *)gameObject_ transparent:(BOOL)transparent width:(int)width height:(int)height ua:(const char *)ua_
{
    self = [super init];
    monoMethod = 0;
    webView = [[WebView alloc] initWithFrame:NSMakeRect(0, 0, width, height)];
    webView.hidden = YES;
    if (transparent) {
        [webView setDrawsBackground:NO];
    }
    [webView setAutoresizingMask:(NSViewWidthSizable|NSViewHeightSizable)];
    [webView setFrameLoadDelegate:(id)self];
    [webView setPolicyDelegate:(id)self];
    gameObject = [[NSString stringWithUTF8String:gameObject_] retain];
    if (ua_ != NULL && strcmp(ua_, "") != 0) {
        ua = [[NSString stringWithUTF8String:ua_] retain];
        [webView setCustomUserAgent:ua];
    }
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
        if (ua != nil) {
            [ua release];
            ua = nil;
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
    UnitySendMessage([gameObject UTF8String], "CallOnError", [[error description] UTF8String]);
}

- (void)webView:(WebView *)sender didFinishLoadForFrame:(WebFrame *)frame
{
    UnitySendMessage([gameObject UTF8String], "CallOnLoaded", [[[[[frame dataSource] request] URL] absoluteString] UTF8String]);
}

- (void)webView:(WebView *)sender decidePolicyForNavigationAction:(NSDictionary *)actionInformation request:(NSURLRequest *)request frame:(WebFrame *)frame decisionListener:(id<WebPolicyDecisionListener>)listener
{
    NSString *url = [[request URL] absoluteString];
    if ([url hasPrefix:@"unity:"]) {
        UnitySendMessage([gameObject UTF8String], "CallFromJS", [[url substringFromIndex:6] UTF8String]);
        [listener ignore];
    } else {
        [listener use];
    }
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

- (void)loadURL:(const char *)url
{
    if (webView == nil)
        return;
    NSString *urlStr = [NSString stringWithUTF8String:url];
    NSURL *nsurl = [NSURL URLWithString:urlStr];
    NSURLRequest *request = [NSURLRequest requestWithURL:nsurl];
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

- (void)update:(int)x y:(int)y deltaY:(float)deltaY buttonDown:(BOOL)buttonDown buttonPress:(BOOL)buttonPress buttonRelease:(BOOL)buttonRelease keyPress:(BOOL)keyPress keyCode:(unsigned short)keyCode keyChars:(const char*)keyChars
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
                context:context eventNumber:nil clickCount:1 pressure:nil];
            [view mouseDown:event];
        } else {
            event = [NSEvent mouseEventWithType:NSLeftMouseDragged
                location:NSMakePoint(x, y) modifierFlags:nil
                timestamp:GetCurrentEventTime() windowNumber:0
                context:context eventNumber:nil clickCount:0 pressure:nil];
            [view mouseDragged:event];
        }
    } else if (buttonRelease) {
        event = [NSEvent mouseEventWithType:NSLeftMouseUp
            location:NSMakePoint(x, y) modifierFlags:nil
            timestamp:GetCurrentEventTime() windowNumber:0
            context:context eventNumber:nil clickCount:0 pressure:nil];
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
        if (bitmap == nil)
            bitmap = [[webView bitmapImageRepForCachingDisplayInRect:webView.frame] retain];
        memset([bitmap bitmapData], 0, [bitmap bytesPerRow] * [bitmap pixelsHigh]);
        [webView cacheDisplayInRect:webView.frame toBitmapImageRep:bitmap];
        needsDisplay = YES; // TODO (bitmap == nil || [view needsDisplay]);
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

@end

typedef void (*UnityRenderEventFunc)(int eventId);
extern "C" {
const char *_CWebViewPlugin_GetAppPath();
void *_CWebViewPlugin_Init(
    const char *gameObject, BOOL transparent, int width, int height, const char *ua, BOOL ineditor);
void _CWebViewPlugin_Destroy(void *instance);
void _CWebViewPlugin_SetRect(void *instance, int width, int height);
void _CWebViewPlugin_SetVisibility(void *instance, BOOL visibility);
void _CWebViewPlugin_LoadURL(void *instance, const char *url);
void _CWebViewPlugin_LoadHTML(void *instance, const char *html, const char *baseUrl);
void _CWebViewPlugin_EvaluateJS(void *instance, const char *url);
BOOL _CWebViewPlugin_CanGoBack(void *instance);
BOOL _CWebViewPlugin_CanGoForward(void *instance);
void _CWebViewPlugin_GoBack(void *instance);
void _CWebViewPlugin_GoForward(void *instance);
void _CWebViewPlugin_Update(void *instance, int x, int y, float deltaY,
    BOOL buttonDown, BOOL buttonPress, BOOL buttonRelease,
    BOOL keyPress, unsigned char keyCode, const char *keyChars);
int _CWebViewPlugin_BitmapWidth(void *instance);
int _CWebViewPlugin_BitmapHeight(void *instance);
void _CWebViewPlugin_SetTextureId(void *instance, int textureId);
void _CWebViewPlugin_SetCurrentInstance(void *instance);
void UnityRenderEvent(int eventId);
UnityRenderEventFunc GetRenderEventFunc();
}

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
    BOOL buttonDown, BOOL buttonPress, BOOL buttonRelease, BOOL keyPress,
    unsigned char keyCode, const char *keyChars)
{
    CWebViewPlugin *webViewPlugin = (CWebViewPlugin *)instance;
    [webViewPlugin update:x y:y deltaY:deltaY buttonDown:buttonDown
        buttonPress:buttonPress buttonRelease:buttonRelease keyPress:keyPress
        keyCode:keyCode keyChars:keyChars];
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
