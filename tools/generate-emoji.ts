// Generates Resources/emoji.json: every emoji with the union of its Discord,
// Slack, GitHub and Unicode shortcodes, its skin tone variants, and a
// popularity rank. Run with `make emoji`; the output is committed.

import { readFileSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import * as discord from "discord-emoji";
import data from "emojibase-data/en/data.json";
import cldr from "emojibase-data/en/shortcodes/cldr.json";
import emojibase from "emojibase-data/en/shortcodes/emojibase.json";
import github from "emojibase-data/en/shortcodes/github.json";
import iamcal from "emojibase-data/en/shortcodes/iamcal.json";
import joypixels from "emojibase-data/en/shortcodes/joypixels.json";

type Shortcodes = Record<string, string | string[]>;
type Entry = { emoji: string; names: string[]; tones?: string[]; rank?: number };

const root = join(import.meta.dir, "..");

// Presentation selectors vary between sources, so emoji are compared without them.
const bare = (emoji: string) => emoji.replaceAll("️", "");

// A name is only reachable if it can be typed without dropping the armed code:
// a letter, then letters, digits or underscores.
const normalize = (name: string) => {
  const normalized = name.toLowerCase().replaceAll("-", "_");
  return /^[a-z][a-z0-9_]*$/.test(normalized) ? normalized : undefined;
};

const FLAGS_GROUP = 9;

const entries: Entry[] = [];
const flags = new Set<number>();
const indexByEmoji = new Map<string, number>();
const indexByHexcode = new Map<string, number>();

for (const item of [...data].sort((a, b) => (a.order ?? Infinity) - (b.order ?? Infinity))) {
  const entry: Entry = { emoji: item.emoji, names: [] };
  const tones = [1, 2, 3, 4, 5].map((tone) => item.skins?.find((skin) => skin.tone === tone)?.emoji);
  if (tones.every((tone) => tone !== undefined)) entry.tones = tones as string[];
  indexByEmoji.set(bare(item.emoji), entries.length);
  indexByHexcode.set(item.hexcode, entries.length);
  if (item.group === FLAGS_GROUP) flags.add(entries.length);
  entries.push(entry);
}

// Sources in priority order. When two sources give the same name to different
// emoji, the earlier source keeps it.
const discordNames: [string, number][] = [];
for (const category of Object.values(discord)) {
  for (const [name, emoji] of Object.entries(category as Record<string, string>)) {
    const index = indexByEmoji.get(bare(emoji));
    // Skin tone variants (`wave_tone1`) are not in the index and are skipped.
    if (index !== undefined) discordNames.push([name, index]);
  }
}

const fromHexcodes = (shortcodes: Shortcodes): [string, number][] =>
  Object.entries(shortcodes).flatMap(([hexcode, names]) => {
    const index = indexByHexcode.get(hexcode);
    return index === undefined ? [] : [names].flat().map((name): [string, number] => [name, index]);
  });

const sources: Record<string, [string, number][]> = {
  discord: discordNames,
  slack: fromHexcodes(iamcal),
  github: fromHexcodes(github),
  joypixels: fromHexcodes(joypixels),
  emojibase: fromHexcodes(emojibase),
  cldr: fromHexcodes(cldr),
};

const owner = new Map<string, number>();
let conflicts = 0;
for (const [source, names] of Object.entries(sources)) {
  let added = 0;
  for (const [raw, index] of names) {
    const name = normalize(raw);
    if (name === undefined) continue;
    // Bare country codes (`so`, `it`, `no`) are exact names, so they would win
    // Tab over every longer name. Flags stay reachable as `flag_so`.
    if (name.length <= 2 && flags.has(index)) continue;
    const existing = owner.get(name);
    if (existing === undefined) {
      owner.set(name, index);
      entries[index].names.push(name);
      added++;
    } else if (existing !== index) {
      conflicts++;
    }
  }
  console.log(`${source}: ${names.length} names, ${added} new`);
}

const baseline = readFileSync(join(import.meta.dir, "baseline.txt"), "utf8")
  .split("\n")
  .filter((line) => !line.startsWith("#"))
  .join(" ")
  .split(/\s+/)
  .filter(Boolean);

let rank = 0;
for (const emoji of baseline) {
  const index = indexByEmoji.get(bare(emoji));
  if (index === undefined) throw new Error(`baseline.txt: unknown emoji ${emoji}`);
  if (entries[index].rank === undefined) entries[index].rank = rank++;
}

const named = entries.filter((entry) => entry.names.length > 0);
const lines = named.map((entry) => JSON.stringify(entry));
writeFileSync(join(root, "Resources", "emoji.json"), `[\n${lines.join(",\n")}\n]\n`);

console.log(`${named.length} emoji, ${owner.size} names, ${rank} ranked, ${conflicts} conflicting names dropped`);
