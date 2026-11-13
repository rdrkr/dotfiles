#Requires -Version 5.1
<#
.SYNOPSIS
    Switches the Dell between "external monitor only" and "laptop screen only".

.DESCRIPTION
    The Windows half of the desk-keyboard rule. The Keychron pairs with the
    MacBook, whose display watcher (switchbot: display/ard_virtual_display.sh)
    switches its own monitor/built-in on every connect and disconnect. It then
    runs this script on the Dell over SSH so both machines follow the keyboard:

        keyboard connects    -> external   (external monitor on, laptop panel off)
        keyboard disconnects -> internal   (laptop panel on, external monitor off)

    It calls SetDisplayConfig with the SDC_TOPOLOGY_* flags: the same operation
    as Win+P's "Second screen only" / "PC screen only", without the flyout.
    Windows applies the arrangement it last stored for that topology, so the
    resolution and placement of each monitor survive the round trip.

    SSH reaches the Dell's WSL sshd, and WSL interop starts this through
    powershell.exe in the logged-in desktop session (session 1). A display
    change made from a service session would not reach the console.

.PARAMETER Mode
    external  Show the desktop on the external monitor(s) only.
    internal  Show the desktop on the laptop panel only.
    status    Print the current topology: internal, clone, extend or external.

.EXAMPLE
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File display-topology.ps1 external

.NOTES
    Exits 0 on success, 1 when Windows rejects the change (for example
    "external" with no external monitor attached), 2 on bad usage. Switching to
    the topology that is already active succeeds and changes nothing.
#>
param(
    [Parameter(Mandatory = $true, Position = 0)]
    [ValidateSet('external', 'internal', 'status')]
    [string]$Mode
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;

/// <summary>
/// Minimal user32 display-configuration interop: apply a topology preset and
/// read back the current one.
/// </summary>
public static class DisplayTopology
{
    /// <summary>SetDisplayConfig flag: apply the configuration now.</summary>
    public const uint SDC_APPLY = 0x00000080;
    /// <summary>Topology preset: laptop panel only ("PC screen only").</summary>
    public const uint SDC_TOPOLOGY_INTERNAL = 0x00000001;
    /// <summary>Topology preset: external monitor(s) only ("Second screen only").</summary>
    public const uint SDC_TOPOLOGY_EXTERNAL = 0x00000008;
    /// <summary>QueryDisplayConfig flag: report which topology preset is active.</summary>
    public const uint QDC_DATABASE_CURRENT = 0x00000004;

    /// <summary>Applies a display configuration; with null arrays, a topology preset.</summary>
    [DllImport("user32.dll")]
    public static extern int SetDisplayConfig(uint numPathArrayElements, IntPtr pathArray,
                                              uint numModeInfoArrayElements, IntPtr modeInfoArray,
                                              uint flags);

    /// <summary>Returns the buffer sizes QueryDisplayConfig needs for the given flags.</summary>
    [DllImport("user32.dll")]
    public static extern int GetDisplayConfigBufferSizes(uint flags, out uint numPathArrayElements,
                                                         out uint numModeInfoArrayElements);

    /// <summary>Reads the current configuration, including the active topology preset.</summary>
    [DllImport("user32.dll")]
    public static extern int QueryDisplayConfig(uint flags, ref uint numPathArrayElements, IntPtr pathArray,
                                                ref uint numModeInfoArrayElements, IntPtr modeInfoArray,
                                                out uint currentTopologyId);

    /// <summary>
    /// Returns the active topology id (1 internal, 2 clone, 4 extend, 8 external),
    /// or a negative Win32 error code.
    /// </summary>
    public static int Current()
    {
        uint paths, modes, topology;
        int err = GetDisplayConfigBufferSizes(QDC_DATABASE_CURRENT, out paths, out modes);
        if (err != 0) return -err;
        // DISPLAYCONFIG_PATH_INFO is 72 bytes and DISPLAYCONFIG_MODE_INFO 64; the
        // contents are not needed, only the topology id, so raw buffers will do.
        IntPtr pathBuf = Marshal.AllocHGlobal((int)Math.Max(1, paths) * 72);
        IntPtr modeBuf = Marshal.AllocHGlobal((int)Math.Max(1, modes) * 64);
        try
        {
            err = QueryDisplayConfig(QDC_DATABASE_CURRENT, ref paths, pathBuf, ref modes, modeBuf, out topology);
            return err != 0 ? -err : (int)topology;
        }
        finally
        {
            Marshal.FreeHGlobal(pathBuf);
            Marshal.FreeHGlobal(modeBuf);
        }
    }
}
'@

<#
.SYNOPSIS
    Names a topology id as returned by DisplayTopology::Current().
.PARAMETER Id
    The topology id, or a negative Win32 error code.
.OUTPUTS
    internal, clone, extend, external, or "error <code>".
#>
function Get-TopologyName([int]$Id) {
    switch ($Id) {
        1 { 'internal' }
        2 { 'clone' }
        4 { 'extend' }
        8 { 'external' }
        default { "error $(-$Id)" }
    }
}

$before = Get-TopologyName ([DisplayTopology]::Current())
if ($Mode -eq 'status') {
    $before
    exit 0
}

$flag = if ($Mode -eq 'external') { [DisplayTopology]::SDC_TOPOLOGY_EXTERNAL } else { [DisplayTopology]::SDC_TOPOLOGY_INTERNAL }
$err = [DisplayTopology]::SetDisplayConfig(0, [IntPtr]::Zero, 0, [IntPtr]::Zero, [DisplayTopology]::SDC_APPLY -bor $flag)
$after = Get-TopologyName ([DisplayTopology]::Current())

if ($err -ne 0) {
    # 31 (ERROR_GEN_FAILURE) / 1610 (ERROR_BAD_CONFIGURATION) is what "external"
    # returns with no external monitor attached.
    "$before -> $Mode failed (Win32 error $err); now $after"
    exit 1
}
"$before -> $after"
exit 0
