# Milestone 4: QA and UI polish pass

The owner asked for a full QA pass before the M4 gate tests: check every screen for clipped text, scroll bugs and rough edges, polish the UI, and check that everything works.

## How it was checked

- **Snapshot sweep:** Debug › Save window snapshots, or post `com.swaritsheel.Murmur.debug.snapshot`. It renders every Hub page at 760×480, 920×620 and 920×1250, in light and dark, on demo data. It also renders every onboarding step, every Flow Bar state, and the empty states. Contact sheets and `checks.txt` go to `~/Library/Application Support/Murmur/snapshots`.
- **In-process click checks** (part of the sweep). Back button, a sidebar row, and window dragging from the empty header and the sidebar top, all under the transparent title bar: **all pass**.
- **Self-test:** Debug › Run self-test in TextEdit, or post `com.swaritsheel.Murmur.debug.selfTest`. Spoken phrases go through the real pipeline into a scratch TextEdit document, and the document is read back through Accessibility. It covers:
  - plain dictation;
  - a dictionary word;
  - a snippet;
  - AI edits off;
  - a numbered list;
  - Esc while processing, then Undo;
  - Paste last;
  - clipboard restored;
  - History rows written.

  The report goes to `selftest/report.txt` in the data folder. *Not run yet: it brings TextEdit to the front for about a minute, so it waits for the owner's go.*
- Unit tests: 98 pass (`Scripts/test.sh`).

## Found and fixed

| Area | Problem | Fix |
|---|---|---|
| Settings pages | Page header (Back/Forward and title) disappeared under the new title bar | Header drawn above the page (`zIndex`) |
| General, onboarding | Language caption cut off ("…stray words from o…") | Caption wraps |
| Style | "AI edits" (Transforms, C1 master switch) existed only in the old Settings window | Added to Style › Auto Cleanup; level cards and Smart Formatting grey out when it is off |
| Style | Card titles read as typos ("Formal.", "very casual") | "Formal", "Casual", "Very casual", "Excited" |
| Onboarding | Models step showed raw ids ("parakeet-ultra and mlx:qwen3.5-4b") | Display names |
| Onboarding | Window title and page both said "Set up Murmur" | Transparent title bar, single heading |
| Onboarding preview | Auto-advanced and saved progress | Preview never saves or advances |
| Menu | Info line showed raw ids | "Parakeet ultra · Qwen3.5 4B" |
| Menu | Shortcuts submenu always described the default keys, and a preset did nothing once custom shortcuts were saved | Shows the configured keys; a preset clears custom shortcuts; "Change shortcuts…" |
| Dictation | Esc in the first moments after release lost Undo (audio dropped if the History row was not written yet) | Audio kept whenever processing |
| Snippets | Multi-line expansions showed only the first line and could not be edited with line breaks | Cell shows up to 3 lines; Option-Return adds a line |
| Flow Bar | Short notices wrapped to two lines | Notice width token 360 → 400 |
| Cleanup model picker | Alphabetical by id, so Apple and Groq came before the recommended model | Recommended, local, cloud, rules only |
| Code | Old History, Settings and Permissions windows were unreachable | Removed; "Restart Murmur" moved into the Hub's Permissions section |

## Redesign

- **Hub:**
  - A full-height translucent sidebar with Murmur's mark.
  - A calmer selection: a tinted row with an accent icon, and aligned icons.
  - A status card ("Ready · Hold fn to dictate").
  - Each page has its own header row level with the traffic lights.
- **Home:**
  - Words today, words this week and speaking pace.
  - A rounded search field.
  - History grouped by day (Today, Yesterday, weekday, date).
  - Hover actions float over the row, so the text no longer reflows.
  - Empty and no-match states.
- **Settings pages:** Grouped sections with one-line explanations under each switch.
- **Onboarding:**
  - A step icon, larger titles and a feature list on the welcome step.
  - Large buttons; the last button reads "Start using Murmur".
