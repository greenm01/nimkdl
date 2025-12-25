## KDL v2 Parser - Single-pass recursive descent parser
##
## This is a complete rewrite of the KDL parser based on kdl-rs's proven
## architecture. It uses a hand-rolled recursive descent approach that closely
## mirrors the Winnow combinator patterns from kdl-rs.

import std/[strutils, parseutils, unicode, options, strformat, tables]
import bigints
import ./types
import ./nodes
import ./format
import ./combinator
import ./new_error
import ./internal_types

# Forward declarations
proc nodes(p: Parser): ParseResult[seq[InternalNode]]

# Helper functions moved to top to avoid type inference issues

proc parseDecimalDigits(p: Parser, allowSign: bool = true): ParseResult[string] =
  var numStr = ""
  if allowSign and not p.atEnd() and p.source[p.pos] in {'+', '-'}:
    numStr.add(p.source[p.pos])
    p.advance()

  # Must start with a digit (not underscore)
  if p.atEnd() or p.source[p.pos] notin Digits:
    return ParseResult[string](ok: false)

  let digitStart = p.pos
  while not p.atEnd():
    let c = p.source[p.pos]
    if c in Digits:
      numStr.add(c)
      p.advance()
    elif c == '_':
      p.advance()
    else:
      break
  if p.pos == digitStart:
    return ParseResult[string](ok: false)
  return ParseResult[string](ok: true, value: numStr, endPos: p.pos)

proc slashdash(p: Parser): ParseResult[string] =
  let start = p.pos
  if p.tryStr("/-").ok:
    return ParseResult[string](ok: true, value: "/-", endPos: p.pos)
  return ParseResult[string](ok: false)

# Character-level parsers

const NEWLINES = [
  "\r\n",      # CRLF
  "\r",        # CR
  "\n",        # LF
  "\u{0085}",  # NEL
  "\u{000B}",  # VT
  "\u{000C}",  # FF
  "\u{2028}",  # LS
  "\u{2029}",  # PS
]

proc newline(p: Parser): ParseResult[string] =
  ## Parses a newline sequence
  for nl in NEWLINES:
    let maybeStr = p.peekStr(nl.len)
    if maybeStr.isSome and maybeStr.get == nl:
      p.advance(nl.len)
      return success(nl, p.pos)
  return failure[string]()

proc unicodeSpace(p: Parser): ParseResult[string] =
  ## Parses a single Unicode whitespace character
  if p.atEnd():
    return failure[string]()

  var pos = p.pos
  let r = p.source.runeAt(pos)

  if isUnicodeSpace(r):
    let start = p.pos
    p.pos += r.size
    return success(p.source[start ..< p.pos], p.pos)

  return failure[string]()

proc singleLineComment(p: Parser): ParseResult[string] =
  ## Parses a single-line comment starting with //
  let start = p.pos
  if not p.tryStr("//").ok:
    return failure[string]()

  # Take everything until newline
  var comment = "//"
  while not p.atEnd():
    let c = p.source[p.pos]
    if c == '\n' or c == '\r':
      break
    comment.add(c)
    p.advance()

  return success(comment, p.pos)

proc multiLineComment(p: Parser): ParseResult[string] =
  ## Parses a multi-line comment /* ... */ with nesting support
  let start = p.pos
  if not p.tryStr("/*").ok:
    return failure[string]()

  var comment = "/*"
  var depth = 1

  while not p.atEnd() and depth > 0:
    # Check for nested comment start
    if p.peekStr(2).isSome and p.peekStr(2).get == "/*":
      comment.add("/*")
      p.advance(2)
      depth += 1
    # Check for comment end
    elif p.peekStr(2).isSome and p.peekStr(2).get == "*/":
      comment.add("*/")
      p.advance(2)
      depth -= 1
    else:
      comment.add(p.source[p.pos])
      p.advance()

  if depth > 0:
    p.addError("Unclosed multi-line comment", "expected */")
    return failure[string]()

  return success(comment, p.pos)

proc ws(p: Parser): ParseResult[string] =
  ## Parses whitespace (unicode space or multi-line comment)
  let usRes = unicodeSpace(p)
  if usRes.ok:
    return usRes

  let mlcRes = multiLineComment(p)
  if mlcRes.ok:
    return mlcRes

  return failure[string]()

proc wss(p: Parser): string =
  ## Parses zero or more whitespace
  result = ""
  while true:
    let res = ws(p)
    if res.ok:
      result.add(res.value)
    else:
      break

proc wsp(p: Parser): ParseResult[string] =
  ## Parses one or more whitespace
  let first = ws(p)
  if not first.ok:
    return failure[string]()

  var spaces = first.value
  spaces.add(wss(p))
  return success(spaces, p.pos)

proc lineSpace(p: Parser): ParseResult[string] =
  ## Parses line-space: newline | ws | single-line-comment
  let nlRes = newline(p)
  if nlRes.ok:
    return nlRes

  let wsRes = ws(p)
  if wsRes.ok:
    return wsRes

  let slcRes = singleLineComment(p)
  if slcRes.ok:
    return slcRes

  return failure[string]()

proc escline(p: Parser): ParseResult[string] =
  ## Parses an escaped line continuation: \ + (whitespace|comment) + newline + whitespace
  let start = p.pos
  if not p.tryChar('\\').ok:
    return failure[string]()

  var escape = "\\"
  escape.add(wss(p))

  # Also try to consume single-line comment before newline
  let slcRes = singleLineComment(p)
  if slcRes.ok:
    escape.add(slcRes.value)

  let nlRes = newline(p)
  if nlRes.ok:
    escape.add(nlRes.value)
    escape.add(wss(p))
    return success(escape, p.pos)

  # If no newline but at EOF, escline is still valid
  if p.atEnd():
    return success(escape, p.pos)

  # Not followed by newline or EOF - invalid escline
  p.pos = start
  return failure[string]()

proc nodeSpace(p: Parser): ParseResult[string] =
  ## Parses node-space: (ws* escline ws*) | ws+
  let start = p.pos

  # Try: ws* escline ws*
  let leading = wss(p)
  let escRes = escline(p)
  if escRes.ok:
    let trailing = wss(p)
    return success(leading & escRes.value & trailing, p.pos)

  # Reset and try ws+
  p.pos = start
  return wsp(p)

# String parsing

