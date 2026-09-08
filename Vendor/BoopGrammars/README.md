# Pinned Tree-sitter grammars

Generated C parsers, scanners and headers copied unchanged from:

| Grammar | Tag | Commit |
|---|---|---|
| [JSON](https://github.com/tree-sitter/tree-sitter-json) | v0.24.8 | ee35a6ebefcef0c5c416c0d1ccec7370cfca5a24 |
| [JavaScript](https://github.com/tree-sitter/tree-sitter-javascript) | v0.25.0 | 44c892e0be055ac465d5eeddae6d3e194424e7de |
| [YAML](https://github.com/tree-sitter-grammars/tree-sitter-yaml) | v0.7.2 | 7708026449bed86239b1cd5bce6e3c34dbca6415 |

The corresponding upstream queries/highlights.scm files are copied to Sources/OhMyBoop/Resources/queries. Each grammar retains its LICENSE. Only runtime C sources and headers are included; generated grammar metadata and upstream tests are omitted. A local Swift package avoids the JSON package's obsolete SwiftTreeSitter dependency identity and gives SwiftPM and Xcode the same parser sources. Update these pins and queries together; do not edit generated parsers manually.
