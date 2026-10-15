#Requires -Version 5.1
<#
.SYNOPSIS
    Sets up Apollo (a Sunshine fork) so Microsoft Teams, Outlook and Chrome can be
    streamed to Moonlight on a phone without logging out of the Windows session.
.DESCRIPTION
    Setup mode (the default, run as Administrator):
      1. Installs Apollo, Google Chrome, Microsoft Teams, Outlook and Tailscale
         with winget. With -WithVirtualDisplayDriver, it also installs the
         standalone Virtual Display Driver and the VC++ runtime it needs.
      2. Sets the Apollo web UI credentials if none are configured yet.
      3. Sets `dd_configuration_option = ensure_primary` in sunshine.conf. While a
         stream runs, Apollo's per-session virtual display becomes the primary
         display and the physical monitors stay on as secondary displays.
      4. Adds "Teams", "Outlook" and "Chrome" to apps.json. Each app gets its own
         virtual display that matches the client's resolution, and runs this
         script in launch mode as a detached command.
      5. Turns off sleep and hibernate on AC power so the PC stays reachable.
      6. Sets ApolloService to start automatically and restarts it.

    Launch mode (-Launch <App>, which Apollo invokes at stream start):
      Starts the app, or brings up a new window if it is already running. For
      the next -WindowWaitSeconds seconds, it moves every top-level window of
      the app onto the primary display, which is the stream's virtual display,
      and maximizes it. Windows that were open on a physical monitor follow the
      stream too. When the stream ends, Apollo removes the virtual display and
      Windows moves the windows back to the physical monitors.

    Apollo already ships its own virtual display driver (SudoVDA) and creates a
    display per stream, so the standalone Virtual Display Driver is optional.
    The standalone driver adds a permanent extra monitor that the cursor and
    windows can wander onto when you are not streaming, so it is opt-in.

    Safe to re-run: packages that are already installed are skipped, config
    keys are updated in place, and the three apps are replaced by name while
    other apps in apps.json are kept.
.PARAMETER Launch
    Launch mode: start the named app and move its windows onto the stream's
    virtual display. Apollo uses this; you don't need to run it by hand.
.PARAMETER WindowWaitSeconds
    Launch mode only: how long to keep moving newly appearing windows onto the
    virtual display. Covers splash screens and slow first starts.
.PARAMETER WithVirtualDisplayDriver
    Also install the standalone Virtual Display Driver (VirtualDrivers) and the
    Visual C++ runtime it depends on.
.PARAMETER WebUsername
    Apollo web UI username. If no credentials exist yet and this is omitted,
    the script prompts for it.
.PARAMETER WebPassword
    Apollo web UI password. If no credentials exist yet and this is omitted,
    the script prompts for it.
.PARAMETER ResetCredentials
    Replace existing Apollo web UI credentials instead of keeping them.
.PARAMETER DryRun
    Report what would be done without installing or changing anything.
.EXAMPLE
    .\setup-apollo-streaming.ps1
.EXAMPLE
    .\setup-apollo-streaming.ps1 -WithVirtualDisplayDriver -DryRun
.EXAMPLE
    .\setup-apollo-streaming.ps1 -Launch Teams
#>

