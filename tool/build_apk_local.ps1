param(
    [ValidateSet("debug", "profile", "release")]
    [string]$Mode = "release"
)

$ErrorActionPreference = "Stop"

$projectRoot = Split-Path $PSScriptRoot -Parent
$prepareScript = Join-Path $PSScriptRoot "prepare_local_android.ps1"
$localFlutterMavenRoot = Join-Path $projectRoot ".flutter-maven"

& $prepareScript

function Get-FlutterSdkPath {
    if ($env:FLUTTER_ROOT -and (Test-Path $env:FLUTTER_ROOT)) {
        return (Resolve-Path $env:FLUTTER_ROOT).Path
    }

    $flutterCommand = Get-Command flutter -ErrorAction Stop
    $flutterBinDir = Split-Path $flutterCommand.Source -Parent
    return (Split-Path $flutterBinDir -Parent)
}

function Get-EngineVersion {
    param([string]$FlutterSdkPath)

    return (Get-Content (Join-Path $FlutterSdkPath "bin\cache\engine.stamp")).Trim()
}

function Get-EngineRealm {
    param([string]$FlutterSdkPath)

    $realmFile = Join-Path $FlutterSdkPath "bin\cache\engine.realm"
    if (-not (Test-Path $realmFile)) {
        return ""
    }

    return (Get-Content $realmFile).Trim()
}

function Get-FlutterArtifactsForMode {
    param([string]$BuildMode)

    switch ($BuildMode) {
        "debug" {
            return @(
                "flutter_embedding_debug",
                "armeabi_v7a_debug",
                "arm64_v8a_debug",
                "x86_debug",
                "x86_64_debug"
            )
        }
        "profile" {
            return @(
                "flutter_embedding_profile",
                "armeabi_v7a_profile",
                "arm64_v8a_profile"
            )
        }
        default {
            return @(
                "flutter_embedding_release",
                "armeabi_v7a_release",
                "arm64_v8a_release",
                "x86_64_release"
            )
        }
    }
}

function Ensure-LocalFlutterEngineMirror {
    param(
        [string]$FlutterSdkPath,
        [string]$BuildMode
    )

    $engineVersion = Get-EngineVersion -FlutterSdkPath $FlutterSdkPath
    $engineRealm = Get-EngineRealm -FlutterSdkPath $FlutterSdkPath
    $artifactVersion = "1.0.0-$engineVersion"
    $remoteBaseUrl = "https://storage.googleapis.com"

    $localDownloadRoot = $localFlutterMavenRoot
    if ($engineRealm) {
        $remoteBaseUrl = "$remoteBaseUrl/$engineRealm"
        $localDownloadRoot = Join-Path $localDownloadRoot $engineRealm
    }

    $localDownloadRoot = Join-Path $localDownloadRoot "download.flutter.io\io\flutter"
    $artifactNames = Get-FlutterArtifactsForMode -BuildMode $BuildMode

    foreach ($artifactName in $artifactNames) {
        $artifactRoot = Join-Path $localDownloadRoot (Join-Path $artifactName $artifactVersion)
        New-Item -ItemType Directory -Force -Path $artifactRoot | Out-Null

        foreach ($extension in @("pom", "jar")) {
            $fileName = "$artifactName-$artifactVersion.$extension"
            $localPath = Join-Path $artifactRoot $fileName
            if (Test-Path $localPath) {
                continue
            }

            $artifactUrl = "$remoteBaseUrl/download.flutter.io/io/flutter/$artifactName/$artifactVersion/$fileName"
            Invoke-WebRequest -Uri $artifactUrl -OutFile $localPath -TimeoutSec 600
        }
    }
}

$androidSdkRoot = Join-Path $projectRoot ".android-sdk"
$jdkHome = Get-ChildItem (Join-Path $projectRoot ".jdk") -Directory -Filter "jdk-*" |
    Sort-Object Name -Descending |
    Select-Object -First 1

if (-not $jdkHome) {
    throw "No local JDK found under $projectRoot\.jdk"
}

$flutterSdkPath = Get-FlutterSdkPath
Ensure-LocalFlutterEngineMirror -FlutterSdkPath $flutterSdkPath -BuildMode $Mode

$env:JAVA_HOME = $jdkHome.FullName
$env:ANDROID_SDK_ROOT = $androidSdkRoot
$env:ANDROID_HOME = $androidSdkRoot
$env:FLUTTER_STORAGE_BASE_URL = "file:///$($localFlutterMavenRoot.Replace('\', '/'))"
$env:PATH = "$($jdkHome.FullName)\bin;$androidSdkRoot\platform-tools;$env:PATH"

Push-Location $projectRoot
try {
    & flutter build apk "--$Mode"
}
finally {
    Pop-Location
}
