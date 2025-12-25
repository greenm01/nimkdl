## Format preservation structures for KDL parsing
##
## This module defines types used to preserve formatting information
## (whitespace, comments, original representations) when parsing KDL documents.
## This allows for round-tripping: parse → modify → serialize while maintaining
## the original document formatting.

import std/options

type
  Span* = object
    ## Source location tracking for error reporting and IDE features
    start*: int  ## Starting position in source string
    len*: int    ## Length of the span

  KdlIdentifier* = object
    ## A KDL identifier with optional formatting preservation
    value*: string           ## The parsed identifier value
    repr*: Option[string]    ## Original representation (e.g., quoted vs bare)
    span*: Option[Span]      ## Source location

  KdlEntryFormat* = object
    ## Formatting details for KDL entries (arguments and properties)
    valueRepr*: string        ## The actual text representation of the entry's value
    leading*: string          ## Whitespace and comments preceding the entry
    trailing*: string         ## Whitespace and comments following the entry
    afterTy*: string          ## Whitespace after the type annotation's closing ')'
    beforeTyName*: string     ## Whitespace between '(' and type name in annotation
    afterTyName*: string      ## Whitespace between type name and ')' in annotation
    afterKey*: string         ## Whitespace between key name and '=' (for properties)
    afterEq*: string          ## Whitespace between '=' and value (for properties)
    autoformatKeep*: bool     ## Do not clobber this format during autoformat

  KdlNodeFormat* = object
    ## Formatting details for KDL nodes
    leading*: string          ## Whitespace and comments preceding the node
    trailing*: string         ## Whitespace and comments following the node
    beforeTyName*: string     ## Whitespace between '(' and type name in annotation
    afterTyName*: string      ## Whitespace between type name and ')' in annotation
    afterTy*: string          ## Whitespace after the node's type annotation
    beforeChildren*: string   ## Whitespace preceding the node's children block
    beforeTerminator*: string ## Whitespace right before the node's terminator
    terminator*: string       ## The terminator for the node (";" or "\n")

  KdlDocumentFormat* = object
    ## Formatting details for KDL documents
    leading*: string          ## Whitespace and comments before the first node
    trailing*: string         ## Whitespace and comments after the last node

  FormatConfig* = object
    ## Configuration for autoformatting KDL documents
    indentLevel*: int         ## How deeply to indent, in repetitions of indent
    indent*: string           ## The indentation string to use at each level
    noComments*: bool         ## Whether to remove comments during formatting
    entryAutoformatKeep*: bool ## Whether to keep individual entry formatting

# Constructor procs

proc initKdlIdentifier*(value: string, repr: Option[string] = none(string),
                       span: Option[Span] = none(Span)): KdlIdentifier =
  ## Creates a new KdlIdentifier
  KdlIdentifier(value: value, repr: repr, span: span)

proc initKdlEntryFormat*(): KdlEntryFormat =
  ## Creates a new KdlEntryFormat with default values
  KdlEntryFormat(
    valueRepr: "",
    leading: "",
    trailing: "",
    afterTy: "",
    beforeTyName: "",
    afterTyName: "",
    afterKey: "",
    afterEq: "",
    autoformatKeep: false
  )

proc initKdlNodeFormat*(): KdlNodeFormat =
  ## Creates a new KdlNodeFormat with default values
  KdlNodeFormat(
    leading: "",
    trailing: "\n",  # Default newline terminator
    beforeTyName: "",
    afterTyName: "",
    afterTy: "",
    beforeChildren: "",
    beforeTerminator: "",
    terminator: "\n"
  )

proc initKdlDocumentFormat*(): KdlDocumentFormat =
  ## Creates a new KdlDocumentFormat with default values
  KdlDocumentFormat(
    leading: "",
    trailing: ""
  )

proc initFormatConfig*(indentLevel: int = 0, indent: string = "    ",
                       noComments: bool = false,
                       entryAutoformatKeep: bool = false): FormatConfig =
  ## Creates a new FormatConfig with specified or default values
  FormatConfig(
    indentLevel: indentLevel,
    indent: indent,
    noComments: noComments,
    entryAutoformatKeep: entryAutoformatKeep
  )

proc initSpan*(start, len: int): Span =
  ## Creates a new Span
  Span(start: start, len: len)

# Utility procs

proc `$`*(id: KdlIdentifier): string =
  ## Converts a KdlIdentifier to its string representation
  if id.repr.isSome:
    id.repr.get
  else:
    # For bare identifiers, return the value as-is
    # For identifiers that need quoting, we'll handle that during serialization
    id.value

proc `==`*(a, b: KdlIdentifier): bool =
  ## Compares two KdlIdentifiers (ignoring span)
  a.value == b.value and a.repr == b.repr

proc `==`*(a, b: Span): bool =
  ## Compares two Spans
  a.start == b.start and a.len == b.len
