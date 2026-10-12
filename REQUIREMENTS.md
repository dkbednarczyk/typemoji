# typemoji — prototype requirements

A macOS menu bar app that expands Discord-style emoji codes (`:sob:`, `:fire:`) in any app, with Tab completion that learns which emoji you use most.

## Goals

- Type `:sob:` anywhere on macOS and get 😭.
- Type a partial code and press Tab to complete it to the most likely emoji.
- Learn from usage so shorter prefixes resolve correctly over time (`:sob` → `:so` → `:s`).
- Stay out of the way: per-app opt-out and a global killswitch.

## Platform and packaging

- Native Swift menu bar app, no UI framework dependencies.
- Built as a SwiftPM package, with a script that bundles and ad-hoc signs the `.app`.
- Keyboard input is observed and modified through a `CGEventTap`, which requires the Accessibility permission.
- Own git repo in `~/Developer/typemoji`.

## Arming a code

- A code starts at `:` followed immediately by a letter.
- The colon only counts when it comes after whitespace or at the start of input (after focus change, click, or a previous conversion). `10:30`, `https://`, `std::vec`, and `key:value` never arm it.
- A deletion the app cannot follow also counts as the start of input: a delete shortcut (⌥⌫, ⌘⌫, ⌃K, forward delete), or Backspace over a selection or over text typed before the last focus change.
- An armed code is dropped on any of:
  - space or punctuation (other than `_` and the closing `:`)
  - arrow keys or other navigation keys
  - mouse click
  - app switch
  - any ⌘ or ⌃ shortcut
  - about 10 seconds of idle
- The app only knows what was typed, not what is in the text field, so stale state is discarded aggressively.

## Conversion

### Tab

- With a code armed and at least one match, Tab is swallowed and the partial code is replaced with the selected emoji, which is the top-ranked one unless the popup selection was moved.
- With nothing armed, or no match, Tab passes through unchanged so terminals and editors behave as usual.

### Suggestion popup

- While the armed code matches at least one emoji, a small popup under the text caret lists the top 5 matches with their names, in ranking order. It stays up when a full name narrows the list to one.
- The first entry is always selected by default, and again whenever the code changes.
- Up and Down move the selection, wrapping at the ends. They are swallowed only while the popup is showing; otherwise they drop the code as usual.
- Tab completes the selected entry. Enter is not intercepted.
- The popup never takes focus or mouse input. It closes when the code is dropped or converted.
- The caret position comes from the Accessibility API. Apps that do not expose it get the popup at the mouse pointer.

### Closing colon

- Typing the closing colon of a complete code (`:sob:`) converts immediately, without Tab.
- This applies to exact name matches only. A partial name followed by `:` is left as typed.

### Replacement mechanism

- Send one backspace per typed character, then type the emoji as a synthetic Unicode key event.
- The clipboard is not touched.

### Undo

- Pressing Backspace immediately after a conversion restores exactly the text that was typed (`:so`), re-armed so typing can continue.
- An undo counts as a negative signal for that emoji.
- Any other key after a conversion clears the undo state; Backspace then behaves normally.

## Names and matching

- Recognized names are the union of Discord, Slack/GitHub, and Unicode shortcodes, so `:question:`, `:question_mark:`, and `:grey_question:` all resolve.
- Partial input matches from the start of a name only (`:so` matches `sob`, not `person_sob`).
- Matching is case-insensitive.

## Ranking and learning

- One global frecency score per emoji.
  - Each use adds 1.
  - Scores decay with a 30-day half-life.
  - An undo subtracts 1.
- A built-in popularity baseline ships with the app, so `:so` gives 😭 on day one. The baseline only breaks ties and ranks emoji that have no usage yet; personal usage always overrides it.
- An exact name match always beats frecency: `:fire` + Tab gives 🔥 even if `fire_engine` has a higher score.
  - Names of one or two characters (`:a:`, `:ok:`, `:no:`) are the exception. They are ranked like any other match, so that `:o` + Tab can still learn. Their closing colon converts as usual.
- Both Tab completions and closing-colon conversions count as a use.

## Skin tone

- One default tone setting (default: yellow), applied to every emoji that supports it.
- No per-use tone syntax.

## Controls

- Menu bar icon with:
  - `Enabled` toggle (the killswitch)
  - `Disable in <frontmost app>` toggle
  - skin tone setting
  - `Launch at login` toggle, off by default
- Global hotkey ⌃⌥⌘E toggles the killswitch. Hard-coded in the prototype.
- The icon dims when the app is disabled or the frontmost app is excluded.

## Per-app exclusions

- Exclusions are stored by bundle ID.
- Discord and Slack are excluded by default, because they have their own `:code` autocomplete (including custom emoji) that would fight over Tab.
- The list is editable; defaults can be removed.

## Storage and privacy

- Settings and per-emoji scores live in `~/Library/Application Support/typemoji/` as readable JSON.
- Keystrokes are never written to disk.
- The in-memory buffer holds only the currently armed code.
- macOS Secure Input blocks event taps in password fields, so the app is inert there.

## Out of scope for the prototype

- Tab cycling through candidates
- Scrolling the popup past the top 5
- Fuzzy or mid-name matching
- Per-prefix memory
- Custom emoji
- Stats UI
- Configurable hotkey
- Notarization and distribution

## Known rough edges

- **Accessibility permission:** with ad-hoc signing, macOS may ask for the permission again after each rebuild.
- **Backspace count:** apps that auto-insert characters or autocorrect while typing can throw off the number of backspaces sent. Undo is the safety net.
