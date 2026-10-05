# MLX memory kept after each model reload: found and fixed

2026-10-05, branch `fix/mlx-unload-leak` (from `ui-redesign`). mlx-swift 0.32.3, mlx-swift-lm 3.32.3, macOS 27, M4 Pro.

**Result.** Idle unload no longer leaks. Over 10 unload → reload cycles, the footprint after each unload stays at 129–136 MB, where it used to grow by about 440 MB per reload. Cleanup outputs are unchanged: 110 of 110 corpus outputs are identical, both on a fresh load and after three reloads. "Free memory when idle" is on by default again.

## Measurements

`murmur-bench reload-test` keeps one provider for the whole run, as the app does. Each cycle loads Qwen3.5 4B, cleans one dictation and unloads. Memory is sampled 2 s after each unload, after `Memory.clearCache()`. The footprint is what Activity Monitor shows as Memory. It includes compressed pages, so it shows the leak; the resident size hides it, because macOS compresses the unused buffers.

Footprint after each unload, in MB (MLX arrays still alive in brackets). The "before" run built a new provider each cycle; the old provider rebuilt the model on every load anyway, so that makes no difference.

| Cycle | Before (`ui-redesign`) | After (this branch) | After, with Parakeet too |
|---|---|---|---|
| 1 | 545 (407) | 129 (0) | 175 (0) |
| 2 | 940 (815) | 134 (0) | 194 (0) |
| 3 | 1,487 (1,222) | 135 (0) | 200 (0) |
| 4 | 1,906 (1,630) | 135 (0) | 206 (0) |
| 5 | 2,326 (2,038) | 136 (0) | 102 (0) |
| 6 | 2,743 (2,445) | 136 (0) | 105 (0) |
| 7 | | 136 (0) | 105 (0) |
| 8 | | 136 (0) | 105 (0) |
| 9 | | 136 (0) | |
| 10 | | 136 (0) | |
| Per reload | **+440 MB** | **+0.8 MB** | no growth |

- With models loaded, the footprint after a dictation is 2,650–2,657 MB in every cycle. Before, it rose by the same ~400 MB per reload: 2,692 → 4,891 MB over six cycles.
- The Parakeet column (`--engine parakeet-ultra`) transcribes a corpus clip and unloads both models, as the app does. CoreML moves the first cycles around, but nothing grows.
- A reload now takes 1.3 s instead of 2.0 s, because the model is no longer rebuilt.

## Cause

There were two leaks, both upstream.

**1. Compiled decode traces kept about 408 MB per reload.** mlx-swift-lm compiles Qwen3.5's single-token decode into traces (`CompiledDecodeSegmentCache`). Each trace declares the weights of the layers it runs as inputs. It reads one array it does not declare: the fused GDN input projection (`fusedInputProjection.fused`, 17 MB per layer, 24 layers), which sits in a private helper outside the module tree. MLX therefore stores it in every trace as a constant. Releasing the model releases the traces, but MLX does not free them:

- MLX keeps a compile cache per thread. mlx-swift erases a released trace only from the cache of the thread that releases it, and mlx-swift-lm generates on a fresh dispatch queue each time. The traces were never erased.
- Even when a trace is erased on the right thread, nodes of multi-output operations (`split`, the GDN kernel) can keep each other alive, and with them everything they reach. MLX breaks those cycles only in the `array` destructor, and only when every sibling's reference count is exactly right at that moment. How much survived varied from run to run: confining all MLX work to one thread, so erasure works, still left 85–289 MB per reload.

The evidence:

- Turning compile off (`MLX_DISABLE_COMPILE=1`) or turning the fusion off (`MLX_QWEN_FOUR_GDN=0`) both bring retained arrays to 0 MB.
- A load with no generation leaks nothing, because nothing is traced.
- The leak matches 24 layers × 17 MB. It only matches the embedding table's size by coincidence.

The earlier session on branch `fix/mlx-reload-leak` found the same and drafted upstream reports with minimal repros (`docs/mlx-reload-leak.md` on that branch).

**2. Building a model strands about 4.3 MB.** With leak 1 gone, the footprint still grew 4–5 MB per reload, and the same happened with load → unload alone. `heap` snapshots after each unload show what is left: per load, about 5,900 MLX graph nodes (`ArrayDesc`) are never freed. Among them are 249 `fast::Quantize` nodes (one per quantized layer) and the random initialisation below them (`RandomBits`, `Split`, `Broadcast`, about 1,000 scalar buffers). mlx-swift-lm builds the model with random weights, quantizes them lazily, then assigns the checkpoint's arrays over them (`update(parameters:)`). `Quantize` has three outputs that hold each other as siblings, and an assignment never runs the destructor that would break that cycle. So each layer's unevaluated quantization graph is stranded on every load.