proc resolveEscapeSequence(escSeq: string): string =
  ## Resolves a stored escape sequence (e.g., "\\n" -> newline)
  ## This is called AFTER dedentation for multiline strings
  if escSeq.len < 2 or escSeq[0] != '\\':
    return escSeq

  let c = escSeq[1]
  case c
  of 'n': return "\n"
  of 'r': return "\r"
  of 't': return "\t"
  of '\\': return "\\"
  of '"': return "\""
  of 'b': return "\b"
  of 'f': return "\f"
  of 's': return " "
  of 'u':
    # Unicode escape: \u{HEXDIGITS}
    if escSeq.len > 3 and escSeq[2] == '{':
      let closeBrace = escSeq.find('}', 3)
      if closeBrace > 3:
        let hexDigits = escSeq[3..<closeBrace]
        try:
          let codepoint = parseHexInt(hexDigits)
          if codepoint <= 0x10FFFF:
            return Rune(codepoint).toUTF8
        except:
          discard
    return escSeq  # Invalid, return as-is
  else:
    return escSeq  # Unknown escape, return as-is

proc resolveNonWhitespaceEscapes(s: string): string =
  ## Resolves all non-whitespace escapes in a string after dedentation
  ## This implements the KDL v2 spec requirement to resolve non-whitespace
  ## escapes AFTER dedentation and blank line detection
  result = ""
  var i = 0
  while i < s.len:
    if s[i] == '\\' and i + 1 < s.len:
      # Check if this is an escape we should resolve
      let next = s[i + 1]
      if next in {'n', 'r', 't', '\\', '"', 'b', 'f', 's', 'u'}:
        # Find the full escape sequence
        var escSeq = "\\"
        i += 1
        escSeq.add(s[i])
        i += 1

        # For \u{...}, include the full sequence
        if next == 'u' and i < s.len and s[i] == '{':
          escSeq.add(s[i])
          i += 1
          while i < s.len and s[i] != '}':
            escSeq.add(s[i])
            i += 1
          if i < s.len:  # Include closing }
            escSeq.add(s[i])
            i += 1

        result.add(resolveEscapeSequence(escSeq))
      else:
        # Not a valid escape, keep backslash
        result.add(s[i])
        i += 1
    else:
      result.add(s[i])
      i += 1

proc escapedCharMultiline(p: Parser): ParseResult[string] =
  ## Parses escape in multiline string - only resolves whitespace escapes immediately
  ## Other escapes are stored literally for later resolution (per KDL v2 spec)
  if not p.tryChar('\\').ok:
    return failure[string]()

  if p.atEnd():
    p.unexpectedEof("escape sequence")
    return failure[string]()

  let c = p.source[p.pos]

  # Check if this is a whitespace escape (must be resolved immediately)
  if c in {' ', '\t', '\n', '\r'}:
    p.advance()
    # Whitespace escape: consume all following whitespace
    while not p.atEnd():
      let ch = p.source[p.pos]
      if ch in {' ', '\t', '\n', '\r'}:
        p.advance()
      else:
        break
    return success("", p.pos)

  # For non-whitespace escapes, store literally for later resolution
  p.advance()

  # Validate it's a known escape sequence
  if c in {'n', 'r', 't', '\\', '"', 'b', 'f', 's'}:
    return success("\\" & $c, p.pos)
  elif c == 'u':
    # Store \u{...} literally
    var escSeq = "\\u"
    if not p.atEnd() and p.source[p.pos] == '{':
      escSeq.add('{')
      p.advance()
      while not p.atEnd() and p.source[p.pos] != '}':
        escSeq.add(p.source[p.pos])
        p.advance()
      if not p.atEnd() and p.source[p.pos] == '}':
        escSeq.add('}')
        p.advance()
    return success(escSeq, p.pos)
  else:
    p.addError("Invalid escape sequence: \\" & $c)
    return failure[string]()

proc escapedChar(p: Parser): ParseResult[string] =
  ## Parses an escaped character sequence (for single-line strings)
  if not p.tryChar('\\').ok:
    return failure[string]()

  if p.atEnd():
    p.unexpectedEof("escape sequence")
    return failure[string]()

  let c = p.source[p.pos]
  p.advance()

  case c
  of 'n': return success("\n", p.pos)
  of 'r': return success("\r", p.pos)
  of 't': return success("\t", p.pos)
  of '\\': return success("\\", p.pos)
  of '"': return success("\"", p.pos)
  of 'b': return success("\b", p.pos)
  of 'f': return success("\f", p.pos)
  of 's': return success(" ", p.pos)
  of 'u':
    # Unicode escape: \u{HEXDIGITS}
    if not p.expect('{').ok:
      p.addError("Expected '{' after \\u")
      return failure[string]()

    var hexDigits = ""
    while not p.atEnd() and p.source[p.pos] != '}':
      let c = p.source[p.pos]
      if c in HexDigits:
        hexDigits.add(c)
        p.advance()
      else:
        break

    if not p.expect('}').ok:
      p.addError("Expected '}' after Unicode escape")
      return failure[string]()

    if hexDigits.len == 0 or hexDigits.len > 6:
      p.addError("Invalid Unicode escape length")
      return failure[string]()

    try:
      let codepoint = parseHexInt(hexDigits)
      if codepoint > 0x10FFFF:
        p.addError("Unicode code point too large")
        return failure[string]()
      # KDL v2 spec: Reject Unicode surrogates (U+D800-U+DFFF)
      if codepoint >= 0xD800 and codepoint <= 0xDFFF:
        p.addError("Unicode surrogates (U+D800..U+DFFF) not allowed in escape sequences")
        return failure[string]()
      let rune = Rune(codepoint)
      if isDisallowedCodePoint(rune):
        p.disallowedCodePointError(rune)
        return failure[string]()
      return success(rune.toUTF8, p.pos)
    except:
      p.addError("Invalid Unicode escape")
      return failure[string]()
  of ' ', '\t', '\n', '\r':
    # Whitespace escape: backslash followed by whitespace consumes all following whitespace
    # This is used for line continuation in strings
    # The backslash and all following whitespace are discarded
    while not p.atEnd():
      let ch = p.source[p.pos]
      if ch in {' ', '\t', '\n', '\r'}:
        p.advance()
      else:
        break
    return success("", p.pos)
  else:
    p.addError("Invalid escape sequence: \\" & $c)
    return failure[string]()

