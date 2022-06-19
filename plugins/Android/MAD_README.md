# MAD forked unity-webview

(This setup file is for building on mac, I've run it and committed the changes)

## Sample Project
This is a custom unity webview fork to allow pausing and resuming unity while the WebView is running. (Notice: some of our unique implementation is in `webviewObject.cs`)
 	 
1. `plugins/Android/local.properties` needs to be configured w/ path to Android SDK used by Unity (i.e. `sdk.dir=/Applications/Unity/Hub/Editor/2020.3.30f1/PlaybackEngines/AndroidPlayer/SDK`)
2. Goto `plugins\Android` and open `install.sh`. (**Don't use `install-nofragment.sh`**)
3. In the sh script update `UNITY` variable with your unity version path (i.e. `UNITY="/Applications/Unity/Hub/Editor/2020.3.30f1"`) This batch sets up the android project (copies files into src)
4. Run the script!
   1. The script updates `webview/libs/classes.jar` with the relevant unity classes (i.e. `${UNITY}/PlaybackEngines/AndroidPlayer/Variations/${SCRIPTING_BACKEND}/${MODE}/Classes/classes.jar`)
   2. The script generates `WebViewPlugin.aar` and place it in `DEST_DIR` folder `../../build/Packager/Assets/Plugins/Android`
5. Copy `WebViewPlugin.aar` and `core-1.6.0.aar.tmpl` (why not in the script) to `dist/package/Assets/Plugins/Android` 
6. Push to git files from previous step. 
7. In your SlateApps's branch - reimport the plugin (delete `packages-lock` entry or remove and reimport from packages manager) - the package's `hash` should change in the packages-lock file
8. For reimporting the package to unity project delete the relevant section in "Packages/packages-lock.json" under the unity project and reload.

If you get this error:
> Failed to install the following Android SDK packages as some licences have not been accepted.
> 
you need to install the sdk tool follow this guide https://developer.android.com/studio/intro/update#sdk-manager in your android-studio/intelij
