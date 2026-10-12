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

  /// Writes happen here so that a slow disk never holds up the event tap.
  private static let queue = DispatchQueue(label: "xyz.bednarczyk.typemoji.storage", qos: .utility)

  static func load<Value: Decodable>(_ type: Value.Type, from name: String) -> Value? {
    let url = directory.appendingPathComponent(name)
    guard let data = try? Data(contentsOf: url) else { return nil }
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    do {
      return try decoder.decode(type, from: data)
    } catch {
      // The defaults are saved over this file next, so keep the unreadable one to be fixed by hand.
      let backup = url.appendingPathExtension("bak")
      try? FileManager.default.removeItem(at: backup)
      try? FileManager.default.moveItem(at: url, to: backup)
      NSLog(
        "typemoji: ignoring unreadable %@, kept as %@: %@", name, backup.lastPathComponent,
        String(describing: error))
      return nil
    }
  }

  static func save<Value: Encodable>(_ value: Value, to name: String) {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    encoder.dateEncodingStrategy = .iso8601
    do {
      let data = try encoder.encode(value)
      queue.async {
        do {
          try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
          try data.write(to: directory.appendingPathComponent(name), options: .atomic)
        } catch {
          NSLog("typemoji: could not save %@: %@", name, String(describing: error))
        }
      }
    } catch {
      NSLog("typemoji: could not save %@: %@", name, String(describing: error))
    }
  }

  /// Waits for pending writes to reach the disk.
  static func flush() {
    queue.sync {}
  }
}
