#if UNITY_IOS
using System.Collections;
using System.IO;
using UnityEditor.Callbacks;
using UnityEditor.iOS.Xcode;
using UnityEditor;
using UnityEngine;

public class UnityWebViewPostprocessBuild {
    [PostProcessBuild(100)]
    public static void OnPostprocessBuild(BuildTarget buildTarget, string path) {
        if (buildTarget == BuildTarget.iOS) {
            string projPath = path + "/Unity-iPhone.xcodeproj/project.pbxproj";
            PBXProject proj = new PBXProject();
            proj.ReadFromString(File.ReadAllText(projPath));
            string target = proj.TargetGuidByName("Unity-iPhone");
            proj.AddFrameworkToProject(target, "WebKit.framework", false);
            File.WriteAllText(projPath, proj.WriteToString());
        }
    }
}
#endif