proc quotedString(p: Parser): ParseResult[KdlVal] =
  ## Parses a quoted string: "..." or """..."""
  let start = p.pos
  if not p.tryChar('"').ok:
    return failure[KdlVal]()

  # Check for multiline string (""")
  let isMultiline = p.peekStr(2).isSome and p.peekStr(2).get == "\"\""
  if isMultiline:
    p.advance(2)  # consume the other two quotes

    # Must have at least one newline after opening """
    let nlRes = newline(p)
    if not nlRes.ok:
      p.addError("Multiline string must start with a newline")
      return failure[KdlVal]()

    # Collect lines
    var lines: seq[string] = @[]
    var currentLine = ""

    while not p.atEnd():
      let c = p.source[p.pos]

      # Check for closing """
      if c == '"':
        if p.peekStr(3).isSome and p.peekStr(3).get == "\"\"\"":
          p.advance(3)
          # Add the current line (might be closing line with indent)
          lines.add(currentLine)
          # Dedent based on last line's indentation (Unicode whitespace)
          var indent = ""
          if lines.len > 0:
            let lastLine = lines[lines.len - 1]
            var pos = 0
            while pos < lastLine.len:
              let r = lastLine.runeAt(pos)
              if isUnicodeSpace(r):
                # Add the UTF-8 bytes for this rune
                for i in 0 ..< r.size:
                  indent.add(lastLine[pos + i])
                pos += r.size
              else:
                break
          # Remove indent from all lines and remove last line (closing delimiter line)
          # Empty lines (whitespace-only) should be reflected as empty per spec
          var dedented: seq[string] = @[]
          for i in 0 ..< lines.len - 1:
            let line = lines[i]
            # Check if line is empty (whitespace-only or truly empty)
            # Must check for Unicode whitespace, not just ASCII space/tab
            var isEmpty = true
            var pos = 0
            while pos < line.len:
              let r = line.runeAt(pos)
              if not isUnicodeSpace(r):
                isEmpty = false
                break
              pos += r.size

            if isEmpty:
              # Empty line - add as empty string
              dedented.add("")
            elif line.startsWith(indent):
              # Non-empty line starting with indent - remove indent
              dedented.add(line[indent.len .. ^1])
            else:
              # Non-empty line not starting with indent - keep as-is
              dedented.add(line)

          # Per KDL v2 spec: resolve non-whitespace escapes AFTER dedentation
          let dedentedStr = dedented.join("\n")
          let finalStr = resolveNonWhitespaceEscapes(dedentedStr)
          return success(initKString(finalStr), p.pos)
        else:
          currentLine.add(c)
          p.advance()
      elif c == '\\':
        # Use multiline-specific escape handler that defers non-whitespace escapes
        let escRes = escapedCharMultiline(p)
        if escRes.ok:
          currentLine.add(escRes.value)
        else:
          return failure[KdlVal]()
      elif c == '\n' or c == '\r':
        lines.add(currentLine)
        currentLine = ""
        let nlRes = newline(p)
        if not nlRes.ok:
          p.advance()
      else:
        currentLine.add(c)
        p.advance()

    p.unexpectedEof("multiline quoted string")
    return failure[KdlVal]()

  # Single-line string
  var str = ""

  while not p.atEnd():
    let c = p.source[p.pos]

    if c == '"':
      p.advance()
      return success(initKString(str), p.pos)
    elif c == '\\':
      let escRes = escapedChar(p)
      if not escRes.ok:
        return failure[KdlVal]()
      str.add(escRes.value)
    elif c == '\n' or c == '\r':
      p.addError("Unescaped newline in string")
      return failure[KdlVal]()
    else:
      # Check for disallowed code points
      let r = p.source.runeAt(p.pos)
      if isDisallowedCodePoint(r):
        p.disallowedCodePointError(r)
        return failure[KdlVal]()
      str.add(c)
      p.advance()

  p.unexpectedEof("quoted string")
  return failure[KdlVal]()

proc rawString(p: Parser): ParseResult[KdlVal] =
  ## Parses a raw string: #"..."# or #"""..."""# (with any number of #)
  let start = p.pos

  # Count leading hashes
  var hashCount = 0
  while not p.atEnd() and p.source[p.pos] == '#':
    hashCount += 1
    p.advance()

  if hashCount == 0:
    return failure[KdlVal]()

  # Check for triple-quote (multiline raw string)
  let isMultiline = p.peekStr(3).isSome and p.peekStr(3).get == "\"\"\""

  if isMultiline:
    # Multiline raw string
    p.advance(3)  # Skip """

    # Must have at least one newline after opening """
    let nlRes = newline(p)
    if not nlRes.ok:
      p.addError("Multiline raw string must start with a newline")
      return failure[KdlVal]()

    var lines: seq[string] = @[]
    var currentLine = ""
    var foundClosing = false

    while not p.atEnd():
      # Check for closing """ followed by matching hashes
      if p.peekStr(3).isSome and p.peekStr(3).get == "\"\"\"":
        let afterQuotes = p.pos + 3
        var closingHashes = 0
        var checkPos = afterQuotes
        while checkPos < p.source.len and p.source[checkPos] == '#' and closingHashes < hashCount:
          closingHashes += 1
          checkPos += 1

        if closingHashes == hashCount:
          # Found closing delimiter
          p.pos = checkPos
          lines.add(currentLine)
          foundClosing = true
          break

      # Regular character
      let c = p.source[p.pos]
      if c == '\n' or c == '\r':
        lines.add(currentLine)
        currentLine = ""
        let nlRes = newline(p)
        if not nlRes.ok:
          p.advance()
      else:
        currentLine.add(c)
        p.advance()

    if not foundClosing:
      p.unexpectedEof("multiline raw string")
      return failure[KdlVal]()

    # Dedent based on last line's indentation (Unicode whitespace)
    var indent = ""
    if lines.len > 0:
      let lastLine = lines[lines.len - 1]
      var pos = 0
      while pos < lastLine.len:
        let r = lastLine.runeAt(pos)
        if isUnicodeSpace(r):
          # Add the UTF-8 bytes for this rune
          for i in 0 ..< r.size:
            indent.add(lastLine[pos + i])
          pos += r.size
        else:
          break

    # Remove indent from all lines except the last line (closing delimiter line)
    # Empty lines (whitespace-only) should be reflected as empty per spec
    var dedented: seq[string] = @[]
    for i in 0 ..< lines.len - 1:
      let line = lines[i]
      # Check if line is empty (whitespace-only or truly empty)
      # Must check for Unicode whitespace, not just ASCII space/tab
      var isEmpty = true
      var pos = 0
      while pos < line.len:
        let r = line.runeAt(pos)
        if not isUnicodeSpace(r):
          isEmpty = false
          break
        pos += r.size

      if isEmpty:
        # Empty line - add as empty string
        dedented.add("")
      elif line.startsWith(indent):
        # Non-empty line starting with indent - remove indent
        dedented.add(line[indent.len .. ^1])
      else:
        # Non-empty line not starting with indent - keep as-is
        dedented.add(line)

    return success(initKString(dedented.join("\n")), p.pos)

  else:
    # Single-line raw string
    if not p.tryChar('"').ok:
      return failure[KdlVal]()

    var str = ""

    while not p.atEnd():
      let c = p.source[p.pos]

      # Check for closing quote followed by matching hashes
      if c == '"':
        p.advance()
        var closingHashes = 0
        while not p.atEnd() and p.source[p.pos] == '#' and closingHashes < hashCount:
          closingHashes += 1
          p.advance()

        if closingHashes == hashCount:
          return success(initKString(str), p.pos)
        else:
          # Not enough hashes, continue
          str.add('"')
          str.add(repeat('#', closingHashes))
      elif c == '\n' or c == '\r':
        p.addError("Unescaped newline in single-line raw string")
        return failure[KdlVal]()
      else:
        str.add(c)
        p.advance()

    p.unexpectedEof("raw string")
    return failure[KdlVal]()

