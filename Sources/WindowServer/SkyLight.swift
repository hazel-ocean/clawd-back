import CoreGraphics
import Foundation

// A full-screen window is its own Space, and nothing public carries focus across
// one: `open -b`, `set frontmost` and AXRaise all reorder windows inside a
// single app. `_SLPSSetFrontProcessWithOptions` fronts a window id, and the
// Space switch follows as a side effect.
//
// dlsym, not @_silgen_name, because an absent symbol has to close the gate. An
// undefined symbol reference is resolved by dyld at load, so a missing one kills
// the process before any code runs and takes notify and capture with it.
//
// Byte layout and call order are ported from AltTab:
//   src/macos/api-wrappers/SkyLight.framework.swift
//   src/switcher/state/Window.swift

typealias CGSConnectionID = UInt32
typealias CGSSpaceID = UInt64

private let skyLightPath = "/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight"
private let applicationServicesPath =
  "/System/Library/Frameworks/ApplicationServices.framework/ApplicationServices"

// Marks the switch user-initiated. 0x100 fronts all the app's windows, 0x400
// none.
private let slpsUserGenerated: UInt32 = 0x200

// 5 is the current Space, 6 the others.
private let cgsSpaceMaskAll = 7

private typealias GetProcessForPIDFn =
  @convention(c) (pid_t, UnsafeMutablePointer<ProcessSerialNumber>) -> OSStatus
private typealias SetFrontProcessFn =
  @convention(c) (UnsafeMutablePointer<ProcessSerialNumber>, CGWindowID, UInt32) -> CGError
private typealias PostEventRecordFn =
  @convention(c) (UnsafeMutablePointer<ProcessSerialNumber>, UnsafeMutablePointer<UInt8>) -> CGError
private typealias MainConnectionIDFn = @convention(c) () -> CGSConnectionID
private typealias CopySpacesForWindowsFn =
  @convention(c) (CGSConnectionID, Int, CFArray) -> Unmanaged<CFArray>?
private typealias CopyActiveMenuBarDisplayFn =
  @convention(c) (CGSConnectionID) -> Unmanaged<CFString>?
private typealias ManagedDisplayCurrentSpaceFn =
  @convention(c) (CGSConnectionID, CFString) -> CGSSpaceID
private typealias SpaceSetFrontPSNFn =
  @convention(c) (CGSConnectionID, CGSSpaceID, ProcessSerialNumber) -> CGError

// Optional as a group: without them the raise still lands, and the only cost is
// the origin Space remembering our app as its front (AltTab #4507).
private struct SpaceRepairSymbols {
  let mainConnectionID: MainConnectionIDFn
  let copySpacesForWindows: CopySpacesForWindowsFn
  let copyActiveMenuBarDisplay: CopyActiveMenuBarDisplayFn
  let managedDisplayCurrentSpace: ManagedDisplayCurrentSpaceFn
  let spaceSetFrontPSN: SpaceSetFrontPSNFn

  init?(_ handle: UnsafeMutableRawPointer) {
    guard
      let connection: MainConnectionIDFn = bind(handle, "SLSMainConnectionID"),
      let spaces: CopySpacesForWindowsFn = bind(handle, "SLSCopySpacesForWindows"),
      let display: CopyActiveMenuBarDisplayFn = bind(
        handle, "SLSCopyActiveMenuBarDisplayIdentifier"),
      let current: ManagedDisplayCurrentSpaceFn = bind(
        handle, "SLSManagedDisplayGetCurrentSpace"),
      let setFront: SpaceSetFrontPSNFn = bind(handle, "SLSSpaceSetFrontPSN")
    else { return nil }
    mainConnectionID = connection
    copySpacesForWindows = spaces
    copyActiveMenuBarDisplay = display
    managedDisplayCurrentSpace = current
    spaceSetFrontPSN = setFront
  }
}

// `load` is the gate. Nil sends every caller back to the shell plan.
struct SkyLight {
  fileprivate let getProcessForPID: GetProcessForPIDFn
  fileprivate let setFrontProcess: SetFrontProcessFn
  fileprivate let postEventRecord: PostEventRecordFn
  fileprivate let repair: SpaceRepairSymbols?

  static func load(
    forceEnabled: Bool,
    version: OperatingSystemVersion = ProcessInfo.processInfo.operatingSystemVersion
  ) -> SkyLight? {
    guard architectureSupported else {
      counter(.gateClosedByArchitecture)
      return nil
    }
    guard versionSupported(version, forceEnabled: forceEnabled) else {
      counter(.gateClosedByVersion)
      return nil
    }
    guard
      let sky = dlopen(skyLightPath, RTLD_LAZY),
      let services = dlopen(applicationServicesPath, RTLD_LAZY),
      let pidToPSN: GetProcessForPIDFn = bind(services, "GetProcessForPID"),
      let front: SetFrontProcessFn = bind(sky, "_SLPSSetFrontProcessWithOptions"),
      let post: PostEventRecordFn = bind(sky, "SLPSPostEventRecordTo")
    else {
      counter(.gateClosedByMissingSymbol)
      return nil
    }
    return SkyLight(
      getProcessForPID: pidToPSN, setFrontProcess: front, postEventRecord: post,
      repair: SpaceRepairSymbols(sky))
  }
}

