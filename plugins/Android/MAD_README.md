# MAD forked unity-webview

(This setup file is for building on mac, I've run it and committed the changes)

## Recording of the process:
https://sites.google.com/slatescience.com/knowledgebase/product/applications/unity/webview


## Creating new Plugin
This is a custom unity webview fork to allow pausing and resuming unity while the WebView is running. 
(**Notice:** all of our unique implementation is in `webviewObject.cs`, `CUnityPlayerActivity.java`, and `CWebViewPlugin.java` under `plugins/Android/webview/src/main/java/net/gree/unitywebview`)
 	 
1. `plugins/Android/local.properties` needs to be configured w/ path to Android SDK used by Unity (i.e. `sdk.dir=/Applications/Unity/Hub/Editor/2020.3.30f1/PlaybackEngines/AndroidPlayer/SDK`)
2. Goto `plugins\Android` and open `install.sh`. (**Don't use `install-nofragment.sh`**)
3. In the sh script update `UNITY` variable with your unity version (i.e. `UNITY="2020.3.30f1"`) This batch sets up the android project (copies files into src).
There's no need to enter the full path - the script appends it.
4. From the terminal, call `install.sh [--development]`
   1. The script updates `webview/libs/classes.jar` with the relevant unity classes (i.e. `${UNITY}/PlaybackEngines/AndroidPlayer/Variations/${SCRIPTING_BACKEND}/${MODE}/Classes/classes.jar`)
   2. The script generates `WebViewPlugin-release.aar.tmpl` or `WebViewPlugin-development.aar.tmpl` and place it in `DEST_DIR` folder `../../build/Packager/Assets/Plugins/Android`
5. If succeeded, 2 files (among others) would be generated - `WebViewPlugin-*.aar.tmpl` and `core-1.6.0.aar.tmpl` under `build/Packager/Assets/Plugins/Android`.

If you get this error:
> Failed to install the following Android SDK packages as some licences have not been accepted.
> 
Sometimes if you build android from unity editor it will generate the missing licences.
If not working, you need to install the sdk tool follow this guide https://developer.android.com/studio/intro/update#sdk-manager in your android-studio/intelij.

### Alternate solution to licensing issue
You can install and update the appropriate Android SDKs directly into your Unity installation folder
1. Go to Android Studio
2. Go to Settings Menu > Android SDK
3. in the Android SDK Location field (top) click Edit
4. Navigate to your Unity install, e.g. `/Applications/Unity/Hub/Editor/2022.3.32f1/PlaybackEngines/AndroidPlayer/SDK`
5. Update the SDKs there and accept the licenses


## Deploying new Plugin locally
1. Copy `unity-webview` folder from `Packages` (Read only) and paste them in `Vendors` folder.
2. Now you have 2 webviews and you can't build the project. Remove the unity-webview import from `packages.json`.
3. You need to remove old assembly (will appear greyed-out/error) and reimport new assembly (from `Vendors`) under `Assets/AssetsAssembly.asmdf`.
4. Now you can take `WebViewPlugin-*.aar.tmpl` and `core-1.6.0.aar.tmpl` that were created in previous section and paste them in `Vendors/unity-webview/dist/package/Assets/Plugins/Android`.
5. You can modify WebViewObject.cs as you like.
6. If you add more changes to `CUnityPlayerActivity` or `CWebViewPlugin` Build the project, rebuild plugin and redo step 4.
 

## Deploying new Plugin in git
1. The `.tmpl` files for `WebViewPlugin` and `core-*` are already in the repo.
2. After running `install.sh` and recompiling, 
3. Copy `WebViewPlugin-*.aar.tmpl` and `core-1.6.0.aar.tmpl` from `build/Packager/Assets/Plugins/Android` to `dist/package/Assets/Plugins/Android`
4. Push updated files from previous step to git 
5. In your SlateApps's branch - edit `Packages/manifest.json` and replace the current hash with that of your latest commit.
   
   e.g., on the appropriate package line:
   > "net.gree.unity-webview": "https://github.com/SlateScience/unity-webview.git?path=/dist/package#ab84fb0517eb7b3a113465a23ed28fdb5ce92446",
   
   change the hash to the new commit, like so:
   > "net.gree.unity-webview": "https://github.com/SlateScience/unity-webview.git?path=/dist/package#[NEW_HASH]",
6. *Be sure to commit the relevant changes in `Packages/packages-lock.json`* as well.
7. Unity will reimport the package and update the plugin files.