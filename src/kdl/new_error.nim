## Error recovery and diagnostic formatting for KDL parsing
##
## This module provides rich error reporting with spans, context, and helpful
## messages. It supports collecting multiple errors during parsing and
## formatting them for display.

import std/[strutils, options, unicode]
import ./format
import ./combinator

# Re-export ParseError from combinator for convenience
export ParseError

proc formatError*(error: ParseError, source: string): string =
  ## Formats a single error for display with context
  result = ""

  # Calculate line and column from span
  var line = 1
  var col = 1
  var lineStart = 0

  for i in 0 ..< error.span.start:
    if i < source.len and source[i] == '\n':
      line += 1
      col = 1
      lineStart = i + 1
    else:
      col += 1

  # Find the end of the current line
  var lineEnd = lineStart
  while lineEnd < source.len and source[lineEnd] != '\n':
    lineEnd += 1

  # Extract the line
  let lineText = if lineStart < source.len:
    source[lineStart ..< lineEnd]
  else:
    ""

  # Format the error
  if error.message.isSome:
    result.add("Error: " & error.message.get & "\n")
  else:
    result.add("Parse Error\n")

  result.add("  at line " & $line & ", column " & $col & ":\n\n")

  # Show the problematic line
  let lineNumStr = $line
  result.add("  " & lineNumStr & " | " & lineText & "\n")

  # Add indicator pointing to the error
  let spaces = "  " & repeat(" ", lineNumStr.len) & " | " & repeat(" ", col - 1)
  let indicator = if error.span.len > 1:
    repeat("^", min(error.span.len, lineText.len - col + 1))
  else:
    "^"
  result.add(spaces & indicator & "\n")

  # Add label if present
  if error.label.isSome:
    result.add(spaces & error.label.get & "\n")

  # Add help text if present
  if error.help.isSome:
    result.add("\n  help: " & error.help.get & "\n")

proc formatErrors*(errors: seq[ParseError], source: string): string =
  ## Formats multiple errors for display
  result = ""
  for i, error in errors:
    if i > 0:
      result.add("\n")
    result.add(formatError(error, source))
    if i < errors.len - 1:
      result.add("\n" & repeat("-", 60) & "\n")

proc hasErrors*(p: Parser): bool =
  ## Returns true if parser has collected any errors
  p.errors.len > 0

proc clearErrors*(p: Parser) =
  ## Clears all collected errors
  p.errors = @[]

proc getErrorMessage*(p: Parser, source: string): string =
  ## Gets a formatted error message for all collected errors
  if p.errors.len == 0:
    return "No errors"
  return formatErrors(p.errors, source)

# Error recovery strategies

proc tryRecover*(p: Parser, targets: set[char]) =
  ## Attempts to recover by skipping to the next occurrence of target character
  while not p.atEnd():
    let c = p.source[p.pos]
    if c in targets:
      break
    p.advance()

proc tryRecoverToNextLine*(p: Parser) =
  ## Attempts to recover by skipping to the next line
  while not p.atEnd():
    let c = p.source[p.pos]
    if c == '\n':
      p.advance()  # Skip the newline
      break
    p.advance()

proc resumeAfterCut*[T](p: Parser, parser: proc(p: Parser): ParseResult[T],
                        recoverTargets: set[char] = {}): ParseResult[T] =
  ## Executes parser with error recovery support
  ## If parser fails critically, attempts to recover to next valid token
  let savedPos = p.pos
  let savedErrorCount = p.errors.len
  let res = parser(p)

  if not res.ok and p.errors.len > savedErrorCount:
    # An error occurred - try to recover if targets provided
    if recoverTargets.card > 0:
      p.tryRecover(recoverTargets)

  return res

# Diagnostic context helpers

proc expectedError*(p: Parser, expected: string) =
  ## Creates an error for an expected token
  p.addError(
    "Expected " & expected,
    label = "expected here",
    help = "Check your KDL syntax"
  )

proc unexpectedEof*(p: Parser, context: string = "") =
  ## Creates an error for unexpected end of file
  let msg = if context.len > 0:
    "Unexpected end of file while parsing " & context
  else:
    "Unexpected end of file"

  p.addError(
    msg,
    label = "unexpected EOF",
    help = "The input ended before the document was complete"
  )

proc invalidCharError*(p: Parser, context: string) =
  ## Creates an error for an invalid character
  let c = if not p.atEnd(): "'" & $p.source[p.pos] & "'" else: "EOF"
  p.addError(
    "Invalid character " & c & " in " & context,
    label = "invalid character",
    help = "Check the KDL specification for valid " & context & " characters"
  )

proc disallowedCodePointError*(p: Parser, r: Rune) =
  ## Creates an error for a disallowed Unicode code point
  p.addError(
    "Disallowed Unicode code point U+" & toHex(r.int32, 4),
    label = "disallowed code point",
    help = "This code point is not allowed in KDL documents"
  )
