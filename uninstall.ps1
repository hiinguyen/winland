<#
.SYNOPSIS
    Turns winland off: stops GlazeWM, Zebar and the AHK helpers, removes the
    startup shortcuts, shows the native taskbar and turns taskbar auto-hide off.

.DESCRIPTION
    Apps and config files are left in place. Config backups made by setup.ps1
    are in %USERPROFILE%\.glzr\backups\<timestamp>. To remove the apps:
        winget uninstall glzr-io.glazewm glzr-io.zebar AutoHotkey.AutoHotkey Flow-Launcher.Flow-Launcher

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\uninstall.ps1
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$StartupDir = [Environment]::GetFolderPath('Startup')

Add-Type -Namespace Winland -Name Win32 -MemberDefinition @'
[DllImport("user32.dll")] public static extern bool PostMessage(IntPtr h, uint m, IntPtr w, IntPtr l);
[DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern IntPtr FindWindowEx(IntPtr p, IntPtr a, string c, string t);
[DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint p);
[DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int c);
'@

function Write-Step([string]$Message) {
    Write-Host "==> $Message" -ForegroundColor Cyan
}

Write-Step 'Stopping the AHK helpers'
$procs = @(Get-CimInstance Win32_Process -Filter "Name LIKE 'AutoHotkey%'" |
    Where-Object { $_.CommandLine -like '*\.glzr\*' })
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

Write-Step 'Stopping GlazeWM and Zebar'
$glaze = Get-Process glazewm -ErrorAction SilentlyContinue | Select-Object -First 1
if ($glaze) {
    # wm-exit shows every hidden window again before quitting.
    $cli = Join-Path (Split-Path $glaze.Path) 'cli\glazewm.exe'
    if (Test-Path $cli) { & $cli command wm-exit | Out-Null }
    Start-Sleep -Seconds 2
    Stop-Process -Name glazewm -Force -ErrorAction SilentlyContinue
}
Stop-Process -Name zebar -Force -ErrorAction SilentlyContinue

Write-Step 'Removing startup shortcuts'
foreach ($name in 'GlazeWM', 'Winland', 'Workspace AltTab') {
    $link = Join-Path $StartupDir "$name.lnk"
    if (Test-Path $link) { Remove-Item $link -Force; Write-Host "    removed $name" }
}

Write-Step 'Showing the native taskbar'
foreach ($class in 'Shell_TrayWnd', 'Shell_SecondaryTrayWnd') {
    $hwnd = [IntPtr]::Zero
    while (($hwnd = [Winland.Win32]::FindWindowEx([IntPtr]::Zero, $hwnd, $class, $null)) -ne [IntPtr]::Zero) {
        [Winland.Win32]::ShowWindow($hwnd, 8) | Out-Null # SW_SHOWNA
    }
}
$key = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\StuckRects3'
$value = (Get-ItemProperty $key -Name Settings).Settings
if ($value[8] -ne 2) {
    $value[8] = 2
    Set-ItemProperty $key -Name Settings -Value $value
    Write-Host '    auto-hide off; restarting Explorer to apply'
    Stop-Process -Name explorer -Force
    Start-Sleep -Seconds 2
    if (-not (Get-Process explorer -ErrorAction SilentlyContinue)) { Start-Process explorer.exe }
}

Write-Host ''
Write-Host 'winland is off. Run setup.ps1 to turn it back on.' -ForegroundColor Green
