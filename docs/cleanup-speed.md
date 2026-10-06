# Cleanup speed: prompt-lookup decoding on Qwen3.5 4B

2026-10-05, branch `perf/prompt-lookup-cleanup` (from `ui-redesign` at b5b3d81). Qwen3.5 4B 4-bit, mlx-swift 0.32.3, mlx-swift-lm 3.32.3, macOS 27, M4 Pro, release build, Smart Formatting on unless noted.

**Result.** Prompt-lookup decoding works and makes long cleanups 1.6× faster at the median (61+ words: 1,334 → 818 ms), but **it cannot be made lossless on MLX, so it is off by default.** 9 of 251 outputs changed. MLX computes a forward pass over several tokens with different matrix kernels than a one-token pass. The logits come out up to 0.33 apart, and a near-tie between two tokens can go the other way. This affects any way of checking several tokens in one pass: prompt lookup, a draft model, or Qwen's MTP head. The cause is MLX's quantized matrix kernels, so it should apply to every 4-bit model on this Mac, not only Qwen3.5; only Qwen3.5 4B was measured. 61+ words also stayed above the 600 ms target even with it on.

With the switch off (the default), the app's cleanup output is unchanged. The corpus outputs are identical to the unmodified build in all three passes (110/110 each), Command Mode is 16/16 identical, and long dictations are 11/11. The next-best option is cleaning finished sentences while the speaker is still talking. It is written up below as a proposal, with simulated numbers. It cannot keep the output identical either.

## What was built

- **`PromptLookupDrafter`** (`Sources/Cleanup/PromptLookup.swift`) guesses the next tokens from the dictation. It looks up the output's last 3 tokens in the prompt from the dictation on, then 2, then 1, and copies what followed. A cleanup mostly copies its transcript in order, so when a token appears more than once, it prefers the match at or after the previous one. Pure Swift, unit-tested.
- **`GuessSizer`** (same file) picks how many guessed tokens each pass checks. It uses the measured cost of a pass (below) and a running estimate of how often guesses are right. It chooses the length with the most expected tokens per millisecond: 1–4 tokens while guesses keep failing, up to 31 while the output is copying the dictation.
- **`PromptLookupTokenIterator`** (`Sources/CleanupMLX/`) runs the model. It sends the prompt through exactly as `TokenIterator` does. Each pass then feeds `[replayed tokens…, newest token, guess…]` and takes the argmax at every position. It keeps the longest prefix of the guess that matches those argmaxes, plus the model's own next token.
- **`MLXCleanupProvider`** uses it when `MURMUR_PROMPT_LOOKUP=1` is set. Nothing else in the app changed. Prompts, the guard, capture, transcription, insertion and shortcuts are untouched, and MLX compile stays off.
- **Bench:** `speed-test` (plain and lookup side by side on the same inputs, alternating which goes first, with every output pair compared), `pass-cost`, `numerics-test`, `sentence-test`, `cleanup-pass --expect`, and `long-test --save/--expect`.

### Can mlx-swift-lm's own speculative decoding take a custom drafter?

No, not for Qwen3.5.

- `SpeculativeTokenIterator` takes a draft *model* (`any LanguageModel`), not a drafter, and refuses caches that do not trim: "Speculative decoding requires trimmable KV caches." Qwen3.5's GatedDeltaNet layers use `MambaCache`, which does not trim. A guesser wrapped as a fake model would still hit that check.
- `MTPSpeculativeTokenIterator` drives Qwen3.5's own multi-token-prediction head. The mlx-community 4-bit checkpoint has no MTP weights: 0 of its 1,221 tensors start with `mtp.`. For hybrid models it also rewinds only one token (`maximumNativeTargetCacheRewind = 1`). It does this with a recurrent-state checkpoint after the first verified token, which is restored through package-internal API.
- Both check several tokens per pass, so the rounding problem below applies to them as well.

## How rollback works

Qwen3.5 has 8 attention layers, with KV caches that trim, and 24 GatedDeltaNet layers. A GatedDeltaNet layer's recurrent state has absorbed every token of a pass and cannot be trimmed.

