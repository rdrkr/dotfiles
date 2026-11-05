<#
.SYNOPSIS
  Guest-side logon script of the mf-side-by-side profile: prepares the sandbox and reports ready.
.DESCRIPTION
  Installs the VC++ redistributable from C:\host\redist, copies each build C:\host\<b> to C:\mf\<b> (skipping
  debug artifacts and test data), gives each copy its own data root C:\mfdata\<b> through tps_dir.ini, copies
  the test job into every data root, then writes C:\work\ready.flag. Progress goes to C:\work\out\logon.log.
.PARAMETER Builds
  Names of the mapped builds (folders under C:\host).
.PARAMETER Job
  Optional .mjf to copy into each data root's Jobs folder.
.PARAMETER JobName
  File name (without .mjf) the job gets there.
#>
param([string[]]$Builds = @("dev", "fix"), [string]$Job = "", [string]$JobName = "")
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
  # powershell -File hands "dev,fix" over as one string
  $Builds = @($Builds | ForEach-Object { $_ -split "," } | Where-Object { $_ })
  $rt = Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\VisualStudio\14.0\VC\Runtimes\x64" -ErrorAction SilentlyContinue
  if ($rt -and $rt.Installed -eq 1) { Log "vc_redist already installed ($($rt.Version))" }
  else {
    $p = Start-Process "C:\host\redist\vc_redist.x64.exe" -ArgumentList "/install", "/quiet", "/norestart" -Wait -PassThru
    Log "vc_redist exit $($p.ExitCode)"
  }
  foreach ($b in $Builds) {
    $dst = "C:\mf\$b"
    robocopy "C:\host\$b" $dst /E /XF *.pdb *.lib *.exp *.ilk tps_dir.ini /XD test /NFL /NDL /NJH /NP /MT:16 | Out-Null
    Log "copied $b (robocopy $LASTEXITCODE)"
    $data = "C:\mfdata\$b"
    New-Item -ItemType Directory -Force "$data\Documents\Jobs", "$data\User" | Out-Null
    Set-Content "$dst\tps_dir.ini" "[Directories]`r`nDocuments=$data\Documents`r`nUser=$data\User`r`n"
    if ($Job) { Copy-Item $Job "$data\Documents\Jobs\$JobName.mjf"; Log "job $JobName.mjf -> $b" }
  }
  Set-Content "C:\work\ready.flag" ("builds " + ($Builds -join ","))
  Log "ready"
} catch {
  Log "ERROR $($_.Exception.Message)"
  Set-Content "C:\work\ready.flag" "FAILED $($_.Exception.Message)"
}
