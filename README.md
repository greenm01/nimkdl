# nimkdl

A KDL 2.0 document parser for Nim.

![Tests](https://img.shields.io/badge/tests-98.4%25%20passing-brightgreen)
![Nim](https://img.shields.io/badge/nim-2.0%2B-blue)
![License](https://img.shields.io/badge/license-MIT-green)

## Features

- **98.4% KDL 2.0 Spec Compliance** (673/684 official tests)
- **Full Unicode Support** (identifiers, whitespace, escapes)
- **Robust Edge Case Handling** (multiline strings, slashdash, escaping)
- **Minimal Dependencies** (graphemes, unicodedb)
- **Production Ready**

## Installation

```bash
nimble install nimkdl
```

## Quick Start

```nim
import nimkdl

# Parse KDL from string
let doc = parseKdl("""
  node "value" key=123 {
    child #true
  }
""")

# Access nodes
echo doc[0].name  # "node"
echo doc[0].args[0]  # "value"
echo doc[0].props["key"]  # 123

# Pretty print
echo doc.pretty()
```

## What is KDL?

KDL (pronounced "cuddle") is a document language with a focus on human
readability and ease of authoring. It's similar to JSON but more flexible
and pleasant to work with.

Learn more at [kdl.dev](https://kdl.dev)

## KDL 2.0 Support

nimkdl implements the KDL 2.0 specification, including:
- Type annotations `(i32)123`, `(date)"2024-01-01"`
- Keywords with `#` prefix: `#true`, `#false`, `#null`, `#inf`, `#nan`
- Raw strings: `#"no\\escapes"#`
- Multiline strings with dedentation
- Slashdash comments: `/-` to comment out nodes/values
- Line continuations: `\\` for multi-line values

## Known Limitations

- **Float precision**: Limited to float64 range (±1.7E+308)
  - Values like `1.23E+1000` overflow to `#inf`
  - Alternative: Use string values for extreme precision needs
- **Float formatting**: `1e10` outputs as `1.0E+10` (minor difference)
- **Complex multiline edge case**: One test with unusual whitespace combinations fails

These represent 1.6% of the test suite and are documented limitations.

## Credits

Based on [kdl-nim](https://github.com/Patitotective/kdl-nim) by Patitotective.

Enhanced with Claude Code to achieve 98.4% spec compliance.

## License

MIT - See LICENSE file
