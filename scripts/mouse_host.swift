// mouse-host: move a Logitech mouse to another Easy-Switch host (macOS side).
//
// The desk keyboard (Keychron K2) talks to the Mac or the Dell, one at a time,
// and the Logitech MX Master 4 should follow it. Only the machine that still
// holds the mouse can tell it to move, so the machine the keyboard just LEFT
// runs this helper on that edge (switchbot: display/desk_keyboard.sh on the Mac,
// scripts/keyboard-display-watch.ps1 on the Dell, whose twin is
// scripts/mouse-host.ps1).
//
// Protocol: HID++ 2.0 over the mouse's direct Bluetooth link. The mouse exposes
// a vendor collection (usage page 0xFF43, usage 0x0202) that takes 20-byte
// "long" reports, ID 0x11:
//
//   [0x11, deviceIndex 0xFF, featureIndex, function << 4 | softwareID, params...]
//
// Feature indexes differ per model, so CHANGE_HOST (0x1814) is first looked up
// through the root feature (index 0, getFeature). CHANGE_HOST function 0
// (getHostInfo) answers [hostCount, currentHost]; function 1 (setCurrentHost)
// takes a 0-based host and makes the mouse drop this link and reconnect to that
// host, so it gets no reply.
//
// Usage:
//   mouse-host status [--match NAME]        print the mouse's host slots
//   mouse-host switch SLOT [--match NAME]   move it to SLOT (1-3, as on the mouse)
//
// --match is a case-insensitive substring of the HID product name
// (default "MX Master"). Exit codes: 0 done (or already on SLOT), 2 no such mouse
// connected to this Mac, 1 any other failure.
//
// Opening the HID device may need Input Monitoring for the calling process
// (System Settings > Privacy & Security > Input Monitoring).
//
// Build (the binary is committed beside this file, like keyboard-idle):
//   swiftc -O -swift-version 5 -o scripts/mouse-host scripts/mouse_host.swift

import Foundation
import IOKit.hid

/// Logitech's USB/Bluetooth vendor ID.
let logitechVendorID = 0x046D
/// Usage page of Logitech's HID++ vendor collection on Bluetooth devices.
let hidppUsagePage = 0xFF43
/// Usage of the HID++ "long report" collection within that page.
let hidppLongUsage = 0x0202
/// Report ID of an HID++ long report.
let hidppLongReportID: UInt8 = 0x11
/// Length of an HID++ long report, report ID included.
let hidppLongReportLength = 20
/// Device index addressing the device itself (direct link, no receiver).
let directDeviceIndex: UInt8 = 0xFF
/// Software ID tagging our requests, so replies can be told apart (1-15).
let softwareID: UInt8 = 0x0B
/// HID++ 2.0 feature ID of CHANGE_HOST.
let changeHostFeature: UInt16 = 0x1814
/// Feature index byte HID++ 2.0 uses for error replies.
let errorFeatureIndex: UInt8 = 0xFF

/// Exit code: done, or already on the requested slot.
let exitOK: Int32 = 0
/// Exit code: any failure other than a missing mouse.
let exitFailure: Int32 = 1
/// Exit code: no matching mouse is connected to this machine.
let exitNoMouse: Int32 = 2

/// Most recent input report from the open mouse, always starting with its
/// report ID. Written by `inputReportCallback`, consumed by `Mouse.request`.
var lastInputReport: [UInt8]?

/// IOKit input-report callback: stores the report in `lastInputReport`,
/// prefixing the report ID when IOKit delivered the payload without it.
let inputReportCallback: IOHIDReportCallback = { _, result, _, _, reportID, report, length in
  guard result == kIOReturnSuccess, length > 0 else { return }
  var bytes = Array(UnsafeBufferPointer(start: report, count: length))
  if reportID != 0, bytes.first != UInt8(truncatingIfNeeded: reportID) {
    bytes.insert(UInt8(truncatingIfNeeded: reportID), at: 0)
  }
  lastInputReport = bytes
}

/// Failures while talking HID++ to the mouse.
enum HIDPPError: Error, CustomStringConvertible {
  /// IOHIDDeviceOpen failed with this status.
  case open(IOReturn)
  /// IOHIDDeviceSetReport failed with this status.
  case send(IOReturn)
  /// No matching reply arrived in time.
  case timeout
  /// The device answered with an HID++ 2.0 error code.
  case device(UInt8)
  /// The device does not implement CHANGE_HOST.
  case unsupported

