#Requires -Version 5.1
<#
.SYNOPSIS
    Sets up Apollo (a Sunshine fork) so Microsoft Teams, Outlook and Chrome can be
    streamed to Moonlight on a phone without logging out of the Windows session.
.DESCRIPTION
    Setup mode (the default, run as Administrator):
      1. Installs Apollo, Google Chrome, Microsoft Teams, Outlook and Tailscale
         with winget.
      2. Sets the Apollo web UI credentials if none are configured yet.
      3. Sets `dd_configuration_option = verify_only` in sunshine.conf, so
         Apollo only adds its virtual display and leaves the physical monitors
         alone. This script switches the monitors itself (see -StreamStart),
         because it has to pause komorebi first.
      4. Adds "Teams", "Outlook" and "Chrome" to apps.json. Each app gets
         Apollo's built-in virtual display (SudoVDA), which exists only while a
         stream runs and matches the client's resolution. Each app calls this
         script with -StreamStart / -StreamEnd as prep commands and with
         -Launch as a detached command. Each app also ends its session when
         the client disconnects, so the PC is restored right away.
      5. Turns off sleep and hibernate on AC power so the PC stays reachable.
      6. Sets ApolloService to start automatically and restarts it.

    Stream start (-StreamStart, an Apollo prep "do" command):
      Records whether komorebi is running and paused, and pauses it if it is
      running and active. Saves the current display layout, then makes the
      virtual display the only active display, which moves every window onto
      the stream.

    App launch (-Launch <App>, an Apollo detached command):
      Starts the app, or brings up a new window if it is already running, and
      for -WindowWaitSeconds seconds maximizes each of its windows on the
      stream's display.

    Stream end (-StreamEnd, an Apollo prep "undo" command):
      Restores the saved layout without the virtual display, so the physical
      monitors come back exactly as they were and Windows moves the windows
      back. Then it unpauses komorebi only if -StreamStart paused it, so
      komorebi ends up running, paused or stopped as it was before.

    Stream modes log to %LOCALAPPDATA%\ApolloStreaming\stream.log.

    Safe to re-run: packages that are already installed are skipped, config
    keys are updated in place, and the three apps are replaced by name while
    other apps in apps.json are kept.
.PARAMETER Launch
    Start the named app and maximize its windows on the stream's display.
    Apollo runs this; you don't need to run it by hand.
.PARAMETER WindowWaitSeconds
    Launch mode only: how long to keep maximizing newly appearing windows.
    Covers splash screens and slow first starts.
.PARAMETER StreamStart
    Pause komorebi and switch to the virtual display only. Apollo runs this.
.PARAMETER StreamEnd
    Restore the physical displays and komorebi's previous state. Apollo runs
    this.
.PARAMETER WebUsername
    Apollo web UI username. If no credentials exist yet and this is omitted,
    the script prompts for it.
.PARAMETER WebPassword
    Apollo web UI password. If no credentials exist yet and this is omitted,
    the script prompts for it.
.PARAMETER ResetCredentials
    Replace existing Apollo web UI credentials instead of keeping them.
.PARAMETER DryRun
    Report what setup would do without installing or changing anything.
.EXAMPLE
    .\setup-apollo-streaming.ps1
.EXAMPLE
    .\setup-apollo-streaming.ps1 -DryRun
#>

