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

// GPU capture path: DirectComposition visual tree + Windows Graphics Capture.
#include <d3d11.h>
#include <dxgi.h>
#include <DispatcherQueue.h>
#include <winrt/base.h>
#include <winrt/Windows.Foundation.h>
#include <winrt/Windows.System.h>
#include <winrt/Windows.UI.Composition.h>
#include <winrt/Windows.UI.Composition.Desktop.h>
#include <winrt/Windows.Graphics.Capture.h>
#include <winrt/Windows.Graphics.DirectX.Direct3D11.h>
#include <windows.ui.composition.interop.h>
#include <windows.graphics.capture.interop.h>
#include <Windows.Graphics.DirectX.Direct3D11.interop.h>

// Unity native plugin API, for the zero-copy path: it gives us Unity's own D3D11
// device and a way to run the frame copy on Unity's render thread.
#include "Unity/IUnityInterface.h"
#include "Unity/IUnityGraphics.h"
#include "Unity/IUnityGraphicsD3D11.h"

#include <vector>
#include <utility>

#pragma comment(lib, "user32.lib")
#pragma comment(lib, "ole32.lib")
#pragma comment(lib, "d3d11.lib")
#pragma comment(lib, "dxgi.lib")
#pragma comment(lib, "windowsapp.lib")

namespace wgc {
    using namespace winrt;
    using namespace winrt::Windows::UI::Composition;
    using namespace winrt::Windows::UI::Composition::Desktop;
    using namespace winrt::Windows::Graphics;
    using namespace winrt::Windows::Graphics::Capture;
    using namespace winrt::Windows::Graphics::DirectX;
    using namespace winrt::Windows::Graphics::DirectX::Direct3D11;
}

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

    // GPU capture path. When captureActive is true, frames arrive on a threadpool
    // thread and are read back into bitmapPixels; CapturePreview is not used at all.
    // Everything here lives on this instance's own D3D11 device, so Unity's graphics
    // device is never touched.
    bool winrtReady = false;
    std::atomic<bool> captureActive{ false };
    std::mutex captureMutex;
    ComPtr<ID3D11Device> d3dDevice;
    ComPtr<ID3D11DeviceContext> d3dContext;
    ComPtr<ID3D11Texture2D> stagingTexture;
    UINT stagingWidth = 0;
    UINT stagingHeight = 0;

    // Zero-copy path: when Unity's D3D11 device is available the frame pool runs on
    // it, so a capture frame can be copied straight into a texture Unity samples
    // through CreateExternalTexture. No staging texture, no readback, no upload.
    std::atomic<bool> zeroCopy{ false };
    ComPtr<ID3D11Texture2D> sharedTexture;
    UINT sharedWidth = 0;
    UINT sharedHeight = 0;
    std::atomic<void*> texturePtr{ nullptr };
    wgc::IDirect3DDevice rtDevice{ nullptr };
    wgc::Compositor compositor{ nullptr };
    wgc::DesktopWindowTarget windowTarget{ nullptr };
    wgc::ContainerVisual rootVisual{ nullptr };
    wgc::ContainerVisual webViewVisual{ nullptr };
    wgc::GraphicsCaptureItem captureItem{ nullptr };
    wgc::Direct3D11CaptureFramePool framePool{ nullptr };
    wgc::GraphicsCaptureSession captureSession{ nullptr };
    wgc::Direct3D11CaptureFramePool::FrameArrived_revoker frameArrivedRevoker;

    // Custom headers for navigation
    std::mutex headersMutex;
    std::wstring customHeaders; // "Key: Value\r\n..."

    // URL pattern (allow/deny/hook) - simplified: we allow all for now
    bool allowAllUrls = true;

    // Cached for main-thread read
    std::mutex cacheMutex;
    bool canGoBack = false;
    bool canGoForward = false;
    std::atomic<int> progress{ 0 };

    // Set when Destroy is in progress; main-thread APIs return early to avoid use-after-free.
    std::atomic<bool> destroying{ false };
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
// GPU capture: visual tree + Windows Graphics Capture
//
// WebView2 is hosted through a CompositionController, which renders nothing until
// a visual tree is attached with put_RootVisualTarget. Once attached, the
// off-screen host window carries the page content and Windows Graphics Capture can
// read it back from the GPU, replacing the CapturePreview PNG round trip
// (PNG encode -> WIC decode) that dominated the previous frame cost.
//
// There are two capture modes:
//
//   zero copy  Unity's D3D11 device is available, so the frame pool runs on it and
//              the frame is copied GPU to GPU into a texture Unity samples through
//              CreateExternalTexture. The CPU never sees a pixel.
//   readback   No Unity device (DX12, or the graphics device event has not arrived
//              yet). Frames are read back through a staging texture into
//              bitmapPixels, which keeps _CWebViewPlugin_Render working unchanged.
//
// If Graphics Capture itself is unavailable, both fall back to CapturePreview.
//------------------------------------------------------------------------------

