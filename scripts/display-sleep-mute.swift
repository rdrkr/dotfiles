//
//  display-sleep-mute.swift
//
//  Mutes the default audio output device when the display goes to sleep and
//  restores the previous state when it wakes.
//
//  Runs as a per-user LaunchAgent (see com.ronendruker.display-sleep-mute.plist).
//  macOS exposes no launchd hook for display sleep, so this has to be a
//  long-lived watcher. It polls CGDisplayIsAsleep once a second - a cheap
//  Mach call - after the event-driven alternatives were measured and rejected
//  on this machine (macOS 26, Apple Silicon):
//
//    * NSWorkspace screensDidSleep/screensDidWake - the obvious choice, but a
//      plain command-line tool is not registered with the window server and
//      receives NO NSWorkspace notifications at all, with or without an
//      NSApplication and .prohibited activation policy. Verified by observing
//      `forName: nil` across a full display sleep/wake cycle: nothing arrived.
//      Making this work would mean shipping a real .app bundle.
//    * IOPMConnection video-capability notifications - the API powerd clients
//      use, but IOPMConnection and the kIOPMCapability* constants are not
//      exported to Swift, so it would need a C bridging header.
//    * `pmset -g log --stream` "Display is turned off/on" - works, but means
//      parsing human-readable log text and skipping the backlog the stream
//      replays on connect.
//    * IORegistry display power state - the IODisplayWrangler node that older
//      recipes watch does not exist on Apple Silicon.
//
//  Audio goes through the CoreAudio HAL rather than `osascript`: muting via
//  kAudioDevicePropertyMute leaves the volume level untouched, so restoring is
//  just an unmute rather than a lossy round-trip through AppleScript's coarse
//  0-100 scale. Devices that expose no mute property fall back to zeroing the
//  volume scalar and putting the saved scalar back on wake.
//
//  Build:  swiftc -O display-sleep-mute.swift -o ~/.local/bin/display-sleep-mute
//

import CoreAudio
import CoreGraphics
import Foundation

// MARK: - Logging

/// Formatter for log line timestamps, in the local time zone.
let logDateFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
    return formatter
}()

/// Writes one timestamped line to stdout and flushes it.
///
/// launchd redirects stdout to the agent's log file, and stdout to a file is
/// block-buffered, so an unflushed line can sit invisible for hours in a
/// process that is idle most of the time.
///
/// - Parameter message: The text to log, without a trailing newline.
func log(_ message: String) {
    print("\(logDateFormatter.string(from: Date()))  \(message)")
    fflush(stdout)
}

// MARK: - CoreAudio access

