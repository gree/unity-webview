mergeInto(LibraryManager.library, {
	_gree_unity_webview_init: function(name) {
		unityWebView.init(Pointer_stringify(name));
	},

	_gree_unity_webview_setMargins: function (name, left, top, right, bottom) {
		unityWebView.setMargins(Pointer_stringify(name), left, top, right, bottom);
	},

	_gree_unity_webview_setVisibility: function(name, visible) {
		unityWebView.setVisibility(Pointer_stringify(name), visible);
	},

	_gree_unity_webview_loadURL: function(name, url) {
		unityWebView.loadURL(Pointer_stringify(name), Pointer_stringify(url));
	},

	_gree_unity_webview_evaluateJS: function(name, js) {
		unityWebView.evaluateJS(Pointer_stringify(name), Pointer_stringify(js));
	},

	_gree_unity_webview_destroy: function(name) {
		unityWebView.destroy(Pointer_stringify(name));
	},
});