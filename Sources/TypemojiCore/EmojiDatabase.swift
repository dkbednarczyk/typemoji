import Foundation

public struct Emoji: Codable, Equatable, Sendable {
  public var emoji: String
  public var names: [String]
  /// Light to dark, when the emoji supports skin tones.
  public var tones: [String]?
  /// Position in the built-in popularity baseline, lower is more popular.
  public var rank: Int?

  public init(emoji: String, names: [String], tones: [String]? = nil, rank: Int? = nil) {
    self.emoji = emoji
    self.names = names
    self.tones = tones
    self.rank = rank
  }

  /// The name a partial code is completing, for display.
  public func name(matching prefix: String) -> String {
    let prefix = prefix.lowercased()
    return names.first { $0 == prefix } ?? names.first { $0.hasPrefix(prefix) } ?? names.first ?? ""
  }

  public func rendered(with tone: SkinTone) -> String {
    guard let index = tone.variantIndex, let tones, tones.indices.contains(index) else { return emoji }
    return tones[index]
  }
}

public enum SkinTone: String, Codable, CaseIterable, Sendable {
  case yellow, light, mediumLight, medium, mediumDark, dark

  var variantIndex: Int? {
    switch self {
    case .yellow: nil
    case .light: 0
    case .mediumLight: 1
    case .medium: 2
    case .mediumDark: 3
    case .dark: 4
    }
  }
}

public struct EmojiDatabase: Sendable {
  public let entries: [Emoji]
  private let indexByName: [String: Int]

  public init(entries: [Emoji]) {
    self.entries = entries
    var indexByName: [String: Int] = [:]
    for (index, entry) in entries.enumerated() {
      for name in entry.names where indexByName[name] == nil {
        indexByName[name] = index
      }
    }
    self.indexByName = indexByName
  }

  /// Decodes the JSON written by `tools/generate-emoji.ts`.
  public init(json: Data) throws {
    self.init(entries: try JSONDecoder().decode([Emoji].self, from: json))
  }

  public func exact(_ name: String) -> Emoji? {
    indexByName[name.lowercased()].map { entries[$0] }
  }

  /// Emoji with at least one name starting with `prefix`, in database order.
  public func matches(prefix: String) -> [Emoji] {
    let prefix = prefix.lowercased()
    guard !prefix.isEmpty else { return [] }
    return entries.filter { entry in entry.names.contains { $0.hasPrefix(prefix) } }
  }
}