1. **Snapshot before the pass.** The iterator keeps a reference to each `MambaCache`'s two arrays (conv state and recurrent state). MLX arrays are immutable and the pass replaces them with new arrays, so keeping the references copies nothing and costs nothing.
2. **All of the guess accepted:** nothing to undo.
3. **Part of the guess rejected:** the iterator puts the 24 snapshots back. It trims the attention caches by the whole pass (bookkeeping only). The kept tokens go into `replay`.
4. **Replay rides along with the next pass.** The next pass feeds `replay + [newest token] + next guess`, so the caches catch up without a pass of their own, and the sizer counts the replayed tokens into the pass's cost. `MURMUR_LOOKUP_REPLAY=own` replays in a separate pass instead. On the 43 long inputs, that was no slower within noise: 1.58× and 1.66× (36–60 and 61+ words) against 1.59× and 1.60×.

Models whose caches all trim (Qwen3) just trim the rejected tokens. Over the 251 inputs, 41% of passes rolled back, and 0.29 tokens were replayed per token produced.

`KVCache.copy()` would also work as a snapshot, as "MLX prefix KV cache" in decisions.md notes. Holding the references is the same thing without allocating new cache objects. Replaying is used because there is no public way to read the recurrent state at an intermediate position of a pass. The library saves exactly one such checkpoint for MTP, but its restore is package-internal.

## Measurements

### What a pass costs (`pass-cost`)

One forward pass over n new tokens after a cached cleanup prompt (median of 15):

| Tokens | 1 | 2 | 3 | 4 | 5 | 6 | 8 | 10 | 11–12 | 13–32 |
|---|---|---|---|---|---|---|---|---|---|---|
| ms | 14.4 | 14.8 | 18.1 | 21.8 | 26.2 | 31.8 | 39.2 | 48.3 | 58–62 | 60–65 |
| × one token | 1.00 | 1.03 | 1.26 | 1.51 | 1.81 | 2.20 | 2.72 | 3.34 | 4.0–4.3 | 4.2–4.5 |

The usual assumption is that checking a few tokens costs about the same as one, because decoding is limited by memory bandwidth. Here that only holds up to 2. From 2 to 12 tokens MLX uses `qmv_wide`, which is limited by arithmetic on this GPU, so each extra token adds about a third of a step. From 13 tokens it uses `qmm`, which is flat up to at least 32. A fully accepted 4-token pass gives 2.6× and a 32-token pass gives 7×, but any rejection wastes most of the pass.

### Speed by length (`speed-test`, 251 inputs)

The inputs are the 90 Parakeet transcripts of the corpus (plus the 20 "levels" ones again at Medium). Long dictations are runs of 2, 3, 4, 5, 6 and 8 consecutive transcripts joined together. Each input ran once plain and once with lookup, in alternating order, in the same process. Times are the model call (`llmMs`), with no time limit. Murmur.app and another session were running on the same Mac, so absolute times are noisy; the two columns share the noise.

| Words | Inputs | Plain p50 | Plain p95 | Lookup p50 | Lookup p95 | p50 speed-up | Identical output | Guessed tokens kept | Tokens per pass |
|---|---|---|---|---|---|---|---|---|---|
| 1–15 | 95 | 235 | 372 | 182 | 269 | 1.29× | 95/95 | 46% | 3.8 |
| 16–35 | 83 | 480 | 854 | 333 | 584 | 1.44× | 79/83 | 47% | 4.1 |
| 36–60 | 45 | 876 | 1,748 | 549 | 790 | 1.59× | 43/45 | 50% | 4.3 |
| 61+ | 28 | 1,334 | 1,996 | 818 | 1,995 | 1.63× | 25/28 | 60% | 4.5 |
| All | 251 | 429 | 1,595 | 294 | 896 | 1.46× | 242/251 | 51% | 4.2 |

- Lookup was slower than plain on 19 of 251 inputs. They are mostly outputs the model restructures, such as Smart Formatting's numbered lists, where guesses keep failing.
- `long-test` (11 dictations of 34–60 words, Light, no Smart Formatting, which copy their input more closely): p50 under the app's time limit fell from 756–822 ms to 321–350 ms (3 runs each). Over 800 ms: 1–2 of 11 plain, 0–1 of 11 with lookup. Without the limit, p50 went from 659–678 ms to 282–309 ms (about 2.3×).
- Command Mode (`command-test`): p50 300 ms plain, 305 ms with lookup. A rewrite does not copy its input, so there is nothing to gain.

### Choosing the guess length

These ran on the 43 inputs of 36 words or more. Each row is its own run; the speed-up is against that run's plain times.

