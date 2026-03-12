/*
 * Copyright (C) 2012 GREE, Inc.
 * Windows WebView2 implementation for unity-webview.
 *
 * This software is provided 'as-is'. See repository root LICENSE.
 * Uses Microsoft WebView2 (Edge Chromium). Requires WebView2 Runtime.
 */

#define WIN32_LEAN_AND_MEAN
#define NOMINMAX
#include <windows.h>
#include <objbase.h>
#include <wrl.h>
#include <string>
#include <cstring>
#include <queue>
#include <mutex>
#include <memory>
#include <atomic>
#include <stdio.h>

#include "WebView2.h"

#pragma comment(lib, "user32.lib")
#pragma comment(lib, "ole32.lib")

// Set to 1 to log input and window info to OutputDebugString.
// View logs: run DebugView (Sysinternals) as admin and enable "Capture Global Win32", or run Unity from Visual Studio and check Output.
#ifndef WEBVIEW_DEBUG
#define WEBVIEW_DEBUG 0
#endif
#if WEBVIEW_DEBUG
#define WV_LOG(fmt, ...) do { char _buf[384]; snprintf(_buf, sizeof(_buf), "[WebView2] " fmt "\n", ##__VA_ARGS__); OutputDebugStringA(_buf); } while(0)
#else
#define WV_LOG(fmt, ...) ((void)0)
#endif

using namespace Microsoft::WRL;

//------------------------------------------------------------------------------
// Message queue (thread-safe; producer = WebView2 callbacks on STA, consumer = GetMessage on Unity thread)
//------------------------------------------------------------------------------
struct MessageQueue {
    std::mutex mtx;
    std::queue<std::string> q;

    void push(const std::string& s) {
        std::lock_guard<std::mutex> lk(mtx);
        q.push(s);
    }

    bool pop(std::string& out) {
        std::lock_guard<std::mutex> lk(mtx);
        if (q.empty()) return false;
        out = std::move(q.front());
        q.pop();
        return true;
    }
};

//------------------------------------------------------------------------------
// Instance state
//------------------------------------------------------------------------------
struct WebViewInstance {
    HWND hwnd = nullptr;
    ComPtr<ICoreWebView2Controller> controller;
    ComPtr<ICoreWebView2CompositionController> compositionController;
    ComPtr<ICoreWebView2> webview;
    MessageQueue messages;
    std::string gameObjectName;

    int rectWidth = 0;
    int rectHeight = 0;
    bool visible = true;

    // Bitmap from CapturePreview (decoded to RGBA). Double-buffered: STA thread decodes into
    // bitmapPixelsBack then swaps with bitmapPixels so Render() reads consistent front buffer.
    std::mutex bitmapMutex;
    std::vector<uint8_t> bitmapPixels;
    int bitmapWidth = 0;
    int bitmapHeight = 0;
    std::vector<uint8_t> bitmapPixelsBack;
    int bitmapWidthBack = 0;
    int bitmapHeightBack = 0;
    std::atomic<bool> captureInProgress{ false };
    HANDLE captureDoneEvent = nullptr;

    // Custom headers for navigation
    std::mutex headersMutex;
    std::wstring customHeaders; // "Key: Value\r\n..."

    // URL pattern (allow/deny/hook) - simplified: we allow all for now
    bool allowAllUrls = true;

    // Cached for main-thread read
    std::mutex cacheMutex;
    bool canGoBack = false;
    bool canGoForward = false;
};

static std::mutex s_instancesMutex;
static std::vector<std::unique_ptr<WebViewInstance>> s_instances;

//------------------------------------------------------------------------------
// PNG stream -> RGBA using WIC
//------------------------------------------------------------------------------
#include <wincodec.h>
#pragma comment(lib, "windowscodecs.lib")

static bool DecodePngStreamToRgba(IStream* stream, std::vector<uint8_t>& outPixels, int& outWidth, int& outHeight) {
    ComPtr<IWICImagingFactory> factory;
    HRESULT hr = CoCreateInstance(CLSID_WICImagingFactory, nullptr, CLSCTX_INPROC_SERVER, IID_PPV_ARGS(&factory));
    if (FAILED(hr)) return false;

    ComPtr<IWICBitmapDecoder> decoder;
    hr = factory->CreateDecoderFromStream(stream, nullptr, WICDecodeMetadataCacheOnLoad, &decoder);
    if (FAILED(hr)) return false;

    ComPtr<IWICBitmapFrameDecode> frame;
    hr = decoder->GetFrame(0, &frame);
    if (FAILED(hr)) return false;

    UINT width, height;
    hr = frame->GetSize(&width, &height);
    if (FAILED(hr)) return false;

    ComPtr<IWICFormatConverter> converter;
    hr = factory->CreateFormatConverter(&converter);
    if (FAILED(hr)) return false;

    WICPixelFormatGUID format = GUID_WICPixelFormat32bppRGBA;
    hr = converter->Initialize(frame.Get(), format, WICBitmapDitherTypeNone, nullptr, 0.f, WICBitmapPaletteTypeCustom);
    if (FAILED(hr)) return false;

    UINT stride = width * 4;
    UINT size = stride * height;
    outPixels.resize(size);
    hr = converter->CopyPixels(nullptr, stride, size, outPixels.data());
    if (FAILED(hr)) return false;

    outWidth = (int)width;
    outHeight = (int)height;
    return true;
}

