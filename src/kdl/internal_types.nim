## Internal representation for KDL parsing
##
## This module defines the internal types used during parsing that closely
## match kdl-rs's design. These are then converted to the public API types
## for backward compatibility.

import std/[options, tables]
import ./format
import ./types  # Import public types

type
  InternalEntry* = object
    ## Internal representation of a KDL entry (argument or property)
    ## Matches kdl-rs's unified KdlEntry design
    ty*: Option[KdlIdentifier]          ## Type annotation
    value*: KdlVal                       ## The value
    name*: Option[KdlIdentifier]         ## None = argument, Some = property
    format*: Option[KdlEntryFormat]      ## Formatting information
    span*: Option[Span]                  ## Source location

  InternalNode* = object
    ## Internal representation of a KDL node
    ## Matches kdl-rs's KdlNode design
    ty*: Option[KdlIdentifier]           ## Type annotation
    name*: KdlIdentifier                 ## Node name
    entries*: seq[InternalEntry]         ## Unified args + props
    children*: Option[seq[InternalNode]] ## Child nodes
    format*: Option[KdlNodeFormat]       ## Formatting information
    span*: Option[Span]                  ## Source location

# Constructor procs

proc initInternalEntry*(value: KdlVal, name: Option[KdlIdentifier] = none(KdlIdentifier),
                       ty: Option[KdlIdentifier] = none(KdlIdentifier),
                       format: Option[KdlEntryFormat] = none(KdlEntryFormat),
                       span: Option[Span] = none(Span)): InternalEntry =
  ## Creates a new InternalEntry
  InternalEntry(ty: ty, value: value, name: name, format: format, span: span)

proc initInternalNode*(name: KdlIdentifier, ty: Option[KdlIdentifier] = none(KdlIdentifier),
                      entries: seq[InternalEntry] = @[],
                      children: Option[seq[InternalNode]] = none(seq[InternalNode]),
                      format: Option[KdlNodeFormat] = none(KdlNodeFormat),
                      span: Option[Span] = none(Span)): InternalNode =
  ## Creates a new InternalNode
  InternalNode(ty: ty, name: name, entries: entries, children: children, format: format, span: span)

# Conversion functions

proc toPublicNode*(n: InternalNode): KdlNode =
  ## Converts an InternalNode to a public KdlNode
  ## Separates unified entries into args (seq) and props (Table)
  result = KdlNode(
    tag: n.ty.map(proc(id: KdlIdentifier): string = id.value),
    name: n.name.value,
    args: @[],
    props: initTable[string, KdlVal](),
    children: @[]
  )

  # Separate entries into args and props
  for entry in n.entries:
    var val = entry.value

    # Transfer type annotation from entry to value
    if entry.ty.isSome:
      val.tag = some(entry.ty.get.value)

    if entry.name.isNone:
      # It's an argument
      result.args.add(val)
    else:
      # It's a property
      result.props[entry.name.get.value] = val

  # Convert children
  if n.children.isSome:
    for child in n.children.get:
      result.children.add(toPublicNode(child))

proc toInternalNode*(n: KdlNode): InternalNode =
  ## Converts a public KdlNode to an InternalNode
  ## Combines args and props into unified entries
  var entries: seq[InternalEntry] = @[]

  # Add arguments (no name)
  for arg in n.args:
    entries.add(initInternalEntry(
      value = arg,
      name = none(KdlIdentifier)
    ))

  # Add properties (with name)
  for key, val in n.props:
    entries.add(initInternalEntry(
      value = val,
      name = some(initKdlIdentifier(key))
    ))

  # Convert children
  let children = if n.children.len > 0:
    var childNodes: seq[InternalNode] = @[]
    for child in n.children:
      childNodes.add(toInternalNode(child))
    some(childNodes)
  else:
    none(seq[InternalNode])

  result = initInternalNode(
    name = initKdlIdentifier(n.name),
    ty = n.tag.map(proc(s: string): KdlIdentifier = initKdlIdentifier(s)),
    entries = entries,
    children = children
  )

proc toPublicDoc*(nodes: seq[InternalNode]): KdlDoc =
  ## Converts a sequence of InternalNodes to a KdlDoc
  result = @[]
  for node in nodes:
    result.add(toPublicNode(node))

proc toInternalDoc*(doc: KdlDoc): seq[InternalNode] =
  ## Converts a KdlDoc to a sequence of InternalNodes
  result = @[]
  for node in doc:
    result.add(toInternalNode(node))
