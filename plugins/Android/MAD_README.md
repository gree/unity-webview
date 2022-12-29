# MAD forked unity-webview

(This setup file is for building on mac, I've run it and committed the changes)

## Creating new Plugin
This is a custom unity webview fork to allow pausing and resuming unity while the WebView is running. 
(**Notice:** all of our unique implementation is in `webviewObject.cs`, `CUnityPlayerActivity.java`, and `CWebViewPlugin.java` under `plugins/Android/webview/src/main/java/net/gree/unitywebview`)
 	 
1. `plugins/Android/local.properties` needs to be configured w/ path to Android SDK used by Unity (i.e. `sdk.dir=/Applications/Unity/Hub/Editor/2020.3.30f1/PlaybackEngines/AndroidPlayer/SDK`)
2. Goto `plugins\Android` and open `install.sh`. (**Don't use `install-nofragment.sh`**)
3. In the sh script update `UNITY` variable with your unity version path (i.e. `UNITY="/Applications/Unity/Hub/Editor/2020.3.30f1"`) This batch sets up the android project (copies files into src)
4. Run the script! (`install.sh`...)
   1. The script updates `webview/libs/classes.jar` with the relevant unity classes (i.e. `${UNITY}/PlaybackEngines/AndroidPlayer/Variations/${SCRIPTING_BACKEND}/${MODE}/Classes/classes.jar`)
   2. The script generates `WebViewPlugin.aar` and place it in `DEST_DIR` folder `../../build/Packager/Assets/Plugins/Android`
5. If succeeded, 2 files (among others) would be generated - `WebViewPlugin.aar` and `core-1.6.0.aar.tmpl` under `build/Packager/Assets/Plugins/Android`. 


If you get this error:
> Failed to install the following Android SDK packages as some licences have not been accepted.
> 
Sometimes if you build android from unity editor it will generate the missing licences.
If not working, you need to install the sdk tool follow this guide https://developer.android.com/studio/intro/update#sdk-manager in your android-studio/intelij.


## Deploying new Plugin locally
1. Copy `unity-webview` folder from `Packages` (Read only) and paste them in `Vendors` folderץ
2. Now you have 2 webviews and you can't build the project. Remove the unity-webview import from `packages.json`.
3. You need to remove old assembly (will appear grey) and reimport new assembly (from `Vendors`) in `AssetsAssembly`.
4. Now you can take `WebViewPlugin.aar` and `core-1.6.0.aar.tmpl` that were created in previous section and paste them in `Vendors/unity-webview/dist/package/Assets/Plugins/Android`.
5. You can modify WebViewObject.cs as you like.
6. If you add more changes to `CUnityPlayerActivity` or `CWebViewPlugin` rebuild plugin and redo step 4.
 

## Deploying new Plugin in git
1. Copy `WebViewPlugin.aar` and `core-1.6.0.aar.tmpl` from `build/Packager/Assets/Plugins/Android` to `dist/package/Assets/Plugins/Android`
2. Push to git `WebViewPlugin.aar` and `core-1.6.0.aar.tmpl` from previous section.
3. In your SlateApps's branch - reimport the plugin (delete `packages-lock` entry or remove and reimport from packages manager) - the package's `hash` should change in the packages-lock file
4. For reimporting the package to unity project delete the relevant section in "Packages/packages-lock.json" under the unity project and reload.