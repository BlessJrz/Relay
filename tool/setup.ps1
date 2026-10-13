# Relay - one-step build for Windows.
# Installs what's missing (Flutter, Java 17, Android SDK), generates the Android
# project, applies Relay's Android settings and builds the APK.
# Everything is logged to build-log.txt next to this project.
#
# Run from the project folder:   powershell -ExecutionPolicy Bypass -File tool\setup.ps1

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$Root = Split-Path -Parent $PSScriptRoot
Set-Location $Root
$Log = Join-Path $Root 'build-log.txt'
Set-Content -Path $Log -Value "Relay build log  $(Get-Date)"

function Say($m) { Write-Host "==> $m" -ForegroundColor Cyan; Add-Content -Path $Log -Value "==> $m" }
function Run($exe, [string[]]$a) {
  # Run through cmd.exe so the tool's stderr (normal progress output for Flutter
  # and Gradle) is merged before PowerShell sees it. Only the exit code matters.
  $parts = @('"' + $exe + '"') + ($a | ForEach-Object { if ($_ -match '[\s&|<>^;,=]') { '"' + $_ + '"' } else { $_ } })
  $line = $parts -join ' '
  Add-Content -Path $Log -Value "`n> $line"
  cmd /s /c "`"$line 2>&1`"" | ForEach-Object { Write-Host $_; Add-Content -Path $Log -Value $_ }
  if ($LASTEXITCODE -ne 0) { throw "Step failed (exit $LASTEXITCODE): $line  - see build-log.txt" }
}
function Refresh-Path { $env:Path = [Environment]::GetEnvironmentVariable('Path','Machine') + ';' + [Environment]::GetEnvironmentVariable('Path','User') }

try {
  $Tools = Join-Path $env:USERPROFILE 'relay-tools'
  New-Item -ItemType Directory -Force -Path $Tools | Out-Null

  # ---------------------------------------------------------------- Java 17
  Say 'Checking Java'
  $java = $null
  foreach ($c in @("$env:JAVA_HOME", 'C:\Program Files\Android\Android Studio\jbr', "$env:LOCALAPPDATA\Programs\Android Studio\jbr")) {
    if ($c -and (Test-Path "$c\bin\java.exe")) { $java = $c; break }
  }
  if (-not $java) {
    $jdk = Get-ChildItem 'C:\Program Files\Microsoft' -Directory -Filter 'jdk-17*' -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($jdk) { $java = $jdk.FullName }
  }
  if (-not $java) {
    Say 'Installing Microsoft OpenJDK 17 (winget)'
    winget install --id Microsoft.OpenJDK.17 -e --accept-source-agreements --accept-package-agreements --silent | Out-Host
    $jdk = Get-ChildItem 'C:\Program Files\Microsoft' -Directory -Filter 'jdk-17*' -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $jdk) { throw 'Java 17 install failed. Install Android Studio, then run this again.' }
    $java = $jdk.FullName
  }
  $env:JAVA_HOME = $java
  $env:Path = "$java\bin;$env:Path"
  Say "Java: $java"

  # ---------------------------------------------------------------- Android SDK
  Say 'Checking Android SDK'
  $sdk = $env:ANDROID_HOME
  if (-not $sdk -or -not (Test-Path $sdk)) { $sdk = "$env:LOCALAPPDATA\Android\Sdk" }
  $sdkmanager = Get-ChildItem "$sdk\cmdline-tools" -Recurse -Filter 'sdkmanager.bat' -ErrorAction SilentlyContinue | Select-Object -First 1
  if (-not $sdkmanager) {
    Say 'Installing Android command-line tools'
    New-Item -ItemType Directory -Force -Path "$sdk\cmdline-tools" | Out-Null
    $zip = Join-Path $Tools 'cmdline-tools.zip'
    Invoke-WebRequest 'https://dl.google.com/android/repository/commandlinetools-win-11076708_latest.zip' -OutFile $zip
    $tmp = Join-Path $Tools 'clt'
    if (Test-Path $tmp) { Remove-Item $tmp -Recurse -Force }
    Expand-Archive $zip -DestinationPath $tmp
    if (Test-Path "$sdk\cmdline-tools\latest") { Remove-Item "$sdk\cmdline-tools\latest" -Recurse -Force }
    Move-Item "$tmp\cmdline-tools" "$sdk\cmdline-tools\latest"
    $sdkmanager = Get-Item "$sdk\cmdline-tools\latest\bin\sdkmanager.bat"
  }
  $env:ANDROID_HOME = $sdk
  $env:ANDROID_SDK_ROOT = $sdk
  [Environment]::SetEnvironmentVariable('ANDROID_HOME', $sdk, 'User')
  Say 'Accepting Android licenses and installing SDK packages (first time takes a few minutes)'
  $yes = ('y' + "`n") * 30
  $ErrorActionPreference = 'Continue'
  $yes | & $sdkmanager.FullName --licenses 2>&1 | ForEach-Object { Add-Content -Path $Log -Value "$_" }
  $ErrorActionPreference = 'Stop'
  Run $sdkmanager.FullName @('platform-tools', 'platforms;android-35', 'build-tools;35.0.0')

  # ---------------------------------------------------------------- Flutter
  Say 'Checking Flutter'
  $flutter = (Get-Command flutter -ErrorAction SilentlyContinue).Source
  if (-not $flutter) {
    foreach ($c in @("$env:USERPROFILE\flutter\bin\flutter.bat", 'C:\src\flutter\bin\flutter.bat', "$env:USERPROFILE\dev\flutter\bin\flutter.bat", "$Tools\flutter\bin\flutter.bat")) {
      if (Test-Path $c) { $flutter = $c; break }
    }
  }
  if (-not $flutter) {
    Say 'Downloading Flutter (stable) - about 1 GB'
    $rel = Invoke-RestMethod 'https://storage.googleapis.com/flutter_infra_release/releases/releases_windows.json'
    $hash = $rel.current_release.stable
    $item = $rel.releases | Where-Object { $_.hash -eq $hash } | Select-Object -First 1
    $zip = Join-Path $Tools 'flutter.zip'
    Invoke-WebRequest ($rel.base_url + '/' + $item.archive) -OutFile $zip
    Say 'Unpacking Flutter'
    Expand-Archive $zip -DestinationPath $Tools -Force
    Remove-Item $zip
    $flutter = "$Tools\flutter\bin\flutter.bat"
    $userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
    if ($userPath -notlike "*$Tools\flutter\bin*") { [Environment]::SetEnvironmentVariable('Path', "$userPath;$Tools\flutter\bin", 'User') }
  }
  Say "Flutter: $flutter"
  Run $flutter @('config', '--android-sdk', $sdk, '--no-analytics')
  Run $flutter @('--version')

  # ---------------------------------------------------------------- Android project
  if (-not (Test-Path (Join-Path $Root 'android'))) {
    Say 'Generating Android project'
    Run $flutter @('create', '--platforms=android', '--org', 'com.bluebubbles', '--project-name', 'relay', '.')
    if (Test-Path (Join-Path $Root 'test\widget_test.dart')) { Remove-Item (Join-Path $Root 'test\widget_test.dart') }
  }

  Say 'Applying Relay Android settings'
  # App icon (adaptive, edge to edge, with a themed-icon layer), notification icon, splash colour.
  Copy-Item -Path (Join-Path $Root 'tool\android_res\*') -Destination (Join-Path $Root 'android\app\src\main\res') -Recurse -Force
  $app = Join-Path $Root 'android\app'
  $gradle = @("$app\build.gradle.kts", "$app\build.gradle") | Where-Object { Test-Path $_ } | Select-Object -First 1
  $g = Get-Content $gradle -Raw
  $kts = $gradle.EndsWith('.kts')
  # Package name must match the Android app registered in the Firebase project
  # the Mac's BlueBubbles Server created, or push notifications won't work.
  $g = $g -replace 'applicationId\s*=?\s*"[^"]+"', ($(if ($kts) { 'applicationId = "com.bluebubbles.messaging"' } else { 'applicationId "com.bluebubbles.messaging"' }))
  $g = $g -replace 'minSdk\s*=?\s*[\w\.]+', ($(if ($kts) { 'minSdk = 23' } else { 'minSdk 23' }))
  if ($g -notmatch 'CoreLibraryDesugaring') {
    if ($kts) {
      $g = $g -replace '(compileOptions\s*\{)', "`$1`n        isCoreLibraryDesugaringEnabled = true"
      $g += "`ndependencies {`n    coreLibraryDesugaring(""com.android.tools:desugar_jdk_libs:2.1.4"")`n}`n"
    } else {
      $g = $g -replace '(compileOptions\s*\{)', "`$1`n        coreLibraryDesugaringEnabled true"
      $g += "`ndependencies {`n    coreLibraryDesugaring 'com.android.tools:desugar_jdk_libs:2.1.4'`n}`n"
    }
  }
  Set-Content $gradle $g -Encoding utf8

  $manifest = "$app\src\main\AndroidManifest.xml"
  $m = Get-Content $manifest -Raw
  $perms = @('android.permission.INTERNET', 'android.permission.CAMERA', 'android.permission.POST_NOTIFICATIONS', 'android.permission.VIBRATE', 'android.permission.RECEIVE_BOOT_COMPLETED')
  foreach ($p in $perms) {
    if ($m -notmatch [regex]::Escape($p)) { $m = $m -replace '(<manifest[^>]*>)', "`$1`n    <uses-permission android:name=""$p"" />" }
  }
  $m = $m -replace 'android:label="[^"]*"', 'android:label="Relay"'
  if ($m -notmatch 'enableOnBackInvokedCallback') { $m = $m -replace '<application', '<application android:enableOnBackInvokedCallback="true"' }
  Set-Content $manifest $m -Encoding utf8

  # ---------------------------------------------------------------- build
  Say 'Getting packages'
  Run $flutter @('pub', 'get')
  Say 'Checking code'
  cmd /s /c "`"`"$flutter`" analyze --no-fatal-infos --no-fatal-warnings 2>&1`"" | ForEach-Object { Write-Host $_; Add-Content -Path $Log -Value $_ }
  Say 'Building the app (first build takes 5-10 minutes)'
  Run $flutter @('build', 'apk', '--release')
  $apk = Join-Path $Root 'build\app\outputs\flutter-apk\app-release.apk'
  Copy-Item $apk (Join-Path $Root 'Relay.apk') -Force
  Say "Done: $(Join-Path $Root 'Relay.apk')"

  # Install straight to the phone if it's plugged in with USB debugging on.
  $adb = Join-Path $sdk 'platform-tools\adb.exe'
  $devices = (& $adb devices) | Select-String "`tdevice$"
  if ($devices) {
    Say 'Phone detected - installing'
    Run $adb @('install', '-r', (Join-Path $Root 'Relay.apk'))
  } else {
    Say 'No phone connected over USB. Copy Relay.apk to your phone to install it (see README).'
  }
  Add-Content -Path $Log -Value 'BUILD-OK'
}
catch {
  Write-Host "`nBuild stopped: $_" -ForegroundColor Red
  Add-Content -Path $Log -Value "BUILD-FAILED: $_"
  exit 1
}