// Unity graphics interop. Populated by UnityPluginLoad / the device event callback.
static IUnityInterfaces* s_unityInterfaces = nullptr;
static IUnityGraphics* s_unityGraphics = nullptr;
static ComPtr<ID3D11Device> s_unityDevice;
static ComPtr<ID3D11DeviceContext> s_unityContext;
static bool s_linearColorSpace = false;

// Unity keeps sampling an external Texture2D until it actually destroys the object,
// which happens at the end of the frame at the earliest. Releasing the underlying
// texture the moment we replace or drop it would leave Unity reading freed memory,
// so retired textures are parked here for a few render events first.
static std::mutex s_retiredMutex;
static std::vector<std::pair<ComPtr<ID3D11Texture2D>, int>> s_retiredTextures;
static const int kRetireFrames = 3;

static void RetireSharedTexture(ComPtr<ID3D11Texture2D> tex) {
    if (!tex) return;
    std::lock_guard<std::mutex> lk(s_retiredMutex);
    s_retiredTextures.emplace_back(std::move(tex), kRetireFrames);
}

static void DrainRetiredTextures(bool force) {
    std::lock_guard<std::mutex> lk(s_retiredMutex);
    for (auto it = s_retiredTextures.begin(); it != s_retiredTextures.end();) {
        if (force || --it->second <= 0) {
            it = s_retiredTextures.erase(it);
        } else {
            ++it;
        }
    }
}

static bool CreateCaptureDevice(WebViewInstance* inst) {
    // Prefer Unity's device: that is what makes the zero-copy path possible, because
    // a capture frame can only be copied into a texture on the same device.
    if (s_unityDevice && s_unityContext) {
        inst->d3dDevice = s_unityDevice;
        inst->d3dContext = s_unityContext;
        inst->zeroCopy = true;
        WV_LOG("CreateCaptureDevice: using Unity's D3D11 device (zero copy)");
    } else {
        const UINT flags = D3D11_CREATE_DEVICE_BGRA_SUPPORT;
        D3D_FEATURE_LEVEL level{};
        HRESULT hr = D3D11CreateDevice(nullptr, D3D_DRIVER_TYPE_HARDWARE, nullptr, flags,
            nullptr, 0, D3D11_SDK_VERSION,
            inst->d3dDevice.GetAddressOf(), &level, inst->d3dContext.GetAddressOf());
        if (FAILED(hr)) {
            hr = D3D11CreateDevice(nullptr, D3D_DRIVER_TYPE_WARP, nullptr, flags,
                nullptr, 0, D3D11_SDK_VERSION,
                inst->d3dDevice.GetAddressOf(), &level, inst->d3dContext.GetAddressOf());
        }
        if (FAILED(hr)) {
            WV_LOG("CreateCaptureDevice: D3D11CreateDevice failed 0x%08X", (unsigned)hr);
            return false;
        }
        inst->zeroCopy = false;
        WV_LOG("CreateCaptureDevice: using a private D3D11 device (readback)");
    }

    ComPtr<IDXGIDevice> dxgiDevice;
    if (FAILED(inst->d3dDevice.As(&dxgiDevice))) return false;
    winrt::com_ptr<::IInspectable> inspectable;
    if (FAILED(CreateDirect3D11DeviceFromDXGIDevice(dxgiDevice.Get(), inspectable.put())))
        return false;
    inst->rtDevice = inspectable.as<wgc::IDirect3DDevice>();
    return true;
}

// Connects WebView2's output to the host window. Without this the window stays
// empty and Windows Graphics Capture would only ever see a blank surface.
static bool BuildVisualTree(WebViewInstance* inst) {
    if (!inst->compositionController || !inst->hwnd) return false;
    try {
        inst->compositor = wgc::Compositor();

        auto interop = inst->compositor.as<ABI::Windows::UI::Composition::Desktop::ICompositorDesktopInterop>();
        winrt::check_hresult(interop->CreateDesktopWindowTarget(
            inst->hwnd, false,
            reinterpret_cast<ABI::Windows::UI::Composition::Desktop::IDesktopWindowTarget**>(
                winrt::put_abi(inst->windowTarget))));

        // The root of a DesktopWindowTarget needs an explicit size; the child fills it.
        auto root = inst->compositor.CreateContainerVisual();
        root.Size({ (float)inst->rectWidth, (float)inst->rectHeight });
        root.IsVisible(true);
        inst->windowTarget.Root(root);

        auto child = inst->compositor.CreateContainerVisual();
        child.RelativeSizeAdjustment({ 1.0f, 1.0f });
        root.Children().InsertAtTop(child);

        winrt::check_hresult(inst->compositionController->put_RootVisualTarget(
            reinterpret_cast<::IUnknown*>(winrt::get_abi(child))));

        inst->rootVisual = root;
        inst->webViewVisual = child;
        return true;
    } catch (const winrt::hresult_error& e) {
        WV_LOG("BuildVisualTree failed 0x%08X", (unsigned)e.code());
        return false;
    } catch (...) {
        return false;
    }
}

