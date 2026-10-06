import Foundation
import TypemojiCore

struct Settings: Codable {
  static let defaultExclusions = [
    // Both have their own `:code` autocomplete that would fight over Tab.
    "com.hnc.Discord",
    "com.hnc.DiscordPTB",
    "com.hnc.DiscordCanary",
    "com.tinyspeck.slackmacgap",
  ]

  var enabled = true
  var skinTone = SkinTone.yellow
  var excludedBundleIDs = Settings.defaultExclusions

  init() {}

  // Missing keys fall back to defaults so the file can be edited by hand.
  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? enabled
    skinTone = try container.decodeIfPresent(SkinTone.self, forKey: .skinTone) ?? skinTone
    excludedBundleIDs =
      try container.decodeIfPresent([String].self, forKey: .excludedBundleIDs) ?? excludedBundleIDs
  }
}

/// Readable JSON files in `~/Library/Application Support/typemoji/`.
enum Storage {
  static let directory = FileManager.default
    .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    .appendingPathComponent("typemoji", isDirectory: true)

  static func load<Value: Decodable>(_ type: Value.Type, from name: String) -> Value? {
    guard let data = try? Data(contentsOf: directory.appendingPathComponent(name)) else { return nil }
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    do {
      return try decoder.decode(type, from: data)
    } catch {
      NSLog("typemoji: ignoring unreadable %@: %@", name, String(describing: error))
      return nil
    }
  }

  static func save<Value: Encodable>(_ value: Value, to name: String) {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    encoder.dateEncodingStrategy = .iso8601
    do {
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
      try encoder.encode(value).write(to: directory.appendingPathComponent(name), options: .atomic)
    } catch {
      NSLog("typemoji: could not save %@: %@", name, String(describing: error))
    }
  }
}