[CmdletBinding(DefaultParameterSetName = 'Setup')]
param(
    [Parameter(ParameterSetName = 'Launch', Mandatory)]
    [ValidateSet('Teams', 'Outlook', 'Chrome')]
    [string]$Launch,

    [Parameter(ParameterSetName = 'Launch')]
    [ValidateRange(5, 600)]
    [int]$WindowWaitSeconds = 45,

    [Parameter(ParameterSetName = 'StreamStart', Mandatory)]
    [switch]$StreamStart,

    [Parameter(ParameterSetName = 'StreamEnd', Mandatory)]
    [switch]$StreamEnd,

    [Parameter(ParameterSetName = 'Setup')]
    [string]$WebUsername,

    [Parameter(ParameterSetName = 'Setup')]
    [securestring]$WebPassword,

    [Parameter(ParameterSetName = 'Setup')]
    [switch]$ResetCredentials,

    [Parameter(ParameterSetName = 'Setup')]
    [Alias('d')]
    [switch]$DryRun
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Apollo installs to "Program Files\Apollo" and keeps its config next to the exe.
$script:APOLLO_DIR         = Join-Path $env:ProgramFiles 'Apollo'
$script:APOLLO_EXE         = Join-Path $script:APOLLO_DIR 'sunshine.exe'
$script:APOLLO_CONFIG_DIR  = Join-Path $script:APOLLO_DIR 'config'
$script:APOLLO_CONF        = Join-Path $script:APOLLO_CONFIG_DIR 'sunshine.conf'
$script:APOLLO_APPS        = Join-Path $script:APOLLO_CONFIG_DIR 'apps.json'
$script:APOLLO_STATE       = Join-Path $script:APOLLO_CONFIG_DIR 'sunshine_state.json'
$script:APOLLO_SERVICE     = 'ApolloService'
$script:APOLLO_WEB_UI      = 'https://localhost:47990'

# Absolute path of this script; Apollo runs it from apps.json.
$script:SCRIPT_PATH        = $PSCommandPath
# Mode this run was started in (Setup, Launch, StreamStart or StreamEnd).
$script:MODE               = $PSCmdlet.ParameterSetName

# Per-session state (komorebi + saved display layout) and the stream log.
$script:STREAM_DIR         = Join-Path $env:LOCALAPPDATA 'ApolloStreaming'
$script:STREAM_STATE       = Join-Path $script:STREAM_DIR 'session.json'
$script:STREAM_LOG         = Join-Path $script:STREAM_DIR 'stream.log'

# Store app IDs (AUMIDs) for the MSIX-packaged apps.
$script:TEAMS_AUMID        = 'MSTeams_8wekyb3d8bbwe!MSTeams'
$script:NEW_OUTLOOK_AUMID  = 'Microsoft.OutlookForWindows_8wekyb3d8bbwe!Microsoft.OutlookforWindows'
$script:NEW_OUTLOOK_STORE  = '9NRX63209R7B'

# winget exit codes that mean "already installed / nothing to do".
$script:WINGET_OK_CODES    = @(0, -1978335189, -1978335135)

# Process names whose windows belong to each streamed app.
$script:APP_PROCESSES = @{
    Teams   = @('ms-teams')
    Outlook = @('OUTLOOK', 'olk')
    Chrome  = @('chrome')
}

function Write-Step {
    <#
    .SYNOPSIS
        Prints a progress line for one setup step.
    .PARAMETER Message
        Text to display.
    #>
    param([Parameter(Mandatory)][string]$Message)
    Write-Host "==> $Message" -ForegroundColor Cyan
}

function Write-DryRun {
    <#
    .SYNOPSIS
        Prints what a step would do when -DryRun is set.
    .PARAMETER Message
        Description of the skipped action.
    #>
    param([Parameter(Mandatory)][string]$Message)
    Write-Host "    [DRY RUN] $Message" -ForegroundColor Yellow
}

function Write-StreamLog {
    <#
    .SYNOPSIS
        Appends a timestamped line to the stream log.
    .DESCRIPTION
        Stream modes run hidden under Apollo, so the log is the only place to
        see what they did.
    .PARAMETER Message
        Text to log.
    #>
    param([Parameter(Mandatory)][string]$Message)
    if (-not (Test-Path $script:STREAM_DIR)) {
        New-Item -ItemType Directory -Path $script:STREAM_DIR -Force | Out-Null
    }
    $line = '{0:yyyy-MM-dd HH:mm:ss} [{1}] {2}' -f (Get-Date), $script:MODE, $Message
    Add-Content -Path $script:STREAM_LOG -Value $line
}

function Test-IsAdministrator {
    <#
    .SYNOPSIS
        Returns $true when the current process runs elevated.
    #>
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    return ([Security.Principal.WindowsPrincipal]$identity).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-AppPath {
    <#
    .SYNOPSIS
        Resolves an executable registered under the Windows "App Paths" key.
    .DESCRIPTION
        Checks the machine-wide key first, then the per-user key. Returns $null
        when the executable is not registered or the file no longer exists.
    .PARAMETER ExeName
        File name registered under App Paths, such as OUTLOOK.EXE.
    #>
    param([Parameter(Mandatory)][string]$ExeName)

    foreach ($root in 'HKLM:', 'HKCU:') {
        $key = "$root\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\$ExeName"
        $item = Get-ItemProperty -Path $key -ErrorAction SilentlyContinue
        if ($item -and $item.PSObject.Properties['(default)']) {
            $path = $item.'(default)'.Trim('"')
            if (Test-Path $path) { return $path }
        }
    }
    return $null
}

function Test-AppxInstalled {
    <#
    .SYNOPSIS
        Returns $true when an MSIX/Store package is installed for the current user.
    .PARAMETER Name
        Package name, such as MSTeams.
    #>
    param([Parameter(Mandatory)][string]$Name)
    return [bool](Get-AppxPackage -Name $Name -ErrorAction SilentlyContinue)
}

function Install-WingetPackage {
    <#
    .SYNOPSIS
        Installs a winget package unless it is already present.
    .DESCRIPTION
        Uses -IsInstalled when given, because `winget list` can't always map
        Store and MSIX packages back to their IDs. Otherwise asks winget.
    .PARAMETER Id
        Exact winget package ID.
    .PARAMETER Source
        winget source to install from (winget or msstore).
    .PARAMETER IsInstalled
        Optional check that returns $true when the package is already installed.
    .PARAMETER Required
        Throw on failure instead of warning and continuing.
    #>
    param(
        [Parameter(Mandatory)][string]$Id,
        [string]$Source = 'winget',
        [scriptblock]$IsInstalled,
        [switch]$Required
    )

    $installed = if ($IsInstalled) {
        & $IsInstalled
    } else {
        winget list --id $Id --exact --source $Source --accept-source-agreements *> $null
        $LASTEXITCODE -eq 0
    }

    if ($installed) {
        Write-Step "$Id is already installed"
        return
    }

    if ($DryRun) {
        Write-DryRun "winget install --id $Id --exact --source $Source"
        return
    }

    Write-Step "Installing $Id"
    winget install --id $Id --exact --source $Source --silent `
        --accept-package-agreements --accept-source-agreements
    if ($script:WINGET_OK_CODES -notcontains $LASTEXITCODE) {
        $message = "winget install $Id failed with exit code $LASTEXITCODE."
        if ($Required) { throw $message }
        Write-Warning $message
    }
}

function Install-Packages {
    <#
    .SYNOPSIS
        Installs Apollo, the streamed apps and Tailscale.
    .DESCRIPTION
        Apollo brings its own virtual display driver (SudoVDA), which only adds
        a display while a stream runs, so no separate driver is installed.
        Outlook is only installed when neither classic Outlook (Microsoft 365)
        nor the new Outlook app is present; the new Outlook comes from the
        Microsoft Store because it has no winget-source package.
    #>
    Install-WingetPackage -Id 'ClassicOldSong.Apollo' -Required `
        -IsInstalled { Test-Path $script:APOLLO_EXE }
    Install-WingetPackage -Id 'Google.Chrome' `
        -IsInstalled { [bool](Get-AppPath 'chrome.exe') }
    Install-WingetPackage -Id 'Microsoft.Teams' `
        -IsInstalled { Test-AppxInstalled 'MSTeams' }
    Install-WingetPackage -Id $script:NEW_OUTLOOK_STORE -Source 'msstore' `
        -IsInstalled { (Get-AppPath 'OUTLOOK.EXE') -or (Test-AppxInstalled 'Microsoft.OutlookForWindows') }
    Install-WingetPackage -Id 'tailscale.tailscale'
}

function Write-Utf8File {
    <#
    .SYNOPSIS
        Writes text as UTF-8 without a byte-order mark.
    .DESCRIPTION
        Windows PowerShell 5.1's -Encoding UTF8 adds a BOM, which Apollo's
        config and JSON parsers do not expect.
    .PARAMETER Path
        Destination file.
    .PARAMETER Content
        Text to write.
    #>
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][AllowEmptyString()][string]$Content
    )
    [System.IO.File]::WriteAllText($Path, $Content, (New-Object System.Text.UTF8Encoding($false)))
}

function Test-ApolloCredentials {
    <#
    .SYNOPSIS
        Returns $true when Apollo already has web UI credentials saved.
    #>
    if (-not (Test-Path $script:APOLLO_STATE)) { return $false }
    $state = Get-Content -Path $script:APOLLO_STATE -Raw | ConvertFrom-Json
    return [bool]($state.PSObject.Properties['username'] -and $state.username)
}

function Set-ApolloCredentials {
    <#
    .SYNOPSIS
        Sets the Apollo web UI username and password with `sunshine.exe --creds`.
    .DESCRIPTION
        Skips existing credentials unless -ResetCredentials is set. Prompts for
        any value not passed as a parameter.
    #>
    if ((Test-ApolloCredentials) -and -not $ResetCredentials) {
        Write-Step 'Apollo web UI credentials already set (use -ResetCredentials to replace)'
        return
    }

    if ($DryRun) {
        Write-DryRun "sunshine.exe --creds <username> <password>"
        return
    }

    $user = if ($WebUsername) { $WebUsername } else { Read-Host 'Apollo web UI username' }
    $secure = if ($WebPassword) { $WebPassword } else { Read-Host 'Apollo web UI password' -AsSecureString }

    $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
    try {
        $plain = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
        Write-Step 'Saving Apollo web UI credentials'
        & $script:APOLLO_EXE --creds $user $plain | Out-Null
        if ($LASTEXITCODE -ne 0) { throw "sunshine.exe --creds failed with exit code $LASTEXITCODE." }
    }
    finally {
        [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
    }
}

function Set-ApolloConfigValue {
    <#
    .SYNOPSIS
        Sets one `key = value` line in sunshine.conf, replacing an existing one.
    .PARAMETER Key
        Config key, such as dd_configuration_option.
    .PARAMETER Value
        Value to set.
    #>
    param(
        [Parameter(Mandatory)][string]$Key,
        [Parameter(Mandatory)][string]$Value
    )

    $lines = @()
    if (Test-Path $script:APOLLO_CONF) {
        $lines = @(Get-Content -Path $script:APOLLO_CONF)
    }

    $pattern = '^\s*' + [regex]::Escape($Key) + '\s*='
    $newLine = "$Key = $Value"
    $found = $false
    $lines = @(foreach ($line in $lines) {
        if ($line -match $pattern) {
            if (-not $found) { $newLine }
            $found = $true
        } else {
            $line
        }
    })
    if (-not $found) { $lines += $newLine }

    if ($DryRun) {
        Write-DryRun "Set '$newLine' in $script:APOLLO_CONF"
        return
    }

    Write-Step "Setting '$newLine' in sunshine.conf"
    Write-Utf8File -Path $script:APOLLO_CONF -Content (($lines -join "`r`n") + "`r`n")
}

function Get-ScriptCommand {
    <#
    .SYNOPSIS
        Builds the hidden PowerShell command line Apollo uses to call this script.
    .PARAMETER Arguments
        Arguments for this script, such as "-StreamStart".
    #>
    param([Parameter(Mandatory)][string]$Arguments)
    return 'powershell.exe -NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass ' +
        "-File `"$script:SCRIPT_PATH`" $Arguments"
}

function New-StreamAppEntry {
    <#
    .SYNOPSIS
        Builds the apps.json entry for one streamed app.
    .DESCRIPTION
        - prep-cmd: -StreamStart before the app starts and -StreamEnd when the
          session ends. Both run elevated, like the komorebic calls in
          komorebic-hotkeys.ahk.
        - detached: -Launch, so the stream stays up after the launcher exits
          and ends only when the client quits or disconnects.
        - virtual-display: Apollo's per-session display sized to the client.
        - terminate-on-pause: a client disconnect ends the session instead of
          leaving it paused, so -StreamEnd restores the PC right away.
    .PARAMETER App
        Streamed app key (Teams, Outlook or Chrome).
    .PARAMETER Uuid
        Existing app UUID to keep, so paired clients keep their app list.
    #>
    param(
        [Parameter(Mandatory)][string]$App,
        [string]$Uuid
    )

    if (-not $Uuid) { $Uuid = [guid]::NewGuid().ToString().ToUpperInvariant() }

    return [pscustomobject][ordered]@{
        'name'               = $App
        'uuid'               = $Uuid
        'prep-cmd'           = @([pscustomobject][ordered]@{
            'do'       = Get-ScriptCommand '-StreamStart'
            'undo'     = Get-ScriptCommand '-StreamEnd'
            'elevated' = $true
        })
        'detached'           = @(Get-ScriptCommand "-Launch $App")
        'virtual-display'    = $true
        'auto-detach'        = $true
        'terminate-on-pause' = $true
    }
}

function Update-ApolloApps {
    <#
    .SYNOPSIS
        Adds or replaces the Teams, Outlook and Chrome entries in apps.json.
    .DESCRIPTION
        Keeps every other app and the "env" block. Replaced entries keep their
        UUID.
    #>
    $doc = if (Test-Path $script:APOLLO_APPS) {
        Get-Content -Path $script:APOLLO_APPS -Raw | ConvertFrom-Json
    } else {
        [pscustomobject]@{ env = [pscustomobject]@{}; apps = @() }
    }

    $existing = @()
    if ($doc.PSObject.Properties['apps'] -and $doc.apps) { $existing = @($doc.apps) }

    $streamApps = @('Teams', 'Outlook', 'Chrome')
    $kept = @($existing | Where-Object { $streamApps -notcontains $_.name })

    $added = foreach ($app in $streamApps) {
        $old = $existing | Where-Object { $_.name -eq $app } | Select-Object -First 1
        $uuid = if ($old -and $old.PSObject.Properties['uuid']) { $old.uuid } else { $null }
        New-StreamAppEntry -App $app -Uuid $uuid
    }

    $result = [pscustomobject][ordered]@{
        env  = if ($doc.PSObject.Properties['env']) { $doc.env } else { [pscustomobject]@{} }
        apps = @($kept) + @($added)
    }

    if ($DryRun) {
        Write-DryRun "Write $($streamApps -join ', ') to $script:APOLLO_APPS"
        return
    }

    Write-Step "Writing $($streamApps -join ', ') to apps.json"
    Write-Utf8File -Path $script:APOLLO_APPS -Content ($result | ConvertTo-Json -Depth 10)
}

function Disable-SleepOnAC {
    <#
    .SYNOPSIS
        Stops the PC from sleeping or hibernating while on AC power.
    .DESCRIPTION
        Moonlight can't reach a sleeping PC. The display may still turn off;
        streams use the virtual display, so that doesn't matter.
    #>
    if ($DryRun) {
        Write-DryRun 'powercfg /change standby-timeout-ac 0; powercfg /change hibernate-timeout-ac 0'
        return
    }
    Write-Step 'Disabling sleep and hibernate on AC power'
    powercfg /change standby-timeout-ac 0
    powercfg /change hibernate-timeout-ac 0
}

function Restart-ApolloService {
    <#
    .SYNOPSIS
        Sets ApolloService to start automatically and restarts it so the new
        config and apps take effect.
    #>
    if ($DryRun) {
        Write-DryRun "Set $script:APOLLO_SERVICE to Automatic and restart it"
        return
    }
    Write-Step "Restarting $script:APOLLO_SERVICE"
    Set-Service -Name $script:APOLLO_SERVICE -StartupType Automatic
    Restart-Service -Name $script:APOLLO_SERVICE -Force
}

function Write-NextSteps {
    <#
    .SYNOPSIS
        Prints the manual steps left after setup: pairing and Tailscale login.
    #>
    Write-Host ''
    Write-Host 'Setup complete. Remaining manual steps:' -ForegroundColor Green
    Write-Host "  1. Sign in to Tailscale on this PC and on the phone (tray icon / app)."
    Write-Host "  2. In the Moonlight (or VoidLink) app, add this PC (by Tailscale IP when away from home)."
    Write-Host "  3. Enter the PIN the app shows at $script:APOLLO_WEB_UI (PIN tab)."
    Write-Host "  4. In the app's settings, set touch mode to direct touch (not trackpad)."
    Write-Host "  5. Start Teams, Outlook or Chrome from the app list."
    Write-Host "  Stream log: $script:STREAM_LOG"
}

function Invoke-Setup {
    <#
    .SYNOPSIS
        Runs the full setup: packages, credentials, config, apps, power, service.
    #>
    if (-not (Test-IsAdministrator)) {
        throw 'Setup needs an elevated PowerShell. Re-run it as Administrator.'
    }
    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
        throw 'winget not found. Install App Installer from the Microsoft Store.'
    }

    Install-Packages

    if (-not (Test-Path $script:APOLLO_EXE)) {
        if ($DryRun) {
            Write-DryRun "Apollo is not installed yet, so config steps are only described"
        } else {
            throw "Apollo not found at $script:APOLLO_EXE after installing it."
        }
    }

    Set-ApolloCredentials
    # Apollo only adds the virtual display; -StreamStart turns the physical
    # monitors off after pausing komorebi, and -StreamEnd turns them back on.
    Set-ApolloConfigValue -Key 'dd_configuration_option' -Value 'verify_only'
    Update-ApolloApps
    Disable-SleepOnAC
    Restart-ApolloService
    Write-NextSteps
}

function Initialize-NativeApi {
    <#
    .SYNOPSIS
        Loads the Win32 helpers for display layout and app windows.
    #>
    if ('ApolloStreamNative' -as [type]) { return }

    Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.IO;
using System.Runtime.InteropServices;

/// <summary>
/// Saves and switches the Windows display layout (CCD API) and finds and
/// maximizes top-level app windows.
/// </summary>
public static class ApolloStreamNative
{
    /// <summary>Adapter name the SudoVDA virtual display driver registers.</summary>
    public const string VirtualAdapterName = "SudoMaker Virtual Display Adapter";

    // ---- Display configuration (CCD) ----

    [StructLayout(LayoutKind.Sequential)]
    private struct LUID { public uint LowPart; public int HighPart; }

    [StructLayout(LayoutKind.Sequential)]
    private struct PathSourceInfo
    {
        public LUID adapterId;
        public uint id;
        public uint modeInfoIdx;
        public uint statusFlags;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct PathTargetInfo
    {
        public LUID adapterId;
        public uint id;
        public uint modeInfoIdx;
        public uint outputTechnology;
        public uint rotation;
        public uint scaling;
        public uint refreshNumerator;
        public uint refreshDenominator;
        public uint scanLineOrdering;
        public int targetAvailable;
        public uint statusFlags;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct PathInfo
    {
        public PathSourceInfo sourceInfo;
        public PathTargetInfo targetInfo;
        public uint flags;
    }

    // DISPLAYCONFIG_MODE_INFO: 16-byte header plus a 48-byte union. Only the
    // source-mode position is read or written; the rest is copied verbatim.
    [StructLayout(LayoutKind.Explicit, Size = 64)]
    private struct ModeInfo
    {
        [FieldOffset(0)] public uint infoType;
        [FieldOffset(4)] public uint id;
        [FieldOffset(8)] public LUID adapterId;
        [FieldOffset(28)] public int sourcePositionX;
        [FieldOffset(32)] public int sourcePositionY;
    }

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    private struct SourceDeviceName
    {
        public uint type;
        public uint size;
        public LUID adapterId;
        public uint id;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)] public string viewGdiDeviceName;
    }

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    private struct DisplayDevice
    {
        public int cb;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)] public string DeviceName;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)] public string DeviceString;
        public uint StateFlags;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)] public string DeviceID;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)] public string DeviceKey;
    }

    [DllImport("user32.dll")] private static extern int GetDisplayConfigBufferSizes(uint flags, out uint numPaths, out uint numModes);
    [DllImport("user32.dll")] private static extern int QueryDisplayConfig(uint flags, ref uint numPaths, [Out] PathInfo[] paths, ref uint numModes, [Out] ModeInfo[] modes, IntPtr topologyId);
    [DllImport("user32.dll")] private static extern int SetDisplayConfig(uint numPaths, [In] PathInfo[] paths, uint numModes, [In] ModeInfo[] modes, uint flags);
    [DllImport("user32.dll")] private static extern int DisplayConfigGetDeviceInfo(ref SourceDeviceName request);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] private static extern bool EnumDisplayDevices(string device, uint index, ref DisplayDevice info, uint flags);

    private const uint QDC_ONLY_ACTIVE_PATHS = 0x2;
    private const uint SDC_APPLY = 0x80;
    private const uint SDC_USE_SUPPLIED_DISPLAY_CONFIG = 0x20;
    private const uint SDC_ALLOW_CHANGES = 0x400;
    private const uint DISPLAYCONFIG_PATH_ACTIVE = 0x1;
    private const uint DISPLAYCONFIG_MODE_INFO_TYPE_SOURCE = 1;
    private const uint DISPLAYCONFIG_DEVICE_INFO_GET_SOURCE_NAME = 1;
    private const uint MODE_IDX_INVALID = 0xFFFFFFFF;
    private const int ERROR_INSUFFICIENT_BUFFER = 122;

    /// <summary>Reads the active display paths and their modes.</summary>
    private static void QueryActive(out PathInfo[] paths, out ModeInfo[] modes)
    {
        while (true)
        {
            uint numPaths, numModes;
            int rc = GetDisplayConfigBufferSizes(QDC_ONLY_ACTIVE_PATHS, out numPaths, out numModes);
            if (rc != 0) throw new Win32Exception(rc);
            paths = new PathInfo[numPaths];
            modes = new ModeInfo[numModes];
            rc = QueryDisplayConfig(QDC_ONLY_ACTIVE_PATHS, ref numPaths, paths, ref numModes, modes, IntPtr.Zero);
            if (rc == ERROR_INSUFFICIENT_BUFFER) continue; // layout changed in between; retry
            if (rc != 0) throw new Win32Exception(rc);
            Array.Resize(ref paths, (int)numPaths);
            Array.Resize(ref modes, (int)numModes);
            return;
        }
    }

    /// <summary>Returns the GDI name (\\.\DISPLAYn) of a path's source.</summary>
    private static string GetSourceGdiName(PathInfo path)
    {
        var request = new SourceDeviceName();
        request.type = DISPLAYCONFIG_DEVICE_INFO_GET_SOURCE_NAME;
        request.size = (uint)Marshal.SizeOf(typeof(SourceDeviceName));
        request.adapterId = path.sourceInfo.adapterId;
        request.id = path.sourceInfo.id;
        return DisplayConfigGetDeviceInfo(ref request) == 0 ? request.viewGdiDeviceName : null;
    }

    /// <summary>Returns the adapter name (DeviceString) for each GDI display name.</summary>
    private static Dictionary<string, string> GetAdapterNames()
    {
        var names = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
        var device = new DisplayDevice();
        device.cb = Marshal.SizeOf(typeof(DisplayDevice));
        for (uint i = 0; EnumDisplayDevices(null, i, ref device, 0); i++)
        {
            names[device.DeviceName] = device.DeviceString;
            device.cb = Marshal.SizeOf(typeof(DisplayDevice));
        }
        return names;
    }

    /// <summary>Returns true for paths driven by the SudoVDA virtual display adapter.</summary>
    private static bool[] FindVirtualPaths(PathInfo[] paths)
    {
        var adapters = GetAdapterNames();
        var result = new bool[paths.Length];
        for (int i = 0; i < paths.Length; i++)
        {
            string gdi = GetSourceGdiName(paths[i]);
            string adapter;
            result[i] = gdi != null && adapters.TryGetValue(gdi, out adapter) &&
                adapter.IndexOf(VirtualAdapterName, StringComparison.OrdinalIgnoreCase) >= 0;
        }
        return result;
    }

    /// <summary>
    /// Applies the given paths that pass the filter, with only the modes they
    /// reference. Optionally moves the single kept source to (0, 0) so it can
    /// be the primary display.
    /// </summary>
    private static void ApplySubset(PathInfo[] paths, ModeInfo[] modes, bool[] keep, bool moveToOrigin)
    {
        var keptPaths = new List<PathInfo>();
        var keptModes = new List<ModeInfo>();
        var remap = new Dictionary<uint, uint>();

        Func<uint, uint> mapMode = idx =>
        {
            if (idx == MODE_IDX_INVALID || idx >= modes.Length) return MODE_IDX_INVALID;
            uint mapped;
            if (!remap.TryGetValue(idx, out mapped))
            {
                mapped = (uint)keptModes.Count;
                keptModes.Add(modes[idx]);
                remap[idx] = mapped;
            }
            return mapped;
        };

        for (int i = 0; i < paths.Length; i++)
        {
            if (!keep[i]) continue;
            var path = paths[i];
            path.flags |= DISPLAYCONFIG_PATH_ACTIVE;
            path.sourceInfo.modeInfoIdx = mapMode(path.sourceInfo.modeInfoIdx);
            path.targetInfo.modeInfoIdx = mapMode(path.targetInfo.modeInfoIdx);
            keptPaths.Add(path);
        }

        if (keptPaths.Count == 0) throw new InvalidOperationException("No display would be left active.");

        var modeArray = keptModes.ToArray();
        if (moveToOrigin)
        {
            for (int i = 0; i < modeArray.Length; i++)
            {
                if (modeArray[i].infoType != DISPLAYCONFIG_MODE_INFO_TYPE_SOURCE) continue;
                modeArray[i].sourcePositionX = 0;
                modeArray[i].sourcePositionY = 0;
            }
        }

        int rc = SetDisplayConfig((uint)keptPaths.Count, keptPaths.ToArray(), (uint)modeArray.Length, modeArray,
            SDC_APPLY | SDC_USE_SUPPLIED_DISPLAY_CONFIG | SDC_ALLOW_CHANGES);
        if (rc != 0) throw new Win32Exception(rc);
    }

    /// <summary>Returns true when a SudoVDA virtual display is currently active.</summary>
    public static bool HasActiveVirtualDisplay()
    {
        PathInfo[] paths; ModeInfo[] modes;
        QueryActive(out paths, out modes);
        return Array.IndexOf(FindVirtualPaths(paths), true) >= 0;
    }

    /// <summary>Serializes the active display layout to a Base64 string.</summary>
    public static string SaveLayout()
    {
        PathInfo[] paths; ModeInfo[] modes;
        QueryActive(out paths, out modes);
        using (var stream = new MemoryStream())
        using (var writer = new BinaryWriter(stream))
        {
            writer.Write(paths.Length);
            writer.Write(modes.Length);
            foreach (var p in paths) writer.Write(ToBytes(p));
            foreach (var m in modes) writer.Write(ToBytes(m));
            writer.Flush();
            return Convert.ToBase64String(stream.ToArray());
        }
    }

    /// <summary>
    /// Makes the SudoVDA virtual display the only active display. Returns
    /// false when no virtual display is active.
    /// </summary>
    public static bool UseOnlyVirtualDisplay()
    {
        PathInfo[] paths; ModeInfo[] modes;
        QueryActive(out paths, out modes);
        var isVirtual = FindVirtualPaths(paths);
        if (Array.IndexOf(isVirtual, true) < 0) return false;
        ApplySubset(paths, modes, isVirtual, true);
        return true;
    }

    /// <summary>
    /// Re-applies a layout saved by SaveLayout, leaving out any virtual
    /// display, so only the physical monitors are active again in their
    /// original arrangement.
    /// </summary>
    /// <param name="saved">Base64 string returned by SaveLayout.</param>
    public static void RestoreLayoutWithoutVirtual(string saved)
    {
        PathInfo[] paths; ModeInfo[] modes;
        using (var reader = new BinaryReader(new MemoryStream(Convert.FromBase64String(saved))))
        {
            int pathCount = reader.ReadInt32();
            int modeCount = reader.ReadInt32();
            paths = new PathInfo[pathCount];
            modes = new ModeInfo[modeCount];
            for (int i = 0; i < pathCount; i++) paths[i] = FromBytes<PathInfo>(reader.ReadBytes(Marshal.SizeOf(typeof(PathInfo))));
            for (int i = 0; i < modeCount; i++) modes[i] = FromBytes<ModeInfo>(reader.ReadBytes(Marshal.SizeOf(typeof(ModeInfo))));
        }

        var isVirtual = FindVirtualPaths(paths);
        var keep = new bool[paths.Length];
        for (int i = 0; i < keep.Length; i++) keep[i] = !isVirtual[i];
        ApplySubset(paths, modes, keep, false);
    }

    private static byte[] ToBytes<T>(T value) where T : struct
    {
        var bytes = new byte[Marshal.SizeOf(typeof(T))];
        var handle = GCHandle.Alloc(bytes, GCHandleType.Pinned);
        try { Marshal.StructureToPtr(value, handle.AddrOfPinnedObject(), false); }
        finally { handle.Free(); }
        return bytes;
    }

    private static T FromBytes<T>(byte[] bytes) where T : struct
    {
        var handle = GCHandle.Alloc(bytes, GCHandleType.Pinned);
        try { return (T)Marshal.PtrToStructure(handle.AddrOfPinnedObject(), typeof(T)); }
        finally { handle.Free(); }
    }

    // ---- App windows ----

    private delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);

    [DllImport("user32.dll")] private static extern bool EnumWindows(EnumWindowsProc cb, IntPtr lParam);
    [DllImport("user32.dll")] private static extern bool IsWindowVisible(IntPtr hWnd);
    [DllImport("user32.dll")] private static extern IntPtr GetWindow(IntPtr hWnd, uint cmd);
    [DllImport("user32.dll")] private static extern int GetWindowTextLength(IntPtr hWnd);
    [DllImport("user32.dll")] private static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint pid);
    [DllImport("user32.dll")] private static extern int GetWindowLong(IntPtr hWnd, int index);
    [DllImport("user32.dll")] private static extern bool ShowWindow(IntPtr hWnd, int cmd);
    [DllImport("user32.dll")] private static extern bool IsZoomed(IntPtr hWnd);
    [DllImport("user32.dll")] private static extern bool SetForegroundWindow(IntPtr hWnd);
    [DllImport("dwmapi.dll")] private static extern int DwmGetWindowAttribute(IntPtr hWnd, int attr, out int value, int size);

    private const uint GW_OWNER = 4;
    private const int GWL_EXSTYLE = -20;
    private const int WS_EX_TOOLWINDOW = 0x80;
    private const int DWMWA_CLOAKED = 14;
    private const int SW_MAXIMIZE = 3;

    /// <summary>
    /// Returns visible, uncloaked, unowned, titled top-level windows that
    /// belong to one of the given process IDs (the windows on the taskbar).
    /// </summary>
    /// <param name="processIds">Process IDs whose windows to return.</param>
    public static IntPtr[] GetAppWindows(uint[] processIds)
    {
        var wanted = new HashSet<uint>(processIds);
        var result = new List<IntPtr>();
        EnumWindows((hWnd, lParam) =>
        {
            uint pid;
            GetWindowThreadProcessId(hWnd, out pid);
            if (!wanted.Contains(pid)) return true;
            if (!IsWindowVisible(hWnd) || GetWindow(hWnd, GW_OWNER) != IntPtr.Zero) return true;
            if (GetWindowTextLength(hWnd) == 0) return true;
            if ((GetWindowLong(hWnd, GWL_EXSTYLE) & WS_EX_TOOLWINDOW) != 0) return true;
            int cloaked;
            if (DwmGetWindowAttribute(hWnd, DWMWA_CLOAKED, out cloaked, sizeof(int)) == 0 && cloaked != 0) return true;
            result.Add(hWnd);
            return true;
        }, IntPtr.Zero);
        return result.ToArray();
    }

    /// <summary>Maximizes the window unless it already is.</summary>
    /// <param name="hWnd">Window handle.</param>
    public static void Maximize(IntPtr hWnd)
    {
        if (!IsZoomed(hWnd)) ShowWindow(hWnd, SW_MAXIMIZE);
    }

    /// <summary>Brings the window to the foreground.</summary>
    /// <param name="hWnd">Window handle.</param>
    public static void Focus(IntPtr hWnd)
    {
        SetForegroundWindow(hWnd);
    }
}
'@
}