static void ReadBackFrame(WebViewInstance* inst) {
    std::lock_guard<std::mutex> lk(inst->captureMutex);
    if (!inst->framePool || inst->destroying) return;
    try {
        auto frame = inst->framePool.TryGetNextFrame();
        if (!frame) return;
        auto surface = frame.Surface();
        if (!surface) { frame.Close(); return; }

        auto access = surface.as<::Windows::Graphics::DirectX::Direct3D11::IDirect3DDxgiInterfaceAccess>();
        ComPtr<ID3D11Texture2D> frameTexture;
        if (FAILED(access->GetInterface(IID_PPV_ARGS(frameTexture.GetAddressOf()))) || !frameTexture) {
            frame.Close();
            return;
        }

        D3D11_TEXTURE2D_DESC desc{};
        frameTexture->GetDesc(&desc);

        if (!inst->stagingTexture || inst->stagingWidth != desc.Width || inst->stagingHeight != desc.Height) {
            D3D11_TEXTURE2D_DESC sd = desc;
            sd.Usage = D3D11_USAGE_STAGING;
            sd.BindFlags = 0;
            sd.CPUAccessFlags = D3D11_CPU_ACCESS_READ;
            sd.MiscFlags = 0;
            inst->stagingTexture.Reset();
            if (FAILED(inst->d3dDevice->CreateTexture2D(&sd, nullptr, inst->stagingTexture.GetAddressOf()))) {
                frame.Close();
                return;
            }
            inst->stagingWidth = desc.Width;
            inst->stagingHeight = desc.Height;
        }

        inst->d3dContext->CopyResource(inst->stagingTexture.Get(), frameTexture.Get());

        D3D11_MAPPED_SUBRESOURCE mapped{};
        if (FAILED(inst->d3dContext->Map(inst->stagingTexture.Get(), 0, D3D11_MAP_READ, 0, &mapped))) {
            frame.Close();
            return;
        }

        const size_t rowBytes = (size_t)desc.Width * 4;
        inst->bitmapPixelsBack.resize(rowBytes * desc.Height);
        // Capture frames are top-down, the same row order the decoded PNG had, so the
        // consumer keeps working without a flip. Pixels are BGRA (see BitmapIsBGRA).
        for (UINT y = 0; y < desc.Height; y++) {
            memcpy(inst->bitmapPixelsBack.data() + rowBytes * y,
                   (const uint8_t*)mapped.pData + (size_t)mapped.RowPitch * y,
                   rowBytes);
        }
        inst->d3dContext->Unmap(inst->stagingTexture.Get(), 0);
        frame.Close();

        {
            std::lock_guard<std::mutex> bl(inst->bitmapMutex);
            inst->bitmapPixels.swap(inst->bitmapPixelsBack);
            inst->bitmapWidth = (int)desc.Width;
            inst->bitmapHeight = (int)desc.Height;
        }
    } catch (...) {
        // A frame can fail during resize or teardown; just skip it.
    }
}

// Caller must hold captureMutex.
static bool EnsureSharedTexture(WebViewInstance* inst, UINT width, UINT height) {
    if (inst->sharedTexture && inst->sharedWidth == width && inst->sharedHeight == height)
        return true;
    if (!s_unityDevice) return false;

    D3D11_TEXTURE2D_DESC desc = {};
    desc.Width = width;
    desc.Height = height;
    desc.MipLevels = 1;
    desc.ArraySize = 1;
    // Must match the shader resource view Unity builds for the external texture.
    // CreateExternalTexture is called with linear=false in Linear color space, which
    // makes Unity ask for the sRGB variant, and D3D11 only lets a fully typed resource
    // be viewed with its own format: a mismatch fails with E_INVALIDARG (0x80070057).
    desc.Format = s_linearColorSpace ? DXGI_FORMAT_B8G8R8A8_UNORM_SRGB
                                     : DXGI_FORMAT_B8G8R8A8_UNORM;
    desc.SampleDesc.Count = 1;
    desc.Usage = D3D11_USAGE_DEFAULT;
    desc.BindFlags = D3D11_BIND_SHADER_RESOURCE;

    ComPtr<ID3D11Texture2D> tex;
    if (FAILED(s_unityDevice->CreateTexture2D(&desc, nullptr, tex.GetAddressOf()))) {
        WV_LOG("EnsureSharedTexture: CreateTexture2D failed (%ux%u)", width, height);
        return false;
    }

    RetireSharedTexture(inst->sharedTexture);
    inst->sharedTexture = tex;
    inst->sharedWidth = width;
    inst->sharedHeight = height;
    // Not published yet: the caller does that after the first copy, so C# never wraps
    // a texture whose contents are still undefined.
    inst->texturePtr.store(nullptr, std::memory_order_release);
    return true;
}

