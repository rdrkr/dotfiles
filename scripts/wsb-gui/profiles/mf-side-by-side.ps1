<#
.SYNOPSIS
  wsb-gui profile: two MAGNET Field (MF Classic) builds side by side in one sandbox, e.g. develop vs a fix.
.DESCRIPTION
  Maps both runtime folders read-only, plus the VC++ redistributable (MF builds do not ship the VC/MFC
  runtime and the sandbox has none) and the folder holding a test job. tools\logon.ps1 then copies each
  build to the sandbox's own disk (MF writes next to its exe), points each copy at its own data root with
  tps_dir.ini and drops the job into both Jobs folders. Inside the sandbox the builds live in C:\mf\dev and
  C:\mf\fix, so drive them with  -Do -ExeLike 'C:\mf\dev\' ...
  Example:
    wsb-gui.ps1 -Start mf-side-by-side -ProfileArgs @{ Dev = '<...>\mf17800-dev'; Fix = '<...>\mf17800-fix'; Job = '<...>\MF-34243-tests.mjf'; JobName = 'MF17800' }
.PARAMETER Work
  Host work folder (passed by wsb-gui.ps1).
.PARAMETER Dev
  Host runtime folder of the first build (the one containing MAGNET_Field.exe).
.PARAMETER Fix
  Host runtime folder of the second build.
.PARAMETER Job
  Optional .mjf copied into both data roots' Jobs folder.
.PARAMETER JobName
  Name the job gets there (without .mjf); default: the source file's name.
.PARAMETER Redist
  Folder containing vc_redist.x64.exe; default: Visual Studio 2022's v143 redist.
.PARAMETER MemoryInMB
  Sandbox memory; default 16384.
#>
param(
  [string]$Work, [Parameter(Mandatory)] [string]$Dev, [Parameter(Mandatory)] [string]$Fix, [string]$Job = "", [string]$JobName = "",
  [string]$Redist = "", [int]$MemoryInMB = 16384
)
if (-not $Redist) {
  $vs = Get-ChildItem "C:\Program Files\Microsoft Visual Studio\*\*\VC\Redist\MSVC\v14*\vc_redist.x64.exe" -ErrorAction SilentlyContinue | Select-Object -First 1
  if (-not $vs) { throw "vc_redist.x64.exe not found; pass -Redist" }
  $Redist = Split-Path $vs.FullName
}
$mapped = @(
  @{ Host = (Resolve-Path $Dev).Path; Sandbox = "C:\host\dev"; ReadOnly = $true },
  @{ Host = (Resolve-Path $Fix).Path; Sandbox = "C:\host\fix"; ReadOnly = $true },
  @{ Host = $Redist; Sandbox = "C:\host\redist"; ReadOnly = $true }
)
$jobArg = ""
if ($Job) {
  $jobFile = Get-Item $Job
  $mapped += @{ Host = $jobFile.DirectoryName; Sandbox = "C:\host\job"; ReadOnly = $true }
  $name = if ($JobName) { $JobName } else { $jobFile.BaseName }
  $jobArg = " -Job `"C:\host\job\$($jobFile.Name)`" -JobName `"$name`""
}
@{
  Mapped       = $mapped
  MemoryInMB   = $MemoryInMB
  LogonCommand = "powershell.exe -NoProfile -ExecutionPolicy Bypass -File C:\work\tools\logon.ps1 -Builds dev,fix$jobArg"
}
