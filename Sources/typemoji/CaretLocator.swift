import AppKit
import ApplicationServices

/// Finds the text caret of the focused app through the Accessibility API.
@MainActor
enum CaretLocator {
  /// Keeps an unresponsive app from stalling the popup.
  private static let timeout: Float = 0.15

  /// The caret in AppKit screen coordinates, or nil when the app does not expose it.
  static func caretRect() -> CGRect? {
    let system = AXUIElementCreateSystemWide()
    AXUIElementSetMessagingTimeout(system, timeout)

    var focused: CFTypeRef?
    guard
      AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
      let focused, CFGetTypeID(focused) == AXUIElementGetTypeID()
    else { return nil }
    let element = focused as! AXUIElement
    AXUIElementSetMessagingTimeout(element, timeout)

    var selection: CFTypeRef?
    guard
      AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &selection)
        == .success,
      let selection, CFGetTypeID(selection) == AXValueGetTypeID()
    else { return nil }
    var range = CFRange()
    AXValueGetValue(selection as! AXValue, .cfRange, &range)

    // Some apps only report bounds for a non-empty range, so fall back to the
    // character before the caret and use its trailing edge.
    var rect = bounds(of: CFRange(location: range.location, length: 0), in: element)
    if rect == nil, range.location > 0,
      let previous = bounds(of: CFRange(location: range.location - 1, length: 1), in: element)
    {
      rect = CGRect(x: previous.maxX, y: previous.minY, width: 0, height: previous.height)
    }
    guard let rect, let primary = NSScreen.screens.first else { return nil }

    // Accessibility uses a top-left origin on the primary screen; AppKit uses bottom-left.
    return CGRect(x: rect.minX, y: primary.frame.height - rect.maxY, width: rect.width, height: rect.height)
  }

  private static func bounds(of range: CFRange, in element: AXUIElement) -> CGRect? {
    var range = range
    guard let parameter = AXValueCreate(.cfRange, &range) else { return nil }
    var value: CFTypeRef?
    guard
      AXUIElementCopyParameterizedAttributeValue(
        element, kAXBoundsForRangeParameterizedAttribute as CFString, parameter, &value) == .success,
      let value, CFGetTypeID(value) == AXValueGetTypeID()
    else { return nil }
    var rect = CGRect.zero
    AXValueGetValue(value as! AXValue, .cgRect, &rect)
    // Apps without real support answer with an empty rect at the origin.
    return rect.height > 0 ? rect : nil
  }
}