| Policy | 36–60 speed-up | 61+ p50 | 61+ speed-up | Guessed tokens kept | Tokens per pass |
|---|---|---|---|---|---|
| Up to 1 token | 1.36× | 987 ms | 1.37× | 85% | 1.8 |
| Up to 3 tokens | 1.61× | 869 ms | 1.57× | 77% | 2.9 |
| Up to 8 tokens, passes up to 12 (first full run, all 73 inputs of 36+ words) | 1.33× | 1,004 ms | 1.42× | 60–63% | 4.6–4.8 |
| Up to 31 tokens | 1.56× | 904 ms | 1.49× | 30% | 6.3 |
| **Sized by `GuessSizer` (default)** | **1.57×** | **851 ms** | **1.78×** | 56% | 4.0 |
| Same, run again | 1.59× | 846 ms | 1.60× | 56% | 4.0 |

The repeat shows the noise: differences under about 0.2× between rows are not meaningful.

Long guesses win when the output copies its input: with 31-token guesses, a 75-word dictation took 3 passes and 422 ms, against 1,326 ms plain. Short guesses win when the model edits a lot. The sizer gets most of both. The best per-input mix of the 3-token and 31-token runs would have given 832 ms for 61+ words. That is still well above 600 ms, because about 40% of passes end in a rejection and the 3–12 token passes cost real time on this GPU.

## Identical output

| Check | Plain (default, switch off) | Lookup on |
|---|---|---|
| `cleanup-pass`, Parakeet transcripts, Smart Formatting, against the unmodified build | **110/110** | 109/110 |
| `cleanup-pass`, written sentences, Smart Formatting, against the unmodified build | **110/110** | not run |
| `cleanup-pass`, Parakeet transcripts, no formatting, against the unmodified build | **110/110** | not run |
| `command-test` outputs, against the unmodified build | **16/16** (16/16 pass) | 15/16 (16/16 pass) |
| `long-test`, 11 long dictations | **11/11** across 3 runs | 11/11 in 3 runs |
| `speed-test`, 251 inputs, plain against lookup in one process | | 242/251 |

The unmodified build is `ui-redesign` at b5b3d81, built before any change; its outputs are kept in `results/raw/baseline/`.

The 9 `speed-test` differences:

- **Wording near-ties (5):**
  - "…for the wiki, since that's what everyone already uses." vs "…for the wiki. That's what everyone already uses." (Medium; also the one corpus difference)
  - "eighteen hundred fifty" vs "eighteen hundred and fifty" (twice)
  - "six thirty" vs "6:30"
  - "double check" vs "double-check"
- **Smart Formatting (3):** a numbered list repeating the sentences was appended in one decoding and not the other, or was worded differently. Plain decoding does the same on other inputs; it is a quirk of the model, which a near-tie switches on or off.
- **Paragraph break (1):** same words, one paragraph break more.

Command Mode: "…before signing and onboarding can begin next week." vs "…before signing and starting onboarding next week."

The guard checks lookup's output exactly as it checks plain output, so no fact can change. But the text is not the same, and that was the requirement.

## Why it cannot be lossless (`numerics-test`)

Greedy speculative decoding is lossless only if the verify pass computes the same logits as one-token decoding, bit for bit. On MLX it does not.

**One quantized layer** (`layers.31.self_attn.q_proj`, 2560 → 8192, 4-bit, bf16 input). Each row of a product over n rows was compared with the same row computed alone:

| Rows together | 1 | 2 | 3 | 4 | 5 | 8 | 12 | 13 | 16 | 32 |
|---|---|---|---|---|---|---|---|---|---|---|
| Rows identical to computing alone | 1/1 | 0/2 | 0/3 | 0/4 | 0/5 | 0/8 | 0/12 | 0/13 | 0/16 | 0/32 |
| Outputs that differ | 0% | 79% | 79% | 80% | 80% | 79% | 79% | 80% | 80% | 79% |

**The whole model:** greedy decoding of a 40-word dictation one token per pass, against one pass over the first n of the same tokens from the same cache. For every n from 2 to 32, 0 of n logit rows were identical. The largest logit difference was 0.31–0.33. In those 32 tokens the top choice still agreed, and the smallest gap between the top two logits was 0.75. On the corpus, gaps below roughly 0.3 occur and flip.

