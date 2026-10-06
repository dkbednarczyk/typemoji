import Foundation

/// Tracks the code being typed and decides when to replace it with an emoji.
///
/// The engine only sees keystrokes, never the contents of the text field, so
/// anything that could move the caret or change the text disarms it.
public struct Engine: Sendable {
  public enum Input: Equatable, Sendable {
    case character(Character)
    case tab
    case backspace
    case arrowUp
    case arrowDown
    /// Navigation keys, shortcuts, mouse clicks, app switches.
    case reset
  }

  public enum Output: Equatable, Sendable {
    case passThrough
    /// Swallow the key and do nothing else.
    case swallow
    /// Swallow the key, send `backspaces` backspaces, then type `text`.
    case replace(backspaces: Int, text: String)
  }

  public static let idleTimeout: TimeInterval = 10
  public static let maxSuggestions = 5

  public struct Suggestion: Equatable, Sendable {
    /// The emoji as it would be typed, with the skin tone applied.
    public var emoji: String
    public var name: String
  }

  public var frecency: Frecency
  public var skinTone: SkinTone

  /// The top matches for the armed code, shown as a popup while there are any.
  public var suggestions: [Suggestion] {
    guard let code else { return [] }
    return candidates.map { Suggestion(emoji: $0.rendered(with: skinTone), name: $0.name(matching: code)) }
  }
  /// The suggestion Tab completes to. Always the first one until an arrow key moves it.
  public private(set) var selection = 0

  private let database: EmojiDatabase
  /// Ranked matches for `code`, refreshed whenever it changes.
  private var candidates: [Emoji] = []
  /// Characters typed after the opening colon, or nil when no code is armed.
  private var code: String?
  /// Whether each character typed since the last reset was whitespace, so that
  /// Backspace can step back to an earlier boundary. Only this shape is kept,
  /// never the characters themselves.
  private var shape: [Bool] = []
  /// False once `shape` has overflowed, so its first entry no longer follows the start of input.
  private var shapeStartsAtBoundary = true
  private var lastInput: Date?
  private var undo: Undo?

  private struct Undo: Sendable {
    var typed: String
    var emoji: String
    var rearm: Bool
  }

  private static let maxShapeLength = 256

  /// Whether a colon typed now would follow whitespace or the start of input.
  private var atBoundary: Bool { shape.last ?? shapeStartsAtBoundary }

  public init(database: EmojiDatabase, frecency: Frecency = Frecency(), skinTone: SkinTone = .yellow) {
    self.database = database
    self.frecency = frecency
    self.skinTone = skinTone
  }

  /// Drops the armed code once it has been idle for too long.
  public mutating func expireIfIdle(now: Date = Date()) {
    if code != nil, let lastInput, now.timeIntervalSince(lastInput) > Self.idleTimeout {
      code = nil
      candidates = []
    }
  }

  public mutating func handle(_ input: Input, now: Date = Date()) -> Output {
    let previousCode = code
    let output = process(input, now: now)
    if code != previousCode {
      candidates =
        code.map { database.ranked(for: $0, frecency: frecency, now: now, limit: Self.maxSuggestions) } ?? []
      selection = 0
    }
    return output
  }

  private mutating func process(_ input: Input, now: Date) -> Output {
    let undo = self.undo
    self.undo = nil

    expireIfIdle(now: now)
    lastInput = now

    switch input {
    case .reset:
      code = nil
      clearShape()
      return .passThrough

    case .arrowUp, .arrowDown:
      // The arrows only belong to typemoji while the popup is showing.
      guard !candidates.isEmpty else {
        code = nil
        clearShape()
        return .passThrough
      }
      let step = input == .arrowDown ? 1 : candidates.count - 1
      selection = (selection + step) % candidates.count
      return .swallow

    case .tab:
      if let code, candidates.indices.contains(selection) {
        let emoji = candidates[selection]
        return convert(to: emoji, typed: ":" + code, rearm: true, now: now)
      }
      code = nil
      push(isWhitespace: true)
      return .passThrough

    case .backspace:
      if let undo {
        // Take back the use that was counted, then subtract one more as the negative signal.
        frecency.add(-2, to: undo.emoji, now: now)
        code = undo.rearm ? String(undo.typed.dropFirst()) : nil
        for _ in undo.typed { push(isWhitespace: false) }
        return .replace(backspaces: 1, text: undo.typed)
      }
      if let code {
        self.code = code.isEmpty ? nil : String(code.dropLast())
      }
      // With nothing left to step back through, this deletes text from before
      // the last reset, or a selection. Either way what remains is unknown, and
      // it is treated as the start of input so that clearing a field by any
      // means (select all, ⌥⌫, ⌘⌫, a mouse selection) leaves the next code armable.
      if !shape.isEmpty {
        shape.removeLast()
      }
      return .passThrough

    case .character(let character):
      let wasAtBoundary = atBoundary
      push(isWhitespace: character.isWhitespace)
      guard let code else {
        if character == ":" && wasAtBoundary {
          self.code = ""
        }
        return .passThrough
      }
      if character == ":" {
        self.code = nil
        guard let emoji = database.exact(code) else { return .passThrough }
        // The closing colon is swallowed, so only the opening colon and name are deleted.
        return convert(to: emoji, typed: ":" + code + ":", backspaces: code.count + 1, rearm: false, now: now)
      }
      if Self.isNameCharacter(character), !code.isEmpty || character.isLetter {
        self.code = code + String(character)
        return .passThrough
      }
      self.code = nil
      return .passThrough
    }
  }

  private mutating func push(isWhitespace: Bool) {
    shape.append(isWhitespace)
    if shape.count > Self.maxShapeLength {
      shape.removeFirst()
      shapeStartsAtBoundary = false
    }
  }

  private mutating func clearShape() {
    shape.removeAll()
    shapeStartsAtBoundary = true
  }

  private mutating func convert(
    to emoji: Emoji, typed: String, backspaces: Int? = nil, rearm: Bool, now: Date
  ) -> Output {
    frecency.add(1, to: emoji.emoji, now: now)
    undo = Undo(typed: typed, emoji: emoji.emoji, rearm: rearm)
    code = nil
    clearShape()
    return .replace(backspaces: backspaces ?? typed.count, text: emoji.rendered(with: skinTone))
  }

  private static func isNameCharacter(_ character: Character) -> Bool {
    character.isASCII && (character.isLetter || character.isNumber || character == "_")
  }
}
