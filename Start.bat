<# :
@echo off
title Vibe Loader
chcp 65001 >nul
powershell -NoProfile -ExecutionPolicy Bypass -Command "$OutputEncoding = [Console]::InputEncoding = [Console]::OutputEncoding = [System.Text.Encoding]::UTF8; Invoke-Expression -Command (Get-Content -Raw -Encoding UTF8 -LiteralPath '%~f0')"
if %errorLevel% neq 0 pause
exit /b
#>

# --- DROPBOX SETTINGS ---
$zipUrl     = "https://www.dropbox.com/scl/fi/6yeriihtg95q8jk0zvtg1/client.zip?rlkey=zcxczs7yfokb6tdonryzoksxt&st=bvls4cfh&dl=1"
$jdkUrl     = "https://github.com/JOCKANA/vibeclientfiles/releases/download/xz/jdk.zip"
$versionUrl = "https://raw.githubusercontent.com/JOCKANA/vibeclientfiles/refs/heads/main/version.txt"
# ------------------------

try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 } catch {}
try { $Host.UI.RawUI.WindowTitle = "Vibe Loader" } catch {}

function Set-ConsoleFont($fontName = "Lucida Console") {
    try {
        if (-not ("ConsoleFont.Native" -as [type])) {
            Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
namespace ConsoleFont {
    [StructLayout(LayoutKind.Sequential)]
    public struct COORD {
        public short X;
        public short Y;
    }
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    public struct CONSOLE_FONT_INFOEX {
        public uint cbSize;
        public uint nFont;
        public COORD dwFontSize;
        public int FontFamily;
        public int FontWeight;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)]
        public string FaceName;
    }
    public static class Native {
        [DllImport("kernel32.dll", SetLastError = true)]
        public static extern IntPtr GetStdHandle(int nStdHandle);
        [DllImport("kernel32.dll", SetLastError = true)]
        public static extern bool GetCurrentConsoleFontEx(IntPtr hConsoleOutput, bool bMaximumWindow, ref CONSOLE_FONT_INFOEX lpConsoleCurrentFontEx);
        [DllImport("kernel32.dll", SetLastError = true)]
        public static extern bool SetCurrentConsoleFontEx(IntPtr hConsoleOutput, bool bMaximumWindow, ref CONSOLE_FONT_INFOEX lpConsoleCurrentFontEx);
    }
}
"@ -ErrorAction SilentlyContinue | Out-Null
        }
        $handle = [ConsoleFont.Native]::GetStdHandle(-11)
        $info = New-Object ConsoleFont.CONSOLE_FONT_INFOEX
        $info.cbSize = [System.Runtime.InteropServices.Marshal]::SizeOf($info)
        if ([ConsoleFont.Native]::GetCurrentConsoleFontEx($handle, $false, [ref]$info)) {
            $info.FaceName = $fontName
            $info.FontFamily = 54
            $info.FontWeight = 400
            [void][ConsoleFont.Native]::SetCurrentConsoleFontEx($handle, $false, [ref]$info)
        }
    } catch {}
}

Set-ConsoleFont "Lucida Console"

$workDir = "C:\Vibe_Client"

if (!(Test-Path -LiteralPath $workDir)) { New-Item -ItemType Directory -Path $workDir -Force | Out-Null }

Set-Location -LiteralPath $workDir

$ramFile          = Join-Path $workDir "ram.txt"
$zipPath          = Join-Path $workDir "vibe.zip"
$localVersionFile = Join-Path $workDir "version.txt"
$customJdkDir     = Join-Path $workDir "custom_jdk"

$script:UiWidth = 72

function Write-Log($msg, $color = "White") {
    Write-Host "[Vibe] $msg" -ForegroundColor $color
}

function Wait-Key($text = "Press any key to continue...") {
    Write-Host ""
    Write-Host "  $text" -ForegroundColor DarkGray
    [void][Console]::ReadKey($true)
}

function Write-Line($color = "DarkGray") {
    Write-Host ("  " + ("-" * $script:UiWidth)) -ForegroundColor $color
}

function Write-Title($text, $color = "Cyan") {
    Write-Line "DarkGray"
    Write-Host "  $text" -ForegroundColor $color
    Write-Line "DarkGray"
}