//------------------------------------------------------------------------------
// STA thread and window
//------------------------------------------------------------------------------
enum CustomMsg {
    WM_WEBVIEW_CREATE = WM_USER + 1,
    WM_WEBVIEW_DESTROY,
    WM_WEBVIEW_LOAD_URL,
    WM_WEBVIEW_LOAD_HTML,
    WM_WEBVIEW_EVAL_JS,
    WM_WEBVIEW_SET_RECT,
    WM_WEBVIEW_SET_VISIBILITY,
    WM_WEBVIEW_GO_BACK,
    WM_WEBVIEW_GO_FORWARD,
    WM_WEBVIEW_RELOAD,
    WM_WEBVIEW_CAPTURE,
    WM_WEBVIEW_ADD_HEADER,
    WM_WEBVIEW_REMOVE_HEADER,
    WM_WEBVIEW_CLEAR_HEADERS,
    WM_WEBVIEW_CLEAR_COOKIES,
    WM_WEBVIEW_SEND_MOUSE,
    WM_WEBVIEW_SEND_KEY,
};

struct MouseEventData {
    int x, y;
    float deltaY;
    int mouseState;
};

struct KeyEventData {
    char* keyChars;  // owned; STA thread must free
    unsigned short keyCode;
    int keyState;
};

struct CreateParams {
    WebViewInstance* instance = nullptr;
    std::wstring userDataFolder;
    std::wstring userAgent;
    bool transparent = false;
    bool zoom = true;
    int width = 0;
    int height = 0;
    HANDLE readyEvent = nullptr;
    HRESULT createResult = E_PENDING;
};

