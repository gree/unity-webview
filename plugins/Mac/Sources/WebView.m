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
				@"Contents/Data/Managed/Assembly-CSharp-firstpass.dll";
			assemblyPath = [[[NSBundle mainBundle] bundlePath]
				stringByAppendingPathComponent:dllPath];
		}
		monoDomain = mono_domain_get();
		monoAssembly =
			mono_domain_assembly_open(monoDomain, [assemblyPath UTF8String]);
		monoImage = mono_assembly_get_image(monoAssembly);
		monoDesc = mono_method_desc_new(
			"UnitySendMessageDispatcher:Dispatch(string,string,string)", FALSE);
		monoMethod = mono_method_desc_search_in_image(monoDesc, monoImage);
	}

	void *args[] = {
		mono_string_new(monoDomain, gameObject),
		mono_string_new(monoDomain, method),
		mono_string_new(monoDomain, message),
	};

	mono_runtime_invoke(monoMethod, 0, args, 0);
}

@interface WebViewPlugin : NSObject
{
	WebView *webView;
	NSString *gameObject;
	NSBitmapImageRep *bitmap;
	int textureId;
	BOOL needsDisplay;
}
@end

@implementation WebViewPlugin

- (id)initWithGameObject:(const char *)gameObject_ width:(int)width height:(int)height
{
	self = [super init];
	monoMethod = 0;
	webView = [[WebView alloc] initWithFrame:NSMakeRect(0, 0, width, height)];
	webView.hidden = YES;
	[webView setAutoresizingMask:(NSViewWidthSizable|NSViewHeightSizable)];
	[webView setPolicyDelegate:self];
	gameObject = [[NSString stringWithUTF8String:gameObject_] retain];

	return self;
}

- (void)dealloc
{
	[webView release];
	[gameObject release];
	[bitmap release];
	[super dealloc];
}

- (void)webView:(WebView *)sender decidePolicyForNavigationAction:(NSDictionary *)actionInformation request:(NSURLRequest *)request frame:(WebFrame *)frame decisionListener:(id<WebPolicyDecisionListener>)listener
{
	NSString *url = [[request URL] absoluteString];
	if ([url hasPrefix:@"unity:"]) {
		UnitySendMessage([gameObject UTF8String],
			"CallFromJS", [[url substringFromIndex:6] UTF8String]);
		[listener ignore];
	} else {
		[listener use];
	}
}

- (void)setRect:(int)width height:(int)height
{
	NSRect frame;
	frame.size.width = width;
	frame.size.height = height;
	frame.origin.x = 0;
	frame.origin.y = 0;
	webView.frame = frame;
}

- (void)setVisibility:(BOOL)visibility
{
	webView.hidden = visibility ? NO : YES;
}

- (void)loadURL:(const char *)url
{
	NSString *urlStr = [NSString stringWithUTF8String:url];
	NSURL *nsurl = [NSURL URLWithString:urlStr];
	NSURLRequest *request = [NSURLRequest requestWithURL:nsurl];
	[[webView mainFrame] loadRequest:request];
}

- (void)evaluateJS:(const char *)js
{
	NSString *jsStr = [NSString stringWithUTF8String:js];
	[webView stringByEvaluatingJavaScriptFromString:jsStr];
}

- (void)update:(int)x y:(int)y deltaY:(float)deltaY buttonDown:(BOOL)buttonDown buttonPress:(BOOL)buttonPress buttonRelease:(BOOL)buttonRelease keyPress:(BOOL)keyPress keyCode:(unsigned short)keyCode keyChars:(const char*)keyChars textureId:(int)tId
{
	textureId = tId;
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

	@synchronized(bitmap) {
		needsDisplay = YES; // TODO (bitmap == nil || [view needsDisplay]);
		if (needsDisplay) {
			[bitmap release];
			bitmap = [[webView
				bitmapImageRepForCachingDisplayInRect:[webView visibleRect]] retain];
			[webView cacheDisplayInRect:[webView visibleRect]
				toBitmapImageRep:bitmap];
		}
	}
}