// Runs on Unity's render thread, driven by GL.IssuePluginEventAndData. Unity's
// immediate context is not thread safe, so the copy cannot happen on the thread that
// raises FrameArrived; in zero-copy mode we poll the pool from here instead.
static void UpdateZeroCopyTexture(WebViewInstance* inst) {
    std::lock_guard<std::mutex> lk(inst->captureMutex);
    if (!inst->framePool || inst->destroying || !inst->zeroCopy || !s_unityContext) return;
    try {
        // Drain to the newest frame: the pool buffers a couple and only the last matters.
        wgc::Direct3D11CaptureFrame frame{ nullptr };
        for (;;) {
            auto next = inst->framePool.TryGetNextFrame();
            if (!next) break;
            if (frame) frame.Close();
            frame = next;
        }
        if (!frame) return;

        auto surface = frame.Surface();
        if (!surface) { frame.Close(); return; }

        auto access = surface.as<::Windows::Graphics::DirectX::Direct3D11::IDirect3DDxgiInterfaceAccess>();
        ComPtr<ID3D11Texture2D> frameTexture;
        if (FAILED(access->GetInterface(IID_PPV_ARGS(frameTexture.GetAddressOf()))) || !frameTexture) {
            frame.Close();
            return;
        }

        D3D11_TEXTURE2D_DESC desc = {};
        frameTexture->GetDesc(&desc);

        if (EnsureSharedTexture(inst, desc.Width, desc.Height)) {
            // Same device and same format family (BGRA8 UNORM vs UNORM_SRGB), so this is
            // a plain GPU copy that keeps the sRGB encoded bytes as they are.
            s_unityContext->CopyResource(inst->sharedTexture.Get(), frameTexture.Get());
            inst->texturePtr.store(inst->sharedTexture.Get(), std::memory_order_release);
            std::lock_guard<std::mutex> bl(inst->bitmapMutex);
            inst->bitmapWidth = (int)desc.Width;
            inst->bitmapHeight = (int)desc.Height;
        }
        frame.Close();
    } catch (...) {
        // A frame can fail during resize or teardown; just skip it.
    }
}

static bool StartGraphicsCapture(WebViewInstance* inst) {
    if (!inst->rtDevice || !inst->hwnd) return false;
    if (!wgc::GraphicsCaptureSession::IsSupported()) {
        WV_LOG("StartGraphicsCapture: not supported on this OS");
        return false;
    }
    try {
        auto interop = winrt::get_activation_factory<wgc::GraphicsCaptureItem, IGraphicsCaptureItemInterop>();
        winrt::check_hresult(interop->CreateForWindow(
            inst->hwnd,
            winrt::guid_of<ABI::Windows::Graphics::Capture::IGraphicsCaptureItem>(),
            reinterpret_cast<void**>(winrt::put_abi(inst->captureItem))));

        auto size = inst->captureItem.Size();
        if (size.Width <= 0) size.Width = inst->rectWidth;
        if (size.Height <= 0) size.Height = inst->rectHeight;

        // Free-threaded so TryGetNextFrame may be called from whichever thread owns the
        // copy: Unity's render thread in zero-copy mode, the FrameArrived threadpool
        // thread otherwise (which keeps the readback off Unity's main thread).
        inst->framePool = wgc::Direct3D11CaptureFramePool::CreateFreeThreaded(
            inst->rtDevice, wgc::DirectXPixelFormat::B8G8R8A8UIntNormalized, 2, size);
        if (!inst->zeroCopy) {
            inst->frameArrivedRevoker = inst->framePool.FrameArrived(
                winrt::auto_revoke, [inst](auto&&, auto&&) { ReadBackFrame(inst); });
        }

        inst->captureSession = inst->framePool.CreateCaptureSession(inst->captureItem);
        inst->captureSession.StartCapture();
        inst->captureActive = true;
        WV_LOG("StartGraphicsCapture: started (%dx%d)", size.Width, size.Height);
        return true;
    } catch (const winrt::hresult_error& e) {
        WV_LOG("StartGraphicsCapture failed 0x%08X", (unsigned)e.code());
        return false;
    } catch (...) {
        return false;
    }
}

static void StopGraphicsCapture(WebViewInstance* inst) {
    // Revoke first and outside the lock: revoke() waits for an in-flight
    // FrameArrived handler, which itself takes captureMutex.
    inst->frameArrivedRevoker.revoke();
    inst->captureActive = false;

    std::lock_guard<std::mutex> lk(inst->captureMutex);
    if (inst->captureSession) { inst->captureSession.Close(); inst->captureSession = nullptr; }
    if (inst->framePool) { inst->framePool.Close(); inst->framePool = nullptr; }
    inst->captureItem = nullptr;
    inst->stagingTexture.Reset();
    inst->stagingWidth = 0;
    inst->stagingHeight = 0;

    // Stop handing the texture to C# before it goes away, and let Unity finish with
    // the external texture it may still hold before the resource is actually freed.
    inst->texturePtr.store(nullptr, std::memory_order_release);
    RetireSharedTexture(inst->sharedTexture);
    inst->sharedTexture.Reset();
    inst->sharedWidth = 0;
    inst->sharedHeight = 0;
}

