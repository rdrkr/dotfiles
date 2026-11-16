#Requires -Version 5.1
<#
.SYNOPSIS
    Moves a Logitech mouse to another Easy-Switch host (Windows side).

.DESCRIPTION
    The desk keyboard (Keychron K2) talks to the Dell or the MacBook, one at a
    time, and the Logitech MX Master 4 should follow it. Only the machine that
    still holds the mouse can tell it to move, so the machine the keyboard just
    LEFT runs this on that edge (keyboard-display-watch.ps1 beside this script;
    on the Mac, switchbot's display/desk_keyboard.sh runs the twin helper
    scripts/mouse-host, built from scripts/mouse_host.swift).

    Protocol: HID++ 2.0 over the mouse's direct Bluetooth link. The mouse
    exposes a vendor collection (usage page 0xFF43, usage 0x0202) that takes
    20-byte "long" reports, ID 0x11:

        [0x11, deviceIndex 0xFF, featureIndex, function << 4 | softwareID, params...]

    CHANGE_HOST (0x1814) is looked up through the root feature (index 0,
    getFeature); its function 0 (getHostInfo) answers [hostCount, currentHost]
    and function 1 (setCurrentHost) takes a 0-based host, after which the mouse
    drops this link and reconnects to that host, so it gets no reply.

.PARAMETER Command
    'status' prints the mouse's host slots; 'switch' moves it to Slot.

.PARAMETER Slot
    Target slot for 'switch', 1-3 as printed on the mouse.

.PARAMETER Match
    Case-insensitive substring of the HID product name.

.OUTPUTS
    One line of text. Exit code 0 done (or already on Slot), 2 no such mouse
    connected to this machine, 1 any other failure.

.EXAMPLE
    .\mouse-host.ps1 status
.EXAMPLE
    .\mouse-host.ps1 switch 1
