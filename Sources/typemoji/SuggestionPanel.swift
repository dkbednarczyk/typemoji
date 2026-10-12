import AppKit
import TypemojiCore

/// The popup listing the top matches for the code being typed. It never takes
/// focus or mouse events; the engine drives it from the keyboard.
@MainActor
final class SuggestionPanel {
  private static let gap: CGFloat = 4
  private static let padding: CGFloat = 5

  private let panel: NSPanel
  private let background = NSVisualEffectView()
  private let stack = NSStackView()
  /// Where the caret was when the popup appeared. Kept while it stays open so it does not jump around.
  private var anchor: CGRect?
  private var isShown = false
  /// Counts appearances, so a caret lookup that outlives its popup is ignored.
  private var appearance = 0

  init() {
    panel = NSPanel(
      contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
    panel.level = .popUpMenu
    panel.isOpaque = false
    panel.backgroundColor = .clear
    panel.hasShadow = true
    panel.ignoresMouseEvents = true
    panel.hidesOnDeactivate = false
    panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]

    background.material = .menu
    background.state = .active
    background.wantsLayer = true
    background.layer?.cornerRadius = 8
    background.layer?.masksToBounds = true

    stack.orientation = .vertical
    stack.alignment = .leading
    stack.spacing = 1
    stack.translatesAutoresizingMaskIntoConstraints = false
    background.addSubview(stack)
    NSLayoutConstraint.activate([
      stack.leadingAnchor.constraint(equalTo: background.leadingAnchor, constant: Self.padding),
      stack.trailingAnchor.constraint(equalTo: background.trailingAnchor, constant: -Self.padding),
      stack.topAnchor.constraint(equalTo: background.topAnchor, constant: Self.padding),
      stack.bottomAnchor.constraint(equalTo: background.bottomAnchor, constant: -Self.padding),
    ])
    panel.contentView = background
  }

  /// Shows the suggestions, or hides the popup when there are none.
  func update(_ suggestions: [Engine.Suggestion], selection: Int) {
    guard !suggestions.isEmpty else {
      isShown = false
      anchor = nil
      panel.orderOut(nil)
      return
    }

    for row in stack.arrangedSubviews {
      row.removeFromSuperview()
    }
    for (index, suggestion) in suggestions.enumerated() {
      let row = SuggestionRow(suggestion, isSelected: index == selection)
      stack.addArrangedSubview(row)
      row.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
    }
    panel.setContentSize(background.fittingSize)

    if isShown {
      place()
      return
    }
    isShown = true
    appearance += 1
    let appearance = appearance
    Task { @MainActor in
      let caret = await CaretLocator.caretRect()
      guard self.isShown, self.appearance == appearance else { return }
      self.anchor = caret
      self.place()
      self.panel.orderFrontRegardless()
    }
  }

  private func place() {
    // Apps that do not expose their caret get the popup at the mouse pointer instead.
    let mouse = NSEvent.mouseLocation
    let anchor = anchor ?? CGRect(x: mouse.x, y: mouse.y - 16, width: 0, height: 16)
    let screen = NSScreen.screens.first { $0.frame.contains(CGPoint(x: anchor.midX, y: anchor.midY)) }
    let visible = (screen ?? NSScreen.main)?.visibleFrame ?? .infinite
    let size = panel.frame.size

    var origin = CGPoint(x: anchor.minX, y: anchor.minY - Self.gap - size.height)
    if origin.y < visible.minY {
      origin.y = anchor.maxY + Self.gap
    }
    origin.x = max(visible.minX, min(origin.x, visible.maxX - size.width))
    panel.setFrameOrigin(origin)
  }
}

private final class SuggestionRow: NSView {
  init(_ suggestion: Engine.Suggestion, isSelected: Bool) {
    super.init(frame: .zero)
    wantsLayer = true
    layer?.cornerRadius = 5
    layer?.backgroundColor = isSelected ? NSColor.selectedContentBackgroundColor.cgColor : nil

    let emoji = NSTextField(labelWithString: suggestion.emoji)
    emoji.font = .systemFont(ofSize: 16)
    let name = NSTextField(labelWithString: ":\(suggestion.name):")
    name.font = .systemFont(ofSize: 13)
    name.textColor = isSelected ? .alternateSelectedControlTextColor : .labelColor

    let content = NSStackView(views: [emoji, name])
    content.spacing = 6
    content.edgeInsets = NSEdgeInsets(top: 3, left: 6, bottom: 3, right: 10)
    content.translatesAutoresizingMaskIntoConstraints = false
    addSubview(content)
    NSLayoutConstraint.activate([
      content.leadingAnchor.constraint(equalTo: leadingAnchor),
      content.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor),
      content.topAnchor.constraint(equalTo: topAnchor),
      content.bottomAnchor.constraint(equalTo: bottomAnchor),
    ])
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }
}