static void ReleaseVisualTree(WebViewInstance* inst) {
    if (inst->compositionController) {
        inst->compositionController->put_RootVisualTarget(nullptr);
    }
    inst->webViewVisual = nullptr;
    inst->rootVisual = nullptr;
    inst->windowTarget = nullptr;
    inst->compositor = nullptr;
    inst->rtDevice = nullptr;
    inst->d3dContext.Reset();
    inst->d3dDevice.Reset();
}

// Must run on the STA thread that owns the host window.
static void SetupCapture(WebViewInstance* inst) {
    if (inst->winrtReady && CreateCaptureDevice(inst) && BuildVisualTree(inst)) {
        StartGraphicsCapture(inst);
    }
    if (!inst->captureActive) {
        WV_LOG("GPU capture unavailable, falling back to CapturePreview");
        ReleaseVisualTree(inst);
    }
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
    WM_WEBVIEW_RESTART_CAPTURE,
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

// The keys Windows marks as extended in WM_KEYDOWN. The navigation cluster and the
// arrows share scan codes with the numeric keypad, and without the bit Chromium reads
// VK_DELETE as the keypad's period; the right-hand CTRL and ALT likewise share theirs
// with the left-hand pair.
static bool IsExtendedKey(unsigned short vk) {
    switch (vk) {
    case VK_INSERT: case VK_DELETE: case VK_HOME: case VK_END:
    case VK_PRIOR:  case VK_NEXT:
    case VK_LEFT:   case VK_UP:     case VK_RIGHT: case VK_DOWN:
    case VK_RCONTROL: case VK_RMENU: case VK_NUMLOCK: case VK_DIVIDE:
        return true;
    default:
        return false;
    }
}

// The control characters TranslateMessage would produce for a key down. Text keys are
// not listed: their characters come from Unity through keyChars, which already handles
// layouts, dead keys and IME.
static wchar_t ControlCharForKey(unsigned short vk) {
    switch (vk) {
    case VK_RETURN: return L'\r';
    case VK_BACK:   return L'\b';
    case VK_TAB:    return L'\t';
    case VK_ESCAPE: return L'\x1b';
    default:        return 0;
    }
}

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
                                            inst->progress = 0;
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
                                            // Unity posts WM_WEBVIEW_CAPTURE only when captureInProgress is false. If the previous
                                            // CapturePreview callback is late or stuck, no new frame is captured (texture stays stale).
                                            inst->captureInProgress = false;
                                            BOOL success = FALSE;
                                            args->get_IsSuccess(&success);
                                            inst->progress = success ? 100 : 0;
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

                                // Attach the visual tree so the host window actually carries the
                                // page, then capture it on the GPU. Any failure here just leaves
                                // captureActive false and the CapturePreview path takes over.
                                SetupCapture(inst);

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
            // Stop navigation before releasing COM to avoid crash when tearing down during load (e.g. heavy pages).
            if (inst->webview) {
                inst->webview->Stop();
            }
            // Tear the capture down before the composition controller goes away,
            // otherwise a frame in flight can touch a released visual.
            StopGraphicsCapture(inst);
            ReleaseVisualTree(inst);
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
        // wParam 0: Stop + queue Navigate on next message pump (Stop is not always synchronous;
        // immediate Navigate on a heavy page can be dropped until user retries).
        // wParam 1: perform Navigate and free url.
        wchar_t* url = (wchar_t*)lParam;
        if (!inst || !inst->webview) {
            delete[] url;
            return 0;
        }
        if (wParam == 0) {
            inst->webview->Stop();
            inst->captureInProgress = false;
            PostMessage(hwnd, WM_WEBVIEW_LOAD_URL, 1, (LPARAM)url);
        } else {
            inst->webview->Navigate(url);
            delete[] url;
        }
        return 0;
    }
    case WM_WEBVIEW_LOAD_HTML: {
        if (inst && inst->webview) {
            wchar_t* html = (wchar_t*)wParam;
            wchar_t* baseUrl = (wchar_t*)lParam;
            inst->webview->Stop();
            inst->captureInProgress = false;
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
            const bool sizeChanged = (inst->rectWidth != w || inst->rectHeight != h);
            inst->rectWidth = w;
            inst->rectHeight = h;
            RECT r = { 0, 0, w, h };
            inst->controller->put_Bounds(r);

            if (sizeChanged && w > 0 && h > 0) {
                // The capture follows the host window, not the controller bounds, so the
                // window itself has to be resized too.
                SetWindowPos(hwnd, nullptr, 0, 0, w, h,
                    SWP_NOMOVE | SWP_NOZORDER | SWP_NOACTIVATE);
                if (inst->rootVisual) {
                    inst->rootVisual.Size({ (float)w, (float)h });
                }
                if (inst->captureActive) {
                    // Recreating the item and pool is more robust than FramePool::Recreate,
                    // which is unreliable while a session is running.
                    StopGraphicsCapture(inst);
                    StartGraphicsCapture(inst);
                }
            }
        }
        return 0;
    }
    case WM_WEBVIEW_RESTART_CAPTURE: {
        // Unity's graphics device came back (or appeared for the first time). Rebuild
        // everything so we pick up the new device and switch to zero copy if we can.
        if (!inst || inst->destroying) return 0;
        StopGraphicsCapture(inst);
        ReleaseVisualTree(inst);
        SetupCapture(inst);
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

        HRESULT errCapture = inst->webview->CapturePreview(COREWEBVIEW2_CAPTURE_PREVIEW_IMAGE_FORMAT_PNG, stream.Get(),
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
	if (FAILED(errCapture)) {
	    if (inst->captureDoneEvent) SetEvent(inst->captureDoneEvent);
	    inst->captureInProgress = false;
	}
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
            if (IsExtendedKey(data->keyCode))
                lp |= (LPARAM)1 << 24;
            if (data->keyState == 1 || data->keyState == 2) {
                SendMessage(target, WM_KEYDOWN, (WPARAM)data->keyCode, lp);
                wchar_t ch = ControlCharForKey(data->keyCode);
                if (ch)
                    SendMessage(target, WM_CHAR, (WPARAM)ch, lp);
            }
            if (data->keyState == 3) {
                // Bit 30 is the previous key state, bit 31 the transition state; both are
                // set on a real key up.
                SendMessage(target, WM_KEYUP, (WPARAM)data->keyCode,
                            lp | ((LPARAM)1 << 30) | ((LPARAM)1 << 31));
            }
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

    // WinRT (STA) is needed for the Compositor and Windows Graphics Capture.
    // init_apartment also performs CoInitializeEx(COINIT_APARTMENTTHREADED).
    bool winrtReady = true;
    try {
        winrt::init_apartment(winrt::apartment_type::single_threaded);
    } catch (...) {
        winrtReady = false;
        CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);
    }

    // Compositor() requires a DispatcherQueue on the calling thread.
    ABI::Windows::System::IDispatcherQueueController* dqController = nullptr;
    if (winrtReady) {
        DispatcherQueueOptions opts{};
        opts.dwSize = sizeof(opts);
        opts.threadType = DQTYPE_THREAD_CURRENT;
        opts.apartmentType = DQTAT_COM_STA;
        if (FAILED(CreateDispatcherQueueController(opts, &dqController))) {
            winrtReady = false;
        }
    }
    if (params->instance) params->instance->winrtReady = winrtReady;

    WNDCLASSEXW wc = {};
    wc.cbSize = sizeof(wc);
    wc.lpfnWndProc = WndProc;
    wc.hInstance = GetModuleHandle(nullptr);
    wc.lpszClassName = L"UnityWebView2Window";
    RegisterClassExW(&wc);

    // Use WS_EX_TOOLWINDOW and WS_POPUP to prevent the window from appearing on the taskbar.
    // WS_EX_NOACTIVATE prevents the host from being activated when receiving focus, avoiding Unity window minimize on click.
    // WS_EX_LAYERED with alpha 1 keeps the window effectively invisible while still being
    // composed by DWM, which Windows Graphics Capture requires.
    const int screenWidth = GetSystemMetrics(SM_CXSCREEN);
    HWND hwnd = CreateWindowExW(
        WS_EX_TOOLWINDOW | WS_EX_NOACTIVATE | WS_EX_LAYERED | WS_EX_TRANSPARENT,
        wc.lpszClassName, L"", WS_POPUP,
        screenWidth + 100, 0,
        params->width > 0 ? params->width : 640, params->height > 0 ? params->height : 480,
        nullptr, nullptr, wc.hInstance, params);
    if (!hwnd) {
        params->createResult = E_FAIL;
        SetEvent(params->readyEvent);
        if (dqController) dqController->Release();
        CoUninitialize();
        return 1;
    }

    // Parked just past the right edge of the primary monitor rather than at (-32000,-32000):
    // DWM keeps composing a window placed there, which is what the capture reads from.
    SetLayeredWindowAttributes(hwnd, 0, 1, LWA_ALPHA);
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
    if (dqController) dqController->Release();
    CoUninitialize();
    return 0;
}