proc identifierString(p: Parser): ParseResult[KdlVal] =
  ## Parses an identifier as a bare string (Unicode-aware)
  let start = p.pos

  if p.atEnd():
    return failure[KdlVal]()

  # Parse first rune - identifier must not start with digit
  let firstRune = p.source.runeAt(p.pos)

  # Check if first character is valid
  if isDisallowedCodePoint(firstRune):
    return failure[KdlVal]()

  if isUnicodeSpace(firstRune):
    return failure[KdlVal]()

  # Check for ASCII disallowed characters
  let firstChar = firstRune.int32
  if firstChar < 128:
    let c = char(firstChar)
    if c in {'(', ')', '{', '}', '[', ']', ';', '=', '"', '\\', '#', '/', ' ', '\t', '\v', '\n', '\r'}:
      return failure[KdlVal]()
    if c in Digits:
      return failure[KdlVal]()
    # Check for dot followed by digit (looks like malformed float: .0, .123)
    if c == '.':
      let nextPos = p.pos + 1
      if nextPos < p.source.len and p.source[nextPos] in Digits:
        return failure[KdlVal]()

  var ident = ""
  while not p.atEnd():
    # Check for comment starts: // or /*
    if p.source[p.pos] == '/':
      let next = p.peek()
      if next.isSome and next.get in {'/', '*'}:
        # Stop before comment
        break

    # Parse rune
    let r = p.source.runeAt(p.pos)
    let runeChar = r.int32

    # Check if this rune is allowed in identifiers
    var isValid = true

    # Check for disallowed code points
    if isDisallowedCodePoint(r):
      isValid = false
    # Check for Unicode whitespace
    elif isUnicodeSpace(r):
      isValid = false
    # Check for ASCII disallowed characters
    elif runeChar < 128:
      let c = char(runeChar)
      if c in {'(', ')', '{', '}', '[', ']', ';', '=', '"', '\\', '#', '/', ' ', '\t', '\v', '\n', '\r'}:
        isValid = false

    if isValid:
      # Add the UTF-8 bytes for this rune
      for i in 0 ..< r.size:
        ident.add(p.source[p.pos + i])
      p.pos += r.size
    else:
      break

  if ident.len == 0:
    return failure[KdlVal]()

  # Check if it's a reserved keyword that shouldn't be an identifier
  if ident in ["true", "false", "null", "inf", "-inf", "nan"]:
    p.pos = start
    return failure[KdlVal]()

  return success(initKString(ident), p.pos)

proc string(p: Parser): ParseResult[tuple[value: KdlVal, repr: string]] =
  ## Parses any form of string and returns the value + original representation
  let start = p.pos

  # Try raw string first (starts with #)
  let rawRes = rawString(p)
  if rawRes.ok:
    let repr = p.source[start ..< p.pos]
    return success((rawRes.value, repr), p.pos)

  # Try quoted string
  p.pos = start
  let quotedRes = quotedString(p)
  if quotedRes.ok:
    let repr = p.source[start ..< p.pos]
    return success((quotedRes.value, repr), p.pos)

  # Try identifier string
  p.pos = start
  let identRes = identifierString(p)
  if identRes.ok:
    let repr = p.source[start ..< p.pos]
    return success((identRes.value, repr), p.pos)

  return failure[tuple[value: KdlVal, repr: string]]()

# Identifier parsing

proc identifier(p: Parser): ParseResult[KdlIdentifier] =
  ## Parses a KDL identifier
  let start = p.pos
  let strRes = string(p)
  if not strRes.ok:
    return failure[KdlIdentifier]()

  let (val, repr) = strRes.value
  if val.kind != KString:
    p.pos = start
    return failure[KdlIdentifier]()

  let span = p.getSpan(start)
  return success(initKdlIdentifier(val.str, some(repr), some(span)), p.pos)

# Number parsing

proc keyword(p: Parser): ParseResult[KdlVal] =
  ## Parses KDL keywords: #true, #false, #null, #inf, #-inf, #nan
  let start = p.pos

  if not p.tryChar('#').ok:
    return failure[KdlVal]()

  # Check if this might be a raw string (# followed by " or more #)
  # If so, don't treat it as a keyword error
  let c = p.peek()
  if c.isSome and c.get in {'"', '#'}:
    p.pos = start
    return failure[KdlVal]()

  if p.tryStr("true").ok:
    return success(initKBool(true), p.pos)

  p.pos = start + 1
  if p.tryStr("false").ok:
    return success(initKBool(false), p.pos)

  p.pos = start + 1
  if p.tryStr("null").ok:
    return success(initKNull(), p.pos)

  p.pos = start + 1
  if p.tryStr("inf").ok:
    return success(initKFloat(Inf), p.pos)

  p.pos = start + 1
  if p.tryStr("-inf").ok:
    return success(initKFloat(NegInf), p.pos)

  p.pos = start + 1
  if p.tryStr("nan").ok:
    return success(initKFloat(NaN), p.pos)

  p.pos = start
  p.addError("Invalid keyword after '#'")
  return failure[KdlVal]()

# parseDecimalDigits moved to top of file

proc parseHexNumber(p: Parser): ParseResult[BigInt] =
  ## Parses a hexadecimal number: 0x...
  let start = p.pos

  if not p.tryStr("0x").ok:
    return failure[BigInt]()

  # Check for underscore immediately after prefix (KDL v2 spec violation)
  if not p.atEnd() and p.source[p.pos] == '_':
    p.pos = start
    p.addError("Underscore cannot immediately follow hex prefix '0x'")
    return failure[BigInt]()

  var hexStr = ""
  while not p.atEnd():
    let c = p.source[p.pos]
    if c in HexDigits:
      hexStr.add(c)
      p.advance()
    elif c == '_':
      p.advance()
    elif c in {'g'..'z', 'G'..'Z'} or c in Digits:
      # Invalid character in hex literal (KDL v2 spec violation)
      # This catches cases like 0x10g10 where 'g' is not a valid hex digit
      p.pos = start
      p.addError("Invalid character '" & c & "' in hexadecimal number (valid: 0-9, a-f, A-F)")
      return failure[BigInt]()
    else:
      break

  if hexStr.len == 0:
    p.pos = start
    p.addError("Invalid hexadecimal number")
    return failure[BigInt]()

  try:
    # Parse hex string as BigInt to avoid overflow
    var val = initBigInt(0)
    let sixteen = initBigInt(16)
    for c in hexStr:
      val = val * sixteen
      let digit = if c in '0'..'9': ord(c) - ord('0')
                  elif c in 'a'..'f': ord(c) - ord('a') + 10
                  elif c in 'A'..'F': ord(c) - ord('A') + 10
                  else: 0
      val = val + initBigInt(digit)
    return success(val, p.pos)
  except:
    p.addError("Failed to parse hexadecimal number")
    return failure[BigInt]()

