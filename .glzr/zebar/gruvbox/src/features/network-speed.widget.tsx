import { GroupItem } from "@components/group.component";
import { createSignal, onCleanup, onMount } from "solid-js";
import { FaSolidArrowDown, FaSolidArrowUp } from "solid-icons/fa";
import * as zebar from "zebar";

/** How often to poll network stats, in milliseconds. */
const POLL_INTERVAL_MS = 3000;

/** SI unit thresholds for human-readable byte formatting. */
const SI_UNITS = [
  { threshold: 1e9, unit: "GB" },
  { threshold: 1e6, unit: "MB" },
  { threshold: 1e3, unit: "KB" },
] as const;

/**
 * Converts a bytes-per-second value into a human-readable SI string.
 * @param bytesPerSec - Raw speed in bytes per second.
 * @returns Formatted string like "1.5 MB/s".
 */
function formatSpeed(bytesPerSec: number): string {
  for (const { threshold, unit } of SI_UNITS) {
    if (bytesPerSec >= threshold) {
      return `${(bytesPerSec / threshold).toFixed(1)} ${unit}/s`;
    }
  }
  return `${bytesPerSec.toFixed(0)} B/s`;
}

/**
 * PowerShell command that sums BytesReceived and BytesSent across all
 * active (non-loopback) network interfaces via .NET, outputting a
 * single "received,sent" CSV line.
 */
const PS_NETWORK_CMD = [
  "-NoProfile",
  "-Command",
  `$r=0;$s=0;` +
    `[System.Net.NetworkInformation.NetworkInterface]::GetAllNetworkInterfaces()` +
    `|Where-Object{$_.OperationalStatus -eq 'Up' -and $_.NetworkInterfaceType -ne 'Loopback'}` +
    `|ForEach-Object{$t=$_.GetIPv4Statistics();$r+=$t.BytesReceived;$s+=$t.BytesSent};` +
    `"$r,$s"`,
];

/** Snapshot of cumulative byte counters at a point in time. */
interface ByteSnapshot {
  /** Total bytes received across all interfaces. */
  received: number;
  /** Total bytes sent across all interfaces. */
  sent: number;
  /** Timestamp in milliseconds when the snapshot was taken. */
  timestamp: number;
}

/**
 * Queries total received/sent bytes from all active network interfaces
 * via a PowerShell shell command.
 * @returns A byte snapshot, or null if the command fails.
 */
async function getByteCounters(): Promise<ByteSnapshot | null> {
  try {
    const result = await zebar.shellExec("powershell", PS_NETWORK_CMD);
    const parts = result.stdout.trim().split(",");
    if (parts.length !== 2) return null;
    const received = parseFloat(parts[0]!);
    const sent = parseFloat(parts[1]!);
    if (isNaN(received) || isNaN(sent)) return null;
    return { received, sent, timestamp: Date.now() };
  } catch (e) {
    console.error("[NetworkSpeedWidget] shellExec failed:", e);
    return null;
  }
}

/**
 * Displays current network download and upload speeds.
 * Polls system network counters via PowerShell as a workaround for the
 * broken zebar network provider (v3.1.1).
 */
export function NetworkSpeedWidget() {
  const [downloadSpeed, setDownloadSpeed] = createSignal(0);
  const [uploadSpeed, setUploadSpeed] = createSignal(0);

  let previous: ByteSnapshot | null = null;
  let timer: ReturnType<typeof setInterval> | undefined;

  /**
   * Fetches current byte counters and computes per-second speeds
   * from the delta since the last poll.
   */
  async function poll() {
    const current = await getByteCounters();
    if (!current) return;

    if (previous) {
      const elapsedSec = (current.timestamp - previous.timestamp) / 1000;
      if (elapsedSec > 0) {
        setDownloadSpeed(
          (current.received - previous.received) / elapsedSec,
        );
        setUploadSpeed((current.sent - previous.sent) / elapsedSec);
      }
    }

    previous = current;
  }

  onMount(() => {
    poll();
    timer = setInterval(poll, POLL_INTERVAL_MS);
  });

  onCleanup(() => {
    if (timer) clearInterval(timer);
  });

  return (
    <GroupItem class="flex items-center gap-2">
      <span class="flex items-center gap-1">
        <FaSolidArrowDown class="w-3 h-3 text-gruvbox-mint" />
        {formatSpeed(downloadSpeed())}
      </span>
      <span class="flex items-center gap-1">
        <FaSolidArrowUp class="w-3 h-3 text-gruvbox-peach" />
        {formatSpeed(uploadSpeed())}
      </span>
    </GroupItem>
  );
}