static LRESULT CALLBACK WndProc(HWND hwnd, UINT msg, WPARAM wParam, LPARAM lParam) {
    WebViewInstance* inst = (WebViewInstance*)GetWindowLongPtr(hwnd, GWLP_USERDATA);

    switch (msg) {
    case WM_CREATE: {
        CREATESTRUCT* cs = (CREATESTRUCT*)lParam;
        CreateParams* params = (CreateParams*)cs->lpCreateParams;
        SetWindowLongPtr(hwnd, GWLP_USERDATA, (LONG_PTR)params->instance);
        params->instance->hwnd = hwnd;

        // Create WebView2 in same thread (we are on STA)
        params->instance->gameObjectName = "WebViewObject"; // will be set by Init

        // Use user-writable dir (e.g. %LOCALAPPDATA%\UnityWebView2). Program Files is not writable.
        std::wstring path;
        WCHAR localAppData[MAX_PATH];
        if (GetEnvironmentVariableW(L"LOCALAPPDATA", localAppData, MAX_PATH) > 0) {
            path = localAppData;
            path += L"\\UnityWebView2";
        } else {
            WCHAR tmp[MAX_PATH];
            GetModuleFileNameW(nullptr, tmp, MAX_PATH);
            path = tmp;
            size_t last = path.find_last_of(L"\\/");
            if (last != std::wstring::npos) path = path.substr(0, last);
            path += L"\\WebView2Data";
        }
        CreateDirectoryW(path.c_str(), nullptr);

        ComPtr<ICoreWebView2Environment> env;
        HRESULT hr = CreateCoreWebView2EnvironmentWithOptions(
            nullptr, path.c_str(), nullptr,
            Callback<ICoreWebView2CreateCoreWebView2EnvironmentCompletedHandler>(
                [params](HRESULT err, ICoreWebView2Environment* e) -> HRESULT {
                    if (FAILED(err)) {
                        params->createResult = err;
                        SetEvent(params->readyEvent);
                        return S_OK;
                    }
                    ComPtr<ICoreWebView2Environment> env(e);
                    params->instance->hwnd = params->instance->hwnd;
                    ComPtr<ICoreWebView2Environment3> env3;
                    HRESULT hrQI = e->QueryInterface(IID_PPV_ARGS(&env3));
                    if (FAILED(hrQI) || !env3) {
                        params->createResult = hrQI;
                        SetEvent(params->readyEvent);
                        return S_OK;
                    }
                    env3->CreateCoreWebView2CompositionController(params->instance->hwnd,
                        Callback<ICoreWebView2CreateCoreWebView2CompositionControllerCompletedHandler>(
                            [params](HRESULT err2, ICoreWebView2CompositionController* compCtrl) -> HRESULT {
                                if (FAILED(err2)) {
                                    params->createResult = err2;
                                    SetEvent(params->readyEvent);
                                    return S_OK;
                                }
                                WebViewInstance* inst = params->instance;
                                inst->compositionController = compCtrl;
                                ComPtr<ICoreWebView2Controller> ctrl;
                                if (SUCCEEDED(compCtrl->QueryInterface(IID_PPV_ARGS(&ctrl)))) {
                                    inst->controller = ctrl;
                                    ctrl->get_CoreWebView2(&inst->webview);
                                }
                                if (!inst->webview) {
                                    params->createResult = E_FAIL;
                                    SetEvent(params->readyEvent);
                                    return S_OK;
                                }
                                inst->rectWidth = params->width;
                                inst->rectHeight = params->height;

                                ComPtr<ICoreWebView2Settings> settings;
                                inst->webview->get_Settings(&settings);
                                if (settings) {
                                    settings->put_IsScriptEnabled(TRUE);
                                    settings->put_AreDefaultScriptDialogsEnabled(TRUE);
                                }

                                // Inject Unity.call for JS -> C#
                                std::wstring script = L"window.Unity = { call: function(msg) { window.chrome.webview.postMessage(msg); } };";
                                inst->webview->AddScriptToExecuteOnDocumentCreated(script.c_str(), nullptr);

                                // Message from JS
                                inst->webview->add_WebMessageReceived(
                                    Callback<ICoreWebView2WebMessageReceivedEventHandler>(
                                        [inst](ICoreWebView2* wv, ICoreWebView2WebMessageReceivedEventArgs* args) -> HRESULT {
                                            LPWSTR msgRaw = nullptr;
                                            args->TryGetWebMessageAsString(&msgRaw);
                                            if (msgRaw) {
                                                int n = WideCharToMultiByte(CP_UTF8, 0, msgRaw, -1, nullptr, 0, nullptr, nullptr);
                                                std::string s(n, 0);
                                                WideCharToMultiByte(CP_UTF8, 0, msgRaw, -1, &s[0], n, nullptr, nullptr);
                                                if (s.back() == '\0') s.pop_back();
                                                inst->messages.push("CallFromJS:" + s);
                                                CoTaskMemFree(msgRaw);
                                            }
                                            return S_OK;
                                        }).Get(), nullptr);

                                // Navigation events
                                inst->webview->add_NavigationStarting(
                                    Callback<ICoreWebView2NavigationStartingEventHandler>(
                                        [inst](ICoreWebView2* wv, ICoreWebView2NavigationStartingEventArgs* args) -> HRESULT {
                                            LPWSTR uriRaw = nullptr;
                                            args->get_Uri(&uriRaw);
                                            if (uriRaw) {
                                                int n = WideCharToMultiByte(CP_UTF8, 0, uriRaw, -1, nullptr, 0, nullptr, nullptr);
                                                std::string uri(n, 0);
                                                WideCharToMultiByte(CP_UTF8, 0, uriRaw, -1, &uri[0], n, nullptr, nullptr);
                                                if (uri.back() == '\0') uri.pop_back();
                                                inst->messages.push("CallOnStarted:" + uri);
                                                CoTaskMemFree(uriRaw);
                                            }
                                            return S_OK;
                                        }).Get(), nullptr);

                                inst->webview->add_NavigationCompleted(
                                    Callback<ICoreWebView2NavigationCompletedEventHandler>(
                                        [inst](ICoreWebView2* wv, ICoreWebView2NavigationCompletedEventArgs* args) -> HRESULT {
                                            BOOL success = FALSE;
                                            args->get_IsSuccess(&success);
                                            if (success) {
                                                LPWSTR uriRaw = nullptr;
                                                wv->get_Source(&uriRaw);
                                                if (uriRaw) {
                                                    int n = WideCharToMultiByte(CP_UTF8, 0, uriRaw, -1, nullptr, 0, nullptr, nullptr);
                                                    std::string uri(n, 0);
                                                    WideCharToMultiByte(CP_UTF8, 0, uriRaw, -1, &uri[0], n, nullptr, nullptr);
                                                    if (uri.back() == '\0') uri.pop_back();
                                                    inst->messages.push("CallOnLoaded:" + uri);
                                                    CoTaskMemFree(uriRaw);
                                                }
                                            }
                                            BOOL back = FALSE, fwd = FALSE;
                                            wv->get_CanGoBack(&back);
                                            wv->get_CanGoForward(&fwd);
                                            {
                                                std::lock_guard<std::mutex> lk(inst->cacheMutex);
                                                inst->canGoBack = (back != FALSE);
                                                inst->canGoForward = (fwd != FALSE);
                                            }
                                            return S_OK;
                                        }).Get(), nullptr);

                                // Resize and show (composition controller also implements controller)
                                if (inst->controller) {
                                    RECT r = { 0, 0, params->width, params->height };
                                    inst->controller->put_Bounds(r);
                                    inst->controller->put_IsVisible(TRUE);
                                }

                                params->createResult = S_OK;
                                SetEvent(params->readyEvent);
                                return S_OK;
                            }).Get());
                    return S_OK;
                }).Get());

        return 0;
    }
    case WM_WEBVIEW_DESTROY: {
        HANDLE destroyDoneEvent = (HANDLE)lParam;
        if (inst) {
            inst->controller = nullptr;
            inst->compositionController = nullptr;
            inst->webview = nullptr;
            if (inst->captureDoneEvent) {
                CloseHandle(inst->captureDoneEvent);
                inst->captureDoneEvent = nullptr;
            }
        }
        if (destroyDoneEvent)
            SetEvent(destroyDoneEvent);
        DestroyWindow(hwnd);
        return 0;
    }
    case WM_WEBVIEW_LOAD_URL: {
        if (inst && inst->webview) {
            wchar_t* url = (wchar_t*)lParam;
            inst->webview->Navigate(url);
            delete[] url;
        }
        return 0;
    }
    case WM_WEBVIEW_LOAD_HTML: {
        if (inst && inst->webview) {
            wchar_t* html = (wchar_t*)wParam;
            wchar_t* baseUrl = (wchar_t*)lParam;
            inst->webview->NavigateToString(html);
            delete[] html;
            if (baseUrl) delete[] baseUrl;
        }
        return 0;
    }
    case WM_WEBVIEW_EVAL_JS: {
        if (inst && inst->webview) {
            wchar_t* js = (wchar_t*)lParam;
            inst->webview->ExecuteScript(js, Callback<ICoreWebView2ExecuteScriptCompletedHandler>(
                [](HRESULT err, LPCWSTR result) -> HRESULT { return S_OK; }).Get());
            delete[] js;
        }
        return 0;
    }
    case WM_WEBVIEW_SET_RECT: {
        if (inst && inst->controller) {
            int w = (int)wParam;
            int h = (int)lParam;
            inst->rectWidth = w;
            inst->rectHeight = h;
            RECT r = { 0, 0, w, h };
            inst->controller->put_Bounds(r);
        }
        return 0;
    }
    case WM_WEBVIEW_SET_VISIBILITY: {
        if (inst && inst->controller) {
            inst->visible = (wParam != 0);
            inst->controller->put_IsVisible(inst->visible ? TRUE : FALSE);
        }
        return 0;
    }
    case WM_WEBVIEW_GO_BACK:
        if (inst && inst->webview) inst->webview->GoBack();
        return 0;
    case WM_WEBVIEW_GO_FORWARD:
        if (inst && inst->webview) inst->webview->GoForward();
        return 0;
    case WM_WEBVIEW_RELOAD:
        if (inst && inst->webview) inst->webview->Reload();
        return 0;
    case WM_WEBVIEW_CAPTURE: {
        if (!inst || !inst->webview) {
            if (inst && inst->captureDoneEvent) SetEvent(inst->captureDoneEvent);
            if (inst) inst->captureInProgress = false;
            return 0;
        }
        HANDLE doneEv = (HANDLE)lParam;
        inst->captureDoneEvent = doneEv;

        ComPtr<IStream> stream;
        CreateStreamOnHGlobal(nullptr, TRUE, &stream);
        ComPtr<IStream> streamRef = stream;

        inst->webview->CapturePreview(COREWEBVIEW2_CAPTURE_PREVIEW_IMAGE_FORMAT_PNG, stream.Get(),
            Callback<ICoreWebView2CapturePreviewCompletedHandler>(
                [inst, streamRef](HRESULT err) -> HRESULT {
                    if (SUCCEEDED(err) && streamRef) {
                        LARGE_INTEGER zero = { 0 };
                        streamRef->Seek(zero, STREAM_SEEK_SET, nullptr);
                        std::vector<uint8_t> pixels;
                        int w, h;
                        if (DecodePngStreamToRgba(streamRef.Get(), pixels, w, h)) {
                            std::lock_guard<std::mutex> lk(inst->bitmapMutex);
                            inst->bitmapPixelsBack = std::move(pixels);
                            inst->bitmapWidthBack = w;
                            inst->bitmapHeightBack = h;
                            inst->bitmapPixels.swap(inst->bitmapPixelsBack);
                            inst->bitmapWidth = inst->bitmapWidthBack;
                            inst->bitmapHeight = inst->bitmapHeightBack;
                        }
                    }
                    if (inst->captureDoneEvent) SetEvent(inst->captureDoneEvent);
                    inst->captureInProgress = false;
                    return S_OK;
                }).Get());
        return 0;
    }
    case WM_WEBVIEW_SEND_MOUSE: {
        MouseEventData* data = (MouseEventData*)lParam;
        if (!inst || !data) return 0;
        int winX = data->x;
        int winY = inst->rectHeight > 0 ? (inst->rectHeight - 1 - data->y) : data->y;
        winX = (winX < 0) ? 0 : (winX >= inst->rectWidth ? inst->rectWidth - 1 : winX);
        winY = (winY < 0) ? 0 : (winY >= inst->rectHeight ? inst->rectHeight - 1 : winY);
        POINT pt = { winX, winY };
        COREWEBVIEW2_MOUSE_EVENT_VIRTUAL_KEYS vk = COREWEBVIEW2_MOUSE_EVENT_VIRTUAL_KEYS_NONE;
        if (data->mouseState == 2 || data->mouseState == 1) vk = COREWEBVIEW2_MOUSE_EVENT_VIRTUAL_KEYS_LEFT_BUTTON;

        if (inst->compositionController) {
            WV_LOG("MOUSE SendMouseInput: x=%d y=%d state=%d", winX, winY, data->mouseState);
            inst->compositionController->SendMouseInput(COREWEBVIEW2_MOUSE_EVENT_KIND_MOVE, vk, 0, pt);
            if (data->mouseState == 1)
                inst->compositionController->SendMouseInput(COREWEBVIEW2_MOUSE_EVENT_KIND_LEFT_BUTTON_DOWN, COREWEBVIEW2_MOUSE_EVENT_VIRTUAL_KEYS_LEFT_BUTTON, 0, pt);
            else if (data->mouseState == 3)
                inst->compositionController->SendMouseInput(COREWEBVIEW2_MOUSE_EVENT_KIND_LEFT_BUTTON_UP, COREWEBVIEW2_MOUSE_EVENT_VIRTUAL_KEYS_NONE, 0, pt);
            if (data->deltaY != 0.f) {
                int wheelData = (int)(data->deltaY * 120);
                if (wheelData == 0 && data->deltaY != 0.f) wheelData = data->deltaY > 0 ? 120 : -120;
                inst->compositionController->SendMouseInput(COREWEBVIEW2_MOUSE_EVENT_KIND_WHEEL, COREWEBVIEW2_MOUSE_EVENT_VIRTUAL_KEYS_NONE, (UINT32)wheelData, pt);
            }
        } else {
            HWND target = GetWindow(hwnd, GW_CHILD);
            if (!target) target = hwnd;
            LPARAM lParamPos = MAKELPARAM(winX, winY);
            // Do not SetFocus(target) here: it would activate the off-screen host and cause the Unity window to lose focus (e.g. minimize).
            SendMessage(target, WM_MOUSEMOVE, 0, lParamPos);
            if (data->mouseState == 1) SendMessage(target, WM_LBUTTONDOWN, MK_LBUTTON, lParamPos);
            else if (data->mouseState == 2) SendMessage(target, WM_MOUSEMOVE, MK_LBUTTON, lParamPos);
            else if (data->mouseState == 3) SendMessage(target, WM_LBUTTONUP, 0, lParamPos);
            if (data->deltaY != 0.f) {
                short wheel = (short)(data->deltaY * 120);
                if (wheel == 0 && data->deltaY != 0.f) wheel = data->deltaY > 0 ? 120 : -120;
                POINT ptScreen = { winX, winY };
                ClientToScreen(target, &ptScreen);
                SendMessage(target, WM_MOUSEWHEEL, MAKEWPARAM(0, wheel), MAKELPARAM(ptScreen.x, ptScreen.y));
            }
        }
        delete data;
        return 0;
    }
    case WM_WEBVIEW_SEND_KEY: {
        KeyEventData* data = (KeyEventData*)lParam;
        if (!inst || !data) return 0;
        HWND child = GetWindow(hwnd, GW_CHILD);
        HWND target = child ? child : hwnd;
        WV_LOG("KEY recv: hwnd=%p child=%p target=%p keyCode=%u keyState=%d hasChars=%d",
               (void*)hwnd, (void*)child, (void*)target, (unsigned)data->keyCode, data->keyState,
               data->keyChars && data->keyChars[0] ? 1 : 0);
        HWND fg = GetForegroundWindow();
        SetFocus(target);
        if (data->keyChars && data->keyChars[0]) {
            WCHAR wch[32];
            int n = MultiByteToWideChar(CP_UTF8, 0, data->keyChars, -1, wch, 32);
            if (n > 0) {
                for (int i = 0; wch[i]; i++) {
                    SendMessage(target, WM_CHAR, (WPARAM)wch[i], 0);
                }
            }
        }
        if (data->keyCode != 0) {
            LPARAM lp = 1 | (LPARAM)MapVirtualKeyW(data->keyCode, MAPVK_VK_TO_VSC) << 16;
            if (data->keyState == 1 || data->keyState == 2)
                SendMessage(target, WM_KEYDOWN, (WPARAM)data->keyCode, lp);
            if (data->keyState == 3)
                SendMessage(target, WM_KEYUP, (WPARAM)data->keyCode, lp);
        }
        if (fg && fg != hwnd)
            SetForegroundWindow(fg);
        delete[] data->keyChars;
        delete data;
        return 0;
    }
    case WM_DESTROY:
        PostQuitMessage(0);
        return 0;
    default:
        return DefWindowProc(hwnd, msg, wParam, lParam);
    }
    return DefWindowProc(hwnd, msg, wParam, lParam);
}

