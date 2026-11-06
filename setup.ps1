<#
.SYNOPSIS
    Installs winland: a Hyprland-style desktop for Windows
    (GlazeWM + Zebar bar + AutoHotkey helpers + Flow Launcher).

.DESCRIPTION
    1. Installs GlazeWM, Zebar, AutoHotkey v2 and Flow Launcher with winget.
    2. Backs up existing configs (*.bak-<timestamp>) and installs the ones in .\config.
    3. Configures Flow Launcher (Catppuccin Mocha theme, opens on the focused monitor).
    4. Turns on taskbar auto-hide (the native taskbar is hidden by the AHK helper).
    5. Sets the wallpaper to "Fill" so screens with other aspect ratios have no black bars.
    6. Adds GlazeWM and the AHK helpers to the Startup folder and (re)starts everything.

.PARAMETER SkipInstall
    Do not install packages with winget (they must already be installed).

.PARAMETER SkipWallpaper
    Keep the current wallpaper fit mode.

.PARAMETER NoStart
    Install files only; do not (re)start GlazeWM, Zebar and the AHK helpers.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\setup.ps1
#>
[CmdletBinding()]
param(
    [switch]$SkipInstall,
    [switch]$SkipWallpaper,
    [switch]$NoStart
)

$ErrorActionPreference = 'Stop'

$Repo = $PSScriptRoot
$Glzr = Join-Path $HOME '.glzr'
$AhkDir = Join-Path $Glzr 'winland'
$StartupDir = [Environment]::GetFolderPath('Startup')
$Stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$Utf8NoBom = New-Object System.Text.UTF8Encoding($false)

$Packages = @(
    @{ Id = 'glzr-io.glazewm'; Name = 'GlazeWM' },
    @{ Id = 'glzr-io.zebar'; Name = 'Zebar' },
    @{ Id = 'AutoHotkey.AutoHotkey'; Name = 'AutoHotkey v2' },
    @{ Id = 'Flow-Launcher.Flow-Launcher'; Name = 'Flow Launcher' }
)

$FlowSettings = [ordered]@{
    Theme              = 'Catppuccin Mocha'
    ColorScheme        = 'Dark'
    SearchWindowScreen = 'Focus'
    QueryBoxFont       = 'Segoe UI'
    ResultFont         = 'Segoe UI'
    ResultSubFont      = 'Segoe UI'
    ShowHomePage       = $false
    UseClock           = $false
    BackdropType       = 0
    HideOnStartup      = $true
}

# ---------------------------------------------------------------- helpers

function Write-Step([string]$Message) {
    Write-Host "==> $Message" -ForegroundColor Cyan
}

function Write-Detail([string]$Message) {
    Write-Host "    $Message"
}

function Find-FirstPath([string[]]$Candidates, [string]$What) {
    foreach ($path in $Candidates) {
        if ($path -and (Test-Path $path)) { return $path }
    }
    throw "$What not found. Looked in: $($Candidates -join '; ')"
}

# GlazeWM's shell-exec splits on spaces, so use the 8.3 short path when needed.
function Get-SpacelessPath([string]$Path) {
    if ($Path -notmatch ' ') { return $Path }
    $short = (New-Object -ComObject Scripting.FileSystemObject).GetFile($Path).ShortPath
    if ($short -match ' ') { throw "Cannot get a path without spaces for $Path" }
    return $short
}

# Backups go to ~/.glzr/backups/<timestamp>/<name>, outside the folders the apps
# scan (a copy of the bar inside ~/.glzr/zebar would load as a second pack).
function Backup-Item([string]$Path, [string]$Name) {
    if (Test-Path $Path) {
        $dir = Join-Path $Glzr "backups\$Stamp"
        New-Item -ItemType Directory -Force $dir | Out-Null
        $backup = Join-Path $dir $Name
        Copy-Item $Path $backup -Recurse -Force
        Write-Detail "backed up $Path -> $backup"
    }
}

function Write-TextFile([string]$Path, [string]$Content) {
    New-Item -ItemType Directory -Force (Split-Path $Path) | Out-Null
    [IO.File]::WriteAllText($Path, $Content, $Utf8NoBom)
}

function Update-SessionPath {
    $machine = [Environment]::GetEnvironmentVariable('Path', 'Machine')
    $user = [Environment]::GetEnvironmentVariable('Path', 'User')
    $env:Path = "$machine;$user"
}

function New-StartupShortcut([string]$Name, [string]$Target, [string]$Arguments, [string]$WorkDir) {
    $shell = New-Object -ComObject WScript.Shell
    $link = $shell.CreateShortcut((Join-Path $StartupDir "$Name.lnk"))
    $link.TargetPath = $Target
    $link.Arguments = $Arguments
    if ($WorkDir) { $link.WorkingDirectory = $WorkDir }
    $link.Save()
    Write-Detail "startup shortcut: $Name"
}

