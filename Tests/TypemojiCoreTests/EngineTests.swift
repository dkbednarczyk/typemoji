import Foundation
import Testing

@testable import TypemojiCore

private let database = EmojiDatabase(entries: [
  Emoji(emoji: "😭", names: ["sob", "loudly_crying_face"], rank: 0),
  Emoji(emoji: "⚽", names: ["soccer"]),
  Emoji(emoji: "🧦", names: ["socks"]),
  Emoji(emoji: "🔥", names: ["fire", "flame"], rank: 1),
  Emoji(emoji: "🚒", names: ["fire_engine"]),
  Emoji(emoji: "👋", names: ["wave"], tones: ["👋🏻", "👋🏼", "👋🏽", "👋🏾", "👋🏿"]),
  Emoji(emoji: "🧑‍🦰", names: ["person_sob_test"]),
])

private let start = Date(timeIntervalSince1970: 1_000_000)

/// Feeds text to an engine, with `\t` as Tab and `\u{8}` as Backspace.
private struct Typist {
  var engine = Engine(database: database)
  var now = start

  @discardableResult
  mutating func type(_ text: String) -> [Engine.Output] {
    text.map { character in
      switch character {
      case "\t": engine.handle(.tab, now: now)
      case "\u{8}": engine.handle(.backspace, now: now)
      default: engine.handle(.character(character), now: now)
      }
    }
  }

  /// The last output for `text`.
  mutating func result(_ text: String) -> Engine.Output {
    type(text).last!
  }
}

@Suite struct Arming {
  @Test func tabCompletesPartialCode() {
    var typist = Typist()
    #expect(typist.result(":so\t") == .replace(backspaces: 3, text: "😭"))
  }

  @Test func tabPassesThroughWhenNothingIsArmed() {
    var typist = Typist()
    #expect(typist.result("so\t") == .passThrough)
    #expect(typist.result(":\t") == .passThrough)
    #expect(typist.result(":zzz\t") == .passThrough)
  }

  @Test(arguments: ["10:30\t", "https://so\t", "std::so\t", "key:so\t", ":1so\t", ": so\t"])
  func colonInsideTextDoesNotArm(text: String) {
    var typist = Typist()
    #expect(typist.type(text).allSatisfy { $0 == .passThrough })
  }

  @Test func colonAfterWhitespaceArms() {
    var typist = Typist()
    #expect(typist.result("hello :so\t") == .replace(backspaces: 3, text: "😭"))
    #expect(typist.result("\n:so\t") == .replace(backspaces: 3, text: "😭"))
  }

  @Test func colonRightAfterConversionArms() {
    var typist = Typist()
    typist.type(":sob:")
    #expect(typist.result(":fire:") == .replace(backspaces: 5, text: "🔥"))
  }

  @Test(arguments: [" ", ".", "-", "!"])
  func punctuationDisarms(separator: String) {
    var typist = Typist()
    #expect(typist.result(":so" + separator + "\t") == .passThrough)
  }

  @Test func resetDisarms() {
    var typist = Typist()
    typist.type(":so")
    _ = typist.engine.handle(.reset, now: typist.now)
    #expect(typist.result("\t") == .passThrough)
  }

  @Test func idleDisarms() {
    var typist = Typist()
    typist.type(":so")
    typist.now += 11
    #expect(typist.result("b:") == .passThrough)
  }

  @Test func backspaceEditsTheArmedCode() {
    var typist = Typist()
    #expect(typist.result(":fx\u{8}ire\t") == .replace(backspaces: 5, text: "🔥"))
    // Deleting the colon itself returns to the boundary it was typed at.
    #expect(typist.result(":\u{8}:so\t") == .replace(backspaces: 3, text: "😭"))
  }

  @Test func backspacingToAnEarlierBoundaryArms() {
    var typist = Typist()
    // Deleting a word back to the start of input, or back to a space.
    #expect(typist.result("hello\u{8}\u{8}\u{8}\u{8}\u{8}:so\t") == .replace(backspaces: 3, text: "😭"))
    #expect(typist.result("hi yo\u{8}\u{8}:so\t") == .replace(backspaces: 3, text: "😭"))
    // Deleting only part of a word leaves the colon inside text.
    #expect(typist.result(" yo\u{8}:so\t") == .passThrough)
  }

