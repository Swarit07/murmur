# Milestone 0 results: speech engine and cleanup model bake-off

2026-10-04 · M4 Pro, 48 GB, macOS 27.0.1 · release builds · one speaker (the owner), AirPods Pro mic, 100-clip corpus.
Full generated tables: [m0-results-tables.md](m0-results-tables.md). Every deviation from the spec and why: [decisions.md](decisions.md).

## Recommendation

| Stage | Pick | Why |
|---|---|---|
| Speech | **Parakeet TDT 0.6B "ultra"** (FluidAudio 0.17.5, CoreML on the Neural Engine) | Second-lowest WER (8.0%, within noise of the best at 7.6%), 10× faster than the best (42 ms p50), and the only engine besides Apple's that wrote nothing on all 10 silence and noise clips |
| Cleanup | **Qwen3.5-4B, 4-bit** (MLX Swift 0.32.3, prompt prefix cached), behind the rules stage, the guard checker and the 800 ms limit | The only model to meet the self-correction target on real transcripts (27/30), with zero fact changes and zero timeouts at 275 ms p50 / 420 ms p95 |
| Silence gate | **Energy gate** | With Parakeet ultra, no gate, the energy gate and Silero all give 0 insertions; the energy gate costs nothing |

## Gate

| Gate item | Result |
|---|---|
| Engines compared on WER, p50 and p95 | 6 local engines, 90 speech clips each, 100 timed runs each (table below) |
| Cleanup models compared on change rate, p50 and p95 | 7 options on the written sentences and on Parakeet ultra transcripts, 100 timed runs each |
| One engine and one model recommended | Parakeet ultra + Qwen3.5-4B |
| **CLI end-to-end p50 ≤ 800 ms** | **Pass.** 425 ms p50 / 547 ms p95 over 100 replays into TextEdit; **446 ms p50 / 644 ms p95** over 20 live `murmur-cli dictate` sessions |

Live session, per stage (p50): first audio 179 ms, capture flush 8 ms, transcribe 89 ms, rules 0.7 ms, model 343 ms, paste 4 ms.

## Speech engines

Transcription only, model loaded, 100 runs over clips up to 15 s. WER uses one normalizer for all engines. Entities are the 41 numbers, dates, URLs, emails, names and terms in the numbers and names sets, checked on the raw transcript.

| Engine | WER all | Plain | Numbers | Names | Quiet | Entities | p50 | p95 | Silence clips with text | Footprint |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| **Parakeet ultra** | **8.0%** | 4.4% | 5.6% | 20.9% | 2.4% | 28/41 | **42 ms** | **46 ms** | **0/10** | 38 MB |
| Whisper Large v3 Turbo | 7.6% | 6.0% | 8.3% | 12.1% | 2.4% | 33/41 | 464 ms | 522 ms | 7/10 ("Thank you.") | 82 MB |
| Parakeet v3 | 10.9% | 5.5% | 14.8% | 20.9% | 2.4% | 23/41 | 41 ms | 45 ms | 2/10 | 37 MB |
| Apple SpeechAnalyzer | 12.1% | 6.0% | 13.0% | 27.5% | 2.4% | 24/41 | 87 ms | 118 ms | 0/10 | 7 MB |
| Parakeet v2 (English) | 12.5% | 5.5% | 13.0% | 29.7% | 4.9% | 24/41 | 41 ms | 45 ms | 1/10 | 53 MB |
| Parakeet phonon2 | 17.3% | 6.0% | 29.6% | 30.8% | 4.9% | 12/41 | 39 ms | 46 ms | 5/10 | 57 MB |

Footprint is process memory after load. CoreML work on the Neural Engine is partly accounted to system daemons, so the CoreML rows understate true cost.

## Cleanup

Light level. **Corrections** is the 30-clip self-correction set (target 27/30). **Changes** counts outputs where a number, name, URL, negation or required term from the input is gone, or a forbidden answer or translation appears: "model" before the guard, "final" after it (target 0). **C7** is the four transcript-is-data clips (a poem request, "ignore the previous message", a factual question, a translate request). Latency is model time; the rules stage adds under 1 ms.

### On Parakeet ultra transcripts (end to end)