// Run message loop until WebView2 is created (used in Init)
static DWORD WINAPI STAThreadProc(LPVOID param) {
    CreateParams* params = (CreateParams*)param;
    CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

    WNDCLASSEXW wc = {};
    wc.cbSize = sizeof(wc);
    wc.lpfnWndProc = WndProc;
    wc.hInstance = GetModuleHandle(nullptr);
    wc.lpszClassName = L"UnityWebView2Window";
    RegisterClassExW(&wc);

    // Use WS_EX_TOOLWINDOW and WS_POPUP to prevent the window from appearing on the taskbar.
    // WS_EX_NOACTIVATE prevents the host from being activated when receiving focus, avoiding Unity window minimize on click.
    HWND hwnd = CreateWindowExW(WS_EX_TOOLWINDOW | WS_EX_NOACTIVATE, wc.lpszClassName, L"", WS_POPUP,
        0, 0, params->width > 0 ? params->width : 640, params->height > 0 ? params->height : 480,
        nullptr, nullptr, wc.hInstance, params);
    if (!hwnd) {
        params->createResult = E_FAIL;
        SetEvent(params->readyEvent);
        CoUninitialize();
        return 1;
    }

    // Visible but off-screen so WebView2 child receives input; fully hidden windows may ignore mouse/key.
    SetWindowPos(hwnd, nullptr, -32000, -32000, 0, 0, SWP_NOSIZE | SWP_NOZORDER | SWP_NOACTIVATE);
    ShowWindow(hwnd, SW_SHOWNOACTIVATE);

    MSG msg;
    while (GetMessage(&msg, nullptr, 0, 0)) {
        if (msg.message == WM_WEBVIEW_CREATE) {
            // already handled in WM_CREATE
        }
        TranslateMessage(&msg);
        DispatchMessage(&msg);
    }

    UnregisterClassW(wc.lpszClassName, wc.hInstance);
    CoUninitialize();
    return 0;
}

