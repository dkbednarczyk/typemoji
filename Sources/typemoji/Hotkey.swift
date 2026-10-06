import Carbon.HIToolbox

/// The global ⌃⌥⌘E killswitch. Uses a Carbon hot key so it works even while
/// the event tap is disabled or the Accessibility permission is missing.
@MainActor
enum Hotkey {
  private static var action: (() -> Void)?
  private static var reference: EventHotKeyRef?

  static func register(action: @escaping () -> Void) {
    self.action = action

    var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
    InstallEventHandler(
      GetApplicationEventTarget(),
      { _, _, _ in
        MainActor.assumeIsolated { Hotkey.action?() }
        return noErr
      }, 1, &spec, nil, nil)

    let id = EventHotKeyID(signature: 0x746D_6F6A, id: 1)
    RegisterEventHotKey(
      UInt32(kVK_ANSI_E), UInt32(controlKey | optionKey | cmdKey), id, GetApplicationEventTarget(), 0,
      &reference)
  }
}