function Get-KomorebiState {
    <#
    .SYNOPSIS
        Returns komorebi's current state as 'stopped', 'paused' or 'active'.
    .DESCRIPTION
        'stopped' also covers komorebic not being installed or not answering.
    #>
    if (-not (Get-Process -Name 'komorebi' -ErrorAction SilentlyContinue)) { return 'stopped' }
    if (-not (Get-Command komorebic -ErrorAction SilentlyContinue)) { return 'stopped' }

    try {
        $state = komorebic state | Out-String | ConvertFrom-Json
        if ($state.is_paused) { return 'paused' }
        return 'active'
    } catch {
        Write-StreamLog "komorebic state failed: $_"
        return 'stopped'
    }
}

function Invoke-StreamStart {
    <#
    .SYNOPSIS
        Pauses komorebi (if active), saves the display layout and makes the
        virtual display the only active display.
    .DESCRIPTION
        Never fails: Apollo aborts the launch when a prep command exits non-zero,
        so errors are logged instead.
    #>
    try {
        Initialize-NativeApi

        $komorebi = Get-KomorebiState
        $pausedByUs = $false
        if ($komorebi -eq 'active') {
            komorebic toggle-pause | Out-Null
            $pausedByUs = $true
        }
        Write-StreamLog "komorebi was $komorebi; paused by stream: $pausedByUs"

        # Save before changing anything so a failure below can still be undone.
        $session = [pscustomobject]@{
            komorebiPausedByStream = $pausedByUs
            displayLayout          = [ApolloStreamNative]::SaveLayout()
        }
        Write-Utf8File -Path $script:STREAM_STATE -Content ($session | ConvertTo-Json)

        if ([ApolloStreamNative]::UseOnlyVirtualDisplay()) {
            Write-StreamLog 'Switched to the virtual display only'
        } else {
            Write-StreamLog 'No active virtual display found; physical displays left on'
        }
    } catch {
        Write-StreamLog "Stream start failed: $_"
    }
}

