<#
.SYNOPSIS
  wsb-gui profile: several builds of one Windows app in one sandbox, to compare them (e.g. develop vs a fix).
.DESCRIPTION
  Maps every build folder read-only to C:\host\<name>; tools\logon.ps1 copies each to the sandbox's own disk as
  C:\app\<name> (apps may write next to their exe), installs the VC++ runtime only if the sandbox lacks it, and
  then runs the optional -Setup hook once per build. Drive a build with  -Do -ExeLike 'C:\app\<name>\' ...
  App-specific preparation (config files, test data) belongs in the -Setup hook, which lives with the app or in
  %LOCALAPPDATA%\wsb-gui\setups, not in this repo.
  Example:
    wsb-gui.ps1 -Start compare -ProfileArgs @{ Builds = @{ dev = 'D:\b\dev'; fix = 'D:\b\fix' }; Setup = "$env:LOCALAPPDATA\wsb-gui\setups\myapp.ps1"; Data = 'D:\testdata' }
.PARAMETER Work
  Host work folder (passed by wsb-gui.ps1).
.PARAMETER Builds
  Hashtable name -> host folder of each build (names become C:\app\<name>).
.PARAMETER Setup
  Optional host .ps1 run in the sandbox after the copy, once per build, as
  <setup> -Name <name> -AppDir C:\app\<name> -DataDir C:\host\data (the -Data folder, when given).
.PARAMETER Data
  Optional host folder with test data, mapped read-only as C:\host\data.
.PARAMETER Exclude
  File patterns not copied into the sandbox; default debug artifacts.
.PARAMETER Redist
  A Visual Studio VC\Redist\MSVC\<version> folder; default: the newest one on this machine. Its x64\*.CRT /
  *.MFC / *.OpenMP DLLs are deployed app-locally (seconds); its vc_redist.x64.exe is the fallback (~4 min).
.PARAMETER OpenGL
  none (default) | llvmpipe | d3d12. The sandbox only offers legacy desktop OpenGL (<= 2.0); with llvmpipe
  (CPU, GL 4.5) or d3d12 (GL on the sandbox's vGPU) a current Mesa is deployed next to each build's exe.
  Needs a cached Mesa: run wsb-gui.ps1 -GetMesa once.
.PARAMETER Mesa
  Folder with Mesa's x64 DLLs; default the newest under %LOCALAPPDATA%\wsb-gui\cache\mesa.
.PARAMETER MemoryInMB
  Sandbox memory; default 16384.
#>
param(
  [string]$Work, [Parameter(Mandatory)] [hashtable]$Builds, [string]$Setup = "", [string]$Data = "",
  [string[]]$Exclude = @("*.pdb", "*.lib", "*.exp", "*.ilk"), [string]$Redist = "", [ValidateSet("none", "llvmpipe", "d3d12")] [string]$OpenGL = "none", [string]$Mesa = "",
  [int]$MemoryInMB = 16384
)
$mapped = @()
foreach ($name in $Builds.Keys) {
  if ($name -notmatch '^[\w-]+$') { throw "build name '$name' must be a plain word" }
  $mapped += @{ Host = (Resolve-Path $Builds[$name]).Path; Sandbox = "C:\host\$name"; ReadOnly = $true }
}
if (-not $Redist) {
  # numbered folders (14.44.35112) hold the app-local DLLs; the v143 alias only holds the installer
  $vs = Get-ChildItem "C:\Program Files\Microsoft Visual Studio\*\*\VC\Redist\MSVC\*\x64" -Directory -ErrorAction SilentlyContinue |
    Where-Object { Get-ChildItem $_.FullName -Directory -Filter "*.CRT" } | Sort-Object { [version]($_.Parent.Name) } -Descending | Select-Object -First 1
  if ($vs) { $Redist = $vs.Parent.FullName }
}
if ($Redist) { $mapped += @{ Host = $Redist; Sandbox = "C:\host\redist"; ReadOnly = $true } }
$glArg = ""
if ($OpenGL -ne "none") {
  if (-not $Mesa) {
    $m = Get-ChildItem (Join-Path $env:LOCALAPPDATA "wsb-gui\cache\mesa\*\x64\opengl32.dll") -ErrorAction SilentlyContinue |
      Sort-Object { [version]($_.Directory.Parent.Name) } -Descending | Select-Object -First 1
    if (-not $m) { throw "no Mesa cached: run wsb-gui.ps1 -GetMesa first" }
    $Mesa = $m.DirectoryName
  }
  $mapped += @{ Host = (Resolve-Path $Mesa).Path; Sandbox = "C:\host\mesa"; ReadOnly = $true }
  $glArg = " -OpenGL $OpenGL"
}
if ($Data) { $mapped += @{ Host = (Resolve-Path $Data).Path; Sandbox = "C:\host\data"; ReadOnly = $true } }
$setupArg = ""
if ($Setup) {
  # the hook travels through the work folder, so it never needs its own mapping
  Copy-Item $Setup (Join-Path $Work "tools\setup.ps1") -Force
  $setupArg = " -Setup C:\work\tools\setup.ps1"
}
@{
  Mapped       = $mapped
  MemoryInMB   = $MemoryInMB
  LogonCommand = "powershell.exe -NoProfile -ExecutionPolicy Bypass -File C:\work\tools\logon.ps1 -Builds $(@($Builds.Keys) -join ',') -Exclude `"$($Exclude -join ',')`"$glArg$setupArg"
}
