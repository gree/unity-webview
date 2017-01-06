#if UNITY_ANDROID
using System.Collections;
using System.IO;
using System.Xml;
using UnityEditor.Callbacks;
using UnityEditor;
using UnityEngine;

public class UnityWebViewPostprocessBuild {
    // you need to modify ACTIVITY_NAME if you utilize any custom activty.
    private const string ACTIVITY_NAME = "com.unity3d.player.UnityPlayerActivity";

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
            XmlElement activity = null;
            // Let's find the application node.
            foreach (XmlNode node0 in doc.DocumentElement.ChildNodes) {
                if (node0.Name == "application") {
                    foreach (XmlNode node1 in node0.ChildNodes) {
                        if (node1.Name == "activity"
                            && ((XmlElement)node1).GetAttribute("android:name") == ACTIVITY_NAME) {
                            activity = (XmlElement)node1;
                            break;
                        }
                    }
                    break;
                }
            }
            if (activity != null
                && string.IsNullOrEmpty(activity.GetAttribute("android:hardwareAccelerated"))) {
                activity.SetAttribute("hardwareAccelerated", "http://schemas.android.com/apk/res/android", "true");
                doc.Save(manifest);
                Debug.LogError("adjusted AndroidManifest.xml about android:hardwareAccelerated. Please rebuild the app.");
            }
        }
    }
}
#endif