proc parseOctalNumber(p: Parser): ParseResult[BigInt] =
  ## Parses an octal number: 0o...
  let start = p.pos

  if not p.tryStr("0o").ok:
    return failure[BigInt]()

  # Check for underscore immediately after prefix (KDL v2 spec violation)
  if not p.atEnd() and p.source[p.pos] == '_':
    p.pos = start
    p.addError("Underscore cannot immediately follow octal prefix '0o'")
    return failure[BigInt]()

  var octStr = ""
  while not p.atEnd():
    let c = p.source[p.pos]
    if c in {'0'..'7'}:
      octStr.add(c)
      p.advance()
    elif c == '_':
      p.advance()
    elif c in {'8', '9'}:
      # Invalid octal digit (KDL v2 spec violation)
      p.pos = start
      p.addError("Invalid digit '" & c & "' in octal number (valid: 0-7)")
      return failure[BigInt]()
    elif c in {'a'..'z', 'A'..'Z'} or c in Digits:
      # Invalid character in octal literal
      p.pos = start
      p.addError("Invalid character '" & c & "' in octal number")
      return failure[BigInt]()
    else:
      break

  if octStr.len == 0:
    p.pos = start
    p.addError("Invalid octal number")
    return failure[BigInt]()

  try:
    # Parse octal string as BigInt to avoid overflow
    var val = initBigInt(0)
    let eight = initBigInt(8)
    for c in octStr:
      val = val * eight
      let digit = ord(c) - ord('0')
      val = val + initBigInt(digit)
    return success(val, p.pos)
  except:
    p.addError("Failed to parse octal number")
    return failure[BigInt]()

proc parseBinaryNumber(p: Parser): ParseResult[BigInt] =
  ## Parses a binary number: 0b...
  let start = p.pos

  if not p.tryStr("0b").ok:
    return failure[BigInt]()

  # Check for underscore immediately after prefix (KDL v2 spec violation)
  if not p.atEnd() and p.source[p.pos] == '_':
    p.pos = start
    p.addError("Underscore cannot immediately follow binary prefix '0b'")
    return failure[BigInt]()

  var binStr = ""
  while not p.atEnd():
    let c = p.source[p.pos]
    if c in {'0', '1'}:
      binStr.add(c)
      p.advance()
    elif c == '_':
      p.advance()
    elif c in {'2'..'9'} or c in {'a'..'z', 'A'..'Z'}:
      # Invalid character in binary literal (KDL v2 spec violation)
      p.pos = start
      p.addError("Invalid character '" & c & "' in binary number (valid: 0-1)")
      return failure[BigInt]()
    else:
      break

  if binStr.len == 0:
    p.pos = start
    p.addError("Invalid binary number")
    return failure[BigInt]()

  try:
    # Parse binary string as BigInt to avoid overflow
    var val = initBigInt(0)
    let two = initBigInt(2)
    for c in binStr:
      val = val * two
      let digit = ord(c) - ord('0')
      val = val + initBigInt(digit)
    return success(val, p.pos)
  except:
    p.addError("Failed to parse binary number")
    return failure[BigInt]()

proc parseFloat(p: Parser): ParseResult[KdlVal] =
  ## Parses a floating point number
  let start = p.pos

  # Parse the decimal part
  let decRes = parseDecimalDigits(p, allowSign = true)
  if not decRes.ok:
    return failure[KdlVal]()

  var floatStr = decRes.value

  # Must have decimal point or exponent
  var hasDecimalOrExp = false
  var hasDot = false

  # Optional decimal point + fractional part
  if not p.atEnd() and p.source[p.pos] == '.':
    hasDecimalOrExp = true
    hasDot = true
    floatStr.add('.')
    p.advance()

    # Check for underscore immediately after decimal point (KDL v2 spec violation)
    if not p.atEnd() and p.source[p.pos] == '_':
      p.pos = start
      p.addError("Underscore cannot immediately follow decimal point")
      return failure[KdlVal]()

    # Fractional digits
    var hasFractionDigits = false
    while not p.atEnd():
      let c = p.source[p.pos]
      if c in Digits:
        floatStr.add(c)
        hasFractionDigits = true
        p.advance()
      elif c == '_':
        p.advance()
      elif c == '.':
        # Multiple dots in float (KDL v2 spec violation)
        p.pos = start
        p.addError("Multiple decimal points not allowed in number")
        return failure[KdlVal]()
      else:
        break

    # Decimal point must be followed by at least one digit (reject "1." or "1.e7")
    if not hasFractionDigits:
      p.pos = start
      p.addError("Decimal point must be followed by digits")
      return failure[KdlVal]()

  # Optional exponent
  if not p.atEnd() and p.source[p.pos] in {'e', 'E'}:
    hasDecimalOrExp = true
    floatStr.add(p.source[p.pos])
    p.advance()

    # Optional sign in exponent
    if not p.atEnd() and p.source[p.pos] in {'+', '-'}:
      floatStr.add(p.source[p.pos])
      p.advance()

    # Exponent digits
    var hasExpDigits = false
    while not p.atEnd():
      let c = p.source[p.pos]
      if c in Digits:
        floatStr.add(c)
        hasExpDigits = true
        p.advance()
      elif c == '_':
        p.advance()
      elif c in {'e', 'E'}:
        # Multiple exponents in float (KDL v2 spec violation)
        p.pos = start
        p.addError("Multiple exponent markers not allowed in number")
        return failure[KdlVal]()
      else:
        break

    if not hasExpDigits:
      p.addError("Expected digits after exponent")
      return failure[KdlVal]()

  if not hasDecimalOrExp:
    p.pos = start
    return failure[KdlVal]()

  try:
    let val = parseFloat(floatStr)
    return success(initKFloat(val), p.pos)
  except:
    p.addError("Failed to parse float")
    return failure[KdlVal]()

