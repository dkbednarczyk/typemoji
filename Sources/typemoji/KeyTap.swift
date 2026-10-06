import CoreGraphics
import TypemojiCore

/// Observes key presses and mouse clicks through a `CGEventTap`, and types
/// replacements back as synthetic key events.
@MainActor
final class KeyTap {
  /// Marks events posted by this app so the tap does not process them again.
  private nonisolated static let syntheticMarker: Int64 = 0x746D_6F6A

  private nonisolated static let tabKey: Int64 = 48
  private nonisolated static let downArrowKey: Int64 = 125
  private nonisolated static let upArrowKey: Int64 = 126
  private nonisolated static let backspaceKey: CGKeyCode = 51
  /// Longest string that a single keyboard event carries reliably.
  private nonisolated static let maxUnitsPerEvent = 20

  fileprivate static var current: KeyTap?

  private let handler: (Engine.Input) -> Engine.Output
  private var port: CFMachPort?

  var isRunning: Bool { port != nil }

  var isEnabled = true {
    didSet { applyEnabled() }
  }

  init(handler: @escaping (Engine.Input) -> Engine.Output) {
    self.handler = handler
  }

  /// Returns false until the Accessibility permission has been granted.
  func start() -> Bool {
    guard port == nil else { return true }
    let types: [CGEventType] = [.keyDown, .leftMouseDown, .rightMouseDown, .otherMouseDown]
    let mask = types.reduce(CGEventMask(0)) { $0 | (1 << CGEventMask($1.rawValue)) }
    guard
      let port = CGEvent.tapCreate(
        tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
        eventsOfInterest: mask, callback: tapCallback, userInfo: nil)
    else { return false }

    self.port = port
    Self.current = self
    CFRunLoopAddSource(CFRunLoopGetMain(), CFMachPortCreateRunLoopSource(nil, port, 0), .commonModes)
    applyEnabled()
    return true
  }

  fileprivate func applyEnabled() {
    guard let port else { return }
    CGEvent.tapEnable(tap: port, enable: isEnabled)
  }

  /// Returns true when the event should be swallowed.
  fileprivate func process(_ event: TappedEvent) -> Bool {
    var swallow = false
    for input in event.inputs {
      switch handler(input) {
      case .passThrough:
        break
      case .swallow:
        swallow = true
      case .replace(let backspaces, let text):
        post(backspaces: backspaces, text: text)
        swallow = true
      }
    }
    return swallow
  }

  private func post(backspaces: Int, text: String) {
    let source = CGEventSource(stateID: .combinedSessionState)
    for _ in 0..<backspaces {
      post(CGEvent(keyboardEventSource: source, virtualKey: Self.backspaceKey, keyDown: true))
      post(CGEvent(keyboardEventSource: source, virtualKey: Self.backspaceKey, keyDown: false))
    }

    // Split on character boundaries so an emoji sequence is never cut in half.
    var chunk: [UniChar] = []
    for character in text {
      let units = Array(String(character).utf16)
      if !chunk.isEmpty && chunk.count + units.count > Self.maxUnitsPerEvent {
        post(text: chunk, source: source)
        chunk = []
      }
      chunk += units
    }
    if !chunk.isEmpty {
      post(text: chunk, source: source)
    }
  }

  private func post(text units: [UniChar], source: CGEventSource?) {
    for keyDown in [true, false] {
      let event = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: keyDown)
      event?.keyboardSetUnicodeString(stringLength: units.count, unicodeString: units)
      post(event)
    }
  }

  private func post(_ event: CGEvent?) {
    guard let event else { return }
    // Modifiers still held from the user's own keystroke must not leak in.
    event.flags = []
    event.setIntegerValueField(.eventSourceUserData, value: Self.syntheticMarker)
    event.post(tap: .cgSessionEventTap)
  }

  /// The parts of a `CGEvent` the engine cares about.
  fileprivate struct TappedEvent: Sendable {
    var inputs: [Engine.Input]

    init?(type: CGEventType, event: CGEvent) {
      guard event.getIntegerValueField(.eventSourceUserData) != KeyTap.syntheticMarker else { return nil }
      guard type == .keyDown else {
        inputs = [.reset]
        return
      }

      let flags = event.flags
      let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
      if !flags.isDisjoint(with: [.maskCommand, .maskControl]) {
        inputs = [.reset]
      } else if keyCode == KeyTap.tabKey {
        inputs = [flags.isDisjoint(with: [.maskShift, .maskAlternate]) ? .tab : .reset]
      } else if keyCode == KeyTap.upArrowKey || keyCode == KeyTap.downArrowKey {
        let arrow: Engine.Input = keyCode == KeyTap.upArrowKey ? .arrowUp : .arrowDown
        inputs = [flags.isDisjoint(with: [.maskShift, .maskAlternate]) ? arrow : .reset]
      } else if keyCode == Int64(KeyTap.backspaceKey) {
        // ⌥⌫ deletes a whole word, which the engine cannot step back through.
        inputs = [flags.contains(.maskAlternate) ? .reset : .backspace]
      } else {
        var length = 0
        var units = [UniChar](repeating: 0, count: 8)
        event.keyboardGetUnicodeString(
          maxStringLength: units.count, actualStringLength: &length, unicodeString: &units)
        let text = String(utf16CodeUnits: units, count: length)
        let isText = !text.isEmpty && text.unicodeScalars.allSatisfy(Self.isTypedText)
        inputs = isText ? text.map { .character($0) } : [.reset]
      }
    }

    /// False for arrows, function keys, Escape and other keys that do not insert text.
    private static func isTypedText(_ scalar: Unicode.Scalar) -> Bool {
      switch scalar.value {
      case 0x0A, 0x0D: true
      case 0x00..<0x20, 0x7F, 0xF700...0xF8FF: false
      default: true
      }
    }
  }
}

private func tapCallback(
  proxy: CGEventTapProxy, type: CGEventType, event: CGEvent, userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
  let tapped = KeyTap.TappedEvent(type: type, event: event)
  // The tap's source is on the main run loop, so this always runs on the main thread.
  let swallow = MainActor.assumeIsolated {
    guard let tap = KeyTap.current else { return false }
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
      tap.applyEnabled()
      return false
    }
    return tapped.map(tap.process) ?? false
  }
  return swallow ? nil : Unmanaged.passUnretained(event)
}
