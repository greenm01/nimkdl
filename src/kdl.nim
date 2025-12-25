## # kdl-nim
## kdl-nim is an implementation of the [KDL document language](https://kdl.dev) v2.0.0 in the Nim programming language.
##
## ## Installation
## ```
## nimble install kdl
## ```
##
## ## Overview
## ### Parsing KDL
## kdl-nim parses strings, files or streams into a `KdlDoc` which is a sequence of `KdlNode`s.
##
## Each `KdlNode` holds a name, an optional type annotation (tag), zero ore more arguments, zero or more properties and optionally children nodes.
## Arguments are a sequence of values, while properties are an unordered table of string and values.
## Arguments and properties' values are represented by the object variant `KdlVal`. `KdlVal` can be of any kind `KString`, `KFloat`, `KBool`, `KNull` or `KInt`.
runnableExamples:
  let doc = parseKdl("node (i8)1 null key=\"val\" {child \"abc\" true}")
    # You can also read files using parseKdlFile("file.kdl")
  assert doc ==
    @[ 
      initKNode(
        "node",
        args = @[initKVal(1, "i8".some), initKNull()],
        props = {"key": initKVal("val")}.toTable,
        children = @[initKNode("child", args = @[initKVal("abc"), initKVal(true)])],
      )
    ]

## ### Reading nodes
runnableExamples:
  let doc = parseKdl("(tag)node 1 null key=\"val\" {child \"abc\" true}")

  assert doc[0].name == "node"
  assert doc[0].tag.isSome and doc[0].tag.get == "tag" # Tags are Option[string]
  assert doc[0]["key"] == "val" # Same as doc[0].props["key"]
  assert doc[0].children[0].args[0] == "abc" # Same as doc[0].children[0].args[0]

## ### Reading values
## Accessing to the inner value of any `KdlVal` can be achieved by using any of the following procedures:
## - `getString`
## - `getFloat`
## - `getBool`
## - `getInt`
runnableExamples:
  let doc = parseKdl("node 1 3.14 {child \"abc\" true}")

  assert doc[0].args[0].getInt() == 1
  assert doc[0].args[1].getFloat() == 3.14
  assert doc[0].children[0].args[0].getString() == "abc"
  assert doc[0].children[0].args[1].getBool() == true

## There's also a generic procedure that converts `KdlValue` to the given type, consider this example:
runnableExamples:
  let doc = parseKdl("node 1 3.14 255")

  assert doc[0].args[0].get(float32) == 1f
  assert doc[0].args[1].get(int) == 3
  assert doc[0].args[2].get(uint8) == 255u8
  assert doc[0].args[0].get(string) == "1"

## ### Setting values
runnableExamples:
  var doc = parseKdl("node 1 3.14 {child \"abc\" true}")

  doc[0].args[0].setInt(10)
  assert doc[0].args[0] == 10

  doc[0].children[0].args[1].setBool(false)
  assert doc[0].children[0].args[1] == false

  # You can also use the generic procedure `setTo`
  doc[0].args[0].setTo(3.14)
  assert doc[0].args[0] == 3

  doc[0].children[0].args[0].setTo("def")
  assert doc[0].children[0].args[0] == "def"

## ### Creating KDL
## To create KDL documents, nodes or values without parsing or object constructors you can use the `toKdlDoc`, `toKdlNode` and`toKdlVal` macros which have a similar syntax to KDL:
runnableExamples:
  let doc = toKdlDoc:
    node[tag](1, true, nil, key = "val"):
      child(3.14[pi])

    person(name = "pat")

  assert doc ==
    parseKdl("(tag)node 1 true null key=\"val\" {child (pi)3.14}; person name=\"pat\"")

  let node = toKdlNode:
    numbers(1, 2.13, 3.1e-10)
  assert node == parseKdl("numbers 1 2.13 3.1e-10")[0]

  assert toKdlVal("abc"[tag]) == parseKdl("node (tag)\"abc\"")[0].args[0]

## Furthermore there are the `toKdlArgs` and `toKdlProps` macros, they provide shortcuts for creating a sequence and a table of `KdlVal`:
runnableExamples:
  assert toKdlArgs(1, 2[tag], "a") == [1.initKVal, 2.initKVal("tag".some), "a".initKVal]
  assert toKdlProps({"a": 1[tag], "b": 2}) ==
    {"a": 1.initKVal("tag".some), "b": 2.initKVal}.toTable

## ## Compile flags
## `-d:kdlDecoderAllowHoleyEnums`: to allow converting integers into holey enums.
## `-d:kdlDecoderNoCaseTransitionError`: to not get a compile error when trying to change a discriminator field from an object variant in an init hook.

## ## More
## Checkout these other useful modules:
## - [kdl/encoder](kdl/encoder.html) for KDL serializing (Nim objects to KDL)
## - [kdl/decoder](kdl/decoder.html) for KDL deserializing (KDL to Nim objects)
## - [kdl/xix](kdl/xik.html) for [XML-in-KDL](https://github.com/kdl-org/kdl/blob/main/XML-IN-KDL.md)
## - [kdl/jix](kdl/jix.html) for [JSON-in-KDL](https://github.com/kdl-org/kdl/blob/main/JSON-IN-KDL.md)
## - [kdl/prefs](kdl/prefs.html) for a simple preferences sytem.

import std/[algorithm, enumerate, strformat, strutils, sequtils, options, tables, math]
import bigints

import kdl/[decoder, encoder, parser, nodes, types, utils, xik, jik]

