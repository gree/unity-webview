// Unity Native Plugin API copyright © 2015 Unity Technologies ApS
//
// Licensed under the Unity Companion License for Unity - dependent projects--see[Unity Companion License](http://www.unity3d.com/legal/licenses/Unity_Companion_License).
//
// Unless expressly provided otherwise, the Software under this license is made available strictly on an “AS IS” BASIS WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED.Please review the license for details on these and other terms and conditions.

#pragma once

// Unity native plugin API
// Compatible with C99

#if defined(__CYGWIN32__)
    #define UNITY_INTERFACE_API __stdcall
    #define UNITY_INTERFACE_EXPORT __declspec(dllexport)
#elif defined(WIN32) || defined(_WIN32) || defined(__WIN32__) || defined(_WIN64) || defined(WINAPI_FAMILY)
    #define UNITY_INTERFACE_API __stdcall
    #define UNITY_INTERFACE_EXPORT __declspec(dllexport)
#elif defined(__MACH__) || defined(__ANDROID__) || defined(__linux__) || defined(LUMIN)
    #define UNITY_INTERFACE_API
    #define UNITY_INTERFACE_EXPORT __attribute__ ((visibility ("default")))
#else
    #define UNITY_INTERFACE_API
    #define UNITY_INTERFACE_EXPORT
#endif

/////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// IUnityInterface is a registry of interfaces we choose to expose to plugins.
//
// USAGE:
// ---------
// To retrieve an interface a user can do the following from a plugin, assuming they have the header file for the interface:
//
// IMyInterface * ptr = registry->Get<IMyInterface>();
/////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

// Unity Interface GUID
// Ensures global uniqueness.
//
// Template specialization is used to produce a means of looking up a GUID from its interface type at compile time.
// The net result should compile down to passing around the GUID.
//
// UNITY_REGISTER_INTERFACE_GUID should be placed in the header file of any interface definition outside of all namespaces.
// The interface structure and the registration GUID are all that is required to expose the interface to other systems.
struct UnityInterfaceGUID
{
#ifdef __cplusplus
    UnityInterfaceGUID(unsigned long long high, unsigned long long low)
        : m_GUIDHigh(high)
        , m_GUIDLow(low)
    {
    }

    UnityInterfaceGUID(const UnityInterfaceGUID& other)
    {
        m_GUIDHigh = other.m_GUIDHigh;
        m_GUIDLow  = other.m_GUIDLow;
    }

    UnityInterfaceGUID& operator=(const UnityInterfaceGUID& other)
    {
        m_GUIDHigh = other.m_GUIDHigh;
        m_GUIDLow  = other.m_GUIDLow;
        return *this;
    }

    bool Equals(const UnityInterfaceGUID& other)   const { return m_GUIDHigh == other.m_GUIDHigh && m_GUIDLow == other.m_GUIDLow; }
    bool LessThan(const UnityInterfaceGUID& other) const { return m_GUIDHigh < other.m_GUIDHigh || (m_GUIDHigh == other.m_GUIDHigh && m_GUIDLow < other.m_GUIDLow); }
#endif
    unsigned long long m_GUIDHigh;
    unsigned long long m_GUIDLow;
};
#ifdef __cplusplus
inline bool operator==(const UnityInterfaceGUID& left, const UnityInterfaceGUID& right) { return left.Equals(right); }
inline bool operator!=(const UnityInterfaceGUID& left, const UnityInterfaceGUID& right) { return !left.Equals(right); }
inline bool operator<(const UnityInterfaceGUID& left, const UnityInterfaceGUID& right) { return left.LessThan(right); }
inline bool operator>(const UnityInterfaceGUID& left, const UnityInterfaceGUID& right) { return right.LessThan(left); }
inline bool operator>=(const UnityInterfaceGUID& left, const UnityInterfaceGUID& right) { return !operator<(left, right); }
inline bool operator<=(const UnityInterfaceGUID& left, const UnityInterfaceGUID& right) { return !operator>(left, right); }
#else
typedef struct UnityInterfaceGUID UnityInterfaceGUID;
#endif


#ifdef __cplusplus
    #define UNITY_DECLARE_INTERFACE(NAME) \
    struct NAME : IUnityInterface

// Generic version of GetUnityInterfaceGUID to allow us to specialize it
// per interface below. The generic version has no actual implementation
// on purpose.
//
// If you get errors about return values related to this method then
// you have forgotten to include UNITY_REGISTER_INTERFACE_GUID with
// your interface, or it is not visible at some point when you are
// trying to retrieve or add an interface.
template<typename TYPE>
inline const UnityInterfaceGUID GetUnityInterfaceGUID();