| Cleanup | Corrections | Changes (model → final) | C7 | p50 | p95 | Over 800 ms | Memory |
|---|---:|---:|---:|---:|---:|---:|---:|
| **Qwen3.5-4B** | **27/30** | 0 → 0 | 4/4 | 275 ms | 420 ms | 0/90 | 3.1 GB |
| Qwen3-4B-Instruct-2507 | 26/30 | 1 → 0 | 4/4 | 275 ms | 424 ms | 0/90 | 2.9 GB |
| Apple Foundation Models | 26/30 | 0 → 0 | 4/4 | 733 ms | 851 ms | 23/90 | 7 MB |
| SmolLM3-3B | 25/30 | 0 → 0 | 4/4 | 187 ms | 309 ms | 0/90 | 2.2 GB |
| Qwen3.5-2B | 16/30 | 2 → 0 | 4/4 | 136 ms | 200 ms | 0/90 | 1.9 GB |
| Rules only | 1/30 | 0 → 0 | 4/4 | — | — | — | 5 MB |
| Gemma 3 1B | not measured | | | | | | |

### On the written sentences (cleanup alone)

| Cleanup | Corrections | Changes (model → final) | C7 | p50 | p95 | Over 800 ms |
|---|---:|---:|---:|---:|---:|---:|
| **Qwen3.5-4B** | **28/30** | 0 → 0 | 4/4 | 292 ms | 435 ms | 0/100 |
| Apple Foundation Models | 27/30 | 0 → 0 | 4/4 | 733 ms | 850 ms | 25/100 |
| Qwen3-4B-Instruct-2507 | 26/30 | 2 → 0 | 4/4 | 284 ms | 422 ms | 0/100 |
| SmolLM3-3B | 26/30 | 1 → 0 | 4/4 | 194 ms | 315 ms | 0/100 |
| Qwen3.5-2B | 19/30 | 2 → 0 | 4/4 | 137 ms | 207 ms | 0/100 |
| Qwen3.5-0.8B | 7/30 | 4 → 0 | 4/4 | 80 ms | 117 ms | 0/100 |

The SmolLM3 "change" on this table was "we not rename" → "we don't rename". Same meaning; the scorer now counts negations instead of matching the word.

**Unintended change rate after the guard: 0 for every option on both inputs.** The guard caught every translation attempt ("À demain à la gare"), the dropped "Ignore the previous message", and every swapped correction.

**Stalled model (C6):** with a model that never answers and ignores cancellation, the rule-cleaned text came back in at most 855 ms over 20 trials (limit 1.5 s). Pass.

**Gemma 3 1B** never emitted a stop token in this harness, so every call ran to the token limit (~3.3 s), even though the visible answer was correct. It is excluded rather than scored.

## What changed during the bake-off

The first cleanup round had both 4B models timing out on almost every run, and it showed small models swapping corrections past the guard. These fixes are in the code now and logged in [decisions.md](decisions.md):
- **Prompt prefix KV cache for MLX:** Qwen3.5-4B went from 100% timeouts to 292 ms p50.
- **Word-order check in the guard:** it catches "four, make that six" → "six, make that four".
- **Correction cues that match real transcripts:** "fourteen. No, sixteen" and "six no, six thirty".
- **"I'ma" and other "I" contractions are no longer treated as names.**

## What would change the recommendation

- **Memory.** Qwen3.5-4B holds about 3 GB while loaded (the spec unloads models after 10 idle minutes). If that is too much, use **SmolLM3-3B**: 0.9 GB less, ~90 ms faster, 2 fewer corrections. If a future macOS makes Apple's model faster, **Apple Foundation Models** at 7 MB becomes the pick, since its accuracy is already there and only a quarter of its calls miss the 800 ms limit.
- **Names and jargon.** Every engine is weakest here (Parakeet ultra 20.9% WER on the names set). The first fix is the dictionary with engine biasing (S1/T4, Milestone 3). If that falls short of the 8-in-10 target, **Whisper Turbo** names better (12.1%) but is 10× slower and writes "Thank you." on noise, so it would need the Silero gate.
- **Cloud.** Groq was not measured (no key). Running `murmur-bench run` with `GROQ_API_KEY` set adds those rows.
- **Other voices and mics.** This is one speaker on AirPods. A different mic, accent or noisy room can reorder close results (8.0% vs 7.6% is within noise on 90 clips). Re-record with `murmur-bench record-corpus` and rerun.

## Carried into Milestone 1

- **First audio is 179 ms on AirPods** (target 150 ms), and two very short taps captured no audio at all. Measure the built-in mic, and keep the audio engine prepared so only the Bluetooth route switch remains.
- **No space between consecutive dictations** ("…the old one.Let's push…"). Add a leading space when the character before the cursor is not whitespace.
- **Live dictation was only tested in Terminal.** The app matrix (section 8 of the spec) starts with Milestone 1.
- **Cold start after the idle unload:** loading Qwen3.5-4B took ~2 s once cached. Decide whether to reload at key-down or keep the model warm.