# Asks AutoHotkey scripts under ~/.glzr to exit cleanly (so the taskbar helper
# can restore the native taskbar), then kills any that are left.
function Stop-WinlandAhk {
    $procs = @(Get-CimInstance Win32_Process -Filter "Name LIKE 'AutoHotkey%'" |
        Where-Object { $_.CommandLine -like '*\.glzr\*' })
    if (-not $procs) { return }
    Add-Type -Namespace Winland -Name Win32 -MemberDefinition @'
[DllImport("user32.dll")] public static extern bool PostMessage(IntPtr h, uint m, IntPtr w, IntPtr l);
[DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern IntPtr FindWindowEx(IntPtr p, IntPtr a, string c, string t);
[DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint p);
'@ -ErrorAction SilentlyContinue
    $hwnd = [IntPtr]::Zero
    while (($hwnd = [Winland.Win32]::FindWindowEx([IntPtr]::Zero, $hwnd, 'AutoHotkey', $null)) -ne [IntPtr]::Zero) {
        $procId = [uint32]0
        [Winland.Win32]::GetWindowThreadProcessId($hwnd, [ref]$procId) | Out-Null
        if ($procs.ProcessId -contains $procId) {
            [Winland.Win32]::PostMessage($hwnd, 0x111, [IntPtr]65307, [IntPtr]::Zero) | Out-Null # ID_FILE_EXIT
        }
    }
    Start-Sleep -Seconds 1
    foreach ($p in $procs) { Stop-Process -Id $p.ProcessId -Force -ErrorAction SilentlyContinue }
}

# ---------------------------------------------------------------- steps

function Install-Packages {
    Write-Step 'Installing packages with winget'
    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
        throw 'winget not found. Install "App Installer" from the Microsoft Store, then run setup again.'
    }
    foreach ($pkg in $Packages) {
        $listed = winget list --id $pkg.Id -e --accept-source-agreements 2>$null | Select-String -SimpleMatch $pkg.Id
        if ($listed) {
            Write-Detail "$($pkg.Name) already installed"
            continue
        }
        Write-Detail "installing $($pkg.Name)"
        winget install --id $pkg.Id -e --silent --accept-package-agreements --accept-source-agreements
        if ($LASTEXITCODE -ne 0) { throw "winget could not install $($pkg.Id) (exit code $LASTEXITCODE)" }
    }
    Update-SessionPath
}

function Resolve-Executables {
    $script:GlazeExe = Find-FirstPath @(
        "$env:ProgramFiles\glzr.io\GlazeWM\glazewm.exe",
        "$env:LOCALAPPDATA\Programs\glzr.io\GlazeWM\glazewm.exe"
    ) 'GlazeWM'
    $script:GlazeCli = Join-Path (Split-Path $GlazeExe) 'cli\glazewm.exe'
    $script:ZebarExe = Find-FirstPath @(
        "$env:ProgramFiles\glzr.io\Zebar\zebar.exe",
        "$env:LOCALAPPDATA\Programs\glzr.io\Zebar\zebar.exe"
    ) 'Zebar'
    $script:AhkExe = Find-FirstPath @(
        "$env:LOCALAPPDATA\Programs\AutoHotkey\v2\AutoHotkey64.exe",
        "$env:ProgramFiles\AutoHotkey\v2\AutoHotkey64.exe"
    ) 'AutoHotkey v2'
    $script:FlowExe = Find-FirstPath @("$env:LOCALAPPDATA\FlowLauncher\Flow.Launcher.exe") 'Flow Launcher'
}

function Install-GlazeWMConfig {
    Write-Step 'Installing GlazeWM config'
    $target = Join-Path $Glzr 'glazewm\config.yaml'
    Backup-Item $target 'glazewm-config.yaml'
    $content = Get-Content (Join-Path $Repo 'config\glazewm\config.yaml') -Raw -Encoding UTF8
    $content = $content.Replace('{{FLOW_LAUNCHER}}', (Get-SpacelessPath $FlowExe))
    Write-TextFile $target $content
}

function Install-ZebarConfig {
    Write-Step 'Installing Zebar bar (hyprbar)'
    $packDir = Join-Path $Glzr 'zebar\hyprbar'
    $settings = Join-Path $Glzr 'zebar\settings.json'
    Backup-Item $packDir 'zebar-hyprbar'
    Backup-Item $settings 'zebar-settings.json'
    if (Test-Path $packDir) { Remove-Item $packDir -Recurse -Force }
    New-Item -ItemType Directory -Force $packDir | Out-Null
    Copy-Item (Join-Path $Repo 'config\zebar\hyprbar\*') $packDir -Recurse -Force
    Copy-Item (Join-Path $Repo 'config\zebar\settings.json') $settings -Force
}

function Install-AhkHelpers {
    Write-Step 'Installing AutoHotkey helpers'
    New-Item -ItemType Directory -Force $AhkDir | Out-Null
    Copy-Item (Join-Path $Repo 'config\ahk\*.ahk') $AhkDir -Force
}

