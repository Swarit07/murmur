# Third-party notices

Murmur itself is under the MIT License (see [LICENSE](LICENSE)). The app is built with the open-source packages below and bundles two font families. Each stays under its own license; the license texts come with each package's source, which Swift Package Manager downloads when you build.

## Fonts (bundled in the app)

| Font | License | License file |
|---|---|---|
| Geist, Geist Mono (Vercel) | SIL Open Font License 1.1 | [Sources/UI/Resources/Fonts/Geist-OFL.txt](Sources/UI/Resources/Fonts/Geist-OFL.txt) |
| Newsreader (Production Type) | SIL Open Font License 1.1 | [Sources/UI/Resources/Fonts/Newsreader-OFL.txt](Sources/UI/Resources/Fonts/Newsreader-OFL.txt) |

The Newsreader files are static cuts made from the variable font by `Tools/fetch_fonts.sh`. Under the OFL they keep the font's name and license.

## Swift packages

| Package | License | Copyright |
|---|---|---|
| [mlx-swift](https://github.com/ml-explore/mlx-swift) | MIT | © 2023 ml-explore |
| [mlx-swift-lm](https://github.com/ml-explore/mlx-swift-lm) | MIT | © 2024 ml-explore |
| [FluidAudio](https://github.com/FluidInference/FluidAudio) | Apache 2.0 | FluidInference |
| [argmax-oss-swift](https://github.com/argmaxinc/argmax-oss-swift) (WhisperKit) | MIT | © 2024 argmax, inc. (see its NOTICES file) |
| [swift-transformers](https://github.com/huggingface/swift-transformers) | Apache 2.0 | Hugging Face |
| [swift-huggingface](https://github.com/huggingface/swift-huggingface) | Apache 2.0 | Hugging Face |
| [swift-jinja](https://github.com/huggingface/swift-jinja) | Apache 2.0 | Hugging Face |
| [GRDB.swift](https://github.com/groue/GRDB.swift) | MIT | © 2015–2025 Gwendal Roué |
| [EventSource](https://github.com/mattt/EventSource) | MIT | © 2025 Mattt |
| [yyjson](https://github.com/ibireme/yyjson) | MIT | © 2020 YaoYuan |
| [swift-argument-parser](https://github.com/apple/swift-argument-parser) | Apache 2.0 | Apple Inc. |
| [swift-collections](https://github.com/apple/swift-collections) | Apache 2.0 | Apple Inc. |
| [swift-crypto](https://github.com/apple/swift-crypto) | Apache 2.0 | Apple Inc. (see its NOTICE.txt) |
| [swift-asn1](https://github.com/apple/swift-asn1) | Apache 2.0 | Apple Inc. (see its NOTICE.txt) |
| [swift-numerics](https://github.com/apple/swift-numerics) | Apache 2.0 | Apple Inc. |
| [swift-syntax](https://github.com/swiftlang/swift-syntax) | Apache 2.0 | Apple Inc. (used to build macros, not shipped in the app) |

## Models (downloaded at first launch, not part of this repository or the app)

Murmur downloads its models from Hugging Face the first time it runs. Each model is under the license on its model page:
- **Speech:** [FluidInference/parakeet-ultra-coreml](https://huggingface.co/FluidInference/parakeet-ultra-coreml), built on NVIDIA Parakeet.
- **Speech detection:** [FluidInference/silero-vad-coreml](https://huggingface.co/FluidInference/silero-vad-coreml).
- **Cleanup:** [mlx-community/Qwen3.5-4B-4bit](https://huggingface.co/mlx-community/Qwen3.5-4B-4bit).
- Other engines and cleanup models you pick in Settings come from their own pages, listed in the app's model catalog.

## Original work

The app icon, brand mark, menu bar glyph, UI icons and sounds are original to Murmur and covered by its MIT License.