- (void)render
{
	@synchronized(bitmap) {
		if (!needsDisplay)
			return;

		int samplesPerPixel = [bitmap samplesPerPixel];
        int rowLength = 0;
        int unpackAlign = 0;
        glGetIntegerv(GL_UNPACK_ROW_LENGTH, &rowLength);
        glGetIntegerv(GL_UNPACK_ALIGNMENT, &unpackAlign);
		glPixelStorei(GL_UNPACK_ROW_LENGTH,
			[bitmap bytesPerRow] / samplesPerPixel);
		glPixelStorei(GL_UNPACK_ALIGNMENT, 1);
		glBindTexture(GL_TEXTURE_2D, textureId);
		glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
		
		if (![bitmap isPlanar] &&
				(samplesPerPixel == 3 || samplesPerPixel == 4)) {
			glTexImage2D(GL_TEXTURE_2D,
				0,
				samplesPerPixel == 4 ? GL_RGBA8 : GL_RGB8,
				[bitmap pixelsWide],
				[bitmap pixelsHigh],
				0,
				samplesPerPixel == 4 ? GL_RGBA : GL_RGB,
				GL_UNSIGNED_BYTE,
				[bitmap bitmapData]);
		}
        glPixelStorei(GL_UNPACK_ROW_LENGTH, rowLength);
		glPixelStorei(GL_UNPACK_ALIGNMENT, unpackAlign);
	}
}

@end

extern "C" {
void *_WebViewPlugin_Init(
	const char *gameObject, int width, int height, BOOL inEditor);
void _WebViewPlugin_Destroy(void *instance);
void _WebViewPlugin_SetRect(void *instance, int width, int height);
void _WebViewPlugin_SetVisibility(void *instance, BOOL visibility);
void _WebViewPlugin_LoadURL(void *instance, const char *url);
void _WebViewPlugin_EvaluateJS(void *instance, const char *url);
void _WebViewPlugin_Update(void *instance, int x, int y, float deltaY,
	BOOL buttonDown, BOOL buttonPress, BOOL buttonRelease,
	BOOL keyPress, unsigned char keyCode, const char *keyChars, int textureId);
void UnityRenderEvent(int eventID);
}

static NSMutableSet *pool;

void *_WebViewPlugin_Init(
	const char *gameObject, int width, int height, BOOL ineditor)
{
	if (pool == 0)
		pool = [[NSMutableSet alloc] init];

	inEditor = ineditor;
	id instance = [[WebViewPlugin alloc]
		initWithGameObject:gameObject width:width height:height];
	[pool addObject:[NSValue valueWithPointer:instance]];
	return (void *)instance;
}

void _WebViewPlugin_Destroy(void *instance)
{
	WebViewPlugin *webViewPlugin = (WebViewPlugin *)instance;
	[webViewPlugin release];
	[pool removeObject:[NSValue valueWithPointer:instance]];
}

void _WebViewPlugin_SetRect(void *instance, int width, int height)
{
	WebViewPlugin *webViewPlugin = (WebViewPlugin *)instance;
	[webViewPlugin setRect:width height:height];
}

void _WebViewPlugin_SetVisibility(void *instance, BOOL visibility)
{
	WebViewPlugin *webViewPlugin = (WebViewPlugin *)instance;
	[webViewPlugin setVisibility:visibility];
}

void _WebViewPlugin_LoadURL(void *instance, const char *url)
{
	WebViewPlugin *webViewPlugin = (WebViewPlugin *)instance;
	[webViewPlugin loadURL:url];
}

void _WebViewPlugin_EvaluateJS(void *instance, const char *js)
{
	WebViewPlugin *webViewPlugin = (WebViewPlugin *)instance;
	[webViewPlugin evaluateJS:js];
}

void _WebViewPlugin_Update(void *instance, int x, int y, float deltaY,
	BOOL buttonDown, BOOL buttonPress, BOOL buttonRelease, BOOL keyPress,
	unsigned char keyCode, const char *keyChars, int textureId)
{
	WebViewPlugin *webViewPlugin = (WebViewPlugin *)instance;
	[webViewPlugin update:x y:y deltaY:deltaY buttonDown:buttonDown
		buttonPress:buttonPress buttonRelease:buttonRelease keyPress:keyPress
		keyCode:keyCode keyChars:keyChars textureId:textureId];
}

void UnityRenderEvent(int eventID)
{
	@autoreleasepool {
		if ([pool containsObject:[NSValue valueWithPointer:(void *)eventID]]) {
			WebViewPlugin *webViewPlugin = (WebViewPlugin *)eventID;
			[webViewPlugin render];
		}
	}
}