// This is the macro you provide in your public interface header
// outside of a namespace to allow us to map between type and GUID
// without the user having to worry about it when attempting to
// add or retrieve and interface from the registry.
    #define UNITY_REGISTER_INTERFACE_GUID(HASHH, HASHL, TYPE)      \
    template<>                                                     \
    inline const UnityInterfaceGUID GetUnityInterfaceGUID<TYPE>()  \
    {                                                              \
        return UnityInterfaceGUID(HASHH,HASHL);                    \
    }

// Same as UNITY_REGISTER_INTERFACE_GUID but allows the interface to live in
// a particular namespace. As long as the namespace is visible at the time you call
// GetUnityInterfaceGUID< INTERFACETYPE >() or you explicitly qualify it in the template
// calls this will work fine, only the macro here needs to have the additional parameter
    #define UNITY_REGISTER_INTERFACE_GUID_IN_NAMESPACE(HASHH, HASHL, TYPE, NAMESPACE) \
    const UnityInterfaceGUID TYPE##_GUID(HASHH, HASHL);                               \
    template<>                                                                        \
    inline const UnityInterfaceGUID GetUnityInterfaceGUID< NAMESPACE :: TYPE >()      \
    {                                                                                 \
        return UnityInterfaceGUID(HASHH,HASHL);                                       \
    }

// These macros allow for C compatibility in user code.
    #define UNITY_GET_INTERFACE_GUID(TYPE) GetUnityInterfaceGUID< TYPE >()


#else
    #define UNITY_DECLARE_INTERFACE(NAME) \
    typedef struct NAME NAME;             \
    struct NAME

// NOTE: This has the downside that one some compilers it will not get stripped from all compilation units that
//       can see a header containing this constant. However, it's only for C compatibility and thus should have
//       minimal impact.
    #define UNITY_REGISTER_INTERFACE_GUID(HASHH, HASHL, TYPE) \
    const UnityInterfaceGUID TYPE##_GUID = {HASHH, HASHL};

// In general namespaces are going to be a problem for C code any interfaces we expose in a namespace are
// not going to be usable from C.
    #define UNITY_REGISTER_INTERFACE_GUID_IN_NAMESPACE(HASHH, HASHL, TYPE, NAMESPACE)

// These macros allow for C compatibility in user code.
    #define UNITY_GET_INTERFACE_GUID(TYPE) TYPE##_GUID
#endif

// Using this in user code rather than INTERFACES->Get<TYPE>() will be C compatible for those places in plugins where
// this may be needed. Unity code itself does not need this.
#define UNITY_GET_INTERFACE(INTERFACES, TYPE) (TYPE*)INTERFACES->GetInterfaceSplit (UNITY_GET_INTERFACE_GUID(TYPE).m_GUIDHigh, UNITY_GET_INTERFACE_GUID(TYPE).m_GUIDLow);


#ifdef __cplusplus
struct IUnityInterface
{
};
#else
typedef void IUnityInterface;
#endif


typedef struct IUnityInterfaces
{
    // Returns an interface matching the guid.
    // Returns nullptr if the given interface is unavailable in the active Unity runtime.
    IUnityInterface* (UNITY_INTERFACE_API * GetInterface)(UnityInterfaceGUID guid);

    // Registers a new interface.
    void(UNITY_INTERFACE_API * RegisterInterface)(UnityInterfaceGUID guid, IUnityInterface * ptr);

    // Split APIs for C
    IUnityInterface* (UNITY_INTERFACE_API * GetInterfaceSplit)(unsigned long long guidHigh, unsigned long long guidLow);
    void(UNITY_INTERFACE_API * RegisterInterfaceSplit)(unsigned long long guidHigh, unsigned long long guidLow, IUnityInterface * ptr);

#ifdef __cplusplus
    // Helper for GetInterface.
    template<typename INTERFACE>
    INTERFACE* Get()
    {
        return static_cast<INTERFACE*>(GetInterface(GetUnityInterfaceGUID<INTERFACE>()));
    }

    // Helper for RegisterInterface.
    template<typename INTERFACE>
    void Register(IUnityInterface* ptr)
    {
        RegisterInterface(GetUnityInterfaceGUID<INTERFACE>(), ptr);
    }

#endif
} IUnityInterfaces;


#ifdef __cplusplus
extern "C" {
#endif

// If exported by a plugin, this function will be called when the plugin is loaded.
void UNITY_INTERFACE_EXPORT UNITY_INTERFACE_API UnityPluginLoad(IUnityInterfaces* unityInterfaces);
// If exported by a plugin, this function will be called when the plugin is about to be unloaded.
void UNITY_INTERFACE_EXPORT UNITY_INTERFACE_API UnityPluginUnload();

#ifdef __cplusplus
}
#endif

struct RenderSurfaceBase;
typedef struct RenderSurfaceBase* UnityRenderBuffer;
typedef unsigned int UnityTextureID;
