# Changelog

## [2.1.1] - 2026-10-18

### Changed
- Relaxed `graphemes` and `unicodedb` from exact pins to lower bounds
  (`>= 0.12.0`, `>= 0.13.0`) so downstream projects can resolve newer
  versions, e.g. alongside `regex >= 0.26.1`. Tested with unicodedb 0.13.2
  and 0.14.1.

## [2.0.0] - 2025-12-23

### Initial Release
- Forked from kdl-nim with 98.4% KDL 2.0 spec compliance (673/684 tests)
- Full KDL 2.0 feature support
- Unicode-first design
- Production-ready parser

### Known Limitations
- Float64 precision limits (±1.7E+308)
- Float formatting differences (1e10 → 1.0E+10)
- One complex multiline string edge case
