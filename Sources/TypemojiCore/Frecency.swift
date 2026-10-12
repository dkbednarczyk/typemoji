import Foundation

/// One decaying usage score per emoji, keyed by the emoji without a skin tone.
public struct Frecency: Codable, Equatable, Sendable {
  public static let halfLife: TimeInterval = 30 * 24 * 60 * 60

  public struct Entry: Codable, Equatable, Sendable {
    public var score: Double
    public var updatedAt: Date
  }

  public private(set) var entries: [String: Entry]

  public init(entries: [String: Entry] = [:]) {
    self.entries = entries
  }

  // Stored as a plain `{ "😭": { ... } }` object so the file stays readable.
  public init(from decoder: Decoder) throws {
    entries = try decoder.singleValueContainer().decode([String: Entry].self)
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(entries)
  }

  public func score(for emoji: String, now: Date) -> Double {
    guard let entry = entries[emoji] else { return 0 }
    let elapsed = max(0, now.timeIntervalSince(entry.updatedAt))
    return entry.score * pow(0.5, elapsed / Self.halfLife)
  }

  public mutating func add(_ delta: Double, to emoji: String, now: Date) {
    entries[emoji] = Entry(score: score(for: emoji, now: now) + delta, updatedAt: now)
  }
}

extension EmojiDatabase {
  /// Names this short (`a`, `ok`, `no`) are also the prefixes typed most, so they are
  /// ranked like any other match. Winning outright would keep usage from ever teaching them.
  public static let shortNameLength = 2

  /// The emoji a partial code resolves to. An exact name longer than
  /// `shortNameLength` wins outright, then personal usage, then the popularity baseline.
  public func best(for code: String, frecency: Frecency, now: Date) -> Emoji? {
    ranked(for: code, frecency: frecency, now: now, limit: 1).first
  }

  /// Up to `limit` emoji for a partial code, most likely first.
  public func ranked(for code: String, frecency: Frecency, now: Date, limit: Int) -> [Emoji] {
    let exact = code.count > Self.shortNameLength ? exact(code) : nil
    let candidates = matches(prefix: code).filter { $0 != exact }.enumerated().map { offset, emoji in
      (
        emoji: emoji, score: frecency.score(for: emoji.emoji, now: now), rank: emoji.rank ?? .max,
        offset: offset
      )
    }
    let sorted = candidates.sorted { a, b in
      if a.score != b.score { return a.score > b.score }
      if a.rank != b.rank { return a.rank < b.rank }
      return a.offset < b.offset
    }
    return Array(([exact].compactMap { $0 } + sorted.map(\.emoji)).prefix(limit))
  }
}
