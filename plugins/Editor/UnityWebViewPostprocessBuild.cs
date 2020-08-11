#if UNITY_EDITOR
using System.Collections;
using System.IO;
using System.Text;
using System.Xml;
using UnityEditor.Android;
using UnityEditor.Callbacks;
using UnityEditor.iOS.Xcode;
using UnityEditor;
using UnityEngine;

#if UNITY_2018_1_OR_NEWER
public class UnityWebViewPostprocessBuild : IPostGenerateGradleAndroidProject
#else
public class UnityWebViewPostprocessBuild
#endif
{
    //// for android/unity 2018.1 or newer
    //// cf. https://forum.unity.com/threads/android-hardwareaccelerated-is-forced-false-in-all-activities.532786/
    //// cf. https://github.com/Over17/UnityAndroidManifestCallback

#if UNITY_2018_1_OR_NEWER
    public void OnPostGenerateGradleAndroidProject(string basePath) {
        var changed = false;
        var androidManifest = new AndroidManifest(GetManifestPath(basePath));
        changed = (androidManifest.SetHardwareAccelerated(true) || changed);
#if UNITYWEBVIEW_ANDROID_USES_CLEARTEXT_TRAFFIC
        changed = (androidManifest.SetUsesCleartextTraffic(true) || changed);
#endif
#if UNITYWEBVIEW_ANDROID_ENABLE_CAMERA
        changed = (androidManifest.AddCamera() || changed);
#endif
#if UNITYWEBVIEW_ANDROID_ENABLE_MICROPHONE
        changed = (androidManifest.AddMicrophone() || changed);
#endif
        if (changed) {
            androidManifest.Save();
            Debug.Log("unitywebview: adjusted AndroidManifest.xml.");
        }
    }
#endif

    public int callbackOrder {
        get {
            return 1;
        }
    }

    private string GetManifestPath(string basePath) {
        var pathBuilder = new StringBuilder(basePath);
        pathBuilder.Append(Path.DirectorySeparatorChar).Append("src");
        pathBuilder.Append(Path.DirectorySeparatorChar).Append("main");
        pathBuilder.Append(Path.DirectorySeparatorChar).Append("AndroidManifest.xml");
        return pathBuilder.ToString();
    }

    //// for others

    [PostProcessBuild(100)]
    public static void OnPostprocessBuild(BuildTarget buildTarget, string path) {
#if !UNITY_2018_1_OR_NEWER
        if (buildTarget == BuildTarget.Android) {
            string manifest = Path.Combine(Application.dataPath, "Plugins/Android/AndroidManifest.xml");
            if (!File.Exists(manifest)) {
                string manifest0 = Path.Combine(Application.dataPath, "../Temp/StagingArea/AndroidManifest-main.xml");
                if (!File.Exists(manifest0)) {
                    Debug.LogError("unitywebview: cannot find both Assets/Plugins/Android/AndroidManifest.xml and Temp/StagingArea/AndroidManifest-main.xml. please build the app to generate Assets/Plugins/Android/AndroidManifest.xml and then rebuild it again.");
                    return;
                } else {
                    File.Copy(manifest0, manifest);
                }
            }
            var changed = false;
            var androidManifest = new AndroidManifest(manifest);
            changed = (androidManifest.SetHardwareAccelerated(true) || changed);
#if UNITYWEBVIEW_ANDROID_USES_CLEARTEXT_TRAFFIC
            changed = (androidManifest.SetUsesCleartextTraffic(true) || changed);
#endif
#if UNITYWEBVIEW_ANDROID_ENABLE_CAMERA
            changed = (androidManifest.AddCamera() || changed);
#endif
#if UNITYWEBVIEW_ANDROID_ENABLE_MICROPHONE
            changed = (androidManifest.AddMicrophone() || changed);
#endif
#if UNITY_5_6_0 || UNITY_5_6_1
            changed = (androidManifest.SetActivityName("net.gree.unitywebview.CUnityPlayerActivity") || changed);
#endif
            if (changed) {
                androidManifest.Save();
                Debug.LogError("unitywebview: adjusted AndroidManifest.xml. Please rebuild the app.");
            }
        }
#endif
        if (buildTarget == BuildTarget.iOS) {
            string projPath = path + "/Unity-iPhone.xcodeproj/project.pbxproj";
            PBXProject proj = new PBXProject();
            proj.ReadFromString(File.ReadAllText(projPath));
#if UNITY_2019_3_OR_NEWER
            proj.AddFrameworkToProject(proj.GetUnityFrameworkTargetGuid(), "WebKit.framework", false);
#else
            proj.AddFrameworkToProject(proj.TargetGuidByName("Unity-iPhone"), "WebKit.framework", false);
#endif
            File.WriteAllText(projPath, proj.WriteToString());
        }
    }
}

