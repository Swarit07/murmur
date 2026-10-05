# Design/ — Murmur "Paper & Clay"

Everything `UI_REDESIGN.md` refers to. Nothing in here ships as-is except the brand SVGs (after conversion) and the fonts you bundle yourself.

| Path | Use |
| --- | --- |
| `tokens.json` | Every color (light and dark), type style, spacing step and radius. `Tokens+*.swift` must match it; a unit test checks the colors. |
| `brand/murmur-mark.svg` | The logo lockup: one path, `viewBox 0 0 1002 378`, fill `#B54C3C`. Build `BrandMark` from it. |
| `brand/murmur-mark-dark.svg` | The same path in `#D9705F` for dark surfaces. |
| `brand/app-icon.svg` | 1024 × 1024 app icon source: cream tile, the M, one big lobe, then the logo's tapering tail. Generate the `.iconset` from it. |
| `brand/app-icon-dark.svg` | Dark tile variant for marketing and the Components board. |
| `brand/menubar-template.svg` | Menu bar glyph, 36 × 36 viewBox, black on transparent. Export 18 pt template images at 1×, 2×, 3×. |
| `brand/logo-murmur.png` | The owner's original raster logo. Reference only. |
| `motion/murmur-motion.js` | Working reference for the waveform (`drawWave`), processing dots, countdown ring and mic level meter. Port the math; `speech()` is a demo signal, never ship it. |
| `reference/*.png` | 2× renders of every board: the visual answer key. 1 board px = 1 pt. |
| `reference/html/*.dc.html` | The boards' source. Exact values live in the inline styles. They use a design-canvas wrapper (`<x-dc>`, `<x-import>`); read them as HTML, don't run them. |

Reference renders:

| File | Board |
| --- | --- |
| `reference/flowbar-menubar.png` | 01–02 Flow Bar states and menu bar |
| `reference/hub-home.png` | 03.1 Hub · Home |
| `reference/hub-style.png` | 03.2 Hub · Style |
| `reference/hub-dictionary.png` | 03.3 Hub · Dictionary |
| `reference/hub-snippets.png` | 03.4 Hub · Snippets |
| `reference/hub-settings.png` | 03.5 Hub · Settings |
| `reference/onboarding.png` | 04 Onboarding, ten steps |
| `reference/components.png` | 05 Components: brand, color, type, controls, icons, dark mode |

Note: the boards set small captions in stone `#8A857C` and draw control edges at 18–35% ink. Both fail contrast; `UI_REDESIGN.md` §3.2 replaces them with `text-tertiary` and `border-control`. Build from the tokens, not the pixels, where they differ.
