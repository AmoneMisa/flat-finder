[CmdletBinding()]
param(
    [switch]$Universal,
    [string]$FirebaseApiKey = "",
    [string]$FirebaseAppId = "",
    [string]$FirebaseMessagingSenderId = "",
    [string]$FirebaseProjectId = "",
    [string]$ApiBase = ""
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repoRoot = $PSScriptRoot
$appDir = Join-Path $repoRoot "app"
$pubspecPath = Join-Path $appDir "pubspec.yaml"
$flutterOutputDir = Join-Path $appDir "build\app\outputs\flutter-apk"
$releaseDir = Join-Path $repoRoot "release"

if ([string]::IsNullOrWhiteSpace($FirebaseApiKey)) {
    if (-not [string]::IsNullOrWhiteSpace($env:FIREBASE_API_KEY)) {
        $FirebaseApiKey = $env:FIREBASE_API_KEY
    } else {
        $FirebaseApiKey = "AIzaSyCUc7PVkioirWhw6jPMt1ZVaWxOijsWlnk"
    }
}

if ([string]::IsNullOrWhiteSpace($FirebaseAppId)) {
    if (-not [string]::IsNullOrWhiteSpace($env:FIREBASE_APP_ID)) {
        $FirebaseAppId = $env:FIREBASE_APP_ID
    } else {
        $FirebaseAppId = "1:209896392944:android:b142e13aef2b35ef111a35"
    }
}

if ([string]::IsNullOrWhiteSpace($FirebaseMessagingSenderId)) {
    if (-not [string]::IsNullOrWhiteSpace($env:FIREBASE_MESSAGING_SENDER_ID)) {
        $FirebaseMessagingSenderId = $env:FIREBASE_MESSAGING_SENDER_ID
    } else {
        $FirebaseMessagingSenderId = "209896392944"
    }
}

if ([string]::IsNullOrWhiteSpace($FirebaseProjectId)) {
    if (-not [string]::IsNullOrWhiteSpace($env:FIREBASE_PROJECT_ID)) {
        $FirebaseProjectId = $env:FIREBASE_PROJECT_ID
    } else {
        $FirebaseProjectId = "flat-finder-whiteslove"
    }
}

if ([string]::IsNullOrWhiteSpace($ApiBase) -and -not [string]::IsNullOrWhiteSpace($env:API_BASE)) {
    $ApiBase = $env:API_BASE
}

if (-not (Test-Path $pubspecPath)) {
    throw "pubspec.yaml was not found at $pubspecPath"
}

$pubspec = Get-Content $pubspecPath -Raw
$versionMatch = [regex]::Match($pubspec, '(?m)^version:\s*([^\s]+)\s*$')
if (-not $versionMatch.Success) {
    throw "Could not read the Flutter version from app/pubspec.yaml"
}
$version = $versionMatch.Groups[1].Value

New-Item -ItemType Directory -Path $releaseDir -Force | Out-Null
Get-ChildItem -Path $releaseDir -Filter "FlatFinder-v*.apk" -ErrorAction SilentlyContinue | Remove-Item -Force

$flutterArgs = @("build", "apk", "--release")
if (-not $Universal) {
    $flutterArgs += "--split-per-abi"
}
$flutterArgs += "--dart-define=FIREBASE_API_KEY=$FirebaseApiKey"
$flutterArgs += "--dart-define=FIREBASE_APP_ID=$FirebaseAppId"
$flutterArgs += "--dart-define=FIREBASE_MESSAGING_SENDER_ID=$FirebaseMessagingSenderId"
$flutterArgs += "--dart-define=FIREBASE_PROJECT_ID=$FirebaseProjectId"
if (-not [string]::IsNullOrWhiteSpace($ApiBase)) {
    $flutterArgs += "--dart-define=API_BASE=$ApiBase"
}

Push-Location $appDir
try {
    Write-Host "Fetching Flutter dependencies..." -ForegroundColor Cyan
    & flutter pub get
    if ($LASTEXITCODE -ne 0) {
        throw "flutter pub get failed with exit code $LASTEXITCODE"
    }

    Write-Host "Building Flat Finder v$version..." -ForegroundColor Cyan
    & flutter @flutterArgs
    if ($LASTEXITCODE -ne 0) {
        throw "flutter build apk failed with exit code $LASTEXITCODE"
    }
} finally {
    Pop-Location
}

if ($Universal) {
    $artifacts = @(
        @{
            Source = "app-release.apk"
            Target = "FlatFinder-v$version-universal.apk"
        }
    )
} else {
    $artifacts = @(
        @{
            Source = "app-arm64-v8a-release.apk"
            Target = "FlatFinder-v$version-arm64-v8a.apk"
        },
        @{
            Source = "app-armeabi-v7a-release.apk"
            Target = "FlatFinder-v$version-armeabi-v7a.apk"
        },
        @{
            Source = "app-x86_64-release.apk"
            Target = "FlatFinder-v$version-x86_64.apk"
        }
    )
}

$created = @()
foreach ($artifact in $artifacts) {
    $source = Join-Path $flutterOutputDir $artifact.Source
    if (-not (Test-Path $source)) {
        throw "Expected APK was not produced: $source"
    }
    $target = Join-Path $releaseDir $artifact.Target
    Copy-Item $source $target -Force
    $created += Get-Item $target
}

Write-Host "" 
Write-Host "Release APKs:" -ForegroundColor Green
foreach ($file in $created) {
    $sizeMb = [math]::Round($file.Length / 1MB, 1)
    Write-Host "  $($file.FullName) ($sizeMb MB)"
}
