param(
    [string]$AndroidApi = "36",
    [string]$BuildToolsVersion = "36.0.0"
)

$ErrorActionPreference = "Stop"

$projectRoot = Split-Path $PSScriptRoot -Parent
$repoRoot = Split-Path $projectRoot -Parent
$androidSdkRoot = Join-Path $projectRoot ".android-sdk"
$cmdlineToolsRoot = Join-Path $androidSdkRoot "cmdline-tools\latest"
$localJdkRoot = Join-Path $projectRoot ".jdk"
$localPropertiesPath = Join-Path $projectRoot "android\local.properties"

function Convert-ToPropertiesPath {
    param([string]$PathValue)

    return $PathValue.Replace("\", "\\")
}

function Get-FlutterSdkPath {
    if ($env:FLUTTER_ROOT -and (Test-Path $env:FLUTTER_ROOT)) {
        return (Resolve-Path $env:FLUTTER_ROOT).Path
    }

    $flutterCommand = Get-Command flutter -ErrorAction Stop
    $flutterBinDir = Split-Path $flutterCommand.Source -Parent
    return (Split-Path $flutterBinDir -Parent)
}

function Ensure-AndroidCmdlineTools {
    $sdkManager = Join-Path $cmdlineToolsRoot "bin\sdkmanager.bat"
    if (Test-Path $sdkManager) {
        return $sdkManager
    }

    $repoCmdlineTools = Join-Path $repoRoot "cmdline-tools"
    if (-not (Test-Path $repoCmdlineTools)) {
        throw "Missing repo-local cmdline-tools at $repoCmdlineTools"
    }

    New-Item -ItemType Directory -Force -Path $cmdlineToolsRoot | Out-Null
    Copy-Item -Recurse -Force (Join-Path $repoCmdlineTools "*") $cmdlineToolsRoot

    if (-not (Test-Path $sdkManager)) {
        throw "Failed to stage sdkmanager.bat into $cmdlineToolsRoot"
    }

    return $sdkManager
}

function Get-InstalledLocalJdk {
    Get-ChildItem $localJdkRoot -Directory -Filter "jdk-*" -ErrorAction SilentlyContinue |
        Sort-Object Name -Descending |
        Select-Object -First 1
}

function Ensure-LocalJdk {
    $existingJdk = Get-InstalledLocalJdk
    if ($existingJdk) {
        return $existingJdk.FullName
    }

    New-Item -ItemType Directory -Force -Path $localJdkRoot | Out-Null

    $release = Invoke-RestMethod "https://api.adoptium.net/v3/assets/latest/21/hotspot?architecture=x64&heap_size=normal&image_type=jdk&jvm_impl=hotspot&os=windows&vendor=eclipse"
    $package = $release[0].binary.package

    if (-not $package.link -or -not $package.name) {
        throw "Unable to resolve a Temurin JDK 21 download link."
    }

    $zipPath = Join-Path $localJdkRoot $package.name
    if (-not (Test-Path $zipPath)) {
        Invoke-WebRequest -Uri $package.link -OutFile $zipPath
    }

    Expand-Archive -LiteralPath $zipPath -DestinationPath $localJdkRoot -Force
    Remove-Item -LiteralPath $zipPath -Force

    $installedJdk = Get-InstalledLocalJdk
    if (-not $installedJdk) {
        throw "Failed to extract a local JDK under $localJdkRoot"
    }

    return $installedJdk.FullName
}

function Install-AndroidPackages {
    param(
        [string]$SdkManagerPath,
        [string[]]$Packages
    )

    $sdkManagerArgs = @("--sdk_root=$androidSdkRoot") + $Packages
    1..20 | ForEach-Object { "y" } | & $SdkManagerPath @sdkManagerArgs
}

function Write-LocalProperties {
    param(
        [string]$FlutterSdkPath,
        [string]$SdkRootPath
    )

    $content = @(
        "flutter.sdk=$(Convert-ToPropertiesPath $FlutterSdkPath)"
        "sdk.dir=$(Convert-ToPropertiesPath $SdkRootPath)"
    )

    Set-Content -LiteralPath $localPropertiesPath -Value $content
}

$sdkManagerPath = Ensure-AndroidCmdlineTools
$jdkHome = Ensure-LocalJdk
$flutterSdkPath = Get-FlutterSdkPath

$env:JAVA_HOME = $jdkHome
$env:ANDROID_SDK_ROOT = $androidSdkRoot
$env:ANDROID_HOME = $androidSdkRoot
$env:PATH = "$jdkHome\bin;$androidSdkRoot\platform-tools;$env:PATH"

Install-AndroidPackages -SdkManagerPath $sdkManagerPath -Packages @(
    "platform-tools",
    "platforms;android-$AndroidApi",
    "build-tools;$BuildToolsVersion"
)

Write-LocalProperties -FlutterSdkPath $flutterSdkPath -SdkRootPath $androidSdkRoot

Write-Host "Local Android SDK ready: $androidSdkRoot"
Write-Host "Local JDK ready: $jdkHome"
Write-Host "Android local.properties updated: $localPropertiesPath"
