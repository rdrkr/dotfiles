<#
.SYNOPSIS
  Guest-side logon script of the compare profile: prepares the sandbox and reports ready.
.DESCRIPTION
  Installs the VC++ runtime from C:\host\redist when the sandbox lacks it, copies each build C:\host\<b> to
  C:\app\<b>, runs the optional setup hook per build, then writes C:\work\ready.flag. Progress goes to
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
  if ($rt -and $rt.Installed -eq 1) { Log "VC++ runtime present ($($rt.Version))" }
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
    if ($Setup) { & $Setup -Name $b -AppDir $dst -DataDir "C:\host\data"; Log "setup $b done" }
  }
  Set-Content "C:\work\ready.flag" ("builds " + ($Builds -join ","))
  Log "ready"
} catch {
  Log "ERROR $($_.Exception.Message)"
  Set-Content "C:\work\ready.flag" "FAILED $($_.Exception.Message)"
}
