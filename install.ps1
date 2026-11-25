<#
.SYNOPSIS
  Install the Windows No-TUN silent launcher for Google Antigravity 2.x.

.PARAMETER ProxyUrl
  Local HTTP/SOCKS5 proxy URL (default: http://127.0.0.1:7897).

.PARAMETER DisableCdp
  Omit --remote-debugging-port=0 when launching Antigravity.

.PARAMETER KeepLegacyDll
  Do not move existing version.dll / config.json out of the Antigravity install directory.
#>
[CmdletBinding()]
param(
  [string]$ProxyUrl = "http://127.0.0.1:7897",
  [switch]$DisableCdp,
  [switch]$KeepLegacyDll
)

$ErrorActionPreference = "Stop"

# 1. Locate Antigravity.exe
$exeCandidates = @(
  (Join-Path $env:LOCALAPPDATA "Programs\antigravity\Antigravity.exe"),
  (Join-Path $env:ProgramFiles "antigravity\Antigravity.exe")
)
$exePath = $exeCandidates | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $exePath) {
  throw "Antigravity.exe not found in default install locations."
}
$agDir = Split-Path $exePath -Parent

# 2. Deploy launcher script outside Antigravity install dir (survives auto-updates)
$scriptsDir = Join-Path $HOME ".gemini\antigravity\scripts"
New-Item -ItemType Directory -Path $scriptsDir -Force | Out-Null

$srcVbs = Join-Path $PSScriptRoot "launch-antigravity-no-tun.vbs"
$dstVbs = Join-Path $scriptsDir "launch-antigravity-no-tun.vbs"
$vbsContent = Get-Content -Path $srcVbs -Raw -Encoding UTF8
if ($ProxyUrl -and $ProxyUrl -ne "http://127.0.0.1:7897") {
  $vbsContent = $vbsContent.Replace('http://127.0.0.1:7897', $ProxyUrl)
}
if ($DisableCdp) {
  $vbsContent = $vbsContent.Replace('cdpFlag = " --remote-debugging-port=0"', 'cdpFlag = ""')
}
[System.IO.File]::WriteAllText($dstVbs, $vbsContent, [System.Text.UTF8Encoding]::new($false))
Write-Host "[OK] Installed launcher: $dstVbs" -ForegroundColor Green

# 3. Update Desktop & Start Menu shortcuts in-place (preserving original icon)
$wsh = New-Object -ComObject WScript.Shell
$wscript = Join-Path $env:WINDIR "System32\wscript.exe"
$lnkTargets = @(
  (Join-Path ([Environment]::GetFolderPath("Desktop")) "Antigravity.lnk"),
  (Join-Path $env:APPDATA "Microsoft\Windows\Start Menu\Programs\Antigravity.lnk")
)
foreach ($lnk in $lnkTargets) {
  $lnkDir = Split-Path $lnk -Parent
  if (-not (Test-Path $lnkDir)) { continue }
  $sc = $wsh.CreateShortcut($lnk)
  $sc.TargetPath = $wscript
  $sc.Arguments = "`"$dstVbs`""
  $sc.WorkingDirectory = $agDir
  $sc.IconLocation = "$exePath,0"
  $sc.Description = "Antigravity (No-TUN Proxy Launcher)"
  $sc.Save()
  Write-Host "[OK] Patched shortcut: $lnk" -ForegroundColor Green
}

# 4. Safely back up legacy version.dll / config.json if present
if (-not $KeepLegacyDll) {
  $bakDir = Join-Path $HOME ".gemini\antigravity\backup-no-tun-dll"
  $moved = @()
  foreach ($fname in @("version.dll", "config.json")) {
    $src = Join-Path $agDir $fname
    if (Test-Path $src) {
      New-Item -ItemType Directory -Path $bakDir -Force | Out-Null
      Move-Item -Path $src -Destination (Join-Path $bakDir $fname) -Force
      $moved += $fname
    }
  }
  if ($moved.Count -gt 0) {
    Write-Host "[OK] Backed up legacy files ($($moved -join ', ')) -> $bakDir" -ForegroundColor Yellow
  }
}

Write-Host ""
Write-Host "Done! Quit Antigravity completely and reopen it from the Desktop or Start Menu shortcut." -ForegroundColor Cyan