  /// Human-readable explanation, with a hint where one helps.
  var description: String {
    switch self {
    case .open(let status):
      let hint = status == kIOReturnNotPermitted
        ? " (grant Input Monitoring to the calling app in System Settings > Privacy & Security)" : ""
      return String(format: "cannot open the mouse: IOReturn 0x%08X", status) + hint
    case .send(let status):
      return String(format: "cannot send to the mouse: IOReturn 0x%08X", status)
    case .timeout:
      return "the mouse did not answer"
    case .device(let code):
      return "the mouse returned HID++ error \(code)"
    case .unsupported:
      return "the mouse does not support CHANGE_HOST (0x1814)"
    }
  }
}

/// One Logitech mouse's HID++ collection, opened for request/reply exchanges.
final class Mouse {
  /// The IOKit device for the HID++ collection.
  let device: IOHIDDevice
  /// The device's HID product name, e.g. "MX Master 4".
  let name: String
  /// Buffer IOKit fills with incoming input reports while the device is open.
  private let reportBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 64)

  /// Wraps an IOKit device; call `open()` before sending requests.
  /// - Parameter device: A device matching the HID++ long-report collection.
  init(device: IOHIDDevice) {
    self.device = device
    self.name = IOHIDDeviceGetProperty(device, kIOHIDProductKey as CFString) as? String ?? "unknown"
  }

  deinit {
    reportBuffer.deallocate()
  }

  /// Opens the device and starts delivering its input reports on this thread's run loop.
  /// - Throws: `HIDPPError.open` when IOKit refuses access.
  func open() throws {
    let status = IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeNone))
    guard status == kIOReturnSuccess else { throw HIDPPError.open(status) }
    IOHIDDeviceRegisterInputReportCallback(device, reportBuffer, 64, inputReportCallback, nil)
    IOHIDDeviceScheduleWithRunLoop(device, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
  }

  /// Stops report delivery and closes the device.
  func close() {
    IOHIDDeviceUnscheduleFromRunLoop(device, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
    IOHIDDeviceClose(device, IOOptionBits(kIOHIDOptionsTypeNone))
  }

  /// Sends one HID++ 2.0 request and, unless told not to, waits for its reply.
  /// - Parameters:
  ///   - feature: Feature index (0 is the root feature).
  ///   - function: Function number within the feature (0-15).
  ///   - params: Up to 16 parameter bytes; the rest are zero.
  ///   - expectReply: False for requests the device cannot answer, such as setCurrentHost.
  ///   - timeout: Seconds to wait for the reply.
  /// - Returns: The reply's 16 parameter bytes (empty when no reply was expected).
  /// - Throws: `HIDPPError` on a send failure, an error reply or a timeout.
  @discardableResult
  func request(feature: UInt8, function: UInt8, params: [UInt8] = [],
               expectReply: Bool = true, timeout: TimeInterval = 1.0) throws -> [UInt8] {
    let functionByte = (function << 4) | softwareID
    var report = [UInt8](repeating: 0, count: hidppLongReportLength)
    report[0] = hidppLongReportID
    report[1] = directDeviceIndex
    report[2] = feature
    report[3] = functionByte
    for (offset, byte) in params.prefix(hidppLongReportLength - 4).enumerated() {
      report[4 + offset] = byte
    }

    lastInputReport = nil
    let status = report.withUnsafeBufferPointer {
      IOHIDDeviceSetReport(device, kIOHIDReportTypeOutput, CFIndex(hidppLongReportID),
                           $0.baseAddress!, $0.count)
    }
    guard status == kIOReturnSuccess else { throw HIDPPError.send(status) }
    guard expectReply else { return [] }

    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
      CFRunLoopRunInMode(.defaultMode, 0.05, true)
      guard let reply = lastInputReport else { continue }
      lastInputReport = nil
      guard reply.count >= hidppLongReportLength, reply[0] == hidppLongReportID,
            reply[1] == directDeviceIndex else { continue }
      if reply[2] == feature, reply[3] == functionByte {
        return Array(reply[4..<hidppLongReportLength])
      }
      if reply[2] == errorFeatureIndex, reply[3] == feature, reply[4] == functionByte {
        throw HIDPPError.device(reply[5])
      }
      // Anything else is an unrelated notification (battery, buttons); keep waiting.
    }
    throw HIDPPError.timeout
  }

  /// Looks up the feature index of CHANGE_HOST through the root feature.
  /// - Returns: The index to address CHANGE_HOST requests to.
  /// - Throws: `HIDPPError.unsupported` when the mouse lacks the feature.
  func changeHostIndex() throws -> UInt8 {
    let reply = try request(feature: 0x00, function: 0x0,
                            params: [UInt8(changeHostFeature >> 8), UInt8(changeHostFeature & 0xFF)])
    guard reply[0] != 0 else { throw HIDPPError.unsupported }
    return reply[0]
  }

  /// Reads the mouse's host slots.
  /// - Parameter index: CHANGE_HOST's feature index.
  /// - Returns: The number of slots and the 0-based slot it is on now.
  func hostInfo(index: UInt8) throws -> (count: Int, current: Int) {
    let reply = try request(feature: index, function: 0x0)
    return (Int(reply[0]), Int(reply[1]))
  }

  /// Tells the mouse to reconnect to another host; it drops this link at once.
  /// - Parameters:
  ///   - index: CHANGE_HOST's feature index.
  ///   - host: 0-based target slot.
  func setHost(index: UInt8, host: Int) throws {
    try request(feature: index, function: 0x1, params: [UInt8(host)], expectReply: false)
    // Let the report leave before the process (and its open handle) goes away.
    CFRunLoopRunInMode(.defaultMode, 0.2, true)
  }
}