proc parseInteger(p: Parser): ParseResult[KdlVal] =
  ## Parses an integer (decimal, hex, octal, or binary)
  let start = p.pos

  # Try hex
  let hexRes = parseHexNumber(p)
  if hexRes.ok:
    return success(initKBigInt(hexRes.value), p.pos)

  # Try octal
  p.pos = start
  let octRes = parseOctalNumber(p)
  if octRes.ok:
    return success(initKBigInt(octRes.value), p.pos)

  # Try binary
  p.pos = start
  let binRes = parseBinaryNumber(p)
  if binRes.ok:
    return success(initKBigInt(binRes.value), p.pos)

  # Try decimal
  p.pos = start
  let decRes = parseDecimalDigits(p, allowSign = true)
  if not decRes.ok:
    return failure[KdlVal]()

  try:
    # Try to parse as i64 first
    let val = parseBiggestInt(decRes.value)
    return success(initKInt(val), p.pos)
  except:
    # Fall back to BigInt
    try:
      let val = decRes.value.initBigInt
      return success(initKBigInt(val), p.pos)
    except:
      p.addError("Failed to parse integer")
      return failure[KdlVal]()

proc parseNumber(p: Parser): ParseResult[tuple[value: KdlVal, repr: string]] =
  ## Parses any number (float or integer) and returns value + original repr
  let start = p.pos

  # Try float first (more specific)
  let floatRes = parseFloat(p)
  if floatRes.ok:
    let repr = p.source[start ..< p.pos]
    return success((floatRes.value, repr), p.pos)

  # Try integer
  p.pos = start
  let intRes = parseInteger(p)
  if intRes.ok:
    let repr = p.source[start ..< p.pos]
    return success((intRes.value, repr), p.pos)

  return failure[tuple[value: KdlVal, repr: string]]()

# Value and Type Annotation parsing

proc valueTerminator(p: Parser): bool =
  ## Checks if we're at a value terminator
  if p.atEnd():
    return true

  let c = p.source[p.pos]
  if c in {'=', ')', '{', '}', ';'}:
    return true

  # Check for slashdash or comments (/, //, /*)
  if c == '/':
    let next = p.peek(1)
    if next.isSome and next.get in {'-', '/', '*'}:
      return true

  # Check for whitespace/newline
  let savedPos = p.pos
  if nodeSpace(p).ok or newline(p).ok:
    p.pos = savedPos
    return true

  p.pos = savedPos
  return false

proc ty(p: Parser): ParseResult[tuple[beforeTyName: string, ty: Option[KdlIdentifier], afterTyName: string]] =
  ## Parses a type annotation: (type)
  let start = p.pos

  if not p.tryChar('(').ok:
    return failure[tuple[beforeTyName: string, ty: Option[KdlIdentifier], afterTyName: string]]()

  let beforeTyName = wss(p)

  let idRes = identifier(p)
  if not idRes.ok:
    p.addError("Expected type identifier")
    # Try to recover
    while not p.atEnd() and p.source[p.pos] != ')':
      p.advance()
    if not p.atEnd():
      p.advance()
    return success((beforeTyName, none(KdlIdentifier), ""), p.pos)

  let afterTyName = wss(p)

  if not p.expect(')').ok:
    p.addError("Expected ')' after type annotation")
    return failure[tuple[beforeTyName: string, ty: Option[KdlIdentifier], afterTyName: string]]()

  return success((beforeTyName, some(idRes.value), afterTyName), p.pos)

proc value(p: Parser): ParseResult[Option[InternalEntry]] =
  ## Parses a value with optional type annotation
  let start = p.pos

  # Optional type annotation
  var tyInfo: tuple[beforeTyName: string, ty: Option[KdlIdentifier], afterTyName: string]
  var afterTy = ""

  let tyRes = ty(p)
  if tyRes.ok:
    tyInfo = tyRes.value
    afterTy = wss(p)
  else:
    tyInfo = ("", none(KdlIdentifier), "")

  let valueStart = p.pos

  # Try keyword
  var valRes = keyword(p)
  var repr = ""

  if valRes.ok:
    repr = p.source[valueStart ..< p.pos]
  else:
    # Try number
    p.pos = valueStart
    let numRes = parseNumber(p)
    if numRes.ok:
      valRes = success(numRes.value.value, p.pos)
      repr = numRes.value.repr
    else:
      # Try string
      p.pos = valueStart
      let strRes = string(p)
      if strRes.ok:
        valRes = success(strRes.value.value, p.pos)
        repr = strRes.value.repr
      else:
        # No valid value found
        # If we parsed a type annotation, this is an error
        if tyInfo.ty.isSome:
          p.addError("Expected value after type annotation")
        return success(none(InternalEntry), p.pos)

  # Check for value terminator
  if not valueTerminator(p):
    p.addError("Expected value terminator (space, newline, =, ), {, }, ;, or EOF)")

  let format = some(KdlEntryFormat(
    valueRepr: repr,
    afterTy: afterTy,
    beforeTyName: tyInfo.beforeTyName,
    afterTyName: tyInfo.afterTyName,
    leading: "",
    trailing: "",
    afterKey: "",
    afterEq: "",
    autoformatKeep: false
  ))

  let entry = initInternalEntry(
    value = valRes.value,
    ty = tyInfo.ty,
    format = format,
    span = some(p.getSpan(start))
  )

  return success(some(entry), p.pos)

# Node parsing

# slashdash moved to top of file

