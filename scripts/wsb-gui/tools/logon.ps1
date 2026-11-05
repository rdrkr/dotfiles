<#
.SYNOPSIS
  Guest-side logon script of the compare profile: prepares the sandbox and reports ready.
.DESCRIPTION
  Copies each build C:\host\<b> to C:\app\<b> and, when the sandbox has no VC++ runtime, deploys the runtime
  DLLs from C:\host\redist\x64 next to it (app-local, seconds; the vc_redist installer is the fallback). Then runs the optional setup hook per build, then writes C:\work\ready.flag. Progress goes to
  C:\work\out\logon.log.
.PARAMETER Builds
  Names of the mapped builds (folders under C:\host); "a,b" as one string is accepted.
.PARAMETER Exclude
  File patterns not copied, comma-separated.
.PARAMETER Setup
  Optional script run per build as  <Setup> -Name <b> -AppDir C:\app\<b> -DataDir C:\host\data.
#>
param([string[]]$Builds = @(), [string]$Exclude = "", [string]$Setup = "")
$log = "C:\work\out\logon.log"

<#
.SYNOPSIS
  Appends a timestamped line to the logon log.
.PARAMETER s
  The line.
#>
function Log([string]$s) { Add-Content $log ("{0:HH:mm:ss} {1}" -f (Get-Date), $s) }

try {
  Log "logon start as $(whoami)"
  # powershell -File hands "a,b" over as one string
  $Builds = @($Builds | ForEach-Object { $_ -split "," } | Where-Object { $_ })
  $xf = @($Exclude -split "," | Where-Object { $_ })
  $rt = Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\VisualStudio\14.0\VC\Runtimes\x64" -ErrorAction SilentlyContinue
  $localDlls = @(Get-ChildItem "C:\host\redist\x64\*.CRT", "C:\host\redist\x64\*.MFC", "C:\host\redist\x64\*.MFCLOC", "C:\host\redist\x64\*.OpenMP" -Filter *.dll -Recurse -ErrorAction SilentlyContinue)
  if ($rt -and $rt.Installed -eq 1) { Log "VC++ runtime present ($($rt.Version))"; $localDlls = @() }
  elseif ($localDlls.Count) { Log "VC++ runtime: $($localDlls.Count) DLLs deployed app-locally" }
  elseif (Test-Path "C:\host\redist\vc_redist.x64.exe") {
    $p = Start-Process "C:\host\redist\vc_redist.x64.exe" -ArgumentList "/install", "/quiet", "/norestart" -Wait -PassThru
    Log "vc_redist exit $($p.ExitCode)"
  }
  foreach ($b in $Builds) {
    $dst = "C:\app\$b"
    $rcArgs = @("C:\host\$b", $dst, "/E", "/NFL", "/NDL", "/NJH", "/NP", "/MT:16")
    if ($xf.Count) { $rcArgs += @("/XF") + $xf }
    robocopy @rcArgs | Out-Null
    Log "copied $b (robocopy $LASTEXITCODE)"
    # never overwrite a DLL the build ships itself
    foreach ($dll in $localDlls) { if (-not (Test-Path "$dst\$($dll.Name)")) { Copy-Item $dll.FullName $dst } }
    if ($Setup) { & $Setup -Name $b -AppDir $dst -DataDir "C:\host\data"; Log "setup $b done" }
  }
  Set-Content "C:\work\ready.flag" ("builds " + ($Builds -join ","))
  Log "ready"
} catch {
  Log "ERROR $($_.Exception.Message)"
  Set-Content "C:\work\ready.flag" "FAILED $($_.Exception.Message)"
}
