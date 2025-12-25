# nimkdl

A KDL 2.0 document parser for Nim.

![Tests](https://img.shields.io/badge/tests-100%25%20passing-brightgreen)
![Nim](https://img.shields.io/badge/nim-2.0%2B-blue)
![License](https://img.shields.io/badge/license-MIT-green)

## Features

- **100% KDL 2.0 Spec Compliance** (670/670 official tests passing)
- **High Performance** (2.3x faster than kdl-rs in benchmarks)
- **Full Unicode Support** (identifiers, whitespace, escapes)
- **Robust Parsing** (multiline strings, slashdash, type annotations)
- **Encoder/Decoder** (serialize Nim objects to/from KDL)
- **Minimal Dependencies** (graphemes, unicodedb, bigints)

## Performance

nimkdl is highly optimized for speed while maintaining 100% spec compliance:

- **2.3x faster** than kdl-rs (Rust) overall throughput
- **10.8K operations/sec** average (vs 4.7K for kdl-rs)
- **27.8K ops/s** on small files (Cargo.kdl)
- **33-55% faster** on typical configuration files

Optimizations include zero-copy string slicing, direct integer parsing, ASCII fast-paths, and aggressive compiler optimizations. See [BENCHMARK_COMPARISON.md](BENCHMARK_COMPARISON.md) for detailed results.

**Run benchmarks:**
```bash
nim c -r -d:release benchmark.nim
```

## Installation

```bash
nimble install nimkdl
```

## Quick Start

```nim
import kdl

# Parse KDL from string
let doc = parseKdl("""
  server {
    host "localhost"
    port 8080
    ssl #true
  }
""")

# Access nodes and values
echo doc[0].name  # "server"
echo doc[0].children[0].args[0].getString()  # "localhost"
echo doc[0].children[1].args[0].getInt()  # 8080
echo doc[0].children[2].args[0].getBool()  # true

# Pretty print
echo doc.pretty()
```

## Examples

Check out the [`examples/`](examples/) directory for more detailed demonstrations:

- **[basic_usage.nim](examples/basic_usage.nim)** - Parsing, accessing values, type annotations
- **[config_file.nim](examples/config_file.nim)** - Reading and working with config files
- **[error_handling.nim](examples/error_handling.nim)** - Handling parse errors gracefully
- **[building_documents.nim](examples/building_documents.nim)** - Creating KDL programmatically

Run any example:
```bash
nim r examples/basic_usage.nim
```

## What is KDL?

KDL (pronounced "cuddle") is a document language with a focus on human readability and ease of authoring. It's similar to JSON but more flexible and pleasant to work with.

**Example KDL document:**
```kdl
package {
  name "my-app"
  version "1.0.0"
  authors "Alice" "Bob"

  dependencies {
    http "~>1.0"
    json-lib "^2.1.0"
  }
}

(dev)scripts {
  build "nim c -d:release src/main.nim"
  test "nimble test"
}
```

Learn more at [kdl.dev](https://kdl.dev)

## KDL 2.0 Features

nimkdl implements the complete KDL 2.0 specification:

### Type Annotations
```kdl
age (i32)25
price (f64)19.99
birthday (date)"2000-01-01"
```

### Keyword Values
Use `#` prefix for language keywords:
```kdl
node #true #false #null #inf #-inf #nan
```

### Raw Strings
```kdl
path #"C:\Users\Alice\Documents"#
regex #"[a-z]+"#
```

### Multiline Strings with Dedentation
```kdl
description """
  This is a multiline string.
  Leading indentation is automatically removed.
  """
```

### Slashdash Comments
Comment out nodes, arguments, or properties:
```kdl
server {
  host "localhost"
  /-port 8080       // Commented out
  /-ssl #true       // Also commented
}

/-database {        // Entire node commented
  host "db.local"
}
```

## Advanced Usage

### Encoding/Decoding Nim Objects

```nim
import kdl, kdl/[encoder, decoder]

type
  Config = object
    server: ServerConfig
    database: DatabaseConfig

  ServerConfig = object
    host: string
    port: int
    ssl: bool

  DatabaseConfig = object
    driver: string
    host: string
    port: int

# Encode Nim object to KDL
let config = Config(
  server: ServerConfig(host: "localhost", port: 8080, ssl: true),
  database: DatabaseConfig(driver: "postgres", host: "db.local", port: 5432)
)

let kdl = encode(config)
echo kdl.pretty()

# Decode KDL to Nim object
let parsed = parseKdl(readFile("config.kdl"))
let loadedConfig = parsed.decode(Config)
```

### Building Documents Programmatically

```nim
import kdl

let doc = toKdlDoc:
  server(host = "localhost", port = 8080):
    ssl #true
    workers 4

  (log-level)"info"
  users "alice" "bob"

echo doc.pretty()
```

### XiK and JiK

Convert between KDL and XML/JSON:

```nim
import kdl/[xik, jik]

# XML-in-KDL
let xmlDoc = parseXik("""
  html {
    body {
      p "Hello, World!"
    }
  }
""")

# JSON-in-KDL
let jsonDoc = parseJik("""
  - object {
    - "name" "Alice"
    - "age" 30
  }
""")
```

For complete API reference, generate documentation locally:
```bash
nimble docs
```

Or view the inline documentation in the source files.

## Credits

Core parser rewritten for 100% KDL 2.0 spec compliance with [Claude Code](https://claude.com/claude-code).

Built upon the foundation of [kdl-nim](https://github.com/Patitotective/kdl-nim) by Patitotective, which provides the encoder, decoder, XiK/JiK, and type system infrastructure.

## License

MIT - See LICENSE file
