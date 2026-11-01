# Copyright (c) 2026, Ronen Druker. All rights reserved.

<#
.SYNOPSIS
    Runs `ua` elevated on Windows without a UAC prompt, through a scheduled task.
.DESCRIPTION
    winget installers ask for elevation through UAC, whose dialog only ever appears on the
    desktop. When `ua` runs remotely in a shell that is not elevated (over SSH inside a psmux
    pane whose server was started at the desktop, for instance), nobody can answer it and
    the run hangs. A plain OpenSSH session for an administrator is already elevated, so it
    does not hit this.

    This script registers, once, a scheduled task that runs with highest privileges as the
    current user (S4U logon: no stored password, no window). Starting a task needs no
    elevation, so a remote `ua` starts it and streams its output instead of running the
    tasks itself. The task can only run update-windows.yaml, with arguments limited to the
    runner's own flags.

    Modes:
      -Register    create or update the task (asks for UAC once when not elevated)
      -Unregister  remove the task (asks for UAC once when not elevated)
      -Run         start the task and stream its output; exits with the run's exit code
      -Worker      what the task itself executes; not meant to be run by hand

    Security: anything able to write to this script, the runner or its node_modules as this
    user can get elevated through the task without a prompt. Unregister it when unwanted.
.PARAMETER Register
    Create or update the scheduled task.
.PARAMETER Unregister
    Remove the scheduled task.
.PARAMETER Run
    Start the scheduled task and stream its output.
.PARAMETER Worker
    Execute the runner; used by the scheduled task.
.PARAMETER RunnerArgs
    With -Run: runner flags to pass on (only --verbose / -v are accepted).
.EXAMPLE
    ua-elevated.ps1 -Register
.EXAMPLE
    ua-elevated.ps1 -Run -RunnerArgs --verbose
#>
[CmdletBinding(DefaultParameterSetName = 'Run')]
param(
    [Parameter(ParameterSetName = 'Register', Mandatory)]
    [switch]$Register,

    [Parameter(ParameterSetName = 'Unregister', Mandatory)]
    [switch]$Unregister,

    [Parameter(ParameterSetName = 'Run')]
    [switch]$Run,

    [Parameter(ParameterSetName = 'Worker', Mandatory)]
    [switch]$Worker,

    [Parameter(ParameterSetName = 'Run', ValueFromRemainingArguments)]
    [string[]]$RunnerArgs = @()
)

$ErrorActionPreference = 'Stop'

<# Name of the scheduled task #>
$TaskName = 'dotfiles-ua-elevated'

<# Runner directory: the directory of this script #>
$RunnerDir = $PSScriptRoot

<# Directory for the request, output and exit-code files shared by -Run and -Worker #>
$StateDir = Join-Path $env:LOCALAPPDATA 'dotfiles-ua'

<# Runner flags the elevated task accepts; anything else is refused #>
$AllowedArgs = @('--verbose', '-v')

<# Files exchanged between -Run and -Worker #>
$RequestFile = Join-Path $StateDir 'request.json'
$OutFile = Join-Path $StateDir 'output.log'
$ErrFile = Join-Path $StateDir 'error.log'
$ExitFile = Join-Path $StateDir 'exit-code.txt'

