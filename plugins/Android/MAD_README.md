# MAD forked unity-webview

(This setup file is for building on mac, I've run it and committed the changes)

## Sample Project
This is a custom unity webview fork to allow pausing and resuming unity while the WebView is running. (Notice: some of our unique implementation is in `webviewObject.cs`)
 	 
1. Goto `plugins\Android` and open `install.sh`
2. Update "UNITY" with your unity version path (i.e. UNITY="/Applications/Unity/Hub/Editor/2020.3.30f1") This batch sets up the android project (copies files into src) 
3. Update `classes.jar` with the `webview/libs` folder with the relevant unity classes (i.e. `${UNITY}/PlaybackEngines/AndroidPlayer/Variations/${SCRIPTING_BACKEND}/${MODE}/Classes/classes.jar`)

*NOTE: `local.properties` needs to be configured w/ path to Android SDK used by Unity (i.e. sdk.dir=/Applications/Unity/Hub/Editor/2020.3.30f1/PlaybackEngines/AndroidPlayer/SDK)

####
After Building the project with `install.sh` copy the `WebViewPlugin.aar` from dest directory into the relevant path in dist directory.