function Invoke-StreamEnd {
    <#
    .SYNOPSIS
        Turns the physical displays back on in their saved layout and returns
        komorebi to the state it had before the stream.
    .DESCRIPTION
        The saved layout is applied without the virtual display, so the monitors
        are back before Apollo removes the virtual display. komorebi is only
        unpaused if -StreamStart paused it and it is still paused, after a short
        wait for windows to settle.
    #>
    if (-not (Test-Path $script:STREAM_STATE)) {
        Write-StreamLog 'No saved session; nothing to restore'
        return
    }

    $session = Get-Content -Path $script:STREAM_STATE -Raw | ConvertFrom-Json

    try {
        Initialize-NativeApi
        [ApolloStreamNative]::RestoreLayoutWithoutVirtual($session.displayLayout)
        Write-StreamLog 'Restored the physical display layout'
    } catch {
        Write-StreamLog "Display restore failed: $_"
    }

    try {
        if ($session.komorebiPausedByStream) {
            Start-Sleep -Seconds 2
            if ((Get-KomorebiState) -eq 'paused') {
                komorebic toggle-pause | Out-Null
                Write-StreamLog 'Unpaused komorebi'
            } else {
                Write-StreamLog 'komorebi is no longer paused or running; left as is'
            }
        }
    } catch {
        Write-StreamLog "komorebi restore failed: $_"
    }

    Remove-Item -Path $script:STREAM_STATE -Force -ErrorAction SilentlyContinue
}

