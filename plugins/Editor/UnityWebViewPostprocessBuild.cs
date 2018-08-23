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

    public void OnPostGenerateGradleAndroidProject(string basePath) {
        Debug.Log("adjusted AndroidManifest.xml.");
        var androidManifest = new AndroidManifest(GetManifestPath(basePath));
        androidManifest.SetHardwareAccelerated(true);
        androidManifest.Save();
    }

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

#if UNITYWEBVIEW_ANDROID_USE_ACTIVITY_NAME
    // please modify ACTIVITY_NAME if you set UNITYWEBVIEW_ANDROID_USE_ACTIVITY_NAME and utilize any custom activty.
    private const string ACTIVITY_NAME = "com.unity3d.player.UnityPlayerActivity";
#endif

    [PostProcessBuild(100)]
    public static void OnPostprocessBuild(BuildTarget buildTarget, string path) {
#if !UNITY_2018_1_OR_NEWER
        if (buildTarget == BuildTarget.Android) {
            string manifest = Path.Combine(Application.dataPath, "Plugins/Android/AndroidManifest.xml");
            if (!File.Exists(manifest)) {
                string manifest0 = Path.Combine(Application.dataPath, "../Temp/StagingArea/AndroidManifest-main.xml");
                if (!File.Exists(manifest0)) {
                    Debug.LogError("cannot find both Assets/Plugins/Android/AndroidManifest.xml and Temp/StagingArea/AndroidManifest-main.xml. please build the app to generate Assets/Plugins/Android/AndroidManifest.xml and then rebuild it again.");
                    return;
                } else {
                    File.Copy(manifest0, manifest);
                }
            }
            XmlDocument doc = new XmlDocument();
            doc.Load(manifest);
            XmlElement activity = SearchActivity(doc);
            if (activity != null
                && string.IsNullOrEmpty(activity.GetAttribute("android:hardwareAccelerated"))) {
                activity.SetAttribute("hardwareAccelerated", "http://schemas.android.com/apk/res/android", "true");
                doc.Save(manifest);
                Debug.LogError("adjusted AndroidManifest.xml about android:hardwareAccelerated. Please rebuild the app.");
            }
#if UNITY_5_6_0 || UNITY_5_6_1
            if (activity != null
                && activity.GetAttribute("android:name") == "com.unity3d.player.UnityPlayerActivity") {
                activity.SetAttribute("name", "http://schemas.android.com/apk/res/android", "net.gree.unitywebview.CUnityPlayerActivity");
                doc.Save(manifest);
                Debug.LogError("adjusted AndroidManifest.xml about android:name. Please rebuild the app.");
            }
#endif
        }
#endif
        if (buildTarget == BuildTarget.iOS) {
            string projPath = path + "/Unity-iPhone.xcodeproj/project.pbxproj";
            PBXProject proj = new PBXProject();
            proj.ReadFromString(File.ReadAllText(projPath));
            string target = proj.TargetGuidByName("Unity-iPhone");
            proj.AddFrameworkToProject(target, "WebKit.framework", false);
            File.WriteAllText(projPath, proj.WriteToString());
        }
    }

    private static XmlElement SearchActivity(XmlDocument doc) {
        foreach (XmlNode node0 in doc.DocumentElement.ChildNodes) {
            if (node0.Name == "application") {
                foreach (XmlNode node1 in node0.ChildNodes) {
#if UNITYWEBVIEW_ANDROID_USE_ACTIVITY_NAME
                    if (node1.Name == "activity"
                        && ((XmlElement)node1).GetAttribute("android:name") == ACTIVITY_NAME) {
                        return (XmlElement)node1;
                    }
#else
                    if (node1.Name == "activity") {
                        foreach (XmlNode node2 in node1.ChildNodes) {
                            if (node2.Name == "intent-filter") {
                                bool hasActionMain = false;
                                bool hasCategoryLauncher = false;
                                foreach (XmlNode node3 in node2.ChildNodes) {
                                    if (node3.Name == "action"
                                        && ((XmlElement)node3).GetAttribute("android:name") == "android.intent.action.MAIN") {
                                        hasActionMain = true;
                                    } else if (node3.Name == "category"
                                               && ((XmlElement)node3).GetAttribute("android:name") == "android.intent.category.LAUNCHER") {
                                        hasCategoryLauncher = true;
                                    }
                                }
                                if (hasActionMain && hasCategoryLauncher) {
                                    return (XmlElement)node1;
                                }
                            }
                        }
#endif
                    }
                }
            }
        }
        return null;
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
    private readonly XmlElement ApplicationElement;

    public AndroidManifest(string path) : base(path) {
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

    internal void SetHardwareAccelerated(bool enabled) {
        var activity = GetActivityWithLaunchIntent() as XmlElement;
        activity.SetAttribute("android:hardwareAccelerated", (enabled) ? "true" : "false");
    }
}

