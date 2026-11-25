<#
.SYNOPSIS
  Restore Antigravity shortcuts back to Antigravity.exe and remove the No-TUN launcher script.
#>
[CmdletBinding()]
param(
  [switch]$KeepCdpFlag
)

$ErrorActionPreference = "Stop"

$exeCandidates = @(
  (Join-Path $env:LOCALAPPDATA "Programs\antigravity\Antigravity.exe"),
  (Join-Path $env:ProgramFiles "antigravity\Antigravity.exe")
)
$exePath = $exeCandidates | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $exePath) {
  throw "Antigravity.exe not found."
}
$agDir = Split-Path $exePath -Parent

$wsh = New-Object -ComObject WScript.Shell
$lnkTargets = @(
  (Join-Path ([Environment]::GetFolderPath("Desktop")) "Antigravity.lnk"),
  (Join-Path $env:APPDATA "Microsoft\Windows\Start Menu\Programs\Antigravity.lnk")
)
foreach ($lnk in $lnkTargets) {
  if (-not (Test-Path $lnk)) { continue }
  $sc = $wsh.CreateShortcut($lnk)
  $sc.TargetPath = $exePath
  $sc.Arguments = if ($KeepCdpFlag) { "--remote-debugging-port=0" } else { "" }
  $sc.WorkingDirectory = $agDir
  $sc.IconLocation = "$exePath,0"
  $sc.Description = "Google Antigravity"
  $sc.Save()
  Write-Host "[OK] Restored shortcut: $lnk" -ForegroundColor Green
}

$dstVbs = Join-Path $HOME ".gemini\antigravity\scripts\launch-antigravity-no-tun.vbs"
if (Test-Path $dstVbs) {
  Remove-Item -Path $dstVbs -Force
  Write-Host "[OK] Removed launcher: $dstVbs" -ForegroundColor Green
}

Write-Host "Uninstall complete." -ForegroundColor Cyan
