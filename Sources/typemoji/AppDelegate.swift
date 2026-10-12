import AppKit
import ServiceManagement
import TypemojiCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
  private static let settingsFile = "settings.json"
  private static let scoresFile = "scores.json"

  private var settings = Storage.load(Settings.self, from: AppDelegate.settingsFile) ?? Settings()
  private var engine: Engine!
  private var tap: KeyTap!
  private var statusItem: NSStatusItem!
  private var frontmost: NSRunningApplication?
  private var permissionTimer: Timer?
  private var idleTimer: Timer?
  private let suggestionPanel = SuggestionPanel()

  private var isExcluded: Bool {
    frontmost?.bundleIdentifier.map(settings.excludedBundleIDs.contains) ?? false
  }

  func applicationDidFinishLaunching(_ notification: Notification) {
    engine = Engine(
      database: loadDatabase(),
      frecency: Storage.load(Frecency.self, from: Self.scoresFile) ?? Frecency(),
      skinTone: settings.skinTone)
    // Write the defaults out on first launch so there is a file to edit.
    Storage.save(settings, to: Self.settingsFile)

    statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    statusItem.button?.image = NSImage(systemSymbolName: "face.smiling", accessibilityDescription: "typemoji")
    statusItem.menu = NSMenu()
    statusItem.menu?.delegate = self

    frontmost = NSWorkspace.shared.frontmostApplication
    NSWorkspace.shared.notificationCenter.addObserver(
      self, selector: #selector(applicationActivated),
      name: NSWorkspace.didActivateApplicationNotification, object: nil)

    tap = KeyTap { [unowned self] input in
      let output = engine.handle(input)
      if case .replace = output {
        Storage.save(engine.frecency, to: Self.scoresFile)
      }
      suggestionsChanged()
      return output
    }
    Hotkey.register { [unowned self] in toggleEnabled() }

    // "AXTrustedCheckOptionPrompt" is the value of kAXTrustedCheckOptionPrompt.
    AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
    if !tap.start() {
      permissionTimer = Timer.scheduledTimer(
        timeInterval: 2, target: self, selector: #selector(retryTap), userInfo: nil, repeats: true)
    }
    stateChanged()
  }

  func applicationWillTerminate(_ notification: Notification) {
    Storage.flush()
  }

  private func loadDatabase() -> EmojiDatabase {
    // The bundle script copies emoji.json into the app; the fallback keeps `swift run` working.
    let url =
      Bundle.main.url(forResource: "emoji", withExtension: "json")
      ?? URL(fileURLWithPath: "Resources/emoji.json")
    do {
      return try EmojiDatabase(json: Data(contentsOf: url))
    } catch {
      fatalError("typemoji: could not load \(url.path): \(error)")
    }
  }

  /// Applies the killswitch and exclusion state to the tap and the icon.
  private func stateChanged() {
    let active = settings.enabled && !isExcluded
    _ = engine.handle(.reset)
    suggestionsChanged()
    tap.isEnabled = active
    statusItem.button?.appearsDisabled = !active || !tap.isRunning
  }

  /// Shows or hides the popup to match the engine, and hides it again once the code goes idle.
  private func suggestionsChanged() {
    suggestionPanel.update(engine.suggestions, selection: engine.selection)
    idleTimer?.invalidate()
    idleTimer = nil
    if !engine.suggestions.isEmpty {
      idleTimer = Timer.scheduledTimer(
        timeInterval: Engine.idleTimeout + 0.1, target: self, selector: #selector(idleElapsed), userInfo: nil,
        repeats: false)
    }
  }

  @objc private func idleElapsed() {
    engine.expireIfIdle()
    suggestionsChanged()
  }

  private func saveSettings() {
    Storage.save(settings, to: Self.settingsFile)
    stateChanged()
  }

  @objc private func retryTap() {
    guard tap.start() else { return }
    permissionTimer?.invalidate()
    permissionTimer = nil
    stateChanged()
  }

  @objc private func applicationActivated(_ notification: Notification) {
    frontmost = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
    stateChanged()
  }

  // MARK: Menu

  func menuNeedsUpdate(_ menu: NSMenu) {
    menu.removeAllItems()

    if !tap.isRunning {
      menu.addItem(item("Grant Accessibility Access…", #selector(openAccessibilitySettings)))
      menu.addItem(.separator())
    }

    let enabled = item("Enabled", #selector(toggleEnabled), checked: settings.enabled)
    if Hotkey.isRegistered {
      enabled.keyEquivalent = Hotkey.character
      enabled.keyEquivalentModifierMask = [.control, .option, .command]
    }
    menu.addItem(enabled)

    if let bundleID = frontmost?.bundleIdentifier, bundleID != Bundle.main.bundleIdentifier {
      let name = frontmost?.localizedName ?? bundleID
      let exclude = item("Disable in \(name)", #selector(toggleExclusion), checked: isExcluded)
      exclude.representedObject = bundleID
      menu.addItem(exclude)
    }
    menu.addItem(.separator())

    let tones = NSMenu()
    for tone in SkinTone.allCases {
      let sample = Emoji(emoji: "👋", names: [], tones: ["👋🏻", "👋🏼", "👋🏽", "👋🏾", "👋🏿"]).rendered(with: tone)
      let toneItem = item(
        "\(sample) \(tone.title)", #selector(selectSkinTone), checked: tone == settings.skinTone)
      toneItem.representedObject = tone.rawValue
      tones.addItem(toneItem)
    }
    menu.addItem(submenu("Skin Tone", tones))

    let exclusions = NSMenu()
    for bundleID in settings.excludedBundleIDs {
      let remove = item("Remove \(Self.appName(for: bundleID))", #selector(toggleExclusion))
      remove.representedObject = bundleID
      exclusions.addItem(remove)
    }
    if settings.excludedBundleIDs.isEmpty {
      exclusions.addItem(NSMenuItem(title: "No Excluded Apps", action: nil, keyEquivalent: ""))
    }
    menu.addItem(submenu("Excluded Apps", exclusions))

    menu.addItem(
      item(
        "Launch at Login", #selector(toggleLaunchAtLogin), checked: SMAppService.mainApp.status == .enabled))
    menu.addItem(.separator())
    menu.addItem(
      NSMenuItem(title: "Quit typemoji", action: #selector(NSApplication.terminate), keyEquivalent: "q"))
  }

  private func item(_ title: String, _ action: Selector, checked: Bool = false) -> NSMenuItem {
    let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
    item.target = self
    item.state = checked ? .on : .off
    return item
  }

  private func submenu(_ title: String, _ menu: NSMenu) -> NSMenuItem {
    let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
    item.submenu = menu
    return item
  }

  private static func appName(for bundleID: String) -> String {
    guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
      return bundleID
    }
    return FileManager.default.displayName(atPath: url.path)
  }

  @objc private func toggleEnabled() {
    settings.enabled.toggle()
    saveSettings()
  }

  @objc private func toggleExclusion(_ sender: NSMenuItem) {
    guard let bundleID = sender.representedObject as? String else { return }
    if let index = settings.excludedBundleIDs.firstIndex(of: bundleID) {
      settings.excludedBundleIDs.remove(at: index)
    } else {
      settings.excludedBundleIDs.append(bundleID)
    }
    saveSettings()
  }

  @objc private func selectSkinTone(_ sender: NSMenuItem) {
    guard let tone = (sender.representedObject as? String).flatMap(SkinTone.init) else { return }
    settings.skinTone = tone
    engine.skinTone = tone
    saveSettings()
  }

  @objc private func toggleLaunchAtLogin() {
    do {
      if SMAppService.mainApp.status == .enabled {
        try SMAppService.mainApp.unregister()
      } else {
        try SMAppService.mainApp.register()
      }
    } catch {
      NSLog("typemoji: could not change launch at login: %@", String(describing: error))
      NSSound.beep()
    }
  }

  @objc private func openAccessibilitySettings() {
    NSWorkspace.shared.open(
      URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
  }
}

extension SkinTone {
  fileprivate var title: String {
    switch self {
    case .yellow: "Default"
    case .light: "Light"
    case .mediumLight: "Medium-Light"
    case .medium: "Medium"
    case .mediumDark: "Medium-Dark"
    case .dark: "Dark"
    }
  }
}
