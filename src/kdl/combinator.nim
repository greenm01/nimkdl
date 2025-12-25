## Parser combinator primitives for KDL parsing
##
## This module provides the foundation for building a recursive descent parser
## using combinator-style abstractions. It's inspired by Winnow (Rust) but
## implemented in idiomatic Nim.

import std/[options, unicode]
import ./format

type
  ParseError* = object
    ## Represents a parsing error with location and context
    span*: Span               ## Where the error occurred
    message*: Option[string]  ## Main error message
    label*: Option[string]    ## What was expected
    help*: Option[string]     ## How to fix the error

  Parser* = ref object
    ## The parser state containing source text and current position
    source*: string           ## The input source text
    pos*: int                 ## Current position in source
    errors*: seq[ParseError]  ## Collected errors during parsing

  ParseResult*[T] = object
    ## Result of a parse operation
    case ok*: bool
    of true:
      value*: T
      endPos*: int            ## Position after successful parse
    of false:
      discard               ## Failed parse, position unchanged

# Constructor procs

proc initParser*(source: string): Parser =
  ## Creates a new Parser for the given source string
  Parser(source: source, pos: 0, errors: @[])

proc initParseError*(span: Span, message: Option[string] = none(string),
                     label: Option[string] = none(string),
                     help: Option[string] = none(string)): ParseError =
  ## Creates a new ParseError
  ParseError(span: span, message: message, label: label, help: help)

# Result constructors

proc success*[T](value: T, endPos: int): ParseResult[T] =
  ## Creates a successful parse result
  ParseResult[T](ok: true, value: value, endPos: endPos)

proc failure*[T](): ParseResult[T] =
  ## Creates a failed parse result
  ParseResult[T](ok: false)

# Core utility procs

proc atEnd*(p: Parser): bool =
  ## Returns true if parser is at end of input
  p.pos >= p.source.len

proc peek*(p: Parser, offset: int = 0): Option[char] =
  ## Peeks at character at current position + offset without advancing
  let pos = p.pos + offset
  if pos < p.source.len:
    some(p.source[pos])
  else:
    none(char)

proc peekStr*(p: Parser, len: int): Option[string] =
  ## Peeks at a string of given length without advancing
  if p.pos + len <= p.source.len:
    some(p.source[p.pos ..< p.pos + len])
  else:
    none(string)

proc advance*(p: Parser, count: int = 1) =
  ## Advances the parser position by count characters
  p.pos = min(p.pos + count, p.source.len)

proc getSpan*(p: Parser, start: int): Span =
  ## Creates a span from start position to current position
  initSpan(start, p.pos - start)

proc addError*(p: Parser, error: ParseError) =
  ## Adds an error to the parser's error list
  p.errors.add(error)

proc addError*(p: Parser, message: string, label: string = "",
               help: string = "") =
  ## Convenience proc to add an error at current position
  let span = initSpan(p.pos, 1)
  let msg = if message.len > 0: some(message) else: none(string)
  let lbl = if label.len > 0: some(label) else: none(string)
  let hlp = if help.len > 0: some(help) else: none(string)
  p.addError(initParseError(span, msg, lbl, hlp))

# Character classification

proc isNewline*(c: char): bool =
  ## Returns true if character is a common KDL newline (single-byte)
  ## Note: For full Unicode newline support, use the newline() parser
  c in {'\n', '\r'}

proc isUnicodeSpace*(r: Rune): bool =
  ## Returns true if rune is a Unicode whitespace character recognized by KDL
  let c = r.int32
  case c
  of 0x0009,  # CHARACTER TABULATION
     0x0020,  # SPACE
     0x00A0,  # NO-BREAK SPACE
     0x1680,  # OGHAM SPACE MARK
     0x2000,  # EN QUAD
     0x2001,  # EM QUAD
     0x2002,  # EN SPACE
     0x2003,  # EM SPACE
     0x2004,  # THREE-PER-EM SPACE
     0x2005,  # FOUR-PER-EM SPACE
     0x2006,  # SIX-PER-EM SPACE
     0x2007,  # FIGURE SPACE
     0x2008,  # PUNCTUATION SPACE
     0x2009,  # THIN SPACE
     0x200A,  # HAIR SPACE
     0x202F,  # NARROW NO-BREAK SPACE
     0x205F,  # MEDIUM MATHEMATICAL SPACE
     0x3000:  # IDEOGRAPHIC SPACE
    result = true
  else:
    result = false

proc isDisallowedCodePoint*(r: Rune): bool =
  ## Returns true if rune is disallowed in KDL
  let c = r.int32
  # Control characters (except tab and newlines), BOM, etc.
  if c >= 0x0000 and c <= 0x001F and c != 0x0009 and c != 0x000A and c != 0x000D:
    return true
  if c >= 0x007F and c <= 0x009F:
    return true
  if c == 0xFEFF:  # BOM
    return true
  case c
  of 0x200E, 0x200F, 0x202A, 0x202B, 0x202C, 0x202D, 0x202E, 0x2066, 0x2067, 0x2068, 0x2069:
    return true
  else:
    return false

