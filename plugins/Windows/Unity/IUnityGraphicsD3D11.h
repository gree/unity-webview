// Unity Native Plugin API copyright © 2015 Unity Technologies ApS
//
// Licensed under the Unity Companion License for Unity - dependent projects--see[Unity Companion License](http://www.unity3d.com/legal/licenses/Unity_Companion_License).
//
// Unless expressly provided otherwise, the Software under this license is made available strictly on an “AS IS” BASIS WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED.Please review the license for details on these and other terms and conditions.

#pragma once
#include "IUnityInterface.h"


// Should only be used on the rendering thread unless noted otherwise.
UNITY_DECLARE_INTERFACE(IUnityGraphicsD3D11)
{
    ID3D11Device* (UNITY_INTERFACE_API * GetDevice)();

    ID3D11Resource* (UNITY_INTERFACE_API * TextureFromRenderBuffer)(UnityRenderBuffer buffer);
    ID3D11Resource* (UNITY_INTERFACE_API * TextureFromNativeTexture)(UnityTextureID texture);

    ID3D11RenderTargetView* (UNITY_INTERFACE_API * RTVFromRenderBuffer)(UnityRenderBuffer surface);
    ID3D11ShaderResourceView* (UNITY_INTERFACE_API * SRVFromNativeTexture)(UnityTextureID texture);

    IDXGISwapChain* (UNITY_INTERFACE_API * GetSwapChain)();
    UINT32(UNITY_INTERFACE_API * GetSyncInterval)();
    UINT(UNITY_INTERFACE_API * GetPresentFlags)();
};

UNITY_REGISTER_INTERFACE_GUID(0xAAB37EF87A87D748ULL, 0xBF76967F07EFB177ULL, IUnityGraphicsD3D11)