proc nodeEntry(p: Parser): ParseResult[Option[InternalEntry]] =
  ## Parses a node entry (argument or property)
  let start = p.pos

  # Leading whitespace/comments
  let leading = wss(p)

  # Check for slashdash
  let slashdashRes = slashdash(p)
  if slashdashRes.ok:
    # Slashdashed entry - parse but don't return it
    # Consume whitespace/newlines after slashdash (could be on next line)
    while true:
      let nsRes = nodeSpace(p)
      if nsRes.ok:
        continue
      let nlRes = newline(p)
      if nlRes.ok:
        continue
      let lsRes = lineSpace(p)
      if lsRes.ok:
        continue
      break

    # Check if it's a children block (not an entry)
    if not p.atEnd() and p.source[p.pos] == '{':
      # This is slashdash for children, not an entry
      # Don't consume it here - let the caller handle it
      # Reset position to before slashdash
      p.pos = start
      return success(none(InternalEntry), p.pos)

    # Try to parse as property (key=value) or just value
    let savedPos = p.pos
    # Try optional type annotation
    discard ty(p)
    discard wss(p)
    # Try identifier
    let keyRes = identifier(p)
    if keyRes.ok:
      discard wss(p)
      # Check for '='
      if p.tryChar('=').ok:
        discard wss(p)
        # It's a property, parse the value
        discard value(p)
        return success(none(InternalEntry), p.pos)
    # Not a property, reset and parse as value
    p.pos = savedPos
    discard value(p)
    return success(none(InternalEntry), p.pos)

  # Try to parse as property (key=value)
  let propStart = p.pos

  # Optional type annotation for the key
  var tyInfo: tuple[beforeTyName: string, ty: Option[KdlIdentifier], afterTyName: string]
  var afterTy = ""

  let tyRes = ty(p)
  if tyRes.ok:
    tyInfo = tyRes.value
    afterTy = wss(p)
  else:
    tyInfo = ("", none(KdlIdentifier), "")

  # Try to parse identifier
  let keyRes = identifier(p)
  if keyRes.ok:
    let afterKey = wss(p)

    # Check for '='
    if p.tryChar('=').ok:
      let afterEq = wss(p)

      # Parse the value
      let valStart = p.pos
      let valRes = value(p)

      if valRes.ok and valRes.value.isSome:
        var entry = valRes.value.get
        entry.name = some(keyRes.value)

        # Update format with property-specific fields
        if entry.format.isSome:
          var fmt = entry.format.get
          fmt.leading = leading
          fmt.afterKey = afterKey
          fmt.afterEq = afterEq
          entry.format = some(fmt)

        return success(some(entry), p.pos)
  else:
    # Identifier parsing failed - check if it looks like a property with invalid key
    # Try to manually consume what looks like an identifier to check if '=' follows
    let savedPos = p.pos

    # Skip identifier-like characters (this will consume reserved keywords too)
    if not p.atEnd() and isIdentifierChar(p.source[p.pos]) and p.source[p.pos] notin Digits:
      while not p.atEnd() and isIdentifierChar(p.source[p.pos]):
        p.advance()

      # Now check if '=' follows (with optional whitespace)
      discard wss(p)
      if not p.atEnd() and p.source[p.pos] == '=':
        # This looks like a property with an invalid key (likely a reserved keyword)
        p.addError("Invalid property key (reserved keywords like 'true', 'false', 'null', 'inf', 'nan' cannot be used as bare identifiers)")
        # Skip to next entry/terminator
        while not p.atEnd():
          let c = p.source[p.pos]
          if c in {'\n', '\r', ';', '{', '}'}:
            break
          p.advance()
        return success(none(InternalEntry), p.pos)

    # Reset position - wasn't a property attempt
    p.pos = savedPos

  # Not a property, reset and try as argument
  p.pos = propStart
  let valRes = value(p)

  if valRes.ok and valRes.value.isSome:
    var entry = valRes.value.get
    if entry.format.isSome:
      var fmt = entry.format.get
      fmt.leading = leading
      entry.format = some(fmt)
    return success(some(entry), p.pos)

  return success(none(InternalEntry), p.pos)

proc nodeChildren(p: Parser): ParseResult[seq[InternalNode]] =
  ## Parses node children: { nodes }
  let start = p.pos

  if not p.tryChar('{').ok:
    return failure[seq[InternalNode]]()

  # Parse nodes inside children block
  let nodesRes = nodes(p)

  if not p.expect('}').ok:
    p.addError("Expected '}' to close children block")
    return failure[seq[InternalNode]]()

  if nodesRes.ok:
    return success(nodesRes.value, p.pos)
  else:
    return success(newSeq[InternalNode](), p.pos)

proc baseNode(p: Parser): ParseResult[InternalNode] =
  ## Parses a base node (without leading whitespace)
  let start = p.pos

  # Optional type annotation
  var tyInfo: tuple[beforeTyName: string, ty: Option[KdlIdentifier], afterTyName: string]
  var afterTy = ""

  let tyRes = ty(p)
  if tyRes.ok:
    tyInfo = tyRes.value
    let nsRes = nodeSpace(p)
    if nsRes.ok:
      afterTy = nsRes.value
  else:
    tyInfo = ("", none(KdlIdentifier), "")

  # Node name
  let nameRes = identifier(p)
  if not nameRes.ok:
    # If we parsed a type annotation, this is an error
    if tyInfo.ty.isSome:
      p.addError("Expected node name after type annotation")
    return failure[InternalNode]()

  # Check for invalid characters immediately after node name (KDL v2 spec violation)
  # This catches cases like "foo(bar)" where special chars appear without whitespace
  # Note: '{' is allowed (children block), but '(' is not (type annotations only before name)
  if not p.atEnd():
    let nextChar = p.source[p.pos]
    if nextChar in {'(', ')', '[', ']', '"', '\\'}:
      p.addError("Unexpected character '" & nextChar & "' after node name (whitespace required)")
      return failure[InternalNode]()

  var entries: seq[InternalEntry] = @[]
  var children: Option[seq[InternalNode]] = none(seq[InternalNode])
  var beforeChildren = ""

  # Parse entries and children
  while true:
    # Try node-space
    let savedPos = p.pos
    let nsRes = nodeSpace(p)
    if nsRes.ok:
      # Try to parse entry or children
      let entryStartPos = p.pos
      let entryRes = nodeEntry(p)
      if entryRes.ok:
        # Check if entry was actually parsed by seeing if position advanced
        if entryRes.value.isSome or p.pos != entryStartPos:
          # Entry was parsed OR position advanced (slashdash consumed something)
          if entryRes.value.isSome:
            entries.add(entryRes.value.get)
          # Continue parsing even if it was a slashdashed (None) entry
          continue

      # Try children (don't reset position - we're already after node-space)
      beforeChildren = nsRes.value

      # Check for slashdash before children
      let sdRes = slashdash(p)
      if sdRes.ok:
        # Slashdashed children - parse and discard
        # Consume whitespace, newlines, and esclines after slashdash
        while true:
          if nodeSpace(p).ok:
            continue
          if lineSpace(p).ok:
            continue
          if escline(p).ok:
            continue
          break
        discard nodeChildren(p)
        # Continue to check for more children blocks (could be more slashdashed or real)
        continue
    else:
      # No whitespace - but check for slashdash without preceding whitespace
      # This allows: node "arg"/-otherarg
      let sdRes = slashdash(p)
      if sdRes.ok:
        # Parse and discard the slashdashed entry
        let entryRes = nodeEntry(p)
        if entryRes.ok:
          # Successfully consumed slashdashed entry, continue
          continue
        # If entry parsing failed, could be slashdashed children
        p.pos = savedPos + 2  # Skip past '/-'
        # Consume whitespace, newlines, and esclines after slashdash
        while true:
          if nodeSpace(p).ok:
            continue
          if lineSpace(p).ok:
            continue
          if escline(p).ok:
            continue
          break
        discard nodeChildren(p)
        # Continue to check for more children blocks
        continue

      # Try children without preceding whitespace
      let childrenRes = nodeChildren(p)
      if childrenRes.ok:
        children = some(childrenRes.value)

        # After children block, validate that what follows is a valid terminator
        # (whitespace, newline, semicolon, EOF, or closing brace)
        if not p.atEnd():
          let nextChar = p.source[p.pos]
          # Check if it's a valid terminator or slashdash
          if not (nextChar in {' ', '\t', '\r', '\n', ';', '}', '/'} or isUnicodeSpace(p.source.runeAt(p.pos))):
            p.addError("Missing terminator after children block (expected newline, semicolon, or EOF)")
            return failure[InternalNode]()

        # After children, check for slashdashed children without whitespace
        # Example: node {} /-{}
        let sdAfterRes = slashdash(p)
        if sdAfterRes.ok:
          # Consume any whitespace/newlines after slashdash
          while true:
            if nodeSpace(p).ok:
              continue
            if lineSpace(p).ok:
              continue
            if escline(p).ok:
              continue
            break
          # Parse and discard the slashdashed children
          discard nodeChildren(p)
          # Continue to check for more slashdashed children with whitespace
          continue

        # No immediate slashdash, but continue loop to check for slashdashed children with whitespace
        # This allows: node { three } /-{ four } where there's space between them
        continue

      # No entry or children, just whitespace - break
      p.pos = savedPos
      break

  let format = some(KdlNodeFormat(
    leading: "",
    trailing: "",
    beforeTyName: tyInfo.beforeTyName,
    afterTyName: tyInfo.afterTyName,
    afterTy: afterTy,
    beforeChildren: beforeChildren,
    beforeTerminator: "",
    terminator: "\n"
  ))

  let node = initInternalNode(
    name = nameRes.value,
    ty = tyInfo.ty,
    entries = entries,
    children = children,
    format = format,
    span = some(p.getSpan(start))
  )

  return success(node, p.pos)

