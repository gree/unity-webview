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

call gradlew.bat assembleRelease

jar cf bin\WebViewPlugin.jar -C gradle_build\build\intermediates\classes\release net
