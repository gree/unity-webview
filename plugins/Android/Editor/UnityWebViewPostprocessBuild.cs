#if UNITY_ANDROID
using System.Collections;
using System.IO;
using System.Xml;
using UnityEditor.Callbacks;
using UnityEditor;
using UnityEngine;

public class UnityWebViewPostprocessBuild {
#if UNITYWEBVIEW_ANDROID_USE_ACTIVITY_NAME
    // please modify ACTIVITY_NAME if you set UNITYWEBVIEW_ANDROID_USE_ACTIVITY_NAME and utilize any custom activty.
    private const string ACTIVITY_NAME = "com.unity3d.player.UnityPlayerActivity";
#endif

    [PostProcessBuild(100)]
    public static void OnPostprocessBuild(BuildTarget buildTarget, string path) {
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
#if UNITY_5_6_OR_NEWER
            if (activity != null
                && activity.GetAttribute("android:name") == "com.unity3d.player.UnityPlayerActivity") {
                activity.SetAttribute("name", "http://schemas.android.com/apk/res/android", "net.gree.unitywebview.CUnityPlayerActivity");
                doc.Save(manifest);
                Debug.LogError("adjusted AndroidManifest.xml about android:name. Please rebuild the app.");
            }
#endif
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
#endif