/// Finds the HID++ collections of connected Logitech Bluetooth devices whose
/// product name contains `match`.
/// - Parameter match: Case-insensitive product-name substring.
/// - Returns: Matching devices, wrapped but not yet opened.
func findMice(match: String) -> [Mouse] {
  let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
  let criteria: [String: Any] = [
    kIOHIDVendorIDKey: logitechVendorID,
    kIOHIDDeviceUsagePageKey: hidppUsagePage,
    kIOHIDDeviceUsageKey: hidppLongUsage,
  ]
  IOHIDManagerSetDeviceMatching(manager, criteria as CFDictionary)
  IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
  CFRunLoopRunInMode(.defaultMode, 0.1, true)
  defer { IOHIDManagerUnscheduleFromRunLoop(manager, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue) }

  guard let set = IOHIDManagerCopyDevices(manager) else { return [] }
  let count = CFSetGetCount(set)
  var values = [UnsafeRawPointer?](repeating: nil, count: count)
  CFSetGetValues(set, &values)
  return values.compactMap { $0 }
    .map { Mouse(device: unsafeBitCast($0, to: IOHIDDevice.self)) }
    .filter { $0.name.localizedCaseInsensitiveContains(match) }
}

/// Prints a line to standard error.
/// - Parameter message: The text to print.
func printError(_ message: String) {
  FileHandle.standardError.write((message + "\n").data(using: .utf8)!)
}

/// Prints usage and returns the failure exit code.
func usage() -> Int32 {
  printError("usage: mouse-host status [--match NAME]\n       mouse-host switch SLOT [--match NAME]")
  return exitFailure
}

/// Parses the command line, runs the command and returns the exit code.
func run() -> Int32 {
  var args = Array(CommandLine.arguments.dropFirst())
  var match = "MX Master"
  if let flag = args.firstIndex(of: "--match") {
    guard flag + 1 < args.count else { return usage() }
    match = args[flag + 1]
    args.removeSubrange(flag...(flag + 1))
  }
  guard let command = args.first, ["status", "switch"].contains(command) else { return usage() }
  var target: Int?
  if command == "switch" {
    guard args.count == 2, let slot = Int(args[1]), slot >= 1 else { return usage() }
    target = slot - 1
  }

  let mice = findMice(match: match)
  guard !mice.isEmpty else {
    print("no Bluetooth mouse matching '\(match)' is connected to this Mac")
    return exitNoMouse
  }

  var lastError: Error = HIDPPError.unsupported
  for mouse in mice {
    do {
      try mouse.open()
      defer { mouse.close() }
      let index = try mouse.changeHostIndex()
      let info = try mouse.hostInfo(index: index)
      guard let target else {
        print("\(mouse.name): on slot \(info.current + 1) of \(info.count)")
        return exitOK
      }
      guard target < info.count else {
        printError("\(mouse.name): slot \(target + 1) out of range (it has \(info.count))")
        return exitFailure
      }
      if target == info.current {
        print("\(mouse.name): already on slot \(target + 1)")
        return exitOK
      }
      try mouse.setHost(index: index, host: target)
      print("\(mouse.name): slot \(info.current + 1) -> \(target + 1)")
      return exitOK
    } catch {
      lastError = error
    }
  }
  printError("\(mice[0].name): \(lastError)")
  return exitFailure
}

exit(run())
