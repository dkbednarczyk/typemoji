import Carbon.HIToolbox
import Foundation

/// The global ⌃⌥⌘E killswitch. Uses a Carbon hot key so it works even while
/// the event tap is disabled or the Accessibility permission is missing.
@MainActor
enum Hotkey {
  /// The key shown next to `Enabled` in the menu.
  static let character = "e"

  private static var action: (() -> Void)?
  private static var reference: EventHotKeyRef?

  /// False when another app already owns the combination.
  static var isRegistered: Bool { reference != nil }

  static func register(action: @escaping () -> Void) {
    self.action = action

    var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
    InstallEventHandler(
      GetApplicationEventTarget(),
      { _, _, _ in
        MainActor.assumeIsolated { Hotkey.action?() }
        return noErr
      }, 1, &spec, nil, nil)

    // Carbon hot keys are bound to a physical key, so follow the layout to keep it on the key that types E.
    DistributedNotificationCenter.default().addObserver(
      forName: Notification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String), object: nil,
      queue: .main
    ) { _ in
      MainActor.assumeIsolated { bind() }
    }
    bind()
  }

  private static func bind() {
    if let reference {
      UnregisterEventHotKey(reference)
    }
    reference = nil

    let id = EventHotKeyID(signature: 0x746D_6F6A, id: 1)
    let status = RegisterEventHotKey(
      keyCode(), UInt32(controlKey | optionKey | cmdKey), id, GetApplicationEventTarget(), 0, &reference)
    if status != noErr {
      NSLog("typemoji: could not register the hot key: %d", status)
    }
  }

  /// The key that types `character` in the current layout, or the QWERTY one when the layout has none.
  private static func keyCode() -> UInt32 {
    // Non-Latin input sources fall back to their Latin layout, as menu shortcuts do.
    guard
      let source = TISCopyCurrentASCIICapableKeyboardLayoutInputSource()?.takeRetainedValue(),
      let property = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData)
    else { return UInt32(kVK_ANSI_E) }
    let data = Unmanaged<CFData>.fromOpaque(property).takeUnretainedValue() as Data

    return data.withUnsafeBytes { bytes in
      guard let layout = bytes.bindMemory(to: UCKeyboardLayout.self).baseAddress else {
        return UInt32(kVK_ANSI_E)
      }
      // Layouts such as Dvorak – QWERTY ⌘ move the letters while Command is held, so try that first.
      for modifiers in [UInt32(cmdKey >> 8), 0] {
        for keyCode in UInt16(0)..<128 {
          var deadKeys: UInt32 = 0
          var length = 0
          var units = [UniChar](repeating: 0, count: 4)
          let status = UCKeyTranslate(
            layout, keyCode, UInt16(kUCKeyActionDown), modifiers, UInt32(LMGetKbdType()),
            OptionBits(kUCKeyTranslateNoDeadKeysMask), &deadKeys, units.count, &length, &units)
          if status == noErr, String(utf16CodeUnits: units, count: length).lowercased() == character {
            return UInt32(keyCode)
          }
        }
      }
      return UInt32(kVK_ANSI_E)
    }
  }
}