The cause is in `mlx/backend/metal/quantized.cpp`:
- One row uses `qmv`.
- 2–12 rows use `qmv_wide` on Apple GPU generation 15 and later (`use_qmv_wide`; this M4 Pro is one), which reuses each weight group across rows and adds in a different order.
- 13 or more rows use `qmm`/`qmm_splitk`, which splits K depending on the row count.

All three are deterministic, but they round differently. No setting selects `qmv` for several rows. A product with one row per batch item would use `qmv`, but it reads the weights once per row, which removes the speed-up. Qwen3.5's fused GatedDeltaNet input projection is also out of reach: it sits in a private helper outside the module tree.

So lossless speculative decoding would need MLX to run several rows through a kernel that adds in `qmv`'s order. That would be an upstream change, and attention, RoPE and the conv path would then need the same check.

## The app's output is unchanged

The switch is off by default, and with it off the provider runs the same `TokenIterator` path as before. The 110/110 × 3, 16/16 and 11/11 results above are from this build with the switch off, compared with the unmodified build. Unload and reload still work (`reload-test`, 4 cycles):
- Switch off: footprint after each unload 135–137 MB, +0.7 MB per reload, 0 MB of MLX arrays (the leak fix measured +0.8).
- Switch on: 146–152 MB, +2.0 MB per reload over 3 reloads, 0 MB of MLX arrays. That is small and was not looked into further, since lookup is off by default.

The iterator keeps nothing between calls. `MURMUR_NO_MLX=1 swift test`: 178 tests pass (170 before, plus 8 for the drafter and sizer). `Scripts/check-tokens.sh` passes. The app was not rebuilt or installed, and the self-test and app matrix were not run.

## Next-best option: clean finished sentences while the speaker talks (proposal)

**Idea.** While recording, transcribe the audio so far every few seconds (Parakeet takes 80–190 ms per transcription). When a sentence is complete, meaning the next one has started, clean it in the background; the GPU is idle while the speaker talks. At release, transcribe the whole recording as today. Every sentence whose transcript is unchanged reuses its cleaned text, and only the rest is cleaned. A 27-second dictation then waits only for its last sentence after release.

