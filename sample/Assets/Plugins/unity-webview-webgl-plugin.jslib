mergeInto(LibraryManager.library, {
	_gree_unity_webview_init: function(name) {
		var stringify = (UTF8ToString === undefined) ? Pointer_stringify : UTF8ToString;
		unityWebView.init(stringify(name));
	},

	_gree_unity_webview_setMargins: function (name, left, top, right, bottom) {
		var stringify = (UTF8ToString === undefined) ? Pointer_stringify : UTF8ToString;
		unityWebView.setMargins(stringify(name), left, top, right, bottom);
	},

	_gree_unity_webview_setVisibility: function(name, visible) {
		var stringify = (UTF8ToString === undefined) ? Pointer_stringify : UTF8ToString;
		unityWebView.setVisibility(stringify(name), visible);
	},

	_gree_unity_webview_loadURL: function(name, url) {
		var stringify = (UTF8ToString === undefined) ? Pointer_stringify : UTF8ToString;
		unityWebView.loadURL(stringify(name), stringify(url));
	},

	_gree_unity_webview_evaluateJS: function(name, js) {
		var stringify = (UTF8ToString === undefined) ? Pointer_stringify : UTF8ToString;
		unityWebView.evaluateJS(stringify(name), stringify(js));
	},

	_gree_unity_webview_destroy: function(name) {
		var stringify = (UTF8ToString === undefined) ? Pointer_stringify : UTF8ToString;
		unityWebView.destroy(stringify(name));
	},
});