/// Thin wrapper over the CoreAudio HAL properties this agent needs.
enum Audio {
    /// Address of the system-wide default output device.
    private static var defaultOutputDeviceAddress = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDefaultOutputDevice,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain)

    /// The device currently used for system audio output.
    ///
    /// - Returns: The device ID, or `nil` if the system has no output device.
    static func defaultOutputDevice() -> AudioDeviceID? {
        var deviceID = AudioDeviceID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &defaultOutputDeviceAddress, 0, nil, &size, &deviceID)
        guard status == noErr, deviceID != AudioDeviceID(kAudioObjectUnknown) else {
            return nil
        }
        return deviceID
    }

    /// The persistent unique identifier of a device.
    ///
    /// Device IDs are reassigned across unplug/replug and reboots; the UID is
    /// stable, so it is what gets persisted in the state file.
    ///
    /// - Parameter device: The device to identify.
    /// - Returns: The device UID, or `nil` if the device does not report one.
    static func uid(of device: AudioDeviceID) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceUID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        // The HAL hands back a +1 CFString here, hence takeRetainedValue().
        var uid: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let status = withUnsafeMutablePointer(to: &uid) {
            AudioObjectGetPropertyData(device, &address, 0, nil, &size, $0)
        }
        guard status == noErr, let value = uid?.takeRetainedValue() else { return nil }
        return value as String
    }

    /// Looks a device back up by the UID recorded in the state file.
    ///
    /// - Parameter uid: A UID previously returned by ``uid(of:)``.
    /// - Returns: The matching device ID, or `nil` if that device is gone.
    static func device(withUID uid: String) -> AudioDeviceID? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var size = UInt32(0)
        guard AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size) == noErr else {
            return nil
        }
        let count = Int(size) / MemoryLayout<AudioDeviceID>.size
        guard count > 0 else { return nil }
        var devices = [AudioDeviceID](repeating: AudioDeviceID(kAudioObjectUnknown), count: count)
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &devices) == noErr else {
            return nil
        }
        return devices.first { Audio.uid(of: $0) == uid }
    }

    /// Builds the address of an output-scope property on a given channel.
    ///
    /// - Parameters:
    ///   - selector: The CoreAudio property selector.
    ///   - channel: The channel element; 0 is the master/main element, and
    ///     1 and 2 are the left and right channels used as a fallback by
    ///     devices that implement no master element.
    /// - Returns: The property address to pass to the HAL.
    private static func outputAddress(
        _ selector: AudioObjectPropertySelector, channel: UInt32
    ) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeOutput,
            mElement: channel)
    }

    /// Channel elements to try, master first, then left and right.
    private static let channels: [UInt32] = [kAudioObjectPropertyElementMain, 1, 2]

    /// Whether the device's output is muted.
    ///
    /// - Parameter device: The device to query.
    /// - Returns: The mute state, or `nil` if the device has no mute property
    ///   (in which case the caller falls back to the volume scalar).
    static func isMuted(_ device: AudioDeviceID) -> Bool? {
        for channel in channels {
            var address = outputAddress(kAudioDevicePropertyMute, channel: channel)
            guard AudioObjectHasProperty(device, &address) else { continue }
            var muted = UInt32(0)
            var size = UInt32(MemoryLayout<UInt32>.size)
            guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &muted) == noErr else {
                continue
            }
            return muted != 0
        }
        return nil
    }

    /// Sets the mute state on every writable mute element of the device.
    ///
    /// - Parameters:
    ///   - muted: The state to apply.
    ///   - device: The device to change.
    /// - Returns: `true` if at least one element accepted the change.
    @discardableResult
    static func setMuted(_ muted: Bool, on device: AudioDeviceID) -> Bool {
        var applied = false
        for channel in channels {
            var address = outputAddress(kAudioDevicePropertyMute, channel: channel)
            guard AudioObjectHasProperty(device, &address) else { continue }
            var settable = DarwinBoolean(false)
            guard AudioObjectIsPropertySettable(device, &address, &settable) == noErr,
                  settable.boolValue else { continue }
            var value = UInt32(muted ? 1 : 0)
            let size = UInt32(MemoryLayout<UInt32>.size)
            if AudioObjectSetPropertyData(device, &address, 0, nil, size, &value) == noErr {
                applied = true
                // The master element covers the whole device; stop there so a
                // per-channel write does not undo a device-wide one.
                if channel == kAudioObjectPropertyElementMain { break }
            }
        }
        return applied
    }

    /// The device's output volume, on the HAL's 0.0-1.0 scalar scale.
    ///
    /// - Parameter device: The device to query.
    /// - Returns: The volume, or `nil` for devices with no software volume
    ///   control (for example most digital/HDMI outputs).
    static func volume(of device: AudioDeviceID) -> Float32? {
        for channel in channels {
            var address = outputAddress(kAudioDevicePropertyVolumeScalar, channel: channel)
            guard AudioObjectHasProperty(device, &address) else { continue }
            var volume = Float32(0)
            var size = UInt32(MemoryLayout<Float32>.size)
            guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &volume) == noErr else {
                continue
            }
            return volume
        }
        return nil
    }

    /// Sets the device's output volume on every writable volume element.
    ///
    /// - Parameters:
    ///   - volume: The target volume, 0.0-1.0.
    ///   - device: The device to change.
    /// - Returns: `true` if at least one element accepted the change.
    @discardableResult
    static func setVolume(_ volume: Float32, on device: AudioDeviceID) -> Bool {
        var applied = false
        for channel in channels {
            var address = outputAddress(kAudioDevicePropertyVolumeScalar, channel: channel)
            guard AudioObjectHasProperty(device, &address) else { continue }
            var settable = DarwinBoolean(false)
            guard AudioObjectIsPropertySettable(device, &address, &settable) == noErr,
                  settable.boolValue else { continue }
            var value = volume
            let size = UInt32(MemoryLayout<Float32>.size)
            if AudioObjectSetPropertyData(device, &address, 0, nil, size, &value) == noErr {
                applied = true
                if channel == kAudioObjectPropertyElementMain { break }
            }
        }
        return applied
    }
}

// MARK: - Persisted state

/// What the output device looked like before this agent muted it.
///
/// Persisted so that a crash, a relaunch by launchd, or a logout while the
/// display is asleep still leaves enough information to restore on wake.
struct MuteState: Codable {
    /// UID of the device that was muted.
    let deviceUID: String

    /// Whether the device reported a usable mute property.
    ///
    /// `false` means the agent muted by zeroing the volume instead, and must
    /// restore by writing ``volume`` back.
    let usedMuteProperty: Bool

    /// Output volume at the moment of muting, if the device reports one.
    let volume: Float32?
}

/// Reads and writes ``MuteState`` in Application Support.
enum StateStore {
    /// File backing the persisted state.
    static let url: URL = {
        let directory = FileManager.default
            .homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/display-sleep-mute", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("state.json")
    }()

    /// Loads the persisted state, if any.
    ///
    /// - Returns: The stored state, or `nil` when nothing is pending.
    static func load() -> MuteState? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(MuteState.self, from: data)
    }

    /// Persists the state, or clears it when `nil` is passed.
    ///
    /// - Parameter state: The state to store, or `nil` to remove the file.
    static func save(_ state: MuteState?) {
        guard let state else {
            try? FileManager.default.removeItem(at: url)
            return
        }
        if let data = try? JSONEncoder().encode(state) {
            try? data.write(to: url, options: .atomic)
        }
    }
}

// MARK: - Watcher