  @Test func deletingAfterAResetArms() {
    var typist = Typist()
    // A delete shortcut such as ⌥⌫ or ⌘⌫ arrives as a reset.
    typist.type("hello")
    _ = typist.engine.handle(.reset, now: typist.now)
    #expect(typist.result(":so\t") == .replace(backspaces: 3, text: "😭"))
    // Select all or a mouse selection, then Backspace, any number of times.
    typist.type(" hello")
    _ = typist.engine.handle(.reset, now: typist.now)
    #expect(typist.result("\u{8}\u{8}:so\t") == .replace(backspaces: 3, text: "😭"))
    // Backspacing past everything that was typed since the reset.
    #expect(typist.result(" ab\u{8}\u{8}\u{8}\u{8}\u{8}:so\t") == .replace(backspaces: 3, text: "😭"))
  }

  @Test func matchingIsCaseInsensitive() {
    var typist = Typist()
    #expect(typist.result(":SOB:") == .replace(backspaces: 4, text: "😭"))
  }
}

@Suite struct ClosingColon {
  @Test func exactNameConverts() {
    var typist = Typist()
    #expect(typist.result(":sob:") == .replace(backspaces: 4, text: "😭"))
    #expect(typist.result(" :loudly_crying_face:") == .replace(backspaces: 19, text: "😭"))
  }

  @Test func partialNameIsLeftAsTyped() {
    var typist = Typist()
    #expect(typist.type(":so:").allSatisfy { $0 == .passThrough })
    // The stray colon follows text, so it cannot arm a new code.
    #expect(typist.result("b\t") == .passThrough)
  }
}

@Suite struct UndoBehaviour {
  @Test func backspaceRestoresAndRearmsAfterTab() {
    var typist = Typist()
    typist.type(":so\t")
    #expect(typist.result("\u{8}") == .replace(backspaces: 1, text: ":so"))
    #expect(typist.engine.frecency.score(for: "😭", now: typist.now) == -1)
    // Still armed: one more letter and Tab picks a different emoji.
    #expect(typist.result("c\t") == .replace(backspaces: 4, text: "⚽"))
  }

  @Test func backspaceRestoresClosingColonTextWithoutRearming() {
    var typist = Typist()
    typist.type(":sob:")
    #expect(typist.result("\u{8}") == .replace(backspaces: 1, text: ":sob:"))
    #expect(typist.result("\t") == .passThrough)
  }

  @Test func anyOtherKeyClearsUndo() {
    var typist = Typist()
    typist.type(":so\t")
    #expect(typist.result("a\u{8}") == .passThrough)
    #expect(typist.engine.frecency.score(for: "😭", now: typist.now) == 1)
  }

  @Test func undoIsANegativeSignal() {
    var typist = Typist()
    typist.type(":so\t\u{8}")
    #expect(typist.engine.frecency.score(for: "😭", now: typist.now) == -1)
    // The rejected emoji now ranks below ones that were never used.
    #expect(typist.result(" :so\t") == .replace(backspaces: 3, text: "⚽"))
  }
}

@Suite struct Ranking {
  @Test func prefixMatchesFromStartOfNameOnly() {
    #expect(database.matches(prefix: "so").map(\.emoji) == ["😭", "⚽", "🧦"])
  }

  @Test func usageOverridesBaseline() {
    var typist = Typist()
    typist.type(":soccer: ")
    #expect(typist.result(":so\t") == .replace(backspaces: 3, text: "⚽"))
  }

  @Test func exactNameBeatsFrecency() {
    var typist = Typist()
    typist.type(":fire_engine: :fire_engine: ")
    #expect(typist.result(":fir\t") == .replace(backspaces: 4, text: "🚒"))
    #expect(typist.result(" :fire\t") == .replace(backspaces: 5, text: "🔥"))
  }

  @Test func scoresDecayWithA30DayHalfLife() {
    var frecency = Frecency()
    frecency.add(1, to: "😭", now: start)
    #expect(abs(frecency.score(for: "😭", now: start + Frecency.halfLife) - 0.5) < 1e-9)
    frecency.add(1, to: "😭", now: start + Frecency.halfLife)
    #expect(abs(frecency.score(for: "😭", now: start + Frecency.halfLife) - 1.5) < 1e-9)
  }

  @Test func frecencyRoundTripsAsAPlainObject() throws {
    var frecency = Frecency()
    frecency.add(1, to: "😭", now: start)
    let data = try JSONEncoder().encode(frecency)
    #expect(try JSONSerialization.jsonObject(with: data) is [String: [String: Any]])
    #expect(try JSONDecoder().decode(Frecency.self, from: data) == frecency)
  }
}

@Suite struct Suggestions {
  private func arrow(_ input: Engine.Input, _ typist: inout Typist) -> Engine.Output {
    typist.engine.handle(input, now: typist.now)
  }