function Test-Elevated {
    <#
    .SYNOPSIS
        Returns whether the current process runs with an elevated (administrator) token.
    .OUTPUTS
        System.Boolean.
    #>
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    ([Security.Principal.WindowsPrincipal]$identity).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Invoke-SelfElevated {
    <#
    .SYNOPSIS
        Re-runs this script elevated (one UAC prompt) with the given mode switch and waits.
    .PARAMETER Mode
        The switch to pass, such as -Register.
    #>
    param([Parameter(Mandatory)][string]$Mode)

    $process = Start-Process powershell.exe -Verb RunAs -Wait -PassThru -ArgumentList @(
        '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$PSCommandPath`"", $Mode
    )
    exit $process.ExitCode
}

function Test-TaskRegistered {
    <#
    .SYNOPSIS
        Returns whether the elevated scheduled task exists.
    .OUTPUTS
        System.Boolean.
    #>
    $null -ne (Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue)
}

function Register-UaTask {
    <#
    .SYNOPSIS
        Creates or updates the scheduled task that runs -Worker with highest privileges.
    #>
    if (-not (Test-Elevated)) { Invoke-SelfElevated '-Register' }

    $action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument (
        "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$PSCommandPath`" -Worker"
    )
    $principal = New-ScheduledTaskPrincipal -UserId "$env:USERDOMAIN\$env:USERNAME" -LogonType S4U -RunLevel Highest
    $settings = New-ScheduledTaskSettingsSet -MultipleInstances IgnoreNew -ExecutionTimeLimit (New-TimeSpan -Hours 3) `
        -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
    Register-ScheduledTask -TaskName $TaskName -Action $action -Principal $principal -Settings $settings `
        -Description 'Runs dotfiles ua (update-windows.yaml) elevated; started by ua in remote sessions' -Force | Out-Null
    Write-Host "registered scheduled task $TaskName"
}

function Unregister-UaTask {
    <#
    .SYNOPSIS
        Removes the scheduled task.
    #>
    if (-not (Test-Elevated)) { Invoke-SelfElevated '-Unregister' }
    Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
    Write-Host "removed scheduled task $TaskName"
}

function Invoke-UaWorker {
    <#
    .SYNOPSIS
        Runs the runner on update-windows.yaml with the requested flags, writing its output to
        the state directory and its exit code last, as the completion marker.
    #>
    $code = 1
    try {
        $requested = @()
        if (Test-Path $RequestFile) {
            $requested = @((Get-Content $RequestFile -Raw | ConvertFrom-Json).args)
        }
        $flags = @($requested | Where-Object { $AllowedArgs -contains $_ })

        $tsx = Join-Path $RunnerDir 'node_modules\tsx\dist\cli.mjs'
        $arguments = @(
            "`"$tsx`"", "`"$(Join-Path $RunnerDir 'run-tasks.ts')`"", "`"$(Join-Path $RunnerDir 'update-windows.yaml')`""
        ) + $flags
        $process = Start-Process node -ArgumentList $arguments -NoNewWindow -PassThru `
            -RedirectStandardOutput $OutFile -RedirectStandardError $ErrFile
        # reading Handle keeps the exit code available after the process ends (PowerShell 5.1)
        $null = $process.Handle
        $process.WaitForExit()
        $code = $process.ExitCode
    } catch {
        Add-Content -Path $ErrFile -Value $_.ToString()
    } finally {
        Set-Content -Path $ExitFile -Value $code
    }
    exit $code
}

function Read-NewText {
    <#
    .SYNOPSIS
        Returns the text appended to a file since the given offset, reading it while the
        writer still holds it open.
    .PARAMETER Path
        File to read.
    .PARAMETER Offset
        Byte offset already read; updated to the new end of the file.
    .OUTPUTS
        System.String. The new text, or an empty string.
    #>
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][ref]$Offset)

    if (-not (Test-Path $Path)) { return '' }
    $stream = [IO.File]::Open($Path, 'Open', 'Read', 'ReadWrite')
    try {
        if ($stream.Length -le $Offset.Value) { return '' }
        $null = $stream.Seek($Offset.Value, 'Begin')
        $buffer = New-Object byte[] ($stream.Length - $Offset.Value)
        $read = $stream.Read($buffer, 0, $buffer.Length)
        $Offset.Value += $read
        [Text.Encoding]::UTF8.GetString($buffer, 0, $read)
    } finally {
        $stream.Dispose()
    }
}

function Invoke-UaTask {
    <#
    .SYNOPSIS
        Starts the elevated task, streams its output until it writes its exit code, and exits
        with that code; Ctrl-C stops the task.
    .PARAMETER Arguments
        Runner flags to request.
    #>
    param([string[]]$Arguments = @())

    if (-not (Test-TaskRegistered)) {
        Write-Error "scheduled task $TaskName is not registered; run 'ua-setup' once at the desktop"
    }
    $refused = @($Arguments | Where-Object { $AllowedArgs -notcontains $_ })
    if ($refused.Count -gt 0) {
        Write-Error "the elevated task only accepts $($AllowedArgs -join ', '); refused: $($refused -join ' ')"
    }

    $null = New-Item -ItemType Directory -Force -Path $StateDir
    Remove-Item $OutFile, $ErrFile, $ExitFile -ErrorAction SilentlyContinue
    @{ args = $Arguments } | ConvertTo-Json | Set-Content -Path $RequestFile

    Write-Host "ua: running elevated through scheduled task $TaskName"
    Start-ScheduledTask -TaskName $TaskName

    $offset = 0
    $done = $false
    $started = Get-Date
    try {
        while (-not $done) {
            Start-Sleep -Milliseconds 500
            $done = Test-Path $ExitFile
            $text = Read-NewText -Path $OutFile -Offset ([ref]$offset)
            if ($text) { [Console]::Out.Write($text) }

            # the task never started or died without writing its exit code
            $state = (Get-ScheduledTask -TaskName $TaskName).State
            if (-not $done -and $state -ne 'Running' -and ((Get-Date) - $started).TotalSeconds -gt 10) {
                Write-Error "scheduled task $TaskName is $state and wrote no exit code"
            }
        }
    } finally {
        if (-not $done) {
            Stop-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
        }
    }

    $errors = if (Test-Path $ErrFile) { Get-Content $ErrFile -Raw } else { '' }
    if ($errors) { [Console]::Error.Write($errors) }
    exit [int](Get-Content $ExitFile -Raw).Trim()
}

switch ($PSCmdlet.ParameterSetName) {
    'Register' { Register-UaTask }
    'Unregister' { Unregister-UaTask }
    'Worker' { Invoke-UaWorker }
    default { Invoke-UaTask -Arguments $RunnerArgs }
}