proc isIdentifierChar*(c: char): bool =
  ## Returns true if character is valid in a KDL identifier (after first position)
  ## Digits are allowed, but not as the first character (checked separately)
  c notin {'(', ')', '{', '}', '[', ']', ';', '=', '"', '\\', '#', ' ', '\t', '\n', '\r'}

# Basic parsers

proc tryChar*(p: Parser, expected: char): ParseResult[char] =
  ## Tries to parse a character without adding errors
  if p.atEnd():
    return failure[char]()

  let c = p.source[p.pos]
  if c == expected:
    p.advance()
    return success(c, p.pos)
  else:
    return failure[char]()

proc tryStr*(p: Parser, expected: string): ParseResult[string] =
  ## Tries to parse a string without adding errors
  let maybeStr = p.peekStr(expected.len)
  if maybeStr.isSome and maybeStr.get == expected:
    p.advance(expected.len)
    return success(expected, p.pos)
  else:
    return failure[string]()

proc expect*(p: Parser, expected: char): ParseResult[char] =
  ## Parses an expected character (adds error on failure)
  if p.atEnd():
    p.addError("Unexpected end of input", $expected)
    return failure[char]()

  let c = p.source[p.pos]
  if c == expected:
    p.advance()
    return success(c, p.pos)
  else:
    p.addError("Expected '" & $expected & "' but found '" & $c & "'")
    return failure[char]()

proc expectStr*(p: Parser, expected: string): ParseResult[string] =
  ## Parses an expected string (adds error on failure)
  let maybeStr = p.peekStr(expected.len)
  if maybeStr.isSome and maybeStr.get == expected:
    p.advance(expected.len)
    return success(expected, p.pos)
  else:
    p.addError("Expected '" & expected & "'")
    return failure[string]()

proc takeWhile*(p: Parser, predicate: proc(c: char): bool): string =
  ## Takes characters while predicate is true
  result = ""
  while not p.atEnd():
    let c = p.source[p.pos]
    if predicate(c):
      result.add(c)
      p.advance()
    else:
      break

proc takeWhileRune*(p: Parser, predicate: proc(r: Rune): bool): string =
  ## Takes runes while predicate is true (handles multi-byte UTF-8)
  result = ""
  var pos = p.pos
  while pos < p.source.len:
    let r = p.source.runeAt(pos)
    if predicate(r):
      result.add(r.toUTF8)
      pos += r.size
    else:
      break
  p.pos = pos

proc take*(p: Parser, count: int): Option[string] =
  ## Takes exactly count characters
  if p.pos + count <= p.source.len:
    let s = p.source[p.pos ..< p.pos + count]
    p.advance(count)
    return some(s)
  return none(string)

# Combinator procs

proc optional*[T](p: Parser, parser: proc(p: Parser): ParseResult[T]): ParseResult[Option[T]] =
  ## Tries to parse, returns Some(value) on success, None on failure
  ## Never fails - always succeeds
  let savedPos = p.pos
  let res = parser(p)
  if res.ok:
    return success(some(res.value), res.endPos)
  else:
    p.pos = savedPos
    return success(none(T), p.pos)

proc alt*[T](p: Parser, parsers: varargs[proc(p: Parser): ParseResult[T]]): ParseResult[T] =
  ## Tries parsers in order, returns first success
  let savedPos = p.pos
  for parser in parsers:
    p.pos = savedPos
    let res = parser(p)
    if res.ok:
      return res
  p.pos = savedPos
  return failure[T]()

proc repeatZeroOrMore*[T](p: Parser, parser: proc(p: Parser): ParseResult[T]): ParseResult[seq[T]] =
  ## Parses zero or more occurrences of parser
  var results: seq[T] = @[]
  while true:
    let savedPos = p.pos
    let res = parser(p)
    if res.ok:
      results.add(res.value)
    else:
      p.pos = savedPos
      break
  return success(results, p.pos)

proc repeatOneOrMore*[T](p: Parser, parser: proc(p: Parser): ParseResult[T]): ParseResult[seq[T]] =
  ## Parses one or more occurrences of parser
  var results: seq[T] = @[]
  let first = parser(p)
  if not first.ok:
    return failure[seq[T]]()
  results.add(first.value)

  while true:
    let savedPos = p.pos
    let res = parser(p)
    if res.ok:
      results.add(res.value)
    else:
      p.pos = savedPos
      break
  return success(results, p.pos)

proc peekParser*[T](p: Parser, parser: proc(p: Parser): ParseResult[T]): ParseResult[T] =
  ## Parses without consuming input (lookahead)
  let savedPos = p.pos
  let res = parser(p)
  p.pos = savedPos
  return res

proc notParser*(p: Parser, parser: proc(p: Parser): ParseResult[bool]): ParseResult[bool] =
  ## Succeeds if parser fails (negative lookahead)
  let savedPos = p.pos
  let res = parser(p)
  p.pos = savedPos
  if res.ok:
    return failure[bool]()
  else:
    return success(true, p.pos)
