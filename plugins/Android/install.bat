@echo off

rd /s /q bin
rd /s /q gradle_build\libs
rd /s /q gradle_build\src

mkdir bin
mkdir gradle_build\libs
mkdir gradle_build\src
mkdir gradle_build\src\main
mkdir gradle_build\src\main\java

copy /b "classes.jar" gradle_build\libs
xcopy /s /e src gradle_build\src\main\java


copy /b AndroidManifest.xml gradle_build\src\main

rem call gradlew.bat clean
rem call gradlew.bat assembleDebug

rem cd gradle_build/build/outputs/aar
rem copy /B "gradle_build-debug.aar" "../../../../bin/WebViewPlugin.aar"

call gradlew.bat clean
call gradlew.bat assembleRelease

cd gradle_build/build/outputs/aar
copy /B "gradle_build-release.aar" "../../../../bin/WebViewPlugin.aar"

cd ../../../../

