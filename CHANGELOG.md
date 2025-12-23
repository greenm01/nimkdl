# Changelog

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