// Compile-time on purpose: AltTab #5819 is an x86_64 ABI bug where a pointer
// lands in the wrong register, which no runtime check can dodge. Each slice
// decides for itself, so an x86_64 slice under Rosetta stays closed.
#if arch(arm64)
  let architectureSupported = true
#else
  let architectureSupported = false
#endif

// The rule is nothing older than three years, which on 2026-08-28 is Sonoma.
// Re-evaluate the rule, don't drift the constant.
let skyLightFloorMajorVersion = 14
// A "tested no further than this" tripwire, not protection against an interface
// change: these symbols have not moved since 10.12, and what churns is correct
// usage. Exclusive, so every macOS 26 release passes.
let skyLightCeilingMajorVersion = 27

func versionSupported(_ version: OperatingSystemVersion, forceEnabled: Bool) -> Bool {
  guard version.majorVersion >= skyLightFloorMajorVersion else { return false }
  return forceEnabled || version.majorVersion < skyLightCeilingMajorVersion
}

extension SkyLight {
  // Carbon's GetProcessForPID is marked unavailable to Swift, so it rides
  // through dlsym like the rest.
  func processSerialNumber(for pid: pid_t) -> ProcessSerialNumber? {
    var psn = ProcessSerialNumber()
    guard getProcessForPID(pid, &psn) == noErr else { return nil }
    return psn
  }

  // Passing a wid raises that window alone, not the app's whole stack.
  func front(_ psn: inout ProcessSerialNumber, window: CGWindowID) -> Bool {
    setFrontProcess(&psn, window, slpsUserGenerated) == .success
  }

  // No public API moves key focus across apps. Down with no up: the down alone
  // makes the window key, and without the up no control can ever be activated
  // wherever the point lands. The point aims far past any window's
  // bottom-right, because an app that sanitizes it falls back to (0, 0), which
  // is real content (AltTab #5381).
  func makeKey(_ psn: inout ProcessSerialNumber, window: CGWindowID) {
    var window = window
    var point = CGPoint(x: 300_000, y: 300_000)
    // The record is 0xf8 bytes. macOS 14.7.4+ reads past it in
    // CGSEncodeEventRecord and SIGABRTs on out-of-bounds heap garbage, which
    // takes the whole login session down, so allocate 0x100.
    var bytes = [UInt8](repeating: 0, count: 0x100)
    bytes[0x04] = 0xf8  // the record's own declared length
    bytes[0x3a] = 0x10  // undocumented; yabai and Hammerspoon set it
    withUnsafeBytes(of: &window) { bytes.replaceSubrange(0x3c..<0x40, with: $0) }
    withUnsafeBytes(of: &point) { bytes.replaceSubrange(0x20..<0x30, with: $0) }
    bytes[0x08] = 0x01  // kCGEventLeftMouseDown
    _ = postEventRecord(&psn, &bytes)
  }

  // Empty means the WindowServer has no answer, which is not the same as
  // elsewhere: repairing on an unknown target re-fronts the previous app on the
  // CURRENT Space and undoes the raise (AltTab #5586).
  func spaces(of window: CGWindowID) -> [CGSSpaceID] {
    guard let repair else { return [] }
    let cid = repair.mainConnectionID()
    let wids = [NSNumber(value: window)] as CFArray
    guard let raw = repair.copySpacesForWindows(cid, cgsSpaceMaskAll, wids) else { return [] }
    return (raw.takeRetainedValue() as? [NSNumber])?.map { $0.uint64Value } ?? []
  }

  func currentSpace() -> CGSSpaceID? {
    guard let repair else { return nil }
    let cid = repair.mainConnectionID()
    guard let display = repair.copyActiveMenuBarDisplay(cid) else { return nil }
    return repair.managedDisplayCurrentSpace(cid, display.takeRetainedValue())
  }

  // Fronting a window is global, so it clobbers the front process of every
  // Space where the app has windows, and they pop into view on re-entry
  // (AltTab #4507).
  func restoreFront(of space: CGSSpaceID, to pid: pid_t) {
    guard let repair, let psn = processSerialNumber(for: pid) else { return }
    _ = repair.spaceSetFrontPSN(repair.mainConnectionID(), space, psn)
  }
}

private func bind<T>(_ handle: UnsafeMutableRawPointer, _ symbol: String) -> T? {
  guard let address = dlsym(handle, symbol) else { return nil }
  return unsafeBitCast(address, to: T.self)
}