// Helper: run action on STA thread by posting to the instance's window
static void PostToInstance(WebViewInstance* inst, UINT msg, WPARAM wParam = 0, LPARAM lParam = 0) {
    if (inst && !inst->destroying && inst->hwnd)
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
// Unity graphics interop
//------------------------------------------------------------------------------
enum : int { kWebViewRenderEventUpdate = 1 };

static void UNITY_INTERFACE_API OnGraphicsDeviceEvent(UnityGfxDeviceEventType eventType) {
    switch (eventType) {
    case kUnityGfxDeviceEventInitialize:
    case kUnityGfxDeviceEventAfterReset: {
        if (!s_unityInterfaces) break;
        // Absent on DX12 and every other backend; those stay on the readback path.
        IUnityGraphicsD3D11* d3d11 = s_unityInterfaces->Get<IUnityGraphicsD3D11>();
        if (!d3d11) break;
        s_unityContext.Reset();
        s_unityDevice = d3d11->GetDevice();
        if (s_unityDevice) {
            s_unityDevice->GetImmediateContext(s_unityContext.GetAddressOf());
        }
        // Existing instances were built against the old device (or none at all), so
        // have each one rebuild on the thread that owns its window.
        std::lock_guard<std::mutex> lk(s_instancesMutex);
        for (auto& p : s_instances) {
            if (p->hwnd && !p->destroying) {
                PostMessage(p->hwnd, WM_WEBVIEW_RESTART_CAPTURE, 0, 0);
            }
        }
        break;
    }
    case kUnityGfxDeviceEventBeforeReset:
    case kUnityGfxDeviceEventShutdown: {
        std::lock_guard<std::mutex> lk(s_instancesMutex);
        for (auto& p : s_instances) {
            if (p->zeroCopy) {
                StopGraphicsCapture(p.get());
            }
        }
        // The device is going away, so nothing can still be reading these.
        DrainRetiredTextures(true);
        s_unityContext.Reset();
        s_unityDevice.Reset();
        break;
    }
    default:
        break;
    }
}

// Runs on Unity's render thread.
static void UNITY_INTERFACE_API OnRenderEventAndData(int eventId, void* data) {
    if (eventId != kWebViewRenderEventUpdate) return;

    WebViewInstance* inst = (WebViewInstance*)data;
    if (inst) {
        // C# can issue an event for an instance that was destroyed in the meantime.
        std::lock_guard<std::mutex> lk(s_instancesMutex);
        bool alive = false;
        for (auto& p : s_instances) {
            if (p.get() == inst) { alive = true; break; }
        }
        if (alive && inst->zeroCopy && !inst->destroying) {
            UpdateZeroCopyTexture(inst);
        }
    }
    DrainRetiredTextures(false);
}

extern "C" void UNITY_INTERFACE_EXPORT UNITY_INTERFACE_API UnityPluginLoad(IUnityInterfaces* unityInterfaces) {
    s_unityInterfaces = unityInterfaces;
    s_unityGraphics = unityInterfaces ? unityInterfaces->Get<IUnityGraphics>() : nullptr;
    if (s_unityGraphics) {
        s_unityGraphics->RegisterDeviceEventCallback(OnGraphicsDeviceEvent);
        // The initialize event has already been raised by the time we get here.
        OnGraphicsDeviceEvent(kUnityGfxDeviceEventInitialize);
    }
}

extern "C" void UNITY_INTERFACE_EXPORT UNITY_INTERFACE_API UnityPluginUnload() {
    if (s_unityGraphics) {
        s_unityGraphics->UnregisterDeviceEventCallback(OnGraphicsDeviceEvent);
    }
    OnGraphicsDeviceEvent(kUnityGfxDeviceEventShutdown);
    s_unityGraphics = nullptr;
    s_unityInterfaces = nullptr;
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
    return inst && !inst->destroying && inst->webview != nullptr;
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
    inst->destroying = true;
    // Wait for STA thread to finish cleanup before erasing instance (avoids use-after-free / intermittent crash on exit)
    HANDLE destroyDoneEvent = CreateEventW(nullptr, FALSE, FALSE, nullptr);
    DWORD waitResult = WAIT_TIMEOUT;
    if (destroyDoneEvent && inst->hwnd) {
        PostMessage(inst->hwnd, WM_WEBVIEW_DESTROY, 0, (LPARAM)destroyDoneEvent);
        waitResult = WaitForSingleObject(destroyDoneEvent, 10000);
    }
    if (destroyDoneEvent)
        CloseHandle(destroyDoneEvent);
    // Only erase from s_instances if STA thread completed cleanup. On timeout the STA thread may still
    // be blocked (e.g. in WebView2 on a heavy page); erasing here would run WebViewInstance destructor
    // on the main thread and release COM objects from wrong thread -> crash in EmbeddedBrowserWebView.
    if (waitResult == WAIT_OBJECT_0) {
        std::lock_guard<std::mutex> lk(s_instancesMutex);
        for (auto it = s_instances.begin(); it != s_instances.end(); ++it) {
            if (it->get() == inst) {
                s_instances.erase(it);
                break;
            }
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
    if (!inst || inst->destroying || !url) return;
    int n = MultiByteToWideChar(CP_UTF8, 0, url, -1, nullptr, 0);
    wchar_t* w = new wchar_t[n];
    MultiByteToWideChar(CP_UTF8, 0, url, -1, w, n);
    PostMessage(inst->hwnd, WM_WEBVIEW_LOAD_URL, 0, (LPARAM)w);
}

__declspec(dllexport) void _CWebViewPlugin_LoadHTML(void* instance, const char* html, const char* baseUrl) {
    WebViewInstance* inst = (WebViewInstance*)instance;
    if (!inst || inst->destroying || !html) return;
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
    if (!inst || inst->destroying || !js) return;
    int n = MultiByteToWideChar(CP_UTF8, 0, js, -1, nullptr, 0);
    wchar_t* w = new wchar_t[n];
    MultiByteToWideChar(CP_UTF8, 0, js, -1, w, n);
    PostMessage(inst->hwnd, WM_WEBVIEW_EVAL_JS, 0, (LPARAM)w);
}

// Returns load progress 0-100. Value is 0 when navigation starts, 100 when it completes successfully, and 0 on failure.
// Using Progress() == 100 to detect "load complete" is correct. For a smooth progress bar, note that WebView2 does
// not expose an estimatedProgress like WKWebView; we only get two states (0 and 100), so the progress is not gradual.
__declspec(dllexport) int _CWebViewPlugin_Progress(void* instance) {
    WebViewInstance* inst = (WebViewInstance*)instance;
    if (!inst || inst->destroying) return 0;
    return inst->progress.load();
}

__declspec(dllexport) bool _CWebViewPlugin_CanGoBack(void* instance) {
    WebViewInstance* inst = (WebViewInstance*)instance;
    if (!inst || inst->destroying) return false;
    std::lock_guard<std::mutex> lk(inst->cacheMutex);
    return inst->canGoBack;
}

__declspec(dllexport) bool _CWebViewPlugin_CanGoForward(void* instance) {
    WebViewInstance* inst = (WebViewInstance*)instance;
    if (!inst || inst->destroying) return false;
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
    if (!inst || inst->destroying || !inst->hwnd) return;
    MouseEventData* data = new MouseEventData{ x, y, deltaY, mouseState };
    PostMessage(inst->hwnd, WM_WEBVIEW_SEND_MOUSE, 0, (LPARAM)data);
}

__declspec(dllexport) void _CWebViewPlugin_SendKeyEvent(void* instance, int x, int y, char* keyChars, unsigned short keyCode, int keyState) {
    WebViewInstance* inst = (WebViewInstance*)instance;
    WV_LOG("SendKeyEvent called: inst=%p hwnd=%s keyCode=%u keyState=%d", (void*)inst, inst && inst->hwnd ? "ok" : "null", (unsigned)keyCode, keyState);
    if (!inst || inst->destroying || !inst->hwnd) return;
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
    if (!inst || inst->destroying) return;
    // With Graphics Capture there is nothing to pump: frames arrive on their own and
    // bitmapPixels always holds the newest one.
    if (inst->captureActive) return;
    // Fallback path. Non-blocking: only start a new capture when none is in progress.
    // STA thread uses double-buffering so Render() can read current bitmapPixels without delay.
    if (refreshBitmap && inst->hwnd && inst->webview) {
        if (!inst->captureInProgress.exchange(true)) {
            PostMessage(inst->hwnd, WM_WEBVIEW_CAPTURE, 0, 0);
        }
    }
}

// True when frames come from Graphics Capture (BGRA), false for the CapturePreview
// fallback (RGBA). The caller picks the matching Unity TextureFormat.
__declspec(dllexport) bool _CWebViewPlugin_BitmapIsBGRA(void* instance) {
    WebViewInstance* inst = (WebViewInstance*)instance;
    if (!inst || inst->destroying) return false;
    return inst->captureActive.load();
}

// Non-null only on the zero-copy path, once the first frame has sized the texture.
// Pass it to Texture2D.CreateExternalTexture; the plugin keeps ownership.
__declspec(dllexport) void* _CWebViewPlugin_GetTexturePtr(void* instance) {
    WebViewInstance* inst = (WebViewInstance*)instance;
    if (!inst || inst->destroying) return nullptr;
    return inst->texturePtr.load(std::memory_order_acquire);
}

// Pass to GL.IssuePluginEventAndData with eventId 1 and the instance as data.
__declspec(dllexport) UnityRenderingEventAndData _CWebViewPlugin_GetRenderEventFunc(void) {
    return OnRenderEventAndData;
}

// Selects the shared texture format so it matches the view Unity creates for the
// external texture. Call before _CWebViewPlugin_Init.
__declspec(dllexport) void _CWebViewPlugin_SetColorSpace(bool linearColorSpace) {
    s_linearColorSpace = linearColorSpace;
}

__declspec(dllexport) int _CWebViewPlugin_BitmapWidth(void* instance) {
    WebViewInstance* inst = (WebViewInstance*)instance;
    if (!inst || inst->destroying) return 0;
    std::lock_guard<std::mutex> lk(inst->bitmapMutex);
    return inst->bitmapWidth;
}

__declspec(dllexport) int _CWebViewPlugin_BitmapHeight(void* instance) {
    WebViewInstance* inst = (WebViewInstance*)instance;
    if (!inst || inst->destroying) return 0;
    std::lock_guard<std::mutex> lk(inst->bitmapMutex);
    return inst->bitmapHeight;
}

__declspec(dllexport) void _CWebViewPlugin_Render(void* instance, void* textureBuffer) {
    WebViewInstance* inst = (WebViewInstance*)instance;
    if (!inst || inst->destroying || !textureBuffer) return;
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
    if (!inst || inst->destroying) return nullptr;
    std::string msg;
    if (!inst->messages.pop(msg)) return nullptr;
    char* buf = (char*)CoTaskMemAlloc(msg.size() + 1);
    if (!buf) return nullptr;
    memcpy(buf, msg.c_str(), msg.size() + 1);
    return buf;
}

} // extern "C"
