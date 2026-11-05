<#
.SYNOPSIS
  Host side of wsb-gui: runs and drives Windows GUI apps inside Windows Sandbox, so GUI tests never take over
  the real mouse, keyboard or screen.
.DESCRIPTION
  -Start  creates a sandbox from a profile (profiles\<name>.ps1), opens its session window (a user session is
          needed for GUI work) and waits until the profile's logon script reports ready.
  -Do     runs tools\drive.ps1 inside the sandbox's user session and prints its result. Arguments after -Do are
          passed through, e.g.  wsb-gui.ps1 -Do -Action list -ExeLike 'C:\mf\dev\'
  -Exec   runs any command line inside the sandbox's user session (no output; write to C:\work\out yourself).
  -Stop   destroys the sandbox (nothing it did survives).
  -Status prints the running sandbox id and the work folder.
  wsb exec returns no output, so all results travel through the read-write work folder, mapped into the
  sandbox as C:\work: tools\ (copied from this repo on -Start), out\ (results), shots\ (PNGs).
.PARAMETER Start
  Name of the profile to start (file profiles\<name>.ps1).
.PARAMETER ProfileArgs
  Hashtable passed to the profile script as named parameters.
.PARAMETER Do
  Run tools\drive.ps1 in the sandbox; remaining arguments go to it.
.PARAMETER Exec
  Command line to run in the sandbox's user session.
.PARAMETER Stop
  Stop the running sandbox.
.PARAMETER Status
  Show the running sandbox.
.PARAMETER NoConnect
  With -Start: do not open the session window (only System-context commands will work).
.PARAMETER ReadyTimeoutSec
  With -Start: how long to wait for the profile's logon script (default 900).
.NOTES
  Deliberately not an advanced script: every argument -Do does not know arrives in $args and is forwarded
  to drive.ps1 (an advanced script would claim -Out* as its common -OutVariable/-OutBuffer).
#>
param(
  [string]$Start = "", [hashtable]$ProfileArgs = @{}, [switch]$Do, [string]$Exec = "", [switch]$Stop, [switch]$Status,
  [switch]$NoConnect, [int]$ReadyTimeoutSec = 900
)
$Rest = $args
$ErrorActionPreference = "Stop"
$Root = $PSScriptRoot
$Work = Join-Path $env:LOCALAPPDATA "wsb-gui\work"
$IdFile = Join-Path $Work "sandbox.id"

<#
.SYNOPSIS
  Returns the id of the sandbox started by -Start, failing when there is none.
#>
function Get-SandboxId {
  if (-not (Test-Path $IdFile)) { throw "no sandbox started (run -Start first)" }
  (Get-Content $IdFile -Raw).Trim()
}

<#
.SYNOPSIS
  Runs a command line in the sandbox's active user session and returns its exit code.
.PARAMETER id
  Sandbox id.
.PARAMETER cmd
  Command line, as the sandbox sees it.
#>
function Invoke-InSandbox([string]$id, [string]$cmd) {
  $json = & wsb.exe exec --raw --id $id -r ExistingLogin -c $cmd 2>&1 | Out-String
  try { return [int](($json | ConvertFrom-Json).ExitCode) } catch { Write-Warning $json.Trim(); return -1 }
}

<#
.SYNOPSIS
  Builds the Windows Sandbox configuration XML from a profile's settings.
.PARAMETER p
  Hashtable with Mapped (list of @{Host; Sandbox; ReadOnly}), MemoryInMB, LogonCommand, Networking, vGPU.
#>
function New-SandboxConfig([hashtable]$p) {
  $maps = @(@{ Host = $Work; Sandbox = "C:\work"; ReadOnly = $false }) + @($p.Mapped)
  $mx = ($maps | ForEach-Object {
      "<MappedFolder><HostFolder>$($_.Host)</HostFolder><SandboxFolder>$($_.Sandbox)</SandboxFolder><ReadOnly>$(([bool]$_.ReadOnly).ToString().ToLower())</ReadOnly></MappedFolder>"
    }) -join ""
  $logon = if ($p.LogonCommand) { "<LogonCommand><Command>$($p.LogonCommand)</Command></LogonCommand>" } else { "" }
  $mem = if ($p.MemoryInMB) { $p.MemoryInMB } else { 8192 }
  $net = if ($p.Networking) { $p.Networking } else { "Disable" }
  $gpu = if ($p.vGPU) { $p.vGPU } else { "Enable" }
  "<Configuration><vGPU>$gpu</vGPU><Networking>$net</Networking><MemoryInMB>$mem</MemoryInMB><MappedFolders>$mx</MappedFolders>$logon</Configuration>"
}