What was not the cause: Murmur's prefix KV cache (same with it off), timing (the same 2 s later), and MLX's buffer cache (`Memory.clearCache()` was already called; it reports 0 MB).

## Fix

In `MLXCleanupProvider` only:

1. **MLX compile is off** (`MLX.compile(enable: false)`, set once before any model runs). With no traces, nothing captures the weights. Outputs are identical (110/110). `MURMUR_MLX_COMPILE=1` turns it back on for comparisons.
2. **Unload keeps the model and empties it.** Every weight is replaced by an unevaluated array of zeros of the same shape, which holds no memory. That also drops Qwen3.5's fused projection. Reload loads the checkpoint back into the same model with mlx-swift-lm's public `loadWeights`: the same weight update, with all keys and shapes checked, the same fused-projection preparation and the same evaluation as a first load. The model is never rebuilt, so leak 2 happens once, at the first load. If a reload fails (for example, the files were deleted), the provider loads from scratch.
3. **A call queued behind an unload refuses to run.** A flag that is only read and written inside `ModelContainer.perform` covers this case. Before, it would have run on the empty model.

Keeping the emptied model costs nothing measurable: 129–136 MB after unload, against 135 MB when the model was dropped (compile off, first cycle). Nothing else changed: capture, transcription, cleanup prompts and output, insertion and shortcuts.

## Other checks

- Qwen3 4B 2507 with speculative decoding, where both the main and the draft model are refilled: footprint after unload 110 → 116 MB over 4 cycles, and 110/110 outputs are identical between a fresh load and after two reloads. SmolLM3 3B: 108 → 110 MB.
- Command Mode bench (`command-test`): 16/16, p50 306 ms (before: 16/16 per run, p50 299 ms).
- With compile on and the model kept (`MURMUR_MLX_COMPILE=1`), the old leak returns: +408 MB per reload. So turning compile off is what fixes it; keeping the model removes the remaining 4–5 MB per reload.
- `MURMUR_NO_MLX=1 swift test`: 170 tests pass. `Scripts/check-tokens.sh` passes. The app itself was not rebuilt or installed: another session is using it.

## Cost

Latency, compile on vs off on this branch, run alternately (cleanup p50 over 200 corpus runs; long dictations of 60–80 words, `long-test`):

| | Compile on | Compile off |
|---|---|---|
| Cleanup p50 / p95, 3 × 200 runs pooled | 253 / 453 ms | 251 / 443 ms |
| Cleanup p50 per round | 255, 251, 250 ms | 256, 258, 242 ms |
| Long dictations p50 per round | 897, 833, 757 ms | 772, 778, 774 ms |
| Long dictations over 800 ms | 4, 2, 2 of 11 | 1, 1, 3 of 11 |

There is no measurable cost; the difference is within run-to-run noise. Outputs are identical with compile on and off. An earlier single pass with `MLX_DISABLE_COMPILE=1` had shown +8 ms (short) and +25 ms (long), also within that noise.

## Alternatives tried

| | Leak per reload | Outputs | Why not |
|---|---|---|---|
| One MLX thread (as on `fix/mlx-reload-leak`) | 85–289 MB, varies | identical | Bug 2 above still keeps some of the projections |
| One MLX thread + fusion off (`fix/mlx-reload-leak`) | 0 MB arrays, +4–5 MB footprint | 109/110 (one drops a pair of backticks), one more guard fallback | Changes cleanup output |
| Compile off, model rebuilt on each load | 0 MB arrays, +4.7 MB footprint | identical | Still grows; fixed by keeping the model |
| Releasing malloc's free pages after unload | no change | n/a | The remaining ~130 MB is live memory |
| Patching mlx-swift-lm so the traces declare the fused projection | not tried | identical | Needs a fork of the dependency |

## Reproduce

```
swift build -c release --scratch-path .build-mlx --product murmur-bench
.build-mlx/release/murmur-bench reload-test --cycles 10
.build-mlx/release/murmur-bench reload-test --cycles 8 --engine parakeet-ultra --corpus <folder with corpus audio>
MURMUR_MLX_NO_WARMUP=1 .build-mlx/release/murmur-bench reload-test --cycles 10 --load-only
.build-mlx/release/murmur-bench cleanup-pass --provider mlx:qwen3.5-4b --source parakeet-ultra --smart-formatting --reloads 3
```

To see the old leak, check out `ui-redesign`, or run with `MURMUR_MLX_COMPILE=1` to see leak 1 alone.

## Upstream

Worth reporting, so that compile can go back on:

- mlx-swift: erase a released `CompiledFunction` from every thread's compile cache that traced it.
- mlx: break multi-output sibling cycles when a compile cache entry is destroyed, and when an `array` is assigned over (not only in its destructor).
- mlx-swift-lm: declare Qwen3.5's fused GDN projection as trace state; avoid building random weights that `loadWeights` replaces.