#>
param(
    [Parameter(Position = 0)][ValidateSet('status', 'switch')][string]$Command = 'status',
    [Parameter(Position = 1)][int]$Slot = 0,
    [string]$Match = 'MX Master'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# The type survives in the session, so a watcher calling this repeatedly
# compiles it only once (Add-Type cannot redefine a type).
if (-not ('MouseHost.Hidpp' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading.Tasks;
using Microsoft.Win32.SafeHandles;

namespace MouseHost
{
    /// <summary>Win32 HID and SetupAPI declarations used by <see cref="Hidpp"/>.</summary>
    internal static class Native
    {
        /// <summary>SetupDiGetClassDevs flag: only devices currently present.</summary>
        public const uint DIGCF_PRESENT = 0x02;
        /// <summary>SetupDiGetClassDevs flag: enumerate device interfaces.</summary>
        public const uint DIGCF_DEVICEINTERFACE = 0x10;
        /// <summary>CreateFile access: read.</summary>
        public const uint GENERIC_READ = 0x80000000;
        /// <summary>CreateFile access: write.</summary>
        public const uint GENERIC_WRITE = 0x40000000;
        /// <summary>CreateFile sharing: others may read and write too.</summary>
        public const uint FILE_SHARE_READ_WRITE = 0x3;
        /// <summary>CreateFile disposition: open an existing device.</summary>
        public const uint OPEN_EXISTING = 3;
        /// <summary>CreateFile flag: overlapped I/O, needed for timed reads.</summary>
        public const uint FILE_FLAG_OVERLAPPED = 0x40000000;

        /// <summary>SP_DEVICE_INTERFACE_DATA.</summary>
        [StructLayout(LayoutKind.Sequential)]
        public struct DeviceInterfaceData
        {
            /// <summary>Size of this structure in bytes.</summary>
            public int Size;
            /// <summary>Interface class GUID.</summary>
            public Guid InterfaceClassGuid;
            /// <summary>Interface flags.</summary>
            public int Flags;
            /// <summary>Reserved.</summary>
            public IntPtr Reserved;
        }

        /// <summary>HIDD_ATTRIBUTES.</summary>
        [StructLayout(LayoutKind.Sequential)]
        public struct HidAttributes
        {
            /// <summary>Size of this structure in bytes.</summary>
            public int Size;
            /// <summary>USB/Bluetooth vendor ID.</summary>
            public ushort VendorID;
            /// <summary>Product ID.</summary>
            public ushort ProductID;
            /// <summary>Version number.</summary>
            public ushort VersionNumber;
        }

        /// <summary>HIDP_CAPS.</summary>
        [StructLayout(LayoutKind.Sequential)]
        public struct HidCaps
        {
            /// <summary>Top-level collection usage.</summary>
            public ushort Usage;
            /// <summary>Top-level collection usage page.</summary>
            public ushort UsagePage;
            /// <summary>Input report length, report ID included.</summary>
            public ushort InputReportByteLength;
            /// <summary>Output report length, report ID included.</summary>
            public ushort OutputReportByteLength;
            /// <summary>Feature report length, report ID included.</summary>
            public ushort FeatureReportByteLength;
            /// <summary>Reserved.</summary>
            [MarshalAs(UnmanagedType.ByValArray, SizeConst = 17)]
            public ushort[] Reserved;
            /// <summary>Remaining capability counts, unused here.</summary>
            [MarshalAs(UnmanagedType.ByValArray, SizeConst = 10)]
            public ushort[] Counts;
        }

        /// <summary>Gets the HID device interface class GUID.</summary>
        [DllImport("hid.dll")]
        public static extern void HidD_GetHidGuid(out Guid guid);

        /// <summary>Reads a HID device's vendor and product IDs.</summary>
        [DllImport("hid.dll")]
        public static extern bool HidD_GetAttributes(SafeFileHandle device, ref HidAttributes attributes);

        /// <summary>Reads a HID device's product name (UTF-16).</summary>
        [DllImport("hid.dll")]
        public static extern bool HidD_GetProductString(SafeFileHandle device, byte[] buffer, int length);

        /// <summary>Gets a collection's preparsed report descriptor data.</summary>
        [DllImport("hid.dll")]
        public static extern bool HidD_GetPreparsedData(SafeFileHandle device, out IntPtr data);

        /// <summary>Frees data from HidD_GetPreparsedData.</summary>
        [DllImport("hid.dll")]
        public static extern bool HidD_FreePreparsedData(IntPtr data);

        /// <summary>Reads a collection's usage and report lengths.</summary>
        [DllImport("hid.dll")]
        public static extern int HidP_GetCaps(IntPtr data, ref HidCaps caps);

        /// <summary>Lists device interfaces of a class.</summary>
        [DllImport("setupapi.dll", SetLastError = true)]
        public static extern IntPtr SetupDiGetClassDevs(ref Guid guid, IntPtr enumerator, IntPtr parent, uint flags);

        /// <summary>Gets one interface from a SetupDiGetClassDevs list.</summary>
        [DllImport("setupapi.dll", SetLastError = true)]
        public static extern bool SetupDiEnumDeviceInterfaces(IntPtr set, IntPtr info, ref Guid guid, uint index, ref DeviceInterfaceData data);

        /// <summary>Gets an interface's device path.</summary>
        [DllImport("setupapi.dll", SetLastError = true, CharSet = CharSet.Unicode)]
        public static extern bool SetupDiGetDeviceInterfaceDetail(IntPtr set, ref DeviceInterfaceData data, IntPtr detail, int size, out int required, IntPtr info);

        /// <summary>Frees a SetupDiGetClassDevs list.</summary>
        [DllImport("setupapi.dll")]
        public static extern bool SetupDiDestroyDeviceInfoList(IntPtr set);

        /// <summary>Opens a device path.</summary>
        [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
        public static extern SafeFileHandle CreateFile(string path, uint access, uint share, IntPtr security, uint disposition, uint flags, IntPtr template);
    }

    /// <summary>Failure while talking HID++ to the mouse.</summary>
    public class HidppException : Exception
    {
        /// <summary>Creates the exception.</summary>
        /// <param name="message">What went wrong.</param>
        public HidppException(string message) : base(message) { }
    }

    /// <summary>One Logitech mouse's open HID++ long-report collection.</summary>
    public sealed class Hidpp : IDisposable
    {
        /// <summary>Logitech's vendor ID.</summary>
        const ushort LogitechVendorID = 0x046D;
        /// <summary>Usage page of the HID++ vendor collection on Bluetooth devices.</summary>
        const ushort HidppUsagePage = 0xFF43;
        /// <summary>Usage of the HID++ long-report collection.</summary>
        const ushort HidppLongUsage = 0x0202;
        /// <summary>Report ID of an HID++ long report.</summary>
        const byte LongReportID = 0x11;
        /// <summary>Length of an HID++ long report, report ID included.</summary>
        const int LongReportLength = 20;
        /// <summary>Device index addressing the device itself (direct link).</summary>
        const byte DirectDeviceIndex = 0xFF;
        /// <summary>Software ID tagging our requests (1-15).</summary>
        const byte SoftwareID = 0x0B;
        /// <summary>Feature index byte of HID++ 2.0 error replies.</summary>
        const byte ErrorFeatureIndex = 0xFF;
        /// <summary>HID++ 2.0 feature ID of CHANGE_HOST.</summary>
        public const ushort ChangeHostFeature = 0x1814;

        /// <summary>The HID product name, e.g. "MX Master 4".</summary>
        public string Name { get; private set; }

        /// <summary>Overlapped stream over the device handle.</summary>
        readonly FileStream stream;
        /// <summary>Input report length of the collection.</summary>
        readonly int inputLength;
        /// <summary>Output report length of the collection.</summary>
        readonly int outputLength;
        /// <summary>Read still outstanding from an earlier timed wait, if any.</summary>
        Task<int> pendingRead;
        /// <summary>Buffer the outstanding read fills.</summary>
        byte[] readBuffer;

        /// <summary>Wraps an already opened, verified HID++ collection.</summary>
        Hidpp(SafeFileHandle handle, string name, int inputLength, int outputLength)
        {
            Name = name;
            this.inputLength = inputLength;
            this.outputLength = outputLength;
            stream = new FileStream(handle, FileAccess.ReadWrite, 1, true);
        }

        /// <summary>Opens every connected Logitech HID++ long-report collection
        /// whose product name contains <paramref name="match"/>.</summary>
        /// <param name="match">Case-insensitive product-name substring.</param>
        /// <returns>The opened collections; the caller disposes them.</returns>
        public static List<Hidpp> Find(string match)
        {
            var found = new List<Hidpp>();
            Guid guid;
            Native.HidD_GetHidGuid(out guid);
            IntPtr set = Native.SetupDiGetClassDevs(ref guid, IntPtr.Zero, IntPtr.Zero, Native.DIGCF_PRESENT | Native.DIGCF_DEVICEINTERFACE);
            if (set == new IntPtr(-1)) return found;
            try
            {
                var data = new Native.DeviceInterfaceData();
                data.Size = Marshal.SizeOf(data);
                for (uint i = 0; Native.SetupDiEnumDeviceInterfaces(set, IntPtr.Zero, ref guid, i, ref data); i++)
                {
                    string path = DevicePath(set, ref data);
                    if (path == null) continue;
                    Hidpp device = TryOpen(path, match);
                    if (device != null) found.Add(device);
                }
            }
            finally
            {
                Native.SetupDiDestroyDeviceInfoList(set);
            }
            return found;
        }

        /// <summary>Reads one interface's device path.</summary>
        /// <returns>The path, or null if it cannot be read.</returns>
        static string DevicePath(IntPtr set, ref Native.DeviceInterfaceData data)
        {
            int required;
            Native.SetupDiGetDeviceInterfaceDetail(set, ref data, IntPtr.Zero, 0, out required, IntPtr.Zero);
            if (required <= 0) return null;
            IntPtr detail = Marshal.AllocHGlobal(required);
            try
            {
                // SP_DEVICE_INTERFACE_DETAIL_DATA_W.cbSize: 8 on 64-bit, 6 on 32-bit.
                Marshal.WriteInt32(detail, IntPtr.Size == 8 ? 8 : 6);
                if (!Native.SetupDiGetDeviceInterfaceDetail(set, ref data, detail, required, out required, IntPtr.Zero)) return null;
                return Marshal.PtrToStringUni(IntPtr.Add(detail, 4));
            }
            finally
            {
                Marshal.FreeHGlobal(detail);
            }
        }

        /// <summary>Opens <paramref name="path"/> if it is a Logitech HID++
        /// long-report collection named like <paramref name="match"/>.</summary>
        /// <returns>The opened collection, or null.</returns>
        static Hidpp TryOpen(string path, string match)
        {
            SafeFileHandle handle = Native.CreateFile(path, Native.GENERIC_READ | Native.GENERIC_WRITE,
                Native.FILE_SHARE_READ_WRITE, IntPtr.Zero, Native.OPEN_EXISTING, Native.FILE_FLAG_OVERLAPPED, IntPtr.Zero);
            if (handle.IsInvalid) return null;
            bool keep = false;
            try
            {
                var attributes = new Native.HidAttributes();
                attributes.Size = Marshal.SizeOf(attributes);
                if (!Native.HidD_GetAttributes(handle, ref attributes) || attributes.VendorID != LogitechVendorID) return null;

                IntPtr preparsed;
                if (!Native.HidD_GetPreparsedData(handle, out preparsed)) return null;
                var caps = new Native.HidCaps();
                try { Native.HidP_GetCaps(preparsed, ref caps); }
                finally { Native.HidD_FreePreparsedData(preparsed); }
                if (caps.UsagePage != HidppUsagePage || caps.Usage != HidppLongUsage) return null;

                var nameBuffer = new byte[256];
                string name = Native.HidD_GetProductString(handle, nameBuffer, nameBuffer.Length)
                    ? Encoding.Unicode.GetString(nameBuffer).TrimEnd('\0') : "unknown";
                if (name.IndexOf(match, StringComparison.OrdinalIgnoreCase) < 0) return null;

                keep = true;
                return new Hidpp(handle, name, caps.InputReportByteLength, caps.OutputReportByteLength);
            }
            finally
            {
                if (!keep) handle.Dispose();
            }
        }

        /// <summary>Sends one HID++ 2.0 request and, unless told not to, waits for its reply.</summary>
        /// <param name="feature">Feature index (0 is the root feature).</param>
        /// <param name="function">Function number within the feature (0-15).</param>
        /// <param name="parameters">Up to 16 parameter bytes; the rest are zero.</param>
        /// <param name="expectReply">False for requests the device cannot answer, such as setCurrentHost.</param>
        /// <param name="timeoutMs">Milliseconds to wait for the reply.</param>
        /// <returns>The reply's 16 parameter bytes (empty when no reply was expected).</returns>
        public byte[] Request(byte feature, byte function, byte[] parameters, bool expectReply = true, int timeoutMs = 1000)
        {
            byte functionByte = (byte)((function << 4) | SoftwareID);
            var report = new byte[Math.Max(outputLength, LongReportLength)];
            report[0] = LongReportID;
            report[1] = DirectDeviceIndex;
            report[2] = feature;
            report[3] = functionByte;
            if (parameters != null) Array.Copy(parameters, 0, report, 4, Math.Min(parameters.Length, LongReportLength - 4));

            // Drop replies to earlier requests still buffered, so they are not taken for this one.
            while (pendingRead != null && pendingRead.IsCompleted) TakeRead();

            try { stream.Write(report, 0, report.Length); }
            catch (IOException e) { throw new HidppException("cannot send to the mouse: " + e.Message); }
            if (!expectReply) return new byte[0];

            DateTime deadline = DateTime.UtcNow.AddMilliseconds(timeoutMs);
            while (true)
            {
                int remaining = (int)(deadline - DateTime.UtcNow).TotalMilliseconds;
                if (remaining <= 0) throw new HidppException("the mouse did not answer");
                if (pendingRead == null)
                {
                    readBuffer = new byte[Math.Max(inputLength, LongReportLength)];
                    pendingRead = stream.ReadAsync(readBuffer, 0, readBuffer.Length);
                }
                if (!pendingRead.Wait(remaining)) continue;
                byte[] reply = TakeRead();
                if (reply == null || reply.Length < LongReportLength || reply[0] != LongReportID || reply[1] != DirectDeviceIndex) continue;
                if (reply[2] == feature && reply[3] == functionByte)
                {
                    var result = new byte[LongReportLength - 4];
                    Array.Copy(reply, 4, result, 0, result.Length);
                    return result;
                }
                if (reply[2] == ErrorFeatureIndex && reply[3] == feature && reply[4] == functionByte)
                    throw new HidppException("the mouse returned HID++ error " + reply[5]);
                // Anything else is an unrelated notification (battery, buttons); keep waiting.
            }
        }

        /// <summary>Collects the completed outstanding read.</summary>
        /// <returns>The bytes read, or null if the read failed.</returns>
        byte[] TakeRead()
        {
            Task<int> read = pendingRead;
            pendingRead = null;
            try
            {
                int count = read.Result;
                var bytes = new byte[count];
                Array.Copy(readBuffer, bytes, count);
                return bytes;
            }
            catch (AggregateException)
            {
                return null;
            }
        }

        /// <summary>Looks up CHANGE_HOST's feature index through the root feature.</summary>
        /// <returns>The index to address CHANGE_HOST requests to.</returns>
        public byte ChangeHostIndex()
        {
            byte[] reply = Request(0x00, 0x0, new byte[] { (byte)(ChangeHostFeature >> 8), (byte)(ChangeHostFeature & 0xFF) });
            if (reply[0] == 0) throw new HidppException("the mouse does not support CHANGE_HOST (0x1814)");
            return reply[0];
        }

        /// <summary>Reads the mouse's host slots.</summary>
        /// <param name="index">CHANGE_HOST's feature index.</param>
        /// <returns>[slot count, current 0-based slot].</returns>
        public int[] HostInfo(byte index)
        {
            byte[] reply = Request(index, 0x0, null);
            return new int[] { reply[0], reply[1] };
        }

        /// <summary>Tells the mouse to reconnect to another host; it drops this link at once.</summary>
        /// <param name="index">CHANGE_HOST's feature index.</param>
        /// <param name="host">0-based target slot.</param>
        public void SetHost(byte index, int host)
        {
            Request(index, 0x1, new byte[] { (byte)host }, false);
        }

        /// <summary>Closes the device.</summary>
        public void Dispose()
        {
            try { stream.Dispose(); } catch (IOException) { }
        }
    }
}
'@
}

$mice = [MouseHost.Hidpp]::Find($Match)
if ($mice.Count -eq 0) {
    Write-Output "no Bluetooth mouse matching '$Match' is connected to this machine"
    exit 2
}
if ($Command -eq 'switch' -and $Slot -lt 1) {
    Write-Output 'switch needs a slot (1-3, as printed on the mouse)'
    $mice | ForEach-Object { $_.Dispose() }
    exit 1
}

$code = 1
$failure = $null
try {
    foreach ($mouse in $mice) {
        try {
            $index = $mouse.ChangeHostIndex()
            $info = $mouse.HostInfo($index)
            $count = $info[0]
            $current = $info[1]
            if ($Command -eq 'status') {
                Write-Output "$($mouse.Name): on slot $($current + 1) of $count"
            } elseif ($Slot -gt $count) {
                Write-Output "$($mouse.Name): slot $Slot out of range (it has $count)"
                $code = 1
                break
            } elseif ($Slot - 1 -eq $current) {
                Write-Output "$($mouse.Name): already on slot $Slot"
            } else {
                $mouse.SetHost($index, $Slot - 1)
                Write-Output "$($mouse.Name): slot $($current + 1) -> $Slot"
            }
            $code = 0
            break
        } catch {
            # Exceptions thrown inside .NET methods arrive wrapped by PowerShell.
            $inner = $_.Exception
            while ($inner.InnerException) { $inner = $inner.InnerException }
            $failure = "$($mouse.Name): $($inner.Message)"
        }
    }
} finally {
    $mice | ForEach-Object { $_.Dispose() }
}
if ($code -ne 0 -and $failure) { Write-Output $failure }
exit $code