  @Test func listsRankedMatchesWithTheFirstSelected() {
    var typist = Typist()
    typist.type(":so")
    #expect(typist.engine.suggestions.map(\.emoji) == ["😭", "⚽", "🧦"])
    #expect(typist.engine.suggestions.map(\.name) == ["sob", "soccer", "socks"])
    #expect(typist.engine.selection == 0)
  }

  @Test func exactMatchIsListedFirst() {
    var typist = Typist()
    typist.type(":fire_engine: :fire")
    #expect(typist.engine.suggestions.map(\.emoji) == ["🔥", "🚒"])
  }

  @Test func aSingleMatchIsStillSuggested() {
    var typist = Typist()
    typist.type(":sob")
    #expect(typist.engine.suggestions.map(\.emoji) == ["😭"])
    #expect(arrow(.arrowDown, &typist) == .swallow)
    #expect(typist.engine.selection == 0)
    #expect(typist.result("\t") == .replace(backspaces: 4, text: "😭"))
  }

  @Test func nothingIsSuggestedWithoutAMatch() {
    var typist = Typist()
    #expect(typist.engine.suggestions.isEmpty)
    typist.type(":")
    #expect(typist.engine.suggestions.isEmpty)
    typist.type("zzz")
    #expect(typist.engine.suggestions.isEmpty)
    typist.type(" :sob ")
    #expect(typist.engine.suggestions.isEmpty)
  }

  @Test func arrowsMoveTheSelectionAndTabCompletesIt() {
    var typist = Typist()
    typist.type(":so")
    #expect(arrow(.arrowDown, &typist) == .swallow)
    #expect(typist.engine.selection == 1)
    #expect(typist.result("\t") == .replace(backspaces: 3, text: "⚽"))
    #expect(typist.engine.suggestions.isEmpty)
    #expect(typist.engine.frecency.score(for: "⚽", now: typist.now) == 1)
  }

  @Test func selectionWrapsAndResetsWhenTheCodeChanges() {
    var typist = Typist()
    typist.type(":so")
    #expect(arrow(.arrowUp, &typist) == .swallow)
    #expect(typist.engine.selection == 2)
    #expect(arrow(.arrowDown, &typist) == .swallow)
    #expect(typist.engine.selection == 0)
    _ = arrow(.arrowDown, &typist)
    typist.type("c")
    #expect(typist.engine.selection == 0)
    #expect(typist.engine.suggestions.map(\.emoji) == ["⚽", "🧦"])
  }

  @Test func arrowsPassThroughAndDisarmWithoutAPopup() {
    var typist = Typist()
    #expect(arrow(.arrowDown, &typist) == .passThrough)
    typist.type(":so")
    typist.type("z")
    #expect(arrow(.arrowUp, &typist) == .passThrough)
    // The arrow dropped the code, so deleting the stray letter does not bring it back.
    typist.type("\u{8}")
    #expect(typist.engine.suggestions.isEmpty)
  }

  @Test func idleHidesSuggestions() {
    var typist = Typist()
    typist.type(":so")
    typist.engine.expireIfIdle(now: typist.now + 11)
    #expect(typist.engine.suggestions.isEmpty)
  }

  @Test func bundledDataIsCappedAtFive() throws {
    var engine = Engine(database: try BundledData().database)
    for character in ":s" { _ = engine.handle(.character(character), now: start) }
    #expect(engine.suggestions.count == Engine.maxSuggestions)
  }
}

@Suite struct SkinTones {
  @Test func defaultToneAppliesWhereSupported() {
    var typist = Typist()
    typist.engine.skinTone = .medium
    #expect(typist.result(":wave:") == .replace(backspaces: 5, text: "👋🏽"))
    #expect(typist.result(":sob:") == .replace(backspaces: 4, text: "😭"))
    // Scores are shared across tones.
    #expect(typist.engine.frecency.score(for: "👋", now: typist.now) == 1)
  }
}

@Suite struct BundledData {
  let database: EmojiDatabase

  init() throws {
    let url = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
      .appendingPathComponent("Resources/emoji.json")
    database = try EmojiDatabase(json: Data(contentsOf: url))
  }

  @Test func resolvesNamesFromEverySource() {
    #expect(database.exact("question")?.emoji.unicodeScalars.first == "❓")
    #expect(database.exact("question_mark")?.emoji.unicodeScalars.first == "❓")
    #expect(database.exact("grey_question")?.emoji.unicodeScalars.first == "❔")
    #expect(database.exact("thumbsup")?.tones?.count == 5)
  }

  @Test func baselineRanksCommonPrefixes() {
    let now = Date()
    #expect(database.best(for: "so", frecency: Frecency(), now: now)?.emoji == "😭")
    #expect(database.best(for: "fire", frecency: Frecency(), now: now)?.emoji == "🔥")
  }
}