function Start-StreamApp {
    <#
    .SYNOPSIS
        Starts the streamed app, or opens a new window if it is already running.
    .DESCRIPTION
        Outlook prefers classic Outlook (Microsoft 365) and falls back to the
        new Outlook app.
    .PARAMETER App
        Streamed app key (Teams, Outlook or Chrome).
    #>
    param([Parameter(Mandatory)][string]$App)

    switch ($App) {
        'Teams' {
            Start-Process -FilePath 'explorer.exe' -ArgumentList "shell:AppsFolder\$script:TEAMS_AUMID"
        }
        'Outlook' {
            $classic = Get-AppPath 'OUTLOOK.EXE'
            if ($classic) {
                Start-Process -FilePath $classic
            } else {
                Start-Process -FilePath 'explorer.exe' -ArgumentList "shell:AppsFolder\$script:NEW_OUTLOOK_AUMID"
            }
        }
        'Chrome' {
            $chrome = Get-AppPath 'chrome.exe'
            if (-not $chrome) { throw 'Google Chrome is not installed.' }
            Start-Process -FilePath $chrome
        }
    }
}

function Invoke-Launch {
    <#
    .SYNOPSIS
        Starts the app and maximizes its windows on the stream's display.
    .DESCRIPTION
        The virtual display is the only active display by now, so every window
        is already on it. Each window is maximized once when first seen, so
        un-maximizing one from the phone is left alone.
    #>
    Initialize-NativeApi
    Start-StreamApp -App $Launch
    Write-StreamLog "Started $Launch"

    $names = $script:APP_PROCESSES[$Launch]
    $handled = @{}
    $focused = $false
    $deadline = (Get-Date).AddSeconds($WindowWaitSeconds)

    do {
        $pids = @(Get-Process -Name $names -ErrorAction SilentlyContinue | ForEach-Object { [uint32]$_.Id })
        if ($pids.Count -gt 0) {
            foreach ($hWnd in [ApolloStreamNative]::GetAppWindows([uint32[]]$pids)) {
                $key = $hWnd.ToInt64()
                if ($handled.ContainsKey($key)) { continue }
                [ApolloStreamNative]::Maximize($hWnd)
                $handled[$key] = $true
                if (-not $focused) {
                    [ApolloStreamNative]::Focus($hWnd)
                    $focused = $true
                }
            }
        }
        Start-Sleep -Seconds 1
    } while ((Get-Date) -lt $deadline)
}

switch ($script:MODE) {
    'Launch'      { Invoke-Launch }
    'StreamStart' { Invoke-StreamStart }
    'StreamEnd'   { Invoke-StreamEnd }
    default       { Invoke-Setup }
}