/// Ties display sleep and wake to the mute and restore actions.
final class DisplaySleepMuter {
    /// How often the display power state is sampled, in seconds.
    ///
    /// One second is imperceptible on wake and costs a single Mach call per
    /// tick, which is far cheaper than the process would be to wake up for
    /// anything else.
    private static let pollInterval: TimeInterval = 1.0

    /// State captured when the display went to sleep, `nil` when nothing is
    /// pending restore. Mirrored to disk through ``StateStore``.
    private var pending: MuteState?

    /// Display power state as of the last tick, used to spot transitions.
    private var displayWasAsleep = false

    /// Timer driving the poll; held so it stays scheduled.
    private var timer: Timer?

    /// Whether every display is currently asleep.
    ///
    /// - Returns: `true` while the screens are off.
    private var displayIsAsleep: Bool {
        CGDisplayIsAsleep(CGMainDisplayID()) != 0
    }

    /// Starts watching the display, and settles any state left behind by a
    /// previous run of the agent.
    func start() {
        displayWasAsleep = displayIsAsleep

        pending = StateStore.load()
        if pending != nil {
            if displayWasAsleep {
                log("startup: display asleep, keeping pending restore")
            } else {
                log("startup: found pending restore from a previous run")
                restore()
            }
        } else if displayWasAsleep {
            // Relaunched (crash, or a fresh install) while the screens were
            // already off: no transition will arrive to mute on, so mute now.
            log("startup: display already asleep")
            mute()
        }

        let timer = Timer(timeInterval: Self.pollInterval, repeats: true) { [weak self] _ in
            self?.tick()
        }
        // A generous tolerance lets the kernel coalesce these wakeups with
        // other timers instead of waking the CPU on its own account.
        timer.tolerance = Self.pollInterval / 2
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer

        log("watching for display sleep/wake (asleep=\(displayWasAsleep))")
    }

    /// Samples the display power state and acts on a transition.
    private func tick() {
        let asleep = displayIsAsleep
        guard asleep != displayWasAsleep else { return }
        displayWasAsleep = asleep
        if asleep {
            mute()
        } else {
            restore()
        }
    }

    /// Mutes the default output device and records how to undo it.
    ///
    /// Does nothing when the device is already muted, so that a manual mute is
    /// not mistaken for one of ours and unmuted on wake.
    private func mute() {
        guard let device = Audio.defaultOutputDevice(), let uid = Audio.uid(of: device) else {
            log("display slept: no default output device, nothing to mute")
            return
        }
        let volume = Audio.volume(of: device)

        if let muted = Audio.isMuted(device) {
            guard !muted else {
                log("display slept: already muted, leaving it alone")
                return
            }
            guard Audio.setMuted(true, on: device) else {
                log("display slept: mute property is not settable on \(uid)")
                return
            }
            pending = MuteState(deviceUID: uid, usedMuteProperty: true, volume: volume)
            StateStore.save(pending)
            log("display slept: muted \(uid) (volume \(describe(volume)))")
            return
        }

        // No mute property: fall back to zeroing the volume.
        guard let volume else {
            log("display slept: \(uid) has neither mute nor volume control")
            return
        }
        guard volume > 0 else {
            log("display slept: volume already 0, leaving it alone")
            return
        }
        guard Audio.setVolume(0, on: device) else {
            log("display slept: volume is not settable on \(uid)")
            return
        }
        pending = MuteState(deviceUID: uid, usedMuteProperty: false, volume: volume)
        StateStore.save(pending)
        log("display slept: zeroed volume on \(uid) (was \(describe(volume)))")
    }

    /// Puts back whatever ``mute()`` changed, if it still stands.
    ///
    /// A mute the user lifted by hand while the display was asleep is left
    /// alone, and so is a device that has since disappeared.
    private func restore() {
        guard let state = pending else { return }
        pending = nil
        StateStore.save(nil)

        guard let device = Audio.device(withUID: state.deviceUID) else {
            log("display woke: device \(state.deviceUID) is gone, nothing to restore")
            return
        }

        if state.usedMuteProperty {
            guard Audio.isMuted(device) == true else {
                log("display woke: \(state.deviceUID) was unmuted meanwhile, leaving it alone")
                return
            }
            Audio.setMuted(false, on: device)
            if let volume = state.volume, let now = Audio.volume(of: device), now != volume {
                Audio.setVolume(volume, on: device)
            }
            log("display woke: unmuted \(state.deviceUID) (volume \(describe(state.volume)))")
        } else {
            guard let volume = state.volume else { return }
            guard Audio.volume(of: device) == 0 else {
                log("display woke: volume on \(state.deviceUID) changed meanwhile, leaving it alone")
                return
            }
            Audio.setVolume(volume, on: device)
            log("display woke: restored volume \(describe(volume)) on \(state.deviceUID)")
        }
    }

    /// Renders an optional volume for a log line.
    ///
    /// - Parameter volume: The volume to describe, if the device reports one.
    /// - Returns: The volume as a percentage, or `"n/a"`.
    private func describe(_ volume: Float32?) -> String {
        guard let volume else { return "n/a" }
        return "\(Int((volume * 100).rounded()))%"
    }
}

let muter = DisplaySleepMuter()
muter.start()
RunLoop.main.run()
