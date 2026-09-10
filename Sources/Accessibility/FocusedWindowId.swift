import AppKit
import ApplicationServices

// The app's focused window, as the id the WindowServer raises by.
//
// This is the exact pairing. The window and tab ids come from the app's own
// scripting, and this converts that same window to its id, so nothing has to be
// inferred from what is on screen. Element to id is the only direction with a
// call at all (there is no id to element lookup), and it needs no search and no
// cache.
//
// Private, so it rides through dlsym: an absent symbol has to leave the caller
// its fallback, where an undefined symbol reference would fail the dyld load and
// take the whole app with it.
private typealias GetWindowFn =
  @convention(c) (AXUIElement, UnsafeMutablePointer<CGWindowID>) -> AXError

private let applicationServicesPath =
  "/System/Library/Frameworks/ApplicationServices.framework/ApplicationServices"

private let axGetWindow: GetWindowFn? = {
  guard let handle = dlopen(applicationServicesPath, RTLD_LAZY),
    let symbol = dlsym(handle, "_AXUIElementGetWindow")
  else { return nil }
  return unsafeBitCast(symbol, to: GetWindowFn.self)
}()

// Reading another app's windows needs Accessibility, so this returns nil until
// that is granted, and the claw-back then activates the app the way it always
// did.
//
// There is deliberately no second source. Deriving the id from the on-screen
// window list looked like a graceful fallback and is not: it can name a
// different window from the one the app calls front (measured at 20588 against
// this call's 20587, with the app frontmost and active). A wrong id raises the
// wrong window with confidence, where no id degrades to activation.
func focusedWindowId(pid: pid_t) -> CGWindowID? {
  guard let axGetWindow else {
    counter(.windowIdUnavailable)
    return nil
  }
  guard AXIsProcessTrusted() else {
    counter(.accessibilityNotGranted)
    return nil
  }

  let app = AXUIElementCreateApplication(pid)
  // A beach-balling app must not stall the capture hook, which runs on every
  // prompt.
  AXUIElementSetMessagingTimeout(app, 0.5)

  var focused: CFTypeRef?
  guard
    AXUIElementCopyAttributeValue(app, kAXFocusedWindowAttribute as CFString, &focused)
      == .success,
    let value = focused, CFGetTypeID(value) == AXUIElementGetTypeID()
  else {
    counter(.windowIdUnavailable)
    return nil
  }

  var id = CGWindowID(0)
  guard axGetWindow(value as! AXUIElement, &id) == .success, id != 0 else {
    counter(.windowIdUnavailable)
    return nil
  }
  counter(.windowIdFromAccessibility)
  return id
}
