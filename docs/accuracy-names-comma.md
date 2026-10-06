# Accuracy: dictionary names (T4) and spoken commas (C4)

2026-10-05. Parakeet ultra, Qwen3.5 4B, the corpus `names` set, `murmur-bench vocab-test --pipeline mlx:qwen3.5-4b`, `vocab-false-test`, `punctuation-test`.

## T4 dictionary names: 7/10 → 9/10, still 0 broken and 0 false insertions

| | Before | After |
|---|---|---|
| Names the bare engine missed, fixed with the dictionary | 7 of 10 | **9 of 10** |
| Terms broken | 0 | 0 |
| False insertions (85 clips with no dictionary word said) | 0 | 0 |
| Clean clips changed | 0 | 0 |
| Terms fixed by the rules stage alone | not recorded | 7 |

**What changed** (`SpellingMatcher`, rules stage). The matcher stays deliberately conservative: it never writes a dictionary word over an ordinary English word except in the one list case below. Three narrow additions:
1. **A name the engine cut short.** "Pri" becomes Priya when the fragment is:
   - capitalized;
   - at least 3 letters and 60% of the name;
   - not an English word;
   - not a common first name of its own (`/usr/share/dict/propernames`), so "Alex" never becomes Alexa.
2. **How a hard name is said** (`SpokenNames`). For a dictionary name like Siobhan (said "shiv-awn"), the heard word is compared with the spoken form by sound and, at 65% or more, by spelling. "Chivan" becomes Siobhan without a "Heard as" entry. Rules for the table:
   - only names in the user's dictionary are used;
   - names whose sound collides with a common name are left out of the table (Clodagh ~ Claude, Caoilfhionn ~ Colin, Aoibheann ~ Evan, Ciarán ~ Karen, Gruffydd ~ Griffith, Gráinne ~ Greene, Mairéad ~ Murad).
   - One known residue: a "Shivani" could still become Siobhan if Siobhan is in the dictionary.
3. **A real word that sounds exactly like a dictionary name, in a list of names.** "to Joaquín and mailing." becomes "to Joaquín and Mei-Ling." Only when:
   - it sits right after "and"/"or" and another dictionary name, or right before them;
   - and it ends its phrase.

   "the mailing list" and "Joaquín and mailing lists" stay as they are.

The first-name guard also closed a gap in the older sound-alike rule: "Josh" no longer becomes Joshua, and "Alex" no longer becomes Alexa.

**The remaining miss, Figma (names-06).** The engine heard "Send the Figma link to Joaquín and Mei-Ling" as "Send the fig mailing to Joaquin and mailing".
- "fig" is an English word, so the rules leave it, and whether the cleanup model writes Figma is a near-tie:
  - With Smart Formatting on (the owner's setting), it writes "Figma mailing" for both the old and the new rules output.
  - Without it (the bench), it keeps "fig" once "Mei-Ling" is fixed.
- "link" itself is lost in the engine's "mailing". No rule can recover that safely.

Unit tests: `SpellingMatcherTests` covers each rule and its negatives.

## C4 spoken commas: unchanged, on purpose

`punctuation-test`, synthetic voices: comma 8/10, new line 9/10, question mark 10/10, new paragraph 10/10. The misses are the engine mishearing the synthetic voice:
- "Send it to Sam Kama Priya and Marcus" (for "Sam, Priya and Marcus");
- "Today come and not tomorrow" (for "Today, not tomorrow");
- "Subject new liner launch" (for "Subject: (new line) our launch").

"Kama" and "Kamal" are real names, and "come and" is ordinary English. A rule turning them into punctuation would put commas into normal speech, which is worse than a missed comma. Recordings of the owner's own voice (40 clips, optional) would show whether these mishearings happen with a real voice before anything changes.
