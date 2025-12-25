# Package
packageName = "nimkdl"
version = "2.0.5"
author = "niltempus"
description = "KDL 2.0 document parser for Nim"
license = "MIT"
srcDir = "src"
skipFiles = @["src/nimkdl/query.nim", "src/nimkdl/schema.nim"]
bin = @["kdl"]

# Dependencies
requires "nim >= 2.0.0"
requires "bigints"
# For proper unicode handling when printing errors
requires "graphemes == 0.12.0"
requires "unicodedb == 0.13.0"

# Optimization flags for release builds
when not defined(debug):
  switch("opt", "speed")
  switch("define", "danger")
  # Platform-specific optimizations
  when defined(gcc) or defined(clang):
    switch("passC", "-march=native")
    switch("passC", "-ffast-math")

task docs, "Generate documentation":
  # We create the prefs module documentation separately because it is not imported in the main kdl file as it's not backed:js friendly
  exec "nim doc --outdir:docs/kdl --index:on src/kdl/prefs.nim"
  exec "echo \"<meta http-equiv=\\\"Refresh\\\" content=\\\"0; url='kdl/prefs.html'\\\" />\" >> docs/prefs.html"
  # Here we make it so when you click 'Index' in the prefs.html file it redirects to theindex.html.
  exec "echo \"<meta http-equiv=\\\"Refresh\\\" content=\\\"0; url='../theindex.html'\\\" />\" >> docs/kdl/theindex.html"
  exec "nim doc --git.url:https://github.com/niltempus/nimkdl --git.commit:main --outdir:docs --project src/kdl.nim"
  exec "echo \"<meta http-equiv=\\\"Refresh\\\" content=\\\"0; url='kdl.html'\\\" />\" >> docs/index.html"