New-Item -ItemType Directory -Force $Work, (Join-Path $Work "out"), (Join-Path $Work "shots") | Out-Null

if ($Status) {
  if (Test-Path $IdFile) { "sandbox $(Get-SandboxId)" } else { "no sandbox recorded" }
  "running: " + ((& wsb.exe list 2>&1 | Out-String).Trim())
  "work: $Work"
  return
}

if ($Stop) {
  $id = Get-SandboxId
  & wsb.exe stop --id $id 2>&1 | Out-Null
  Remove-Item $IdFile -Force
  "stopped $id"
  return
}

if ($Start) {
  if (Test-Path $IdFile) { throw "sandbox $(Get-SandboxId) is recorded as running; -Stop it first" }
  # fresh tools and an empty result area for every run
  Remove-Item (Join-Path $Work "tools"), (Join-Path $Work "out"), (Join-Path $Work "ready.flag") -Recurse -Force -ErrorAction SilentlyContinue
  New-Item -ItemType Directory -Force (Join-Path $Work "out") | Out-Null
  Copy-Item (Join-Path $Root "tools") (Join-Path $Work "tools") -Recurse
  $profileScript = Join-Path $Root "profiles\$Start.ps1"
  if (-not (Test-Path $profileScript)) { throw "no profile $profileScript" }
  $settings = & $profileScript -Work $Work @ProfileArgs
  $cfg = New-SandboxConfig $settings
  Set-Content (Join-Path $Work "last-config.wsb") $cfg
  $json = & wsb.exe start --raw -c $cfg 2>&1 | Out-String
  $id = ($json | ConvertFrom-Json).Id
  if (-not $id) { throw "wsb start failed: $json" }
  Set-Content $IdFile $id
  "started $id"
  if (-not $NoConnect) {
    # the session window is what creates the user session GUI work needs; it can be minimized afterwards
    Start-Process wsb.exe -ArgumentList "connect", "--id", $id -WindowStyle Hidden
    "connected (Windows Sandbox window opened)"
  }
  if ($settings.LogonCommand) {
    $flag = Join-Path $Work "ready.flag"
    $sw = [Diagnostics.Stopwatch]::StartNew()
    while (-not (Test-Path $flag) -and $sw.Elapsed.TotalSeconds -lt $ReadyTimeoutSec) { Start-Sleep 3 }
    if (Test-Path $flag) { "ready after $([int]$sw.Elapsed.TotalSeconds) s: $((Get-Content $flag -Raw).Trim())" } else { Write-Warning "not ready after $ReadyTimeoutSec s (see $Work\out\logon.log)" }
  }
  return
}

if ($Exec) {
  $code = Invoke-InSandbox (Get-SandboxId) $Exec
  "exit $code"
  return
}

if ($Do) {
  $id = Get-SandboxId
  $n = [Guid]::NewGuid().ToString("N").Substring(0, 8)
  $resGuest = "C:\work\out\do-$n.txt"; $resHost = Join-Path $Work "out\do-$n.txt"
  # quote every forwarded argument for the guest command line; -Name switches pass through bare
  # (a trailing backslash would escape the closing quote, so it is doubled: "C:\mf\dev\\")
  $fwd = ($Rest | ForEach-Object { if ($_ -match '^-[A-Za-z]+$') { $_ } else { '"' + (($_ -replace '"', '\"') -replace '(\\+)$', '$1$1') + '"' } }) -join " "
  $cmd = "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File C:\work\tools\drive.ps1 $fwd -Result $resGuest"
  $code = Invoke-InSandbox $id $cmd
  # read and delete before printing: a caller's Select-Object -First stops this script at its first output line
  if (Test-Path $resHost) { $out = Get-Content $resHost; Remove-Item $resHost -Force; $out } else { "no result (exit $code)" }
  return
}

Get-Help $PSCommandPath -Detailed