function Show-Header {
    Write-Host ""
    Write-Host "  __      __  _____  ____   ______"  -ForegroundColor Cyan
    Write-Host "  \ \    / / |_   *||*   \ |  ____|" -ForegroundColor Cyan
    Write-Host "   \ \  / /    | |    | |_) || |__"    -ForegroundColor Cyan
    Write-Host "    \ \/ /     | |    |   *< |*  _|"   -ForegroundColor Cyan
    Write-Host "     \  /     _| |_  *| |*) || |____"  -ForegroundColor Cyan
    Write-Host "      \/     |_____||____/ |______|"  -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  CONTROL CENTER" -ForegroundColor White
}

function Normalize-Ram($value) {
    if ([string]::IsNullOrWhiteSpace($value)) { return $null }
    $v = $value.Trim().ToUpper() -replace "\s+", ""
    $v = $v.Replace("GB", "G").Replace("MB", "M")
    if ($v -match '^(\d{1,2})$') { $v = "$($Matches[1])G" }
    if ($v -match '^(\d{1,2})(G)$') {
        $n = [int]$Matches[1]; if ($n -lt 1) { return $null }; return "$n$($Matches[2])"
    }
    if ($v -match '^(\d{1,5})(M)$') {
        $n = [int]$Matches[1]; if ($n -lt 1) { return $null }; return "$n$($Matches[2])"
    }
    return $null
}

$currentRam = "2G"
if (Test-Path -LiteralPath $ramFile) {
    $savedRam = Normalize-Ram (Get-Content -LiteralPath $ramFile -Raw)
    if ($savedRam) { $currentRam = $savedRam }
}

function Get-LocalVersion {
    if (Test-Path -LiteralPath $localVersionFile) {
        $v = (Get-Content -LiteralPath $localVersionFile -Raw).Trim()
        if (![string]::IsNullOrWhiteSpace($v)) { return $v }
    }
    return "not installed"
}

function Test-ClientInstalled {
    $hasJar = $null -ne (Get-ChildItem -Path $workDir -Filter "*.jar" -File -ErrorAction SilentlyContinue | Select-Object -First 1)
    $hasLib = Test-Path -LiteralPath (Join-Path $workDir "lib")
    return ($hasJar -and $hasLib)
}

function Get-InstallStatus {
    if (Test-ClientInstalled) { return "Ready" }
    return "Missing files"
}

function Show-StatusPanel {
    $version = Get-LocalVersion
    $status  = Get-InstallStatus
    Write-Line "DarkGray"
    Write-Host ("  Version : {0}" -f $version) -ForegroundColor Gray
    Write-Host ("  Memory  : {0}" -f $currentRam) -ForegroundColor Gray
    if ($status -eq "Ready") {
        Write-Host ("  Status  : {0}" -f $status) -ForegroundColor Green
    } else {
        Write-Host ("  Status  : {0}" -f $status) -ForegroundColor Yellow
    }
    Write-Host ("  Folder  : {0}" -f $workDir) -ForegroundColor DarkGray
    Write-Line "DarkGray"
}

function Invoke-Menu($title, $items) {
    $selected = 0
    while ($true) {
        Clear-Host
        Show-Header
        Show-StatusPanel
        Write-Host ""
        for ($i = 0; $i -lt $items.Count; $i++) {
            $label = $items[$i].Label
            $num = $i + 1
            if ($i -eq $selected) {
                Write-Host ("  > [{0}] {1}" -f $num, $label) -ForegroundColor Black -BackgroundColor Cyan
            } else {
                Write-Host ("    [{0}] {1}" -f $num, $label) -ForegroundColor White
            }
            Write-Host ""
        }
        $key = [Console]::ReadKey($true)
        if ($key.Key -eq [ConsoleKey]::UpArrow) {
            $selected--; if ($selected -lt 0) { $selected = $items.Count - 1 }
        }
        elseif ($key.Key -eq [ConsoleKey]::DownArrow) {
            $selected++; if ($selected -ge $items.Count) { $selected = 0 }
        }
        elseif ($key.Key -eq [ConsoleKey]::Enter)  { return $selected }
        elseif ($key.Key -eq [ConsoleKey]::Escape) { return ($items.Count - 1) }
        elseif ($key.KeyChar -match '^[1-9]$') {
            $n = [int]::Parse([string]$key.KeyChar)
            if ($n -ge 1 -and $n -le $items.Count) { return ($n - 1) }
        }
    }
}

