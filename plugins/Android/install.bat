@echo off

rd /s /q bin
rd /s /q gradle_build\libs
rd /s /q gradle_build\src

mkdir bin
mkdir gradle_build\libs
mkdir gradle_build\src
mkdir gradle_build\src\main
mkdir gradle_build\src\main\java

copy /b "\Program Files\Unity5.6.1f1\Editor\Data\PlaybackEngines\AndroidPlayer\Variations\mono\Release\Classes\classes.jar" gradle_build\libs >nul
xcopy /s /e src gradle_build\src\main\java >nul
copy /b AndroidManifest.xml gradle_build\src\main >nul

call gradlew.bat clean
call gradlew.bat assembleRelease
copy /b gradle_build/build/outputs/aar/*.aar bin\WebViewPlugins.aar >nul

mkdir -p ${DEST_DIR}
copy /b bin\WebViewPlugins.aar ..\..\build\Packager\Assets\Plugins\Android\WebViewPlugin.aar
