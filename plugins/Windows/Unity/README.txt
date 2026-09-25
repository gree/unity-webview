================================================================================
Unity Native Plugin API Headers
================================================================================

These headers come from Unity and are vendored here so the Windows plugin can
get at Unity's D3D11 device and run code on Unity's render thread. They are used
by the zero-copy capture path in WebViewPlugin.cpp.

Files:
    - IUnityInterface.h
    - IUnityGraphics.h
    - IUnityGraphicsD3D11.h

They ship with every Unity installation under:

    Windows: C:\Program Files\Unity\Hub\Editor\<version>\Editor\Data\PluginAPI\
    macOS:   /Applications/Unity/Hub/Editor/<version>/Unity.app/Contents/PluginAPI/

and are also published at https://github.com/Unity-Technologies/PluginAPI

They are covered by the Unity Companion License, not by this repository's
license: http://www.unity3d.com/legal/licenses/Unity_Companion_License

================================================================================