internal class AndroidXmlDocument : XmlDocument {
    private string m_Path;
    protected XmlNamespaceManager nsMgr;
    public readonly string AndroidXmlNamespace = "http://schemas.android.com/apk/res/android";

    public AndroidXmlDocument(string path) {
        m_Path = path;
        using (var reader = new XmlTextReader(m_Path)) {
            reader.Read();
            Load(reader);
        }
        nsMgr = new XmlNamespaceManager(NameTable);
        nsMgr.AddNamespace("android", AndroidXmlNamespace);
    }

    public string Save() {
        return SaveAs(m_Path);
    }

    public string SaveAs(string path) {
        using (var writer = new XmlTextWriter(path, new UTF8Encoding(false))) {
            writer.Formatting = Formatting.Indented;
            Save(writer);
        }
        return path;
    }
}

internal class AndroidManifest : AndroidXmlDocument {
    private readonly XmlElement ManifestElement;
    private readonly XmlElement ApplicationElement;

    public AndroidManifest(string path) : base(path) {
        ManifestElement = SelectSingleNode("/manifest") as XmlElement;
        ApplicationElement = SelectSingleNode("/manifest/application") as XmlElement;
    }

    private XmlAttribute CreateAndroidAttribute(string key, string value) {
        XmlAttribute attr = CreateAttribute("android", key, AndroidXmlNamespace);
        attr.Value = value;
        return attr;
    }

    internal XmlNode GetActivityWithLaunchIntent() {
        return
            SelectSingleNode(
                "/manifest/application/activity[intent-filter/action/@android:name='android.intent.action.MAIN' and "
                + "intent-filter/category/@android:name='android.intent.category.LAUNCHER']",
                nsMgr);
    }

    internal bool SetUsesCleartextTraffic(bool enabled) {
        // android:usesCleartextTraffic
        bool changed = false;
        if (ApplicationElement.GetAttribute("usesCleartextTraffic", AndroidXmlNamespace) != ((enabled) ? "true" : "false")) {
            ApplicationElement.SetAttribute("usesCleartextTraffic", AndroidXmlNamespace, (enabled) ? "true" : "false");
            changed = true;
        }
        return changed;
    }

    internal bool SetHardwareAccelerated(bool enabled) {
        bool changed = false;
        var activity = GetActivityWithLaunchIntent() as XmlElement;
        if (activity.GetAttribute("hardwareAccelerated", AndroidXmlNamespace) != ((enabled) ? "true" : "false")) {
            activity.SetAttribute("hardwareAccelerated", AndroidXmlNamespace, (enabled) ? "true" : "false");
            changed = true;
        }
        return changed;
    }

    internal bool SetActivityName(string name) {
        bool changed = false;
        var activity = GetActivityWithLaunchIntent() as XmlElement;
        if (activity.GetAttribute("name", AndroidXmlNamespace) != name) {
            activity.SetAttribute("name", AndroidXmlNamespace, name);
            changed = true;
        }
        return changed;
    }

    internal bool AddCamera() {
        bool changed = false;
        if (SelectNodes("/manifest/uses-permission[@android:name='android.permission.CAMERA']", nsMgr).Count == 0) {
            var elem = CreateElement("uses-permission");
            elem.Attributes.Append(CreateAndroidAttribute("name", "android.permission.CAMERA"));
            ManifestElement.AppendChild(elem);
            changed = true;
        }
        if (SelectNodes("/manifest/uses-feature[@android:name='android.hardware.camera']", nsMgr).Count == 0) {
            var elem = CreateElement("uses-feature");
            elem.Attributes.Append(CreateAndroidAttribute("name", "android.hardware.camera"));
            ManifestElement.AppendChild(elem);
            changed = true;
        }
        return changed;
    }

    internal bool AddMicrophone() {
        bool changed = false;
        if (SelectNodes("/manifest/uses-permission[@android:name='android.permission.MICROPHONE']", nsMgr).Count == 0) {
            var elem = CreateElement("uses-permission");
            elem.Attributes.Append(CreateAndroidAttribute("name", "android.permission.MICROPHONE"));
            ManifestElement.AppendChild(elem);
            changed = true;
        }
        if (SelectNodes("/manifest/uses-feature[@android:name='android.hardware.microphone']", nsMgr).Count == 0) {
            var elem = CreateElement("uses-feature");
            elem.Attributes.Append(CreateAndroidAttribute("name", "android.hardware.microphone"));
            ManifestElement.AppendChild(elem);
            changed = true;
        }
        return changed;
    }
}
#endif
