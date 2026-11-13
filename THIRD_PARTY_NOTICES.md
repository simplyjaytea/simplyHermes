# Third-party software

simplyHermes is MIT-licensed (see [LICENSE](LICENSE)). It builds on the packages below, which Swift Package Manager
fetches at build time. None of their source is copied into this repository. Each keeps its own license. A build that
contains them, such as a released `.ipa`, must ship their license texts, and for the Apache-2.0 packages their
`NOTICE` files where they have one.

Checked 2026-11-12 against `Package.resolved` and `project.yml`.

| Package | License | Used by |
|---|---|---|
| [apple/swift-nio](https://github.com/apple/swift-nio) | Apache-2.0 (has NOTICE.txt) | HermesKit, HermesSSH |
| [apple/swift-crypto](https://github.com/apple/swift-crypto) | Apache-2.0 (has NOTICE.txt) | HermesSSH |
| [apple/swift-log](https://github.com/apple/swift-log) | Apache-2.0 (has NOTICE.txt) | dependency of the above |
| [apple/swift-asn1](https://github.com/apple/swift-asn1) | Apache-2.0 | dependency of swift-crypto |
| [apple/swift-atomics](https://github.com/apple/swift-atomics) | Apache-2.0 | dependency of swift-nio |
| [apple/swift-collections](https://github.com/apple/swift-collections) | Apache-2.0 | dependency of swift-nio |
| [apple/swift-system](https://github.com/apple/swift-system) | Apache-2.0 | dependency of swift-nio |
| [apple/swift-argument-parser](https://github.com/apple/swift-argument-parser) | Apache-2.0 | resolved dependency |
| [Joannis/swift-nio-ssh](https://github.com/Joannis/swift-nio-ssh) | Apache-2.0 | HermesSSH |
| [orlandos-nl/Citadel](https://github.com/orlandos-nl/Citadel) | MIT | HermesSSH |
| [attaswift/BigInt](https://github.com/attaswift/BigInt) | MIT | dependency of Citadel |
| [groue/GRDB.swift](https://github.com/groue/GRDB.swift) | MIT | HermesKit |
| [migueldeicaza/SwiftTerm](https://github.com/migueldeicaza/SwiftTerm) | MIT | HermesUI |
| [ml-explore/mlx-swift](https://github.com/ml-explore/mlx-swift) | MIT | app, on-device models |
| [ml-explore/mlx-swift-lm](https://github.com/ml-explore/mlx-swift-lm) | MIT | app, on-device models |
| [huggingface/swift-transformers](https://github.com/huggingface/swift-transformers) | Apache-2.0 | app, on-device models |
| [huggingface/swift-jinja](https://github.com/huggingface/swift-jinja) | Apache-2.0 | dependency of swift-transformers |
| [pointfreeco/swift-snapshot-testing](https://github.com/pointfreeco/swift-snapshot-testing) | MIT | tests only |

The recorded server answers in `Fixtures/` and the testbed build come from
[NousResearch/hermes-agent](https://github.com/NousResearch/hermes-agent), which is MIT-licensed.