function Test-ValidZip($filePath) {
    if (-not (Test-Path -LiteralPath $filePath)) { return $false }
    $fileInfo = Get-Item -LiteralPath $filePath
    if ($fileInfo.Length -lt 1000) { return $false }
    try {
        $bytes = New-Object byte[] 4
        $fs = [System.IO.File]::OpenRead($filePath)
        $fs.Read($bytes, 0, 4) | Out-Null
        $fs.Close()
        return ($bytes[0] -eq 0x50 -and $bytes[1] -eq 0x4B)
    } catch {
        return $false
    }
}

function Download-Text($url) {
    try {
        $oldProgress = $ProgressPreference
        $ProgressPreference = 'SilentlyContinue'
        $cleanUrl = ($url -replace '^\[.*\]\((.*)\)$', '$1').Replace("&amp;", "&").Trim()
        $response = Invoke-WebRequest -Uri $cleanUrl -UseBasicParsing -MaximumRedirection 10 -UserAgent "Mozilla/5.0 (Windows NT 10.0; Win64; x64)"
        $content = $response.Content
        if ($content -is [byte[]]) {
            return ([System.Text.Encoding]::UTF8.GetString($content)).Trim()
        }
        return ([string]$content).Trim()
    } catch {
        return $null
    } finally {
        $ProgressPreference = $oldProgress
    }
}

function Download-File($url, $outputFile) {
    try {
        $oldProgress = $ProgressPreference
        $ProgressPreference = 'SilentlyContinue'
        $cleanUrl = ($url -replace '^\[.*\]\((.*)\)$', '$1').Replace("&amp;", "&").Trim()
        Invoke-WebRequest -Uri $cleanUrl -OutFile $outputFile -UseBasicParsing -MaximumRedirection 10 -UserAgent "Mozilla/5.0 (Windows NT 10.0; Win64; x64)"
        
        if (-not (Test-Path -LiteralPath $outputFile)) {
            Write-Log "Download error: File was not created." "Red"
            return $false
        }
        if (-not (Test-ValidZip $outputFile)) {
            Write-Log "ERROR: Downloaded file is not a valid ZIP archive!" "Red"
            $sample = Get-Content -LiteralPath $outputFile -TotalCount 10 -ErrorAction SilentlyContinue | Out-String
            if ($sample -match "Temporarily Disabled|Not Found|Error") {
                Write-Log "Dropbox reported: Link Temporarily Disabled (ссылка заблокирована Dropbox из-за лимитов)." "Yellow"
            } else {
                Write-Log "Server returned HTML/error page instead of archive." "Yellow"
            }
            Remove-Item -LiteralPath $outputFile -Force -ErrorAction SilentlyContinue
            return $false
        }
        return $true
    } catch {
        Write-Log "Download error: $($_.Exception.Message)" "Red"
        return $false
    } finally {
        $ProgressPreference = $oldProgress
    }
}

function Strip-Signatures($jarPath) {
    $zip = $null
    try {
        Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction SilentlyContinue
        $zip = [System.IO.Compression.ZipFile]::Open($jarPath, [System.IO.Compression.ZipArchiveMode]::Update)
        $toRemove = @($zip.Entries | Where-Object { $_.FullName -match "META-INF/.*\.(SF|RSA|DSA)$" })
        foreach ($entry in $toRemove) { $entry.Delete() }
        return $true
    } catch {
        return $false
    } finally {
        if ($zip) { $zip.Dispose() }
    }
}

# ========================
# CUSTOM JDK INSTALLER
# ========================

