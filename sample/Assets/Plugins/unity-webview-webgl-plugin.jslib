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

	_gree_unity_webview_clearMasks: function() {
		unityWebView.clearMasks();
	},

	_gree_unity_webview_addMask: function(left, top, right, bottom) {
		unityWebView.addMask(left, top, right, bottom);
	},
});
// cf. https://support.unity.com/hc/en-us/articles/208892946-How-can-I-make-the-canvas-transparent-on-WebGL
var LibraryGLClear = {
	glClear: function(mask) {
		if (mask == 0x00004000)
		{
			var v = GLctx.getParameter(GLctx.COLOR_WRITEMASK);
			if (!v[0] && !v[1] && !v[2] && v[3])
				// We are trying to clear alpha only -- skip.
				return;
		}
		GLctx.clear(mask);
	}
};
mergeInto(LibraryManager.library, LibraryGLClear);