function Set-FlowLauncherConfig {
    Write-Step 'Configuring Flow Launcher'
    $flowData = Join-Path $env:APPDATA 'FlowLauncher'
    $themes = Join-Path $flowData 'Themes'
    New-Item -ItemType Directory -Force $themes | Out-Null
    Copy-Item (Join-Path $Repo 'config\flowlauncher\Catppuccin Mocha.xaml') $themes -Force

    $settingsPath = Join-Path $flowData 'Settings\Settings.json'
    if (-not (Test-Path $settingsPath)) {
        Write-Detail 'first run: starting Flow Launcher once to create its settings'
        Start-Process $FlowExe
        $deadline = (Get-Date).AddSeconds(30)
        while (-not (Test-Path $settingsPath) -and (Get-Date) -lt $deadline) { Start-Sleep -Milliseconds 500 }
        if (-not (Test-Path $settingsPath)) { throw "Flow Launcher did not create $settingsPath" }
        Start-Sleep -Seconds 2
    }
    Stop-Process -Name 'Flow.Launcher' -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 1

    Backup-Item $settingsPath 'flowlauncher-Settings.json'
    $json = Get-Content $settingsPath -Raw -Encoding UTF8 | ConvertFrom-Json
    foreach ($key in $FlowSettings.Keys) {
        $json | Add-Member -NotePropertyName $key -NotePropertyValue $FlowSettings[$key] -Force
    }
    Write-TextFile $settingsPath ($json | ConvertTo-Json -Depth 64)
}

function Set-TaskbarAutoHide {
    Write-Step 'Turning on taskbar auto-hide'
    $key = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\StuckRects3'
    $value = (Get-ItemProperty $key -Name Settings).Settings
    if ($value[8] -eq 3) {
        Write-Detail 'already on'
        return
    }
    $value[8] = 3
    Set-ItemProperty $key -Name Settings -Value $value
    Write-Detail 'restarting Explorer to apply (open File Explorer windows will close)'
    Stop-Process -Name explorer -Force
    Start-Sleep -Seconds 2
    if (-not (Get-Process explorer -ErrorAction SilentlyContinue)) { Start-Process explorer.exe }
}

function Set-WallpaperFill {
    Write-Step 'Setting wallpaper fit to Fill'
    $desktop = 'HKCU:\Control Panel\Desktop'
    Set-ItemProperty $desktop -Name WallpaperStyle -Value '10'
    Set-ItemProperty $desktop -Name TileWallpaper -Value '0'
    $wallpaper = (Get-ItemProperty $desktop).WallPaper
    if ($wallpaper -and (Test-Path $wallpaper)) {
        Add-Type -Namespace Winland -Name Wallpaper -MemberDefinition @'
[DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern bool SystemParametersInfo(uint a, uint b, string c, uint d);
'@ -ErrorAction SilentlyContinue
        [Winland.Wallpaper]::SystemParametersInfo(0x14, 0, $wallpaper, 3) | Out-Null # SPI_SETDESKWALLPAPER
    }
}

function Install-StartupShortcuts {
    Write-Step 'Adding startup shortcuts'
    New-StartupShortcut 'GlazeWM' $GlazeExe '' (Split-Path $GlazeExe)
    New-StartupShortcut 'Winland' $AhkExe "`"$AhkDir\main.ahk`"" $AhkDir
    $legacy = Join-Path $StartupDir 'Workspace AltTab.lnk'
    if (Test-Path $legacy) {
        Remove-Item $legacy -Force
        Write-Detail 'removed legacy shortcut: Workspace AltTab'
    }
}

function Restart-Winland {
    Write-Step 'Starting GlazeWM, Zebar, Flow Launcher and the AHK helpers'
    if (Get-Process glazewm -ErrorAction SilentlyContinue) {
        # wm-exit shows every hidden window again before quitting.
        & $GlazeCli command wm-exit | Out-Null
        $deadline = (Get-Date).AddSeconds(10)
        while ((Get-Process glazewm -ErrorAction SilentlyContinue) -and (Get-Date) -lt $deadline) { Start-Sleep -Milliseconds 300 }
    }
    Stop-Process -Name zebar -Force -ErrorAction SilentlyContinue
    Stop-WinlandAhk
    Start-Sleep -Seconds 1
    # GlazeWM's startup_commands start Zebar and Flow Launcher.
    Start-Process $GlazeExe
    Start-Process $AhkExe -ArgumentList "`"$AhkDir\main.ahk`"" -WorkingDirectory $AhkDir
}

# ---------------------------------------------------------------- main

if (-not $SkipInstall) { Install-Packages } else { Update-SessionPath }
Resolve-Executables
Install-GlazeWMConfig
Install-ZebarConfig
Install-AhkHelpers
Set-FlowLauncherConfig
Set-TaskbarAutoHide
if (-not $SkipWallpaper) { Set-WallpaperFill }
Install-StartupShortcuts
if (-not $NoStart) { Restart-Winland }

Write-Host ''
Write-Host 'winland is installed.' -ForegroundColor Green
Write-Host 'Keys: Win+Enter terminal, Win+D launcher, Win+1..0 workspaces, Win+Ctrl+F overview. See README.md.'