proc node(p: Parser): ParseResult[InternalNode] =
  ## Parses a node with leading whitespace and terminator
  let start = p.pos

  # Leading whitespace/comments (may include slashdash comments)
  var leading = ""
  while true:
    let lsRes = lineSpace(p)
    if lsRes.ok:
      leading.add(lsRes.value)
      continue

    # Try escline
    let escRes = escline(p)
    if escRes.ok:
      leading.add(escRes.value)
      continue

    # Check for slashdash of an entire node
    let sdRes = slashdash(p)
    if sdRes.ok:
      leading.add(sdRes.value)
      # Consume whitespace after slashdash
      let sdWs = lineSpace(p)
      if sdWs.ok:
        leading.add(sdWs.value)
      # Parse and discard the slashdashed node
      discard baseNode(p)
      # Consume terminator of slashdashed node
      discard wss(p)
      if not p.atEnd():
        let c = p.peek()
        if c.isSome and c.get == ';':
          p.advance()
        else:
          discard newline(p)
      # Continue loop to check for more slashdashed nodes or whitespace
      continue

    break

  # Parse the actual node
  let nodeRes = baseNode(p)
  if not nodeRes.ok:
    return failure[InternalNode]()

  var node = nodeRes.value

  # Before terminator whitespace
  var beforeTerminator = wss(p)

  # Check for single-line comment before terminator
  let slcRes = singleLineComment(p)
  if slcRes.ok:
    beforeTerminator.add(slcRes.value)

  # Node terminator (semicolon, newline, or escline) - optional at EOF
  var terminator = "\n"
  if not p.atEnd():
    let c = p.peek()
    if c.isSome and c.get == ';':
      p.advance()
      terminator = ";"
    else:
      # Try escline first (backslash continuation)
      let escRes = escline(p)
      if escRes.ok:
        terminator = escRes.value
      else:
        # Try regular newline
        let nlRes = newline(p)
        if nlRes.ok:
          terminator = nlRes.value

  # Trailing whitespace
  let trailing = wss(p)

  # Update format
  if node.format.isSome:
    var fmt = node.format.get
    fmt.leading = leading
    fmt.beforeTerminator = beforeTerminator
    fmt.terminator = terminator
    fmt.trailing = trailing
    node.format = some(fmt)

  return success(node, p.pos)

proc nodes(p: Parser): ParseResult[seq[InternalNode]] =
  ## Parses zero or more nodes
  var result: seq[InternalNode] = @[]

  # Skip leading line-space (including escline)
  while true:
    let lsRes = lineSpace(p)
    if lsRes.ok:
      continue

    # Also try escline
    let escRes = escline(p)
    if escRes.ok:
      continue

    break

  # Parse nodes
  while not p.atEnd():
    # Skip line-space and escline between nodes
    while true:
      let lsRes = lineSpace(p)
      if lsRes.ok:
        continue
      let escRes = escline(p)
      if escRes.ok:
        continue
      break

    # Check for slashdashed nodes before trying to parse a real node
    while true:
      let sdRes = slashdash(p)
      if sdRes.ok:
        # Consume whitespace after slashdash
        while true:
          let lsRes = lineSpace(p)
          if lsRes.ok:
            continue
          break
        # Parse and discard the slashdashed node
        discard node(p)
        continue
      break

    let savedPos = p.pos
    let nodeRes = node(p)
    if nodeRes.ok:
      result.add(nodeRes.value)
    else:
      # No more valid nodes
      p.pos = savedPos
      break

  # Trailing line-space (including escline)
  while true:
    let lsRes = lineSpace(p)
    if lsRes.ok:
      continue

    # Also try escline
    let escRes = escline(p)
    if escRes.ok:
      continue

    break

  return success(result, p.pos)

proc document(p: Parser): ParseResult[seq[InternalNode]] =
  ## Parses a complete KDL document
  let start = p.pos

  # Optional BOM (check without adding error)
  if p.peekStr(3).isSome and p.peekStr(3).get == "\uFEFF":
    p.advance(3)

  # Parse nodes
  return nodes(p)

# Main entry point

proc parseKdl*(source: string): KdlDoc =
  ## Parses a KDL document from source string
  ## Returns the parsed document or raises KdlParserError
  var p = initParser(source)

  let docRes = document(p)

  if p.hasErrors():
    let errMsg = p.getErrorMessage(source)
    raise newException(KdlParserError, errMsg)

  if not docRes.ok:
    raise newException(KdlParserError, "Failed to parse KDL document")

  # Check that we've consumed all input
  if not p.atEnd():
    p.addError("Unexpected content after end of document")
    let errMsg = p.getErrorMessage(source)
    raise newException(KdlParserError, errMsg)

  # Convert internal representation to public API
  return toPublicDoc(docRes.value)
