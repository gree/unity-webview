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

extern UIViewController *UnityGetGLViewController();
extern "C" void UnitySendMessage(const char *, const char *, const char *);

@interface WebViewPlugin : NSObject<UIWebViewDelegate>
{
	UIWebView *webView;
	NSString *gameObjectName;
}
@end

@implementation WebViewPlugin

- (id)initWithGameObjectName:(const char *)gameObjectName_
{
	self = [super init];

	UIView *view = UnityGetGLViewController().view;
	webView = [[UIWebView alloc] initWithFrame:view.frame];
	webView.delegate = self;
	webView.hidden = YES;
	[view addSubview:webView];
	gameObjectName = [[NSString stringWithUTF8String:gameObjectName_] retain];

	return self;
}

- (void)dealloc
{
	[webView removeFromSuperview];
	[webView release];
	[gameObjectName release];
	[super dealloc];
}

- (BOOL)webView:(UIWebView *)webView shouldStartLoadWithRequest:(NSURLRequest *)request navigationType:(UIWebViewNavigationType)navigationType
{
	NSString *url = [[request URL] absoluteString];
	if ([url hasPrefix:@"unity:"]) {
		UnitySendMessage([gameObjectName UTF8String],
			"CallFromJS", [[url substringFromIndex:6] UTF8String]);
		return NO;
	} else {
		return YES;
	}
}

- (void)setFrame:(NSInteger)x positionY:(NSInteger)y width:(NSInteger)width height:(NSInteger)height
{
    UIView* view = UnityGetGLViewController().view;
    CGRect frame = webView.frame;
    CGRect screen = view.bounds;
    frame.origin.x = x + ((screen.size.width - width)/2);
    frame.origin.y = -y + ((screen.size.height - height)/2);
    frame.size.width = width;
    frame.size.height = height;
    webView.frame = frame;
}

- (void)setMargins:(int)left top:(int)top right:(int)right bottom:(int)bottom
{
	UIView *view = UnityGetGLViewController().view;
	CGRect frame = webView.frame;
	CGRect screen = view.bounds;
	CGFloat scale = 1.0f / view.contentScaleFactor;
	frame.size.width = screen.size.width - scale * (left + right) ;
	frame.size.height = screen.size.height - scale * (top + bottom) ;
	frame.origin.x = scale * left ;
	frame.origin.y = scale * top ;
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
	[webView loadRequest:request];
}

- (void)evaluateJS:(const char *)js
{
	NSString *jsStr = [NSString stringWithUTF8String:js];
	[webView stringByEvaluatingJavaScriptFromString:jsStr];
}

@end

extern "C" {
	void *_WebViewPlugin_Init(const char *gameObjectName);
	void _WebViewPlugin_Destroy(void *instance);
	void _WebViewPlugin_SetFrame(void* instace,NSInteger x,NSInteger y,NSInteger width,NSInteger height);
	void _WebViewPlugin_SetMargins(
		void *instance, int left, int top, int right, int bottom);
	void _WebViewPlugin_SetVisibility(void *instance, BOOL visibility);
	void _WebViewPlugin_LoadURL(void *instance, const char *url);
	void _WebViewPlugin_EvaluateJS(void *instance, const char *url);
}

void *_WebViewPlugin_Init(const char *gameObjectName)
{
	id instance = [[WebViewPlugin alloc] initWithGameObjectName:gameObjectName];
	return (void *)instance;
}

void _WebViewPlugin_Destroy(void *instance)
{
	WebViewPlugin *webViewPlugin = (WebViewPlugin *)instance;
	[webViewPlugin release];
}

void _WebViewPlugin_SetFrame(void* instance,NSInteger x,NSInteger y,NSInteger width,NSInteger height)
{
    float screenScale = [ UIScreen instancesRespondToSelector:@selector( scale ) ]?
    [ UIScreen mainScreen ].scale:1.0f;
    
    WebViewPlugin* webViewPlugin = (WebViewPlugin*)instance;
    if(UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad){
        if(screenScale == 2.0)
            screenScale = 1.0f;
    }
    [webViewPlugin setFrame:x/screenScale positionY:y/screenScale width:width/screenScale height: height/screenScale];
}

void _WebViewPlugin_SetMargins(
	void *instance, int left, int top, int right, int bottom)
{
	WebViewPlugin *webViewPlugin = (WebViewPlugin *)instance;
	[webViewPlugin setMargins:left top:top right:right bottom:bottom];
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
