# Third-party software

simplyHermes is MIT-licensed (see [LICENSE](LICENSE)). It builds on the packages below, which Swift Package Manager
fetches at build time. None of their source is copied into this repository. Each keeps its own license. A build that
contains them, such as a released `.ipa`, must ship their license texts, and for the Apache-2.0 packages their
`NOTICE` files where they have one.

Checked 2026-11-13 against the app's exact package set: `tools/acknowledgements/app-graph.resolved`, SwiftPM's
resolution of this package plus `project.yml`'s app-only packages (MLX, swift-transformers). The table and the in-app
list (Settings › About › Acknowledgements) are written from it by `tools/acknowledgements/generate.py`. Build-time tools
that never ship (swift-syntax, swift-docc-plugin) are left out.

| Package | License | Used by |
|---|---|---|
| [apple/swift-argument-parser](https://github.com/apple/swift-argument-parser) | Apache-2.0 | resolved dependency |
| [apple/swift-asn1](https://github.com/apple/swift-asn1) | Apache-2.0 (has NOTICE) | dependency of swift-crypto |
| [apple/swift-atomics](https://github.com/apple/swift-atomics) | Apache-2.0 | dependency of swift-nio |
| [apple/swift-collections](https://github.com/apple/swift-collections) | Apache-2.0 | dependency of swift-nio |
| [apple/swift-crypto](https://github.com/apple/swift-crypto) | Apache-2.0 (has NOTICE) | HermesSSH |
| [apple/swift-log](https://github.com/apple/swift-log) | Apache-2.0 (has NOTICE) | dependency of the above |
| [apple/swift-nio](https://github.com/apple/swift-nio) | Apache-2.0 (has NOTICE) | HermesKit, HermesSSH |
| [apple/swift-numerics](https://github.com/apple/swift-numerics) | Apache-2.0 | app, through the on-device model packages |
| [apple/swift-system](https://github.com/apple/swift-system) | Apache-2.0 | dependency of swift-nio |
| [attaswift/BigInt](https://github.com/attaswift/BigInt) | MIT | dependency of Citadel |
| [groue/GRDB.swift](https://github.com/groue/GRDB.swift) | MIT | HermesKit |
| [huggingface/swift-huggingface](https://github.com/huggingface/swift-huggingface) | Apache-2.0 | app, through the on-device model packages |
| [huggingface/swift-jinja](https://github.com/huggingface/swift-jinja) | Apache-2.0 | dependency of swift-transformers |
| [huggingface/swift-transformers](https://github.com/huggingface/swift-transformers) | Apache-2.0 | app, on-device models |
| [ibireme/yyjson](https://github.com/ibireme/yyjson) | MIT | app, through the on-device model packages |
| [Joannis/swift-nio-ssh](https://github.com/Joannis/swift-nio-ssh) | Apache-2.0 | HermesSSH |
| [mattt/EventSource](https://github.com/mattt/EventSource) | MIT | app, through the on-device model packages |
| [migueldeicaza/SwiftTerm](https://github.com/migueldeicaza/SwiftTerm) | MIT | HermesUI |
| [ml-explore/mlx-swift](https://github.com/ml-explore/mlx-swift) | MIT | app, on-device models |
| [ml-explore/mlx-swift-lm](https://github.com/ml-explore/mlx-swift-lm) | MIT | app, on-device models |
| [orlandos-nl/Citadel](https://github.com/orlandos-nl/Citadel) | MIT | HermesSSH |
| [pointfreeco/swift-snapshot-testing](https://github.com/pointfreeco/swift-snapshot-testing) | MIT | tests only |

The recorded server answers in `Fixtures/` and the testbed build come from
[NousResearch/hermes-agent](https://github.com/NousResearch/hermes-agent), which is MIT-licensed.