// Helper: run action on STA thread by posting to the instance's window
static void PostToInstance(WebViewInstance* inst, UINT msg, WPARAM wParam = 0, LPARAM lParam = 0) {
    if (inst && inst->hwnd)
        PostMessage(inst->hwnd, msg, wParam, lParam);
}

static void PostToInstanceAndWait(WebViewInstance* inst, UINT msg, WPARAM wParam, LPARAM lParam, HANDLE eventToSignal) {
    if (!inst || !inst->hwnd) {
        if (eventToSignal) SetEvent(eventToSignal);
        return;
    }
    PostMessage(inst->hwnd, msg, wParam, lParam);
    if (eventToSignal)
        WaitForSingleObject(eventToSignal, 10000);
}

//------------------------------------------------------------------------------
// C API (exported; match Mac signatures for Unity DllImport)
//------------------------------------------------------------------------------
extern "C" {

__declspec(dllexport) const char* _CWebViewPlugin_GetAppPath(void) {
    static std::string path;
    if (path.empty()) {
        char buf[MAX_PATH] = "";
        GetModuleFileNameA(nullptr, buf, MAX_PATH);
        std::string p(buf);
        size_t last = p.find_last_of("\\/");
        if (last != std::string::npos) p = p.substr(0, last);
        path = p;
    }
    return path.c_str();
}

__declspec(dllexport) void _CWebViewPlugin_InitStatic(bool inEditor, bool useMetal) {
    (void)inEditor;
    (void)useMetal;
}

__declspec(dllexport) bool _CWebViewPlugin_IsInitialized(void* instance) {
    WebViewInstance* inst = (WebViewInstance*)instance;
    return inst && inst->webview != nullptr;
}

__declspec(dllexport) void* _CWebViewPlugin_Init(
    const char* gameObject, bool transparent, bool zoom, int width, int height, const char* ua, bool separated)
{
    (void)transparent;
    (void)separated;
    if (!gameObject) return nullptr;

    auto inst = std::make_unique<WebViewInstance>();
    inst->rectWidth = width > 0 ? width : 640;
    inst->rectHeight = height > 0 ? height : 480;
    inst->captureDoneEvent = CreateEvent(nullptr, FALSE, FALSE, nullptr);

    CreateParams params;
    params.instance = inst.get();
    params.width = inst->rectWidth;
    params.height = inst->rectHeight;
    params.zoom = zoom;
    params.readyEvent = CreateEvent(nullptr, FALSE, FALSE, nullptr);
    if (ua && ua[0]) {
        int n = MultiByteToWideChar(CP_UTF8, 0, ua, -1, nullptr, 0);
        params.userAgent.resize(n);
        MultiByteToWideChar(CP_UTF8, 0, ua, -1, &params.userAgent[0], n);
    }

    HANDLE thread = CreateThread(nullptr, 0, STAThreadProc, &params, 0, nullptr);
    if (!thread) {
        CloseHandle(params.readyEvent);
        return nullptr;
    }
    // Reduce from 30s to 10s so slow/failed WebView2 init does not freeze the app as long
    const DWORD kInitTimeoutMs = 10000;
    WaitForSingleObject(params.readyEvent, kInitTimeoutMs);
    CloseHandle(params.readyEvent);

    if (params.createResult != S_OK) {
        WaitForSingleObject(thread, 5000);
        CloseHandle(thread);
        return nullptr;
    }

    // STA thread is now running its message loop; we keep it alive
    CloseHandle(thread);

    WebViewInstance* raw = inst.get();
    std::lock_guard<std::mutex> lk(s_instancesMutex);
    s_instances.push_back(std::move(inst));
    return raw;
}

__declspec(dllexport) int _CWebViewPlugin_Destroy(void* instance) {
    WebViewInstance* inst = (WebViewInstance*)instance;
    if (!inst) return 0;
    // Wait for STA thread to finish cleanup before erasing instance (avoids use-after-free / intermittent crash on exit)
    HANDLE destroyDoneEvent = CreateEventW(nullptr, FALSE, FALSE, nullptr);
    if (destroyDoneEvent && inst->hwnd) {
        PostMessage(inst->hwnd, WM_WEBVIEW_DESTROY, 0, (LPARAM)destroyDoneEvent);
        WaitForSingleObject(destroyDoneEvent, 10000);
    }
    if (destroyDoneEvent)
        CloseHandle(destroyDoneEvent);
    std::lock_guard<std::mutex> lk(s_instancesMutex);
    for (auto it = s_instances.begin(); it != s_instances.end(); ++it) {
        if (it->get() == inst) {
            s_instances.erase(it);
            break;
        }
    }
    return 1;
}

__declspec(dllexport) void _CWebViewPlugin_SetRect(void* instance, int width, int height) {
    PostToInstance((WebViewInstance*)instance, WM_WEBVIEW_SET_RECT, (WPARAM)width, (LPARAM)height);
}

__declspec(dllexport) void _CWebViewPlugin_SetVisibility(void* instance, bool visibility) {
    PostToInstance((WebViewInstance*)instance, WM_WEBVIEW_SET_VISIBILITY, visibility ? 1 : 0, 0);
}

__declspec(dllexport) bool _CWebViewPlugin_SetURLPattern(void* instance, const char* allowPattern, const char* denyPattern, const char* hookPattern) {
    (void)instance;
    (void)allowPattern;
    (void)denyPattern;
    (void)hookPattern;
    return true;
}

__declspec(dllexport) void _CWebViewPlugin_LoadURL(void* instance, const char* url) {
    WebViewInstance* inst = (WebViewInstance*)instance;
    if (!inst || !url) return;
    int n = MultiByteToWideChar(CP_UTF8, 0, url, -1, nullptr, 0);
    wchar_t* w = new wchar_t[n];
    MultiByteToWideChar(CP_UTF8, 0, url, -1, w, n);
    PostMessage(inst->hwnd, WM_WEBVIEW_LOAD_URL, 0, (LPARAM)w);
}

__declspec(dllexport) void _CWebViewPlugin_LoadHTML(void* instance, const char* html, const char* baseUrl) {
    WebViewInstance* inst = (WebViewInstance*)instance;
    if (!inst || !html) return;
    int n = MultiByteToWideChar(CP_UTF8, 0, html, -1, nullptr, 0);
    wchar_t* wHtml = new wchar_t[n];
    MultiByteToWideChar(CP_UTF8, 0, html, -1, wHtml, n);
    wchar_t* wBase = nullptr;
    if (baseUrl && baseUrl[0]) {
        int nb = MultiByteToWideChar(CP_UTF8, 0, baseUrl, -1, nullptr, 0);
        wBase = new wchar_t[nb];
        MultiByteToWideChar(CP_UTF8, 0, baseUrl, -1, wBase, nb);
    }
    PostMessage(inst->hwnd, WM_WEBVIEW_LOAD_HTML, (WPARAM)wHtml, (LPARAM)wBase);
}

__declspec(dllexport) void _CWebViewPlugin_EvaluateJS(void* instance, const char* js) {
    WebViewInstance* inst = (WebViewInstance*)instance;
    if (!inst || !js) return;
    int n = MultiByteToWideChar(CP_UTF8, 0, js, -1, nullptr, 0);
    wchar_t* w = new wchar_t[n];
    MultiByteToWideChar(CP_UTF8, 0, js, -1, w, n);
    PostMessage(inst->hwnd, WM_WEBVIEW_EVAL_JS, 0, (LPARAM)w);
}

__declspec(dllexport) int _CWebViewPlugin_Progress(void* instance) {
    (void)instance;
    return 0;
}

__declspec(dllexport) bool _CWebViewPlugin_CanGoBack(void* instance) {
    WebViewInstance* inst = (WebViewInstance*)instance;
    if (!inst) return false;
    std::lock_guard<std::mutex> lk(inst->cacheMutex);
    return inst->canGoBack;
}

__declspec(dllexport) bool _CWebViewPlugin_CanGoForward(void* instance) {
    WebViewInstance* inst = (WebViewInstance*)instance;
    if (!inst) return false;
    std::lock_guard<std::mutex> lk(inst->cacheMutex);
    return inst->canGoForward;
}

__declspec(dllexport) void _CWebViewPlugin_GoBack(void* instance) {
    PostToInstance((WebViewInstance*)instance, WM_WEBVIEW_GO_BACK);
}

__declspec(dllexport) void _CWebViewPlugin_GoForward(void* instance) {
    PostToInstance((WebViewInstance*)instance, WM_WEBVIEW_GO_FORWARD);
}

__declspec(dllexport) void _CWebViewPlugin_Reload(void* instance) {
    PostToInstance((WebViewInstance*)instance, WM_WEBVIEW_RELOAD);
}

__declspec(dllexport) void _CWebViewPlugin_SendMouseEvent(void* instance, int x, int y, float deltaY, int mouseState) {
    WebViewInstance* inst = (WebViewInstance*)instance;
    WV_LOG("SendMouseEvent called: inst=%p hwnd=%s x=%d y=%d state=%d", (void*)inst, inst && inst->hwnd ? "ok" : "null", x, y, mouseState);
    if (!inst || !inst->hwnd) return;
    MouseEventData* data = new MouseEventData{ x, y, deltaY, mouseState };
    PostMessage(inst->hwnd, WM_WEBVIEW_SEND_MOUSE, 0, (LPARAM)data);
}

__declspec(dllexport) void _CWebViewPlugin_SendKeyEvent(void* instance, int x, int y, char* keyChars, unsigned short keyCode, int keyState) {
    WebViewInstance* inst = (WebViewInstance*)instance;
    WV_LOG("SendKeyEvent called: inst=%p hwnd=%s keyCode=%u keyState=%d", (void*)inst, inst && inst->hwnd ? "ok" : "null", (unsigned)keyCode, keyState);
    if (!inst || !inst->hwnd) return;
    KeyEventData* data = new KeyEventData();
    data->keyCode = keyCode;
    data->keyState = keyState;
    data->keyChars = nullptr;
    if (keyChars && keyChars[0]) {
        size_t len = strlen(keyChars) + 1;
        data->keyChars = new char[len];
        memcpy(data->keyChars, keyChars, len);
    }
    PostMessage(inst->hwnd, WM_WEBVIEW_SEND_KEY, 0, (LPARAM)data);
}

__declspec(dllexport) void _CWebViewPlugin_Update(void* instance, bool refreshBitmap, int devicePixelRatio) {
    WebViewInstance* inst = (WebViewInstance*)instance;
    if (!inst) return;
    // Non-blocking: only start a new capture when none is in progress. STA thread uses
    // double-buffering so Render() can read current bitmapPixels without delay.
    if (refreshBitmap && inst->hwnd && inst->webview) {
        if (!inst->captureInProgress.exchange(true)) {
            PostMessage(inst->hwnd, WM_WEBVIEW_CAPTURE, 0, 0);
        }
    }
}

__declspec(dllexport) int _CWebViewPlugin_BitmapWidth(void* instance) {
    WebViewInstance* inst = (WebViewInstance*)instance;
    if (!inst) return 0;
    std::lock_guard<std::mutex> lk(inst->bitmapMutex);
    return inst->bitmapWidth;
}

__declspec(dllexport) int _CWebViewPlugin_BitmapHeight(void* instance) {
    WebViewInstance* inst = (WebViewInstance*)instance;
    if (!inst) return 0;
    std::lock_guard<std::mutex> lk(inst->bitmapMutex);
    return inst->bitmapHeight;
}

__declspec(dllexport) void _CWebViewPlugin_Render(void* instance, void* textureBuffer) {
    WebViewInstance* inst = (WebViewInstance*)instance;
    if (!inst || !textureBuffer) return;
    std::lock_guard<std::mutex> lk(inst->bitmapMutex);
    if (inst->bitmapPixels.empty()) return;
    size_t copyLen = (size_t)inst->bitmapWidth * inst->bitmapHeight * 4;
    if (copyLen > inst->bitmapPixels.size()) copyLen = inst->bitmapPixels.size();
    memcpy(textureBuffer, inst->bitmapPixels.data(), copyLen);
}

__declspec(dllexport) void _CWebViewPlugin_AddCustomHeader(void* instance, const char* headerKey, const char* headerValue) {
    (void)instance;
    (void)headerKey;
    (void)headerValue;
}

__declspec(dllexport) const char* _CWebViewPlugin_GetCustomHeaderValue(void* instance, const char* headerKey) {
    (void)instance;
    (void)headerKey;
    return nullptr;
}

__declspec(dllexport) void _CWebViewPlugin_RemoveCustomHeader(void* instance, const char* headerKey) {
    (void)instance;
    (void)headerKey;
}

__declspec(dllexport) void _CWebViewPlugin_ClearCustomHeader(void* instance) {
    (void)instance;
}

__declspec(dllexport) void _CWebViewPlugin_ClearCookie(const char* url, const char* name) {
    (void)url;
    (void)name;
}

__declspec(dllexport) void _CWebViewPlugin_ClearCookies(void) {
}

__declspec(dllexport) void _CWebViewPlugin_SaveCookies(void) {
}

__declspec(dllexport) void _CWebViewPlugin_GetCookies(void* instance, const char* url) {
    (void)instance;
    (void)url;
}

__declspec(dllexport) const char* _CWebViewPlugin_GetMessage(void* instance) {
    WebViewInstance* inst = (WebViewInstance*)instance;
    if (!inst) return nullptr;
    std::string msg;
    if (!inst->messages.pop(msg)) return nullptr;
    char* buf = (char*)CoTaskMemAlloc(msg.size() + 1);
    if (!buf) return nullptr;
    memcpy(buf, msg.c_str(), msg.size() + 1);
    return buf;
}

} // extern "C"
