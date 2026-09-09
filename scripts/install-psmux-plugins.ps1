#Requires -Version 5.1
<#
.SYNOPSIS
    Installs the psmux plugin manager (ppm) and the plugins ~/.psmux.conf declares.
.DESCRIPTION
    psmux cannot use TPM: tpm and its plugins are POSIX shell scripts, and psmux
    runs `run-shell` through cmd.exe. Its ecosystem equivalent is ppm, which lives
    in the psmux-plugins repo alongside the plugins themselves.

    ppm's own documented bootstrap only copies ppm and then expects `Prefix + I`
    inside a live session to clone the rest. This script does both steps up front
    so a fresh machine has a working status bar after `install.ps1 restore`,
    without an interactive psmux session.

    Installed into $HOME\.psmux\plugins:
      ppm         - plugin manager (equivalent of tpm)
      psmux-cpu   - publishes @cpu_percentage / @ram_percentage for status-right

    Safe to re-run: the repo is re-cloned into a temp directory each time and the
    plugin directories are replaced, which doubles as the update path.
.PARAMETER DryRun
    Report what would be installed without touching the filesystem.
.EXAMPLE
    .\install-psmux-plugins.ps1
    .\install-psmux-plugins.ps1 -DryRun
#>

param(
    [Alias('d')]
    [switch]$DryRun
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Plugins to install. Keep in sync with the `set -g @plugin` lines in .psmux.conf.
$script:PLUGIN_REPO  = 'https://github.com/psmux/psmux-plugins.git'
$script:PLUGINS      = @('ppm', 'psmux-cpu')
$script:PLUGINS_DIR  = Join-Path $HOME '.psmux\plugins'

function Write-Step {
    <#
    .SYNOPSIS
        Prints a progress line for one installation step.
    .PARAMETER Message
        Text to display.
    #>
    param([Parameter(Mandatory)][string]$Message)
    Write-Host "==> $Message" -ForegroundColor Cyan
}

function Install-PsmuxPlugins {
    <#
    .SYNOPSIS
        Clones psmux-plugins and copies the declared plugin directories into
        $HOME\.psmux\plugins.
    .DESCRIPTION
        Clones with --depth 1 into a temp directory, copies each plugin over any
        existing copy, then removes the clone. Any missing plugin directory in
        the upstream repo is reported and skipped rather than failing the run.
    #>
    if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
        throw 'git is required to install psmux plugins but was not found on PATH.'
    }

    $tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("psmux-plugins-" + [guid]::NewGuid().ToString('N'))

    if ($DryRun) {
        Write-Step "Would clone $script:PLUGIN_REPO"
        foreach ($p in $script:PLUGINS) {
            Write-Step "Would install $p -> $(Join-Path $script:PLUGINS_DIR $p)"
        }
        return
    }

    Write-Step "Cloning $script:PLUGIN_REPO"
    git clone --depth 1 --quiet $script:PLUGIN_REPO $tmp
    if ($LASTEXITCODE -ne 0) { throw "git clone failed with exit code $LASTEXITCODE." }

    try {
        if (-not (Test-Path $script:PLUGINS_DIR)) {
            New-Item -ItemType Directory -Path $script:PLUGINS_DIR -Force | Out-Null
        }

        foreach ($plugin in $script:PLUGINS) {
            $src = Join-Path $tmp $plugin
            if (-not (Test-Path $src)) {
                Write-Warning "Plugin '$plugin' not found in the upstream repo; skipping."
                continue
            }

            $dest = Join-Path $script:PLUGINS_DIR $plugin
            if (Test-Path $dest) { Remove-Item -Path $dest -Recurse -Force }

            Copy-Item -Path $src -Destination $dest -Recurse -Force
            Write-Step "Installed $plugin -> $dest"
        }
    }
    finally {
        Remove-Item -Path $tmp -Recurse -Force -ErrorAction SilentlyContinue
    }

    Write-Host 'Done. Restart psmux (psmux kill-server) to pick the plugins up.' -ForegroundColor Green
}

Install-PsmuxPlugins