export decoder, encoder, parser, nodes, types
export parseKdl # parser main entry point

func indent(s: string, count: Natural, padding = " ", newLine = "\n"): string =
  for e, line in enumerate(s.splitLines):
    if e > 0:
      result.add newLine

    for j in 1 .. count:
      result.add padding

    result.add line

func noSlashQuoted(s: string): string =
  result = "\""
  for c in s:
    case c
    of '"': result.add "\""
    of '\\': result.add "\\\\"
    else: result.add c
  result.add "\""

proc prettyIdent*(ident: string): string =
  if needsQuoting(ident):
    ident.noSlashQuoted()
  else:
    ident

proc prettyFloat(f: float): string =
  ## Format float for KDL 2.0 output
  ## KDL 2.0 requires uppercase E for scientific notation and explicit + for positive exponents

  proc trimScientific(s: string): string =
    # Trim trailing zeros from mantissa but keep at least one decimal place
    if 'E' notin s:
      return s
    let parts = s.split('E')
    var mantissa = parts[0]
    let exponent = parts[1]
    if '.' in mantissa:
      while mantissa.endsWith("0") and not mantissa.endsWith(".0"):
        mantissa = mantissa[0..^2]
      if mantissa.endsWith("."):
        mantissa &= "0"
    result = mantissa & "E" & exponent

  let s = $f

  # If already uses scientific notation
  if 'e' in s:
    result = s
    let parts = result.split('e')
    var mantissa = parts[0]
    let exponent = parts[1]
    # Ensure decimal point in mantissa
    if '.' notin mantissa:
      mantissa &= ".0"
    result = mantissa & "E" & exponent
    # Add explicit + for positive exponents
    if not (result.contains("E+") or result.contains("E-")):
      result = result.replace("E", "E+")
  # Force scientific notation for very large/small numbers
  elif abs(f) >= 1e10 or (abs(f) < 1e-5 and f != 0.0):
    result = formatFloat(f, ffScientific, -1)
    result = result.replace("e", "E")
    if not (result.contains("E+") or result.contains("E-")):
      result = result.replace("E", "E+")
    result = trimScientific(result)
  else:
    result = s

proc pretty*(val: KdlVal): string =
  if val.tag.isSome:
    result = &"({val.tag.get.prettyIdent})"

  result.add:
    case val.kind
    of KFloat:
      let f = val.getFloat()
      if classify(f) == fcInf:
        "#inf"
      elif classify(f) == fcNegInf:
        "#-inf"
      elif classify(f) == fcNan:
        "#nan"
      else:
        prettyFloat(f)
    of KString:
      # KDL 2.0: only quote strings if needed
      let s = val.getString()
      if needsQuoting(s): s.quoted() else: s
    of KBool:
      # KDL 2.0: booleans use # prefix
      if val.getBool(): "#true" else: "#false"
    of KNull:
      # KDL 2.0: null uses # prefix
      "#null"
    of KInt:
      $val.getInt()
    of KInt8:
      $val.i8
    of KInt16:
      $val.i16
    of KInt32:
      $val.i32
    of KInt64:
      $val.i64
    of KUInt8:
      $val.u8
    of KUInt16:
      $val.u16
    of KUInt32:
      $val.u32
    of KUInt64:
      $val.u64
    of KBigInt:
      $val.bigint  # BigInt has a $ operator that converts to decimal string
    of KFloat32:
      let f = val.f32.float64
      if classify(f) == fcInf:
        "#inf"
      elif classify(f) == fcNegInf:
        "#-inf"
      elif classify(f) == fcNan:
        "#nan"
      else:
        prettyFloat(f)
    of KFloat64:
      let f = val.f64
      if classify(f) == fcInf:
        "#inf"
      elif classify(f) == fcNegInf:
        "#-inf"
      elif classify(f) == fcNan:
        "#nan"
      else:
        prettyFloat(f)
    of KDate:
      val.date.quoted
    of KTime:
      val.time.quoted
    of KDateTime:
      val.datetime.quoted
    of KDuration:
      val.duration.quoted
    of KEmpty:
      "empty"

proc pretty*(doc: KdlDoc, newLine = true): string

proc pretty*(node: KdlNode): string =
  if node.tag.isSome:
    result = &"({node.tag.get.prettyIdent})"

  result.add node.name.prettyIdent()

  if node.args.len > 0:
    result.add " "
    for e, val in node.args:
      if e in 1 .. node.args.high:
        result.add " "

      result.add val.pretty()

  if node.props.len > 0:
    result.add " "
    for e, (key, val) in node.props.pairs.toSeq.sortedByIt(it[0]):
      if e in 1 ..< node.props.len:
        result.add " "

      result.add &"{key.prettyIdent}={val.pretty}"

  if node.children.len > 0:
    result.add " {\p"
    result.add indent(node.children.pretty(newLine = false), 4, newLine = "\p")
    result.add "\p}"

proc pretty*(doc: KdlDoc, newLine = true): string =
  ## Pretty print a KDL document according to the [translation rules](https://github.com/kdl-org/kdl/tree/main/tests#translation-rules).
  ##
  ## If `newLine`, inserts a new line at the end.
  for e, node in doc:
    result.add node.pretty()
    if e < doc.high:
      result.add "\p"

  if newLine:
    result.add "\p"

proc writeFile*(path: string, doc: KdlDoc, pretty = false) =
  ## Writes `doc` to path. Set `pretty` to true to use `pretty` instead of `$`.
  if pretty:
    writeFile(path, doc.pretty())
  else:
    writeFile(path, $doc & '\n')