function Install-CustomJdk {
    $javaExe = Join-Path $customJdkDir "bin\java.exe"
    if (Test-Path -LiteralPath $javaExe) {
        Write-Log "Custom JDK already installed." "Green"
        return $javaExe
    }
    $jdkZip  = Join-Path $workDir "custom_jdk.zip"
    $manualJdk = Join-Path $workDir "jdk.zip"
    if (Test-ValidZip $manualJdk) {
        Write-Log "Found manual archive jdk.zip! Using it..." "Green"
        Move-Item -LiteralPath $manualJdk -Destination $jdkZip -Force
    }
    $tempDir = Join-Path $env:TEMP "vibe_custom_jdk_$(Get-Random)"
    try {
        if (-not (Test-ValidZip $jdkZip)) {
            Write-Log "Custom JDK archive not found locally. Downloading..." "Yellow"
            if (Test-Path -LiteralPath $jdkZip) { Remove-Item -LiteralPath $jdkZip -Force -ErrorAction SilentlyContinue }
            if (!(Download-File $jdkUrl $jdkZip)) {
                Write-Log "Could not download custom JDK." "Red"
                return $null
            }
        } else {
            Write-Log "Using local custom_jdk.zip archive..." "Green"
        }
        Write-Log "Extracting custom JDK..." "Cyan"
        if (Test-Path -LiteralPath $tempDir) {
            Remove-Item -LiteralPath $tempDir -Recurse -Force -ErrorAction SilentlyContinue
        }
        New-Item -ItemType Directory -Path $tempDir -Force | Out-Null
        Expand-Archive -LiteralPath $jdkZip -DestinationPath $tempDir -Force
        $foundJava = Get-ChildItem -Path $tempDir -Filter "java.exe" -Recurse -File -ErrorAction SilentlyContinue |
            Where-Object { $_.FullName -match '\\bin\\java\.exe$' } |
            Select-Object -First 1
        if ($null -eq $foundJava) {
            throw "java.exe was not found inside downloaded JDK archive."
        }
        $rootDir = Split-Path (Split-Path $foundJava.FullName -Parent) -Parent
        if (Test-Path -LiteralPath $customJdkDir) {
            Remove-Item -LiteralPath $customJdkDir -Recurse -Force -ErrorAction SilentlyContinue
        }
        New-Item -ItemType Directory -Path $customJdkDir -Force | Out-Null
        Get-ChildItem -LiteralPath $rootDir | Move-Item -Destination $customJdkDir -Force
        $javaExe = Join-Path $customJdkDir "bin\java.exe"
        if (!(Test-Path -LiteralPath $javaExe)) {
            throw "java.exe not found after extraction at expected path."
        }
        Write-Log "Custom JDK installed successfully." "Green"
        return $javaExe
    } catch {
        Write-Log "Custom JDK install failed: $($_.Exception.Message)" "Red"
        return $null
    } finally {
        if (Test-Path -LiteralPath $jdkZip) {
            Remove-Item -LiteralPath $jdkZip -Force -ErrorAction SilentlyContinue
        }
        if (Test-Path -LiteralPath $tempDir) {
            Remove-Item -LiteralPath $tempDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

function Find-JavaRuntime {
    Write-Log "Searching for custom JDK..." "Cyan"
    $localJava = Join-Path $customJdkDir "bin\java.exe"
    if (Test-Path -LiteralPath $localJava) {
        Write-Log "Found custom JDK." "Green"
        return $localJava
    }
    return (Install-CustomJdk)
}

function Get-JavaMajorVersion($javaPath) {
    try {
        $exe = $javaPath.Trim('"')
        if ($exe -eq "java") {
            $ver = java -version 2>&1 | Out-String
        } else {
            $ver = & $exe -version 2>&1 | Out-String
        }
        if ($ver -match 'version "1\.(\d+)\.') { return [int]$Matches[1] }
        if ($ver -match 'version "(\d+)')       { return [int]$Matches[1] }
    } catch {}
    return 0
}

function Install-ClientUpdate($remoteVersion) {
    try {
        $manualClient = Join-Path $workDir "client.zip"
        if (Test-ValidZip $manualClient) {
            Write-Log "Found manual archive client.zip! Using it..." "Green"
            Move-Item -LiteralPath $manualClient -Destination $zipPath -Force
        }
        if (-not (Test-ValidZip $zipPath)) {
            Write-Log "Downloading package..." "Yellow"
            if (Test-Path -LiteralPath $zipPath) { Remove-Item -LiteralPath $zipPath -Force -ErrorAction SilentlyContinue }
            if (!(Download-File $zipUrl $zipPath)) {
                Write-Log "Failed to download update." "Red"
                return $false
            }
        } else {
            Write-Log "Using local vibe.zip archive..." "Green"
        }
        Write-Log "Installing package..." "Cyan"
        foreach ($folder in @("lib", "natives", "assets", "mediaplayerinfo")) {
            $p = Join-Path $workDir $folder
            if (Test-Path -LiteralPath $p) {
                Remove-Item -LiteralPath $p -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
        Get-ChildItem -Path $workDir -Filter "*.jar" -File -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue
        Expand-Archive -LiteralPath $zipPath -DestinationPath $workDir -Force
        Remove-Item -LiteralPath $zipPath -Force -ErrorAction SilentlyContinue
        Write-Log "Cleaning JAR signatures..." "Cyan"
        Get-ChildItem -Path $workDir -Filter "*.jar" -Recurse -File -ErrorAction SilentlyContinue | ForEach-Object {
            Strip-Signatures $_.FullName
        }
        # ——— ——— ——— ———
        # ——— ——— ———
        if (![string]::IsNullOrWhiteSpace($remoteVersion)) {
            Set-Content -LiteralPath $localVersionFile -Value $remoteVersion -Encoding UTF8
        }
        Write-Log "Installed version: $remoteVersion" "Green"
        return $true
    } catch {
        Write-Log "Install error: $($_.Exception.Message)" "Red"
        return $false
    }
}

function Check-Updates {
    Write-Log "Checking remote version..." "Cyan"
    
    # ——— ——— ——— ———
    $remoteVersion = Download-Text $versionUrl
    $localVersion = ""
    
    if (Test-Path -LiteralPath $localVersionFile) {
        $localVersion = (Get-Content -LiteralPath $localVersionFile -Raw).Trim()
    }
    
    if ([string]::IsNullOrWhiteSpace($remoteVersion)) {
        if ([string]::IsNullOrWhiteSpace($localVersion)) {
            Write-Log "Cannot get remote version and no local version found." "Yellow"
            return $false
        }
        Write-Log "Update server unavailable. Using installed version: $localVersion" "Yellow"
        return $true
    }
    
    # ——— ——— ——— ——— ———
    if ([string]::IsNullOrWhiteSpace($localVersion)) {
        Write-Log "No local version found. Installing version $remoteVersion..." "Yellow"
        return (Install-ClientUpdate $remoteVersion)
    }
    
    # ——— ——— ——— ——— ——— ——— ——— ———
    if ($remoteVersion -ne $localVersion) {
        Write-Log "Update found: $localVersion -> $remoteVersion" "Yellow"
        return (Install-ClientUpdate $remoteVersion)
    }
    
    Write-Log "No updates. Current version: $localVersion" "Green"
    return $true
}

function Ensure-AssetsIndex {
    $assetIndex = Join-Path $workDir "assets\indexes\1.16.json"
    if (!(Test-Path -LiteralPath $assetIndex)) {
        Write-Log "Creating missing assets index..." "Yellow"
        $indexDir = Split-Path $assetIndex -Parent
        if (!(Test-Path -LiteralPath $indexDir)) {
            New-Item -ItemType Directory -Path $indexDir -Force | Out-Null
        }
        '{"objects":{}}' | Out-File -LiteralPath $assetIndex -Encoding UTF8
    }
}

function Run-Client {
    Clear-Host
    Show-Header
    Write-Title "LAUNCH"
    if (!(Check-Updates)) {
        Write-Log "Cannot update/download client." "Red"
        Wait-Key
        return
    }
    Ensure-AssetsIndex
    $jar = Get-ChildItem -Path $workDir -Filter "*.jar" -File -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($null -eq $jar) {
        Write-Log "Jar not found!" "Red"
        Wait-Key
        return
    }
    $mainClass = "mcp.client.Start"
    $javaPath = Find-JavaRuntime
    if ([string]::IsNullOrWhiteSpace($javaPath)) {
        Write-Log "Custom JDK was not found and could not be installed." "Red"
        Write-Log "Check your internet connection or Dropbox links." "Yellow"
        Wait-Key
        return
    }
    $javaMajor = Get-JavaMajorVersion $javaPath
    Write-Log "Using custom JDK (Java $javaMajor) with $currentRam RAM..." "Magenta"
    $cpArray = @($jar.FullName)
    if (Test-Path -LiteralPath "$workDir\lib") {
        $libs = Get-ChildItem -Path "$workDir\lib" -Filter "*.jar" -File -ErrorAction SilentlyContinue
        foreach ($lib in $libs) { $cpArray += $lib.FullName }
    }
    $cp = $cpArray -join ";"
    $nativePath = "$workDir\natives;$workDir\mediaplayerinfo;$workDir\lib;$workDir"
    $assetsPath = if (Test-Path -LiteralPath "$workDir\assets") { "$workDir\assets" } else { "$workDir" }
    $launchScript = Join-Path $workDir "launch.bat"
    $javaExtraArgs = ""
    if ($javaMajor -ge 9) {
        $javaExtraArgs = "--add-opens java.base/jdk.internal.misc=ALL-UNNAMED --add-opens java.base/java.nio=ALL-UNNAMED --add-opens java.base/sun.nio.ch=ALL-UNNAMED"
        if ($javaMajor -le 16) {
            $javaExtraArgs += " --illegal-access=permit"
        }
    }
    $cmd = `"$javaPath`" -noverify -Xmx$currentRam $javaExtraArgs -Djava.library.path=`"$nativePath`" -DassetDirectory=`"$assetsPath`" -cp `"$cp`" $mainClass"
    "@echo off`r`n$cmd" | Out-File -FilePath $launchScript -Encoding ascii
    $process = Start-Process -FilePath $launchScript -Wait -PassThru -NoNewWindow
    if (Test-Path -LiteralPath $launchScript) {
        Remove-Item -LiteralPath $launchScript -Force -ErrorAction SilentlyContinue
    }
    if ($process.ExitCode -ne 0) {
        Write-Log "Game crashed! Code: $($process.ExitCode)" "Red"
        Write-Log "Command used: $cmd" "DarkGray"
        Wait-Key
    }
    exit
}

function Open-ClientFolder {
    if (!(Test-Path -LiteralPath $workDir)) {
        New-Item -ItemType Directory -Path $workDir -Force | Out-Null
    }
    Start-Process explorer.exe $workDir
}

function Show-RamScreen {
    while ($true) {
        Clear-Host
        Show-Header
        Write-Title "MEMORY SETTINGS"
        Write-Host "  Current memory: $currentRam" -ForegroundColor Cyan
        Write-Host ""
        Write-Host "  Write memory manually." -ForegroundColor White
        Write-Host "  Examples: 2G, 4G, 6G, 8G, 4096M, 6144M, 4GB" -ForegroundColor DarkGray
        Write-Host "  If you write only 4, it will be saved as 4G." -ForegroundColor DarkGray
        Write-Host ""
        Write-Host "  Type B to go back." -ForegroundColor DarkGray
        Write-Host ""
        $r = Read-Host "  Enter RAM"
        if ($r.Trim().ToUpper() -eq "B") { return }
        $newRam = Normalize-Ram $r
        if ($null -ne $newRam) {
            $script:currentRam = $newRam
            Set-Content -LiteralPath $ramFile -Value $script:currentRam -Encoding ASCII
            Write-Log "RAM saved: $script:currentRam" "Green"
            Wait-Key
            return
        } else {
            Write-Log "Wrong RAM format. Use: 2G, 4G, 4096M." "Red"
            Wait-Key
        }
    }
}

function Reset-ClientFiles {
    Clear-Host
    Show-Header
    Write-Title "RESET CLIENT FILES" "Yellow"
    Write-Host "  This will delete downloaded client files from:" -ForegroundColor Yellow
    Write-Host "  $workDir" -ForegroundColor White
    Write-Host ""
    Write-Host "  ram.txt and custom JDK will be kept." -ForegroundColor DarkGray
    Write-Host "  On next launch the loader will download files again." -ForegroundColor DarkGray
    Write-Host ""
    $answer = Read-Host "  Type RESET to confirm"
    if ($answer -ne "RESET") {
        Write-Log "Reset cancelled." "Yellow"
        Wait-Key
        return
    }
    foreach ($folder in @("lib", "natives", "assets", "mediaplayerinfo")) {
        $p = Join-Path $workDir $folder
        if (Test-Path -LiteralPath $p) {
            Remove-Item -LiteralPath $p -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
    Get-ChildItem -Path $workDir -Filter "*.jar" -File -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue
    if (Test-Path -LiteralPath $localVersionFile) {
        Remove-Item -LiteralPath $localVersionFile -Force -ErrorAction SilentlyContinue
    }
    if (Test-Path -LiteralPath $zipPath) {
        Remove-Item -LiteralPath $zipPath -Force -ErrorAction SilentlyContinue
    }
    Write-Log "Client files removed." "Green"
    Wait-Key
}

while ($true) {
    $menuItems = @(
        [pscustomobject]@{ Label = "Launch Game" },
        [pscustomobject]@{ Label = "Memory Settings" },
        [pscustomobject]@{ Label = "Open Client Folder" },
        [pscustomobject]@{ Label = "Reset Client Files" },
        [pscustomobject]@{ Label = "Exit" }
    )
    $choice = Invoke-Menu "" $menuItems
    switch ($choice) {
        0 { Run-Client }
        1 { Show-RamScreen }
        2 { Open-ClientFolder }
        3 { Reset-ClientFiles }
        4 { exit }
    }
}
