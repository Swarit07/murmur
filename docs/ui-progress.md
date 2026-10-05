# UI redesign v2 ("Paper & Clay"): progress

One report per milestone (UI_REDESIGN.md §10), newest last. If a session ends midway, the next one resumes from here. The branch is `ui-redesign`: commits are local only, never pushed.

## Setup (U-)

- **Before starting:** the tree held the unfinished v1 U3 Flow Bar work. At the owner's choice it was committed as `8903940 U3 (v1, unfinished)`, then the v2 bundle was installed.
- **Bundle install (`d69c8e3`):**
  - `UI_REDESIGN.md` v2 and `Design/` were copied in.
  - The v1 brief moved to `docs/archive/UI_REDESIGN.v1.md`.
  - The v1 mark files moved to `docs/archive/design-v1/`.
  - The logo raster is byte-identical and now lives at `Design/brand/logo-murmur.png`.
- **SPEC:** `SPEC.md` (there is no `claude-code-prompt.md`).

## U0: Audit and harness

**Changed**
- `docs/ui-audit.md`: a v2 section covering the v1 pieces reused, the token and component migration list (v1 → v2), and what stands in the way.
- `Sources/MurmurSnap/main.swift`: two new flags.
  - `--large` renders at text scale 1.15 into `<set>-large/`.
  - `--reduce-motion` renders with Reduce Motion on into `<set>-reduced/`.
- `.gitignore`: ignores the variant sets and `Artifacts/ui/compare/`.

**Reused from v1** (details in the audit):
- the snapshot tool, Design Gallery, token panel with the debug overrides, token lint;
- the token-file split with `ThemeProvider`, `Motion`, `UIDebug` and `FontRegistry`;
- the `BrandMark` SVG path parser and `MicLevelSource`;
- the sound generator, and the Flow Bar panel and model plumbing.

**Done when**
- **`murmur-snap` produces before-images for every Hub page and Flow Bar state: pass.**
  - `Artifacts/ui/before/{light,dark}/` holds the pre-redesign UI from v1 U0: 8 Hub pages, 12 onboarding steps, 13 Flow Bar states and the gallery. The contact sheet is `Artifacts/ui/sheets/before.png`.
  - That set was rendered before any visual change, so it stays the "before" column. Re-rendering now would capture v1's half-built Flow Bar instead.
  - `murmur-snap after` still runs clean.
- **`docs/ui-audit.md` exists: pass.**

**Judgment calls (defaults taken)**
- **Onboarding keeps SPEC's 12 steps** rather than the board's 10 (§5.4 says "same steps as SPEC §6").
- **Shortcuts show the real bindings:** ⌃⌘V and ⌃⌘C, not the board's ⌃⌥V and ⌃⌥C.
- **The no-audio alert is built but not wired.** The controller has no silent-recording event, and adding one changes dictation behavior. **Owner decision needed.**