**Simulated** with `sentence-test`, on the same 140 joined dictations. Each was cleaned whole, and also sentence by sentence (split at the engine's ". ", "? ", "! "). The second column is what would be left after release: the last sentence.

| Words | Inputs | Whole p50 | Last sentence p50 | Last sentence p95 | Same text as whole | Same, holding corrections open | Last piece p50, holding |
|---|---|---|---|---|---|---|---|
| 16–35 | 65 | 480 | 202 | 424 | 34/65 | 48/65 | 216 |
| 36–60 | 45 | 853 | 225 | 513 | 15/45 | 19/45 | 289 |
| 61+ | 28 | 1,329 | 291 | 430 | 6/28 | 6/28 | 347 |

Release to text for 61+ words would drop from about 1.56 s to about 0.6 s: 192 ms of transcription, ~290 ms of cleanup, and the ~140 ms the rest of the owner's 61+ dictations already take. That beats anything decoding-side on this Mac. But the output changes, so it fails this task's constraint, as a different design rather than a rounding effect:

- **Self-corrections across a sentence end break.** The engine often ends a sentence before the correction: "Call the client at ten. Call them at eleven." Cleaned alone, each half is fine, so the correction is never resolved. That was most of the differences. The "holding" columns keep a sentence open while the next one starts with a correction cue (actually, no, sorry, I mean, make that, scratch that, wait). That fixes most short dictations (16–35 words: 34 → 48 of 65 the same) but not long ones (61+: still 6 of 28).
- **For long dictations, the whole-text cleanup is often the worse one.** Given 60–100 words at once, the model leaves corrections and fillers in more often. A rough count, holding corrections open, looked at differing outputs only:
  - The whole-text version kept more correction phrases than the sentence-by-sentence one in 13 of the 140 inputs.
  - It kept more filler words in 8 (7 of the 28 over 60 words).
  - The sentence-by-sentence version never kept more of either.

  Both still make mistakes. One 65-word example:
  - Whole: "Tell her I'll be there at six no, six thirty. The reset link goes to the old email. Scratch that, the new email. …"
  - Sentence by sentence: "Tell her I'll be there at six thirty. The reset link goes to the old email. The new email. …"
- **Smart Formatting needs the whole text.** A numbered list spans sentences, and paragraphs depend on length. It would need a final formatting pass, or would be decided at release on the joined text.
- **The final transcript can differ from the partial ones.** Parakeet may re-segment a sentence once it hears more. Any sentence whose transcript changed gets cleaned again at release, which costs time in the worst case.
- **Context.** Each sentence loses its neighbours, so some edits come out differently ("We're like 90% done, we just…" vs "We're 90% done; we just…").
- **It touches capture and transcription**, and adds GPU work while the user speaks.

A middle path that keeps the output identical does not exist on the decoding side. Other options, all of which also change the output:
- a smaller model for long dictations (Qwen3.5 2B: cleanup p50 136 ms against 287 ms for 4B on the corpus, in the M0 results),
- prompt lookup with its rare differences accepted (1.6× above),
- or the owner accepting rules-only text for very long dictations.

## Reproduce

```
swift build -c release --scratch-path .build-mlx --product murmur-bench
B=.build-mlx/release/murmur-bench
$B pass-cost
$B numerics-test
$B speed-test                                  # 251 inputs, plain vs lookup side by side, ~12 min
$B speed-test --min-words 36 --joins 4,6,8     # the tuning set
MURMUR_LOOKUP_FIXED=1 MURMUR_LOOKUP_DRAFT=3 MURMUR_LOOKUP_PASS=5 $B speed-test --min-words 36 --joins 4,6,8
$B cleanup-pass --provider mlx:qwen3.5-4b --source parakeet-ultra --smart-formatting --limit 5000 --runs 110 --expect <earlier result file>
MURMUR_PROMPT_LOOKUP=1 $B cleanup-pass … --expect <earlier result file>
$B long-test --providers mlx:qwen3.5-4b --save .plain
MURMUR_PROMPT_LOOKUP=1 $B long-test --providers mlx:qwen3.5-4b --expect .plain
$B command-test; MURMUR_PROMPT_LOOKUP=1 $B command-test
$B sentence-test; $B sentence-test --hold-corrections
```

Settings, all read once at launch:
- `MURMUR_PROMPT_LOOKUP=1` turns lookup on.
- `MURMUR_LOOKUP_FIXED=1` makes every guess as long as the limits allow.
- `MURMUR_LOOKUP_DRAFT` (default 31) and `MURMUR_LOOKUP_PASS` (default 32) are the most tokens per guess and per pass.
- `MURMUR_LOOKUP_NGRAM` (default 3) is the longest run of output tokens looked up.
- `MURMUR_LOOKUP_REPLAY=own` replays rejected passes in a pass of their own.

`speed-test` writes every output pair to `results/raw/speed-test.json`.

## Follow-up (2026-10-05): clean as you speak with a hint, tried and not shipped

With prompt lookup on by default, the next idea was to use the idle GPU while the speaker talks without changing the design of the cleanup:
- every few seconds, clean what has been said so far in the background;
- at release, run the usual whole-text cleanup, but copy the prompt-lookup guesses from that background result first.

The output stays the model's own whole-text cleanup, so corrections across sentences and Smart Formatting are unaffected.

**Measured** with a `hint-test` bench: 59 joined dictations, the first 75% standing in for what was said before release, Smart Formatting on, Qwen3.5 4B. Another session's benchmark was running at the same time, so absolute times are noisy; both columns share the noise.

| Words | Final cleanup p50, no hint | With hint | Identical |
|---|---|---|---|
| 16–35 | 365 ms | 340 ms | 20/20 |
| 36–60 | 542 ms | 433 ms | 21/22 |
| 61+ | 792 ms | 664 ms | 17/17 |

With fixed 24-token guesses the hinted 36–60 p50 was 469 ms, and 61+ was 741 ms.

**Not shipped:**
- It saves 10–20% (about 0.1 s) on long dictations.
- To get that, it runs transcription and the cleanup model on the GPU during every long recording. GPU work while recording is what caused the Flow Bar's dropped frames in U3, and it costs battery.
- One of 59 outputs came out worse ("Vite" became "V").
- Prompt lookup alone already took long-dictation cleanup from 774 to 327 ms p50 (`long-test`).

The code was reverted. The idea is recorded here so it isn't tried again without a new reason, for example a faster GPU kernel that makes the final pass cheaper.