[CmdletBinding(DefaultParameterSetName = 'Setup')]
param(
    [Parameter(ParameterSetName = 'Launch', Mandatory)]
    [ValidateSet('Teams', 'Outlook', 'Chrome')]
    [string]$Launch,

    [Parameter(ParameterSetName = 'Launch')]
    [ValidateRange(5, 600)]
    [int]$WindowWaitSeconds = 45,

    [Parameter(ParameterSetName = 'Setup')]
    [switch]$WithVirtualDisplayDriver,

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

# Absolute path of this script; Apollo runs it in launch mode from apps.json.
$script:SCRIPT_PATH        = $PSCommandPath

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
        Installs Apollo, the streamed apps, Tailscale and optionally the
        standalone Virtual Display Driver.
    .DESCRIPTION
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

    if ($WithVirtualDisplayDriver) {
        Install-WingetPackage -Id 'Microsoft.VCRedist.2015+.x64'
        Install-WingetPackage -Id 'VirtualDrivers.Virtual-Display-Driver'
    }
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

function New-StreamAppEntry {
    <#
    .SYNOPSIS
        Builds the apps.json entry for one streamed app.
    .DESCRIPTION
        The app runs this script in launch mode as a detached command, so the
        stream stays up after the launcher exits and ends only when the client
        quits it. "virtual-display" gives each session its own display sized
        to the client.
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

    $launcher = 'powershell.exe -NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass ' +
        "-File `"$script:SCRIPT_PATH`" -Launch $App"

    return [pscustomobject][ordered]@{
        'name'              = $App
        'uuid'              = $Uuid
        'detached'          = @($launcher)
        'virtual-display'   = $true
        'auto-detach'       = $true
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
    Write-Host "  2. In Moonlight on the phone, add this PC (by Tailscale IP when away from home)."
    Write-Host "  3. Enter the PIN Moonlight shows at $script:APOLLO_WEB_UI (PIN tab)."
    Write-Host "  4. In Moonlight settings, set touch mode to direct touch (not trackpad)."
    Write-Host "  5. Start Teams, Outlook or Chrome from the app list."
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
    # Make the stream's virtual display primary so new windows open on it,
    # while the physical monitors stay on as secondary displays.
    Set-ApolloConfigValue -Key 'dd_configuration_option' -Value 'ensure_primary'
    Update-ApolloApps
    Disable-SleepOnAC
    Restart-ApolloService
    Write-NextSteps
}

function Initialize-WindowApi {
    <#
    .SYNOPSIS
        Loads the Win32 helpers used to find and move app windows.
    #>
    if ('ApolloStreamWindow' -as [type]) { return }

    Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;

/// <summary>Finds top-level app windows and moves them onto the primary display.</summary>
public static class ApolloStreamWindow
{
    private delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);

    [StructLayout(LayoutKind.Sequential)]
    private struct RECT { public int Left, Top, Right, Bottom; }

    [StructLayout(LayoutKind.Sequential)]
    private struct POINT { public int X, Y; }

    [StructLayout(LayoutKind.Sequential)]
    private struct MONITORINFO
    {
        public int cbSize;
        public RECT rcMonitor;
        public RECT rcWork;
        public uint dwFlags;
    }

    [DllImport("user32.dll")] private static extern bool EnumWindows(EnumWindowsProc cb, IntPtr lParam);
    [DllImport("user32.dll")] private static extern bool IsWindowVisible(IntPtr hWnd);
    [DllImport("user32.dll")] private static extern IntPtr GetWindow(IntPtr hWnd, uint cmd);
    [DllImport("user32.dll")] private static extern int GetWindowTextLength(IntPtr hWnd);
    [DllImport("user32.dll")] private static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint pid);
    [DllImport("user32.dll")] private static extern int GetWindowLong(IntPtr hWnd, int index);
    [DllImport("user32.dll")] private static extern IntPtr MonitorFromWindow(IntPtr hWnd, uint flags);
    [DllImport("user32.dll")] private static extern IntPtr MonitorFromPoint(POINT pt, uint flags);
    [DllImport("user32.dll")] private static extern bool GetMonitorInfo(IntPtr hMonitor, ref MONITORINFO info);
    [DllImport("user32.dll")] private static extern bool ShowWindow(IntPtr hWnd, int cmd);
    [DllImport("user32.dll")] private static extern bool IsZoomed(IntPtr hWnd);
    [DllImport("user32.dll")] private static extern bool SetForegroundWindow(IntPtr hWnd);
    [DllImport("user32.dll")] private static extern bool SetWindowPos(IntPtr hWnd, IntPtr after, int x, int y, int cx, int cy, uint flags);
    [DllImport("user32.dll")] private static extern IntPtr SetThreadDpiAwarenessContext(IntPtr context);
    [DllImport("dwmapi.dll")] private static extern int DwmGetWindowAttribute(IntPtr hWnd, int attr, out int value, int size);

    private const uint GW_OWNER = 4;
    private const int GWL_EXSTYLE = -20;
    private const int WS_EX_TOOLWINDOW = 0x80;
    private const int DWMWA_CLOAKED = 14;
    private const uint MONITOR_DEFAULTTONEAREST = 2;
    private const uint MONITOR_DEFAULTTOPRIMARY = 1;
    private const int SW_RESTORE = 9;
    private const int SW_MAXIMIZE = 3;
    private const uint SWP_NOSIZE = 0x1, SWP_NOZORDER = 0x4, SWP_NOACTIVATE = 0x10;
    private static readonly IntPtr DPI_PER_MONITOR_AWARE_V2 = new IntPtr(-4);

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

    /// <summary>Returns true when most of the window is on the primary display.</summary>
    /// <param name="hWnd">Window handle.</param>
    public static bool IsOnPrimary(IntPtr hWnd)
    {
        var primary = MonitorFromPoint(new POINT(), MONITOR_DEFAULTTOPRIMARY);
        return MonitorFromWindow(hWnd, MONITOR_DEFAULTTONEAREST) == primary;
    }

    /// <summary>Returns true when the window is maximized.</summary>
    /// <param name="hWnd">Window handle.</param>
    public static bool IsMaximized(IntPtr hWnd)
    {
        return IsZoomed(hWnd);
    }

    /// <summary>
    /// Moves the window onto the primary display's work area and maximizes it
    /// there. The primary display is the stream's virtual display while
    /// Apollo streams with dd_configuration_option = ensure_primary.
    /// </summary>
    /// <param name="hWnd">Window handle.</param>
    public static void MoveToPrimaryMaximized(IntPtr hWnd)
    {
        var previous = SetThreadDpiAwarenessContext(DPI_PER_MONITOR_AWARE_V2);
        try
        {
            var info = new MONITORINFO { cbSize = Marshal.SizeOf(typeof(MONITORINFO)) };
            GetMonitorInfo(MonitorFromPoint(new POINT(), MONITOR_DEFAULTTOPRIMARY), ref info);

            // Restore first: a maximized window can't be moved to another monitor.
            ShowWindow(hWnd, SW_RESTORE);
            SetWindowPos(hWnd, IntPtr.Zero, info.rcWork.Left + 40, info.rcWork.Top + 40, 0, 0,
                SWP_NOSIZE | SWP_NOZORDER | SWP_NOACTIVATE);
            ShowWindow(hWnd, SW_MAXIMIZE);
        }
        finally
        {
            if (previous != IntPtr.Zero) SetThreadDpiAwarenessContext(previous);
        }
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
        Launch mode: starts the app and keeps its windows on the stream's
        virtual display for -WindowWaitSeconds seconds.
    .DESCRIPTION
        Each window is moved and maximized once. A window is moved again only
        if it leaves the primary display (e.g. an app restoring its saved
        position after its splash screen), so un-maximizing a window on
        the phone is left alone.
    #>
    Initialize-WindowApi
    Start-StreamApp -App $Launch

    $names = $script:APP_PROCESSES[$Launch]
    $handled = @{}
    $focused = $false
    $deadline = (Get-Date).AddSeconds($WindowWaitSeconds)

    do {
        $pids = @(Get-Process -Name $names -ErrorAction SilentlyContinue | ForEach-Object { [uint32]$_.Id })
        if ($pids.Count -gt 0) {
            foreach ($hWnd in [ApolloStreamWindow]::GetAppWindows([uint32[]]$pids)) {
                $key = $hWnd.ToInt64()
                $onPrimary = [ApolloStreamWindow]::IsOnPrimary($hWnd)
                $isNew = -not $handled.ContainsKey($key)

                # New windows get moved and maximized; known ones only if they left the stream.
                if (-not $onPrimary -or ($isNew -and -not [ApolloStreamWindow]::IsMaximized($hWnd))) {
                    [ApolloStreamWindow]::MoveToPrimaryMaximized($hWnd)
                }
                $handled[$key] = $true

                if (-not $focused) {
                    [ApolloStreamWindow]::Focus($hWnd)
                    $focused = $true
                }
            }
        }
        Start-Sleep -Seconds 1
    } while ((Get-Date) -lt $deadline)
}

if ($PSCmdlet.ParameterSetName -eq 'Launch') {
    Invoke-Launch
} else {
    Invoke-Setup
}
