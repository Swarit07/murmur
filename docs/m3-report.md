# Milestone 3 report: cleanup, dictionary, snippets

2026-10-05 · branch `milestone-3`. Measured on the owner's recorded corpus, transcribed by Parakeet ultra, with Qwen3.5-4B cleanup (release build, M4 Pro).

## Gate

| Gate item | Result |
|---|---|
| **27 of 30 corrections resolve** | **Pass: 27/30** end to end, with Smart Formatting off and on (it is on by default); 28/30 on the written sentences |
| **Guard blocks every injected change** | **Pass: 291/291** (`murmur-bench guard-test`): numbers changed 54/54, numbers added 90/90, URLs changed 3/3, names swapped 22/22, names added 90/90, negations flipped 8/8, negations added 24/24. Honest outputs wrongly blocked: 0. Fact changes in real model outputs after the guard: 0/60 |
| **Stalled model lands text within 1.5 s** | **Pass:** at most 855 ms over 20 trials (`murmur-bench stall-test`) |

The three corrections that miss on real transcripts:
- correction-19: the engine heard "Ashley, just elites" for "actually, just the leads"; cleanup cannot recover words that were never transcribed.
- correction-16: "Use production for the report" is right in meaning, but shorter than the scorer's 0.25 word-difference limit against the expected sentence.
- One more varies between runs at greedy decoding's margin.

## Requirements

| Item | Status | Evidence |
|---|---|---|
| C1 levels and Transforms | Done | None, Light, Medium in Settings; an "AI edits" master switch turns the model off while rules still run |
| C2 backtracking | 27/30 | Gate above |
| C3 Smart Formatting | Done | "first the tickets, second the hotel booking, third a rental car" becomes a numbered list (437 ms). The guard accepts list markers as layout, and a correction is never read as a list |
| C4 spoken punctuation | **Partly verified** | Synthetic voices, 10 clips each: question mark 10/10, new paragraph 10/10, new line 9/10, comma 6/10. The misses are the engine hearing "comma" as "Kama", "Kamal", "come and" on synthetic speech, not the rules. Needs 40 clips in the owner's voice to settle (see below) |
| C5 guardrails | Done | Gate above |
| C6 time limit | Done | Gate above, plus 110 back-to-back timeouts in one process with no crash |
| C7 transcript is data | 4/4 | The poem request, "ignore the previous message", the factual question and the translate request are all inserted as text |
| C8 no translation | In the prompt | "Keep the language the speaker used. Never translate; mixed languages stay mixed." |
| C10 undo or redo the AI edit | Done | History right-click: Undo AI edit (use original words) or Redo, without re-running the model; the row is marked |
| S1 dictionary | Done | Dictionary window (word, optional "heard as" spellings). Entries fix spellings in the rules stage, bias the engine and are given to the cleanup model |
| S3 snippets | Done | Snippets window; a cue becomes a protected placeholder the model cannot touch |
| T3 languages | Done | Settings › Languages: automatic, or the languages you speak; one chosen language is passed to the engine |
| T4 dictionary biasing | **8 of 10** | `murmur-bench vocab-test --pipeline mlx:qwen3.5-4b`, 21 names and terms from the corpus: of 10 terms the bare engine missed, the engine's CTC word spotter fixes 6 and the cleanup model with the dictionary fixes 2 more; 0 terms broken. Still missed: "Pri" for Priya and "Chivan" for Siobhan, which a "heard as" entry fixes |

## Speed

- Cleanup, Qwen3.5-4B on real transcripts: p50 287 ms, p95 419 ms.
- Dictionary biasing adds ~110 ms to transcription when the dictionary is not empty (152 vs 43 ms p50).
- **Long dictations (≥ ~20 s) still hit the 800 ms cleanup limit:** 3 of 11 joined 34–60-word inputs time out, and those fall back to rule-cleaned text. Speculative decoding (Qwen3-4B-2507 with a Qwen3-0.6B draft) cut p50 by ~12% and timeouts to 1 of 11, but it needs a different main model (26/30 corrections) and ~0.5 GB more. It is available as `mlx:qwen3-4b-2507+draft` and is not the default. Qwen3.5's hybrid layers cannot be rewound, so they cannot draft.

## Fixed along the way

- The guard rejected correct resolutions where "no" sat inside the cue ("3.2 No wait version 3.3"). Cue words may now be dropped.
- The guard-injection test found that a filler "I mean" let the model drop a later "not". A correction now relaxes only facts spoken before its cue.
- The first dictation after launch, or after changing the dictionary or settings, timed out: the cached prompt prefix only covered the default instructions. The app now prewarms the exact instructions in use.
- A crash in Metal when a timed-out generation was still finishing as the next model call began. Each call now cancels its generator and waits for it before releasing the model.

## Open, for the owner

1. **Long dictations:** keep the spec's fixed 800 ms cleanup limit (long dictations get rules-only polish), or let the limit grow with length, for example 800 ms plus 10 ms per word over 30, capped near 1.4 s so the spec's 1.5 s p95 still holds. This changes rule C6, so it is the owner's call.
2. **C4 with your voice (optional, ~5 min):** 40 short clips saying "comma", "question mark", "new line" and "new paragraph" in sentences, to confirm the synthetic-voice comma result is only a synthetic-voice problem.
