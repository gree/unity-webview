# Restore Microsoft.Web.WebView2 SDK for building WebViewPlugin.dll
# Run this once before building in Visual Studio (or run from Developer PowerShell).

$ErrorActionPreference = "Stop"
$packagesDir = Join-Path $PSScriptRoot "packages"
$packageDir = Join-Path $packagesDir "Microsoft.Web.WebView2.1.0.3800.47"
$includeDir = Join-Path $packageDir "build\native\include"

if (Test-Path $includeDir) {
    Write-Host "WebView2 SDK already present at: $packageDir" -ForegroundColor Green
    exit 0
}

Write-Host "Downloading WebView2 SDK (Microsoft.Web.WebView2 1.0.3800.47)..." -ForegroundColor Yellow

# Try nuget.exe (in PATH or in current folder)
$nugetExe = $null
if (Get-Command nuget -ErrorAction SilentlyContinue) {
    $nugetExe = "nuget"
} elseif (Test-Path (Join-Path $PSScriptRoot "nuget.exe")) {
    $nugetExe = (Join-Path $PSScriptRoot "nuget.exe")
} else {
    Write-Host "Downloading nuget.exe..." -ForegroundColor Yellow
    $nugetUrl = "https://dist.nuget.org/win-x86-commandline/latest/nuget.exe"
    $nugetExe = Join-Path $PSScriptRoot "nuget.exe"
    try {
        Invoke-WebRequest -Uri $nugetUrl -OutFile $nugetExe -UseBasicParsing
    } catch {
        Write-Host "ERROR: Could not download nuget.exe. Please install NuGet from https://www.nuget.org/downloads and run:" -ForegroundColor Red
        Write-Host "  nuget install Microsoft.Web.WebView2 -Version 1.0.3800.47 -OutputDirectory packages" -ForegroundColor Cyan
        exit 1
    }
}

if (-not (Test-Path $packagesDir)) {
    New-Item -ItemType Directory -Path $packagesDir | Out-Null
}

Push-Location $PSScriptRoot
try {
    & $nugetExe install Microsoft.Web.WebView2 -Version 1.0.3800.47 -OutputDirectory packages
    if (-not (Test-Path $includeDir)) {
        # NuGet may use lowercase folder name
        $packageDirLower = Join-Path $packagesDir "microsoft.web.webview2.1.0.3800.47"
        $includeDirLower = Join-Path $packageDirLower "build\native\include"
        if (Test-Path $includeDirLower) {
            Write-Host "WebView2 SDK installed at: $packageDirLower" -ForegroundColor Green
        } else {
            Write-Host "ERROR: SDK not found after install. Check that packages folder contains Microsoft.Web.WebView2.1.0.3800.47" -ForegroundColor Red
            exit 1
        }
    } else {
        Write-Host "WebView2 SDK installed at: $packageDir" -ForegroundColor Green
    }
} finally {
    Pop-Location
}

Write-Host "You can now open WebViewPlugin.vcxproj in Visual Studio and build (Release | x64)." -ForegroundColor Green
