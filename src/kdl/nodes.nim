## This module implements initializers, comparision, getters, setters, operatores and macros to manipilate `KdlVal`, `KdlNode` and `KdlDoc`.
import std/[strformat, strutils, options, tables, macros, math]
import bigints

import types, utils

export options, tables

# ----- Initializers -----

proc initKNode*(
    name: string,
    tag = string.none,
    args: openarray[KdlVal] = newSeq[KdlVal](),
    props = initTable[string, KdlVal](),
    children: openarray[KdlNode] = newSeq[KdlNode](),
): KdlNode =
  KdlNode(tag: tag, name: name, args: @args, props: props, children: @children)

proc initKVal*(val: string, tag = string.none): KdlVal =
  KdlVal(tag: tag, kind: KString, str: val)

proc initKVal*(val: SomeFloat, tag = string.none): KdlVal =
  KdlVal(tag: tag, kind: KFloat, fnum: val.float)

proc initKVal*(val: float32, tag = string.none): KdlVal =
  KdlVal(tag: tag, kind: KFloat32, f32: val)

proc initKVal*(val: float64, tag = string.none): KdlVal =
  KdlVal(tag: tag, kind: KFloat64, f64: val)

proc initKVal*(val: bool, tag = string.none): KdlVal =
  KdlVal(tag: tag, kind: KBool, boolean: val)

proc initKVal*(val: typeof(nil), tag = string.none): KdlVal =
  KdlVal(tag: tag, kind: KNull)

proc initKVal*(val: SomeInteger, tag = string.none): KdlVal =
  KdlVal(tag: tag, kind: KInt, num: val.int64)

proc initKVal*(val: int8, tag = string.none): KdlVal =
  KdlVal(tag: tag, kind: KInt8, i8: val)

proc initKVal*(val: int16, tag = string.none): KdlVal =
  KdlVal(tag: tag, kind: KInt16, i16: val)

proc initKVal*(val: int32, tag = string.none): KdlVal =
  KdlVal(tag: tag, kind: KInt32, i32: val)

proc initKVal*(val: int64, tag = string.none): KdlVal =
  KdlVal(tag: tag, kind: KInt64, i64: val)

proc initKVal*(val: uint8, tag = string.none): KdlVal =
  KdlVal(tag: tag, kind: KUInt8, u8: val)

proc initKVal*(val: uint16, tag = string.none): KdlVal =
  KdlVal(tag: tag, kind: KUInt16, u16: val)

proc initKVal*(val: uint32, tag = string.none): KdlVal =
  KdlVal(tag: tag, kind: KUInt32, u32: val)

proc initKVal*(val: uint64, tag = string.none): KdlVal =
  KdlVal(tag: tag, kind: KUInt64, u64: val)

# Date and Time types
proc initKVal*(val: string, k: KValKind, tag = string.none): KdlVal =
  case k
  of KDate:
    KdlVal(tag: tag, kind: KDate, date: val)
  of KTime:
    KdlVal(tag: tag, kind: KTime, time: val)
  of KDateTime:
    KdlVal(tag: tag, kind: KDateTime, datetime: val)
  of KDuration:
    KdlVal(tag: tag, kind: KDuration, duration: val)
  else:
    raise newException(ValueError, "Invalid KValKind for string initialization")

proc initKVal*(val: KdlVal): KdlVal =
  val

proc initKString*(val = string.default, tag = string.none): KdlVal =
  initKVal(val, tag)

proc initKFloat*(val: SomeFloat = float.default, tag = string.none): KdlVal =
  initKVal(val.float, tag)

proc initKFloat32*(val: float32 = float32.default, tag = string.none): KdlVal =
  initKVal(val, tag)

proc initKFloat64*(val: float64 = float64.default, tag = string.none): KdlVal =
  initKVal(val, tag)

proc initKBool*(val = bool.default, tag = string.none): KdlVal =
  initKVal(val, tag)

proc initKNull*(tag = string.none): KdlVal =
  KdlVal(tag: tag, kind: KNull)

proc initKInt*(val: SomeInteger = int64.default, tag = string.none): KdlVal =
  initKVal(val.int64, tag)

proc initKInt8*(val: int8 = int8.default, tag = string.none): KdlVal =
  initKVal(val, tag)

proc initKInt16*(val: int16 = int16.default, tag = string.none): KdlVal =
  initKVal(val, tag)

proc initKInt32*(val: int32 = int32.default, tag = string.none): KdlVal =
  initKVal(val, tag)

proc initKInt64*(val: int64 = int64.default, tag = string.none): KdlVal =
  initKVal(val, tag)

proc initKUInt8*(val: uint8 = uint8.default, tag = string.none): KdlVal =
  initKVal(val, tag)

proc initKUInt16*(val: uint16 = uint16.default, tag = string.none): KdlVal =
  initKVal(val, tag)

proc initKUInt32*(val: uint32 = uint32.default, tag = string.none): KdlVal =
  initKVal(val, tag)

proc initKUInt64*(val: uint64 = uint64.default, tag = string.none): KdlVal =
  initKVal(val, tag)

proc initKBigInt*(val: BigInt, tag = string.none): KdlVal =
  KdlVal(tag: tag, kind: KBigInt, bigint: val)

proc initKDate*(val: string = string.default, tag = string.none): KdlVal =
  initKVal(val, KDate, tag)

proc initKTime*(val: string = string.default, tag = string.none): KdlVal =
  initKVal(val, KTime, tag)

proc initKDateTime*(val: string = string.default, tag = string.none): KdlVal =
  initKVal(val, KDateTime, tag)

proc initKDuration*(val: string = string.default, tag = string.none): KdlVal =
  initKVal(val, KDuration, tag)

# ----- Comparisions -----

proc isString*(val: KdlVal): bool =
  val.kind == KString

proc isFloat*(val: KdlVal): bool =
  val.kind == KFloat or val.kind == KFloat32 or val.kind == KFloat64

proc isFloat32*(val: KdlVal): bool =
  val.kind == KFloat32

proc isFloat64*(val: KdlVal): bool =
  val.kind == KFloat64

proc isBool*(val: KdlVal): bool =
  val.kind == KBool

proc isInt*(val: KdlVal): bool =
  val.kind == KInt or val.kind == KInt8 or val.kind == KInt16 or val.kind == KInt32 or
  val.kind == KInt64 or val.kind == KUInt8 or val.kind == KUInt16 or
  val.kind == KUInt32 or val.kind == KUInt64

proc isInt8*(val: KdlVal): bool =
  val.kind == KInt8

proc isInt16*(val: KdlVal): bool =
  val.kind == KInt16

proc isInt32*(val: KdlVal): bool =
  val.kind == KInt32

proc isInt64*(val: KdlVal): bool =
  val.kind == KInt64

proc isUInt8*(val: KdlVal): bool =
  val.kind == KUInt8

proc isUInt16*(val: KdlVal): bool =
  val.kind == KUInt16

proc isUInt32*(val: KdlVal): bool =
  val.kind == KUInt32

proc isUInt64*(val: KdlVal): bool =
  val.kind == KUInt64

proc isNull*(val: KdlVal): bool =
  val.kind == KNull

proc isEmpty*(val: KdlVal): bool =
  val.kind == KEmpty

proc isDate*(val: KdlVal): bool =
  val.kind == KDate

proc isTime*(val: KdlVal): bool =
  val.kind == KTime

proc isDateTime*(val: KdlVal): bool =
  val.kind == KDateTime

proc isDuration*(val: KdlVal): bool =
  val.kind == KDuration

# ----- Getters -----

proc getString*(val: KdlVal): string =
  check val.isString()
  val.str

proc getFloat*(val: KdlVal): float =
  check val.isFloat()
  case val.kind
  of KFloat:
    val.fnum
  of KFloat32:
    val.f32.float
  of KFloat64:
    val.f64
  else:
    raise newException(ValueError, "Not a float type")

proc getFloat32*(val: KdlVal): float32 =
  check val.isFloat()
  case val.kind
  of KFloat:
    val.fnum.float32
  of KFloat32:
    val.f32
  of KFloat64:
    val.f64.float32
  else:
    raise newException(ValueError, "Not a float type")

proc getFloat64*(val: KdlVal): float64 =
  check val.isFloat()
  case val.kind
  of KFloat:
    val.fnum
  of KFloat32:
    val.f32.float64
  of KFloat64:
    val.f64
  else:
    raise newException(ValueError, "Not a float type")

proc getBool*(val: KdlVal): bool =
  check val.isBool()
  val.boolean

proc getInt*(val: KdlVal): int64 =
  check val.isInt()
  case val.kind
  of KInt:
    val.num
  of KInt8:
    val.i8.int64
  of KInt16:
    val.i16.int64
  of KInt32:
    val.i32.int64
  of KInt64:
    val.i64
  of KUInt8:
    val.u8.int64
  of KUInt16:
    val.u16.int64
  of KUInt32:
    val.u32.int64
  of KUInt64:
    val.u64.int64
  else:
    raise newException(ValueError, "Not an integer type")

proc getInt8*(val: KdlVal): int8 =
  check val.isInt()
  case val.kind
  of KInt:
    val.num.int8
  of KInt8:
    val.i8
  of KInt16:
    val.i16.int8
  of KInt32:
    val.i32.int8
  of KInt64:
    val.i64.int8
  of KUInt8:
    val.u8.int8
  of KUInt16:
    val.u16.int8
  of KUInt32:
    val.u32.int8
  of KUInt64:
    val.u64.int8
  else:
    raise newException(ValueError, "Not an integer type")

proc getInt16*(val: KdlVal): int16 =
  check val.isInt()
  case val.kind
  of KInt:
    val.num.int16
  of KInt8:
    val.i8.int16
  of KInt16:
    val.i16
  of KInt32:
    val.i32.int16
  of KInt64:
    val.i64.int16
  of KUInt8:
    val.u8.int16
  of KUInt16:
    val.u16.int16
  of KUInt32:
    val.u32.int16
  of KUInt64:
    val.u64.int16
  else:
    raise newException(ValueError, "Not an integer type")

proc getInt32*(val: KdlVal): int32 =
  check val.isInt()
  case val.kind
  of KInt:
    val.num.int32
  of KInt8:
    val.i8.int32
  of KInt16:
    val.i16.int32
  of KInt32:
    val.i32
  of KInt64:
    val.i64.int32
  of KUInt8:
    val.u8.int32
  of KUInt16:
    val.u16.int32
  of KUInt32:
    val.u32.int32
  of KUInt64:
    val.u64.int32
  else:
    raise newException(ValueError, "Not an integer type")

proc getInt64*(val: KdlVal): int64 =
  check val.isInt()
  case val.kind
  of KInt:
    val.num
  of KInt8:
    val.i8.int64
  of KInt16:
    val.i16.int64
  of KInt32:
    val.i32.int64
  of KInt64:
    val.i64
  of KUInt8:
    val.u8.int64
  of KUInt16:
    val.u16.int64
  of KUInt32:
    val.u32.int64
  of KUInt64:
    val.u64.int64
  else:
    raise newException(ValueError, "Not an integer type")

proc getUInt8*(val: KdlVal): uint8 =
  check val.isInt()
  case val.kind
  of KInt:
    val.num.uint8
  of KInt8:
    val.i8.uint8
  of KInt16:
    val.i16.uint8
  of KInt32:
    val.i32.uint8
  of KInt64:
    val.i64.uint8
  of KUInt8:
    val.u8
  of KUInt16:
    val.u16.uint8
  of KUInt32:
    val.u32.uint8
  of KUInt64:
    val.u64.uint8
  else:
    raise newException(ValueError, "Not an integer type")

proc getUInt16*(val: KdlVal): uint16 =
  check val.isInt()
  case val.kind
  of KInt:
    val.num.uint16
  of KInt8:
    val.i8.uint16
  of KInt16:
    val.i16.uint16
  of KInt32:
    val.i32.uint16
  of KInt64:
    val.i64.uint16
  of KUInt8:
    val.u8.uint16
  of KUInt16:
    val.u16
  of KUInt32:
    val.u32.uint16
  of KUInt64:
    val.u64.uint16
  else:
    raise newException(ValueError, "Not an integer type")

proc getUInt32*(val: KdlVal): uint32 =
  check val.isInt()
  case val.kind
  of KInt:
    val.num.uint32
  of KInt8:
    val.i8.uint32
  of KInt16:
    val.i16.uint32
  of KInt32:
    val.i32.uint32
  of KInt64:
    val.i64.uint32
  of KUInt8:
    val.u8.uint32
  of KUInt16:
    val.u16.uint32
  of KUInt32:
    val.u32
  of KUInt64:
    val.u64.uint32
  else:
    raise newException(ValueError, "Not an integer type")

proc getUInt64*(val: KdlVal): uint64 =
  check val.isInt()
  case val.kind
  of KInt:
    val.num.uint64
  of KInt8:
    val.i8.uint64
  of KInt16:
    val.i16.uint64
  of KInt32:
    val.i32.uint64
  of KInt64:
    val.i64.uint64
  of KUInt8:
    val.u8.uint64
  of KUInt16:
    val.u16.uint64
  of KUInt32:
    val.u32.uint64
  of KUInt64:
    val.u64
  else:
    raise newException(ValueError, "Not an integer type")

proc getDate*(val: KdlVal): string =
  check val.isDate()
  val.date

proc getTime*(val: KdlVal): string =
  check val.isTime()
  val.time

proc getDateTime*(val: KdlVal): string =
  check val.isDateTime()
  val.datetime

proc getDuration*(val: KdlVal): string =
  check val.isDuration()
  val.duration

proc get*[T: Value](val: KdlVal, x: typedesc[T]): T =
  ## When x is string, stringifies val using `$`.
  ## when x is SomeNumber, converts val to x.
  runnableExamples:
    let val = initKFloat(3.14)

    assert val.get(int) == 3
    assert val.get(uint) == 3u
    assert val.get(float) == 3.14
    assert val.get(float32) == 3.14f
    assert val.get(range[0f .. 4f]) == 3.14f
    assert val.get(string) == "3.14"

  when T is string:
    result =
      case val.kind
      of KFloat:
        $val.getFloat()
      of KString:
        val.getString()
      of KBool:
        $val.getBool()
      of KNull:
        "null"
      of KInt:
        $val.getInt()
      of KInt8:
        $val.getInt8()
      of KInt16:
        $val.getInt16()
      of KInt32:
        $val.getInt32()
      of KInt64:
        $val.getInt64()
      of KUInt8:
        $val.getUInt8()
      of KUInt16:
        $val.getUInt16()
      of KUInt32:
        $val.getUInt32()
      of KUInt64:
        $val.getUInt64()
      of KBigInt:
        $val.bigint
      of KFloat32:
        $val.getFloat32()
      of KFloat64:
        $val.getFloat64()
      of KDate:
        val.getDate()
      of KTime:
        val.getTime()
      of KDateTime:
        val.getDateTime()
      of KDuration:
        val.getDuration()
      of KEmpty:
        "empty"
  elif T is SomeNumber or T is range:
    check val.isFloat or val.isInt

    result =
      case val.kind
      of KInt:
        T(val.num)
      of KInt8:
        T(val.i8)
      of KInt16:
        T(val.i16)
      of KInt32:
        T(val.i32)
      of KInt64:
        T(val.i64)
      of KUInt8:
        T(val.u8)
      of KUInt16:
        T(val.u16)
      of KUInt32:
        T(val.u32)
      of KUInt64:
        T(val.u64)
      of KFloat:
        T(val.fnum)
      of KFloat32:
        T(val.f32)
      of KFloat64:
        T(val.f64)
      else:
        raise newException(ValueError, "Not a numeric type")
  elif T is bool:
    check val.isBool

    result = val.boolean
  else:
    {.error: "get is not implemented for " & $typeof(T).}

# ----- Setters -----

proc setString*(val: var KdlVal, x: string) =
  check val.isString()
  val.str = x

proc setFloat*(val: var KdlVal, x: SomeFloat) =
  check val.isFloat()
  case val.kind
  of KFloat:
    val.fnum = x
  of KFloat32:
    val.f32 = x.float32
  of KFloat64:
    val.f64 = x.float64
  else:
    raise newException(ValueError, "Not a float type")

proc setFloat32*(val: var KdlVal, x: float32) =
  check val.isFloat()
  case val.kind
  of KFloat:
    val.fnum = x.float
  of KFloat32:
    val.f32 = x
  of KFloat64:
    val.f64 = x.float64
  else:
    raise newException(ValueError, "Not a float type")

proc setFloat64*(val: var KdlVal, x: float64) =
  check val.isFloat()
  case val.kind
  of KFloat:
    val.fnum = x
  of KFloat32:
    val.f32 = x.float32
  of KFloat64:
    val.f64 = x
  else:
    raise newException(ValueError, "Not a float type")

proc setBool*(val: var KdlVal, x: bool) =
  check val.isBool()
  val.boolean = x

proc setInt*(val: var KdlVal, x: SomeInteger) =
  check val.isInt()
  case val.kind
  of KInt:
    val.num = x.int64
  of KInt8:
    val.i8 = x.int8
  of KInt16:
    val.i16 = x.int16
  of KInt32:
    val.i32 = x.int32
  of KInt64:
    val.i64 = x.int64
  of KUInt8:
    val.u8 = x.uint8
  of KUInt16:
    val.u16 = x.uint16
  of KUInt32:
    val.u32 = x.uint32
  of KUInt64:
    val.u64 = x.uint64
  else:
    raise newException(ValueError, "Not an integer type")

proc setInt8*(val: var KdlVal, x: int8) =
  check val.isInt()
  case val.kind
  of KInt:
    val.num = x.int64
  of KInt8:
    val.i8 = x
  of KInt16:
    val.i16 = x.int16
  of KInt32:
    val.i32 = x.int32
  of KInt64:
    val.i64 = x.int64
  of KUInt8:
    val.u8 = x.uint8
  of KUInt16:
    val.u16 = x.uint16
  of KUInt32:
    val.u32 = x.uint32
  of KUInt64:
    val.u64 = x.uint64
  else:
    raise newException(ValueError, "Not an integer type")

proc setInt16*(val: var KdlVal, x: int16) =
  check val.isInt()
  case val.kind
  of KInt:
    val.num = x.int64
  of KInt8:
    val.i8 = x.int8
  of KInt16:
    val.i16 = x
  of KInt32:
    val.i32 = x.int32
  of KInt64:
    val.i64 = x.int64
  of KUInt8:
    val.u8 = x.uint8
  of KUInt16:
    val.u16 = x.uint16
  of KUInt32:
    val.u32 = x.uint32
  of KUInt64:
    val.u64 = x.uint64
  else:
    raise newException(ValueError, "Not an integer type")

proc setInt32*(val: var KdlVal, x: int32) =
  check val.isInt()
  case val.kind
  of KInt:
    val.num = x.int64
  of KInt8:
    val.i8 = x.int8
  of KInt16:
    val.i16 = x.int16
  of KInt32:
    val.i32 = x
  of KInt64:
    val.i64 = x.int64
  of KUInt8:
    val.u8 = x.uint8
  of KUInt16:
    val.u16 = x.uint16
  of KUInt32:
    val.u32 = x.uint32
  of KUInt64:
    val.u64 = x.uint64
  else:
    raise newException(ValueError, "Not an integer type")

proc setInt64*(val: var KdlVal, x: int64) =
  check val.isInt()
  case val.kind
  of KInt:
    val.num = x
  of KInt8:
    val.i8 = x.int8
  of KInt16:
    val.i16 = x.int16
  of KInt32:
    val.i32 = x.int32
  of KInt64:
    val.i64 = x
  of KUInt8:
    val.u8 = x.uint8
  of KUInt16:
    val.u16 = x.uint16
  of KUInt32:
    val.u32 = x.uint32
  of KUInt64:
    val.u64 = x.uint64
  else:
    raise newException(ValueError, "Not an integer type")

proc setUInt8*(val: var KdlVal, x: uint8) =
  check val.isInt()
  case val.kind
  of KInt:
    val.num = x.int64
  of KInt8:
    val.i8 = x.int8
  of KInt16:
    val.i16 = x.int16
  of KInt32:
    val.i32 = x.int32
  of KInt64:
    val.i64 = x.int64
  of KUInt8:
    val.u8 = x
  of KUInt16:
    val.u16 = x.uint16
  of KUInt32:
    val.u32 = x.uint32
  of KUInt64:
    val.u64 = x.uint64
  else:
    raise newException(ValueError, "Not an integer type")

proc setUInt16*(val: var KdlVal, x: uint16) =
  check val.isInt()
  case val.kind
  of KInt:
    val.num = x.int64
  of KInt8:
    val.i8 = x.int8
  of KInt16:
    val.i16 = x.int16
  of KInt32:
    val.i32 = x.int32
  of KInt64:
    val.i64 = x.int64
  of KUInt8:
    val.u8 = x.uint8
  of KUInt16:
    val.u16 = x
  of KUInt32:
    val.u32 = x.uint32
  of KUInt64:
    val.u64 = x.uint64
  else:
    raise newException(ValueError, "Not an integer type")

proc setUInt32*(val: var KdlVal, x: uint32) =
  check val.isInt()
  case val.kind
  of KInt:
    val.num = x.int64
  of KInt8:
    val.i8 = x.int8
  of KInt16:
    val.i16 = x.int16
  of KInt32:
    val.i32 = x.int32
  of KInt64:
    val.i64 = x.int64
  of KUInt8:
    val.u8 = x.uint8
  of KUInt16:
    val.u16 = x.uint16
  of KUInt32:
    val.u32 = x
  of KUInt64:
    val.u64 = x.uint64
  else:
    raise newException(ValueError, "Not an integer type")

proc setUInt64*(val: var KdlVal, x: uint64) =
  check val.isInt()
  case val.kind
  of KInt:
    val.num = x.int64
  of KInt8:
    val.i8 = x.int8
  of KInt16:
    val.i16 = x.int16
  of KInt32:
    val.i32 = x.int32
  of KInt64:
    val.i64 = x.int64
  of KUInt8:
    val.u8 = x.uint8
  of KUInt16:
    val.u16 = x.uint16
  of KUInt32:
    val.u32 = x.uint32
  of KUInt64:
    val.u64 = x
  else:
    raise newException(ValueError, "Not an integer type")

proc setDate*(val: var KdlVal, x: string) =
  check val.isDate()
  val.date = x

proc setTime*(val: var KdlVal, x: string) =
  check val.isTime()
  val.time = x

proc setDateTime*(val: var KdlVal, x: string) =
  check val.isDateTime()
  val.datetime = x

proc setDuration*(val: var KdlVal, x: string) =
  check val.isDuration()
  val.duration = x

proc setTo*[T: Value](val: var KdlVal, x: T) =
  ## Tries to set val to x, raises an error when types are not compatible.
  runnableExamples:
    var val = initKFloat(3.14)

    val.setTo(100u8)

    assert val.getFloat() == 100

    val.setTo(20.12e2f)

    assert val.get(float32) == 20.12e2f

  when T is string:
    case val.kind
    of KString, KDate, KTime, KDateTime, KDuration:
      val.setString(x)
    else:
      raise newException(ValueError, "Cannot set non-string KdlVal to a string")
  elif T is SomeInteger:
    if val.isInt:
      val.setInt(x)
    else:
      raise newException(ValueError, "Cannot set non-integer KdlVal to an integer")
  elif T is SomeFloat:
    if val.isFloat:
      val.setFloat(x)
    else:
      raise newException(ValueError, "Cannot set non-float KdlVal to a float")
  elif T is bool:
    val.setBool(x)
  else:
    raise newException(ValueError, "setTo is not implemented for " & $typeof(T))

# ----- Operators -----

proc `$`*(val: KdlVal): string =
  ## Returns "(tag)val"
  if val.tag.isSome:
    let tagStr = if needsQuoting(val.tag.get): val.tag.get.quoted else: val.tag.get
    result = &"({tagStr})"

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
        $f
    of KString:
      # KDL 2.0: only quote strings if they need quoting
      let s = val.getString()
      if needsQuoting(s): s.quoted else: s
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
      $val.bigint
    of KFloat32:
      let f = val.f32.float64
      if classify(f) == fcInf:
        "#inf"
      elif classify(f) == fcNegInf:
        "#-inf"
      elif classify(f) == fcNan:
        "#nan"
      else:
        $val.f32
    of KFloat64:
      let f = val.f64
      if classify(f) == fcInf:
        "#inf"
      elif classify(f) == fcNegInf:
        "#-inf"
      elif classify(f) == fcNan:
        "#nan"
      else:
        $val.f64
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

proc inline*(doc: KdlDoc): string

proc inline*(node: KdlNode): string =
  ## Returns node's single-line representation
  if node.tag.isSome:
    let tagStr = if needsQuoting(node.tag.get): node.tag.get.quoted else: node.tag.get
    result = &"({tagStr})"

  result.add if needsQuoting(node.name): node.name.quoted else: node.name

  if node.args.len > 0:
    result.add " "
    for e, val in node.args:
      if e in 1 .. node.args.high:
        result.add " "

      result.add $val

  if node.props.len > 0:
    result.add " "
    var count = 0
    for key, val in node.props:
      if count in 1 ..< node.props.len:
        result.add " "

      let keyStr = if needsQuoting(key): key.quoted else: key
      result.add &"{keyStr}={val}"

      inc count

  if node.children.len > 0:
    result.add " { "
    result.add inline(node.children)
    result.add " }"

proc inline*(doc: KdlDoc): string =
  ## Returns doc's single-line representation
  for e, node in doc:
    result.add $node
    if e < doc.high:
      result.add "; "

proc `$`*(doc: KdlDoc): string

proc `$`*(node: KdlNode): string =
  ## The result is always valid KDL.

  if node.tag.isSome:
    let tagStr = if needsQuoting(node.tag.get): node.tag.get.quoted else: node.tag.get
    result = &"({tagStr})"

  result.add if needsQuoting(node.name): node.name.quoted else: node.name

  if node.args.len > 0:
    result.add " "
    for e, val in node.args:
      if e in 1 .. node.args.high:
        result.add " "

      result.add $val

  if node.props.len > 0:
    result.add " "
    var count = 0
    for key, val in node.props:
      if count in 1 ..< node.props.len:
        result.add " "

      let keyStr = if needsQuoting(key): key.quoted else: key
      result.add &"{keyStr}={val}"

      inc count

  if node.children.len > 0:
    result.add " {\n"
    result.add indent($node.children, 2)
    result.add "\n}"

proc `$`*(doc: KdlDoc): string =
  ## The result is always valid KDL.
  for e, node in doc:
    result.add $node
    if e < doc.high:
      result.add "\n"

proc `==`*(val1, val2: KdlVal): bool =
  ## Checks if val1 and val2 have the same value. They must be of the same kind.

  if val1.kind != val2.kind:
    return false

  case val1.kind
  of KString:
    val1.getString() == val2.getString()
  of KFloat:
    val1.getFloat() == val2.getFloat()
  of KFloat32:
    val1.f32 == val2.f32
  of KFloat64:
    val1.f64 == val2.f64
  of KBool:
    val1.getBool() == val2.getBool()
  of KNull, KEmpty:
    true
  of KInt:
    val1.getInt() == val2.getInt()
  of KInt8:
    val1.i8 == val2.i8
  of KInt16:
    val1.i16 == val2.i16
  of KInt32:
    val1.i32 == val2.i32
  of KInt64:
    val1.i64 == val2.i64
  of KUInt8:
    val1.u8 == val2.u8
  of KUInt16:
    val1.u16 == val2.u16
  of KUInt32:
    val1.u32 == val2.u32
  of KUInt64:
    val1.u64 == val2.u64
  of KBigInt:
    val1.bigint == val2.bigint
  of KDate:
    val1.date == val2.date
  of KTime:
    val1.time == val2.time
  of KDateTime:
    val1.datetime == val2.datetime
  of KDuration:
    val1.duration == val2.duration

proc `==`*[T: Value](val: KdlVal, x: T): bool =
  ## Checks if val is x, raises an error when they are not comparable.
  runnableExamples:
    assert initKVal("a") == "a"
    assert initKVal(1) == 1
    assert initKVal(true) == true

  when T is string:
    check val.isString or val.isDate or val.isTime or val.isDateTime or val.isDuration
    case val.kind
    of KString:
      result = val.str == x
    of KDate:
      result = val.date == x
    of KTime:
      result = val.time == x
    of KDateTime:
      result = val.datetime == x
    of KDuration:
      result = val.duration == x
    else:
      result = false # Should not happen due to check
  elif T is SomeInteger:
    check val.isInt
    result = val.getInt() == x.int64
  elif T is SomeFloat:
    check val.isFloat
    result = val.getFloat() == x.float
  elif T is bool:
    check val.isBool
    result = val.getBool() == x
  else:
    {.error: "== is not implemented for " & $typeof(T).}

func `==`*(node1, node2: KdlNode): bool =
  {.cast(noSideEffect).}:
    system.`==`(node1, node2)

proc `[]`*(node: KdlNode, key: string): KdlVal =
  ## Gets the value of the key property.
  node.props[key]

proc `[]`*(node: var KdlNode, key: string): var KdlVal = # TODO test
  ## Gets the value of the key property.
  node.props[key]

proc `[]=`*(node: var KdlNode, key: string, val: KdlVal) =
  ## Sets the key property to val in node.
  node.props[key] = val

proc contains*(node: KdlNode, key: string): bool =
  ## Checks if node has the key property.
  key in node.props

proc contains*(node: KdlNode, val: KdlVal): bool =
  ## Checks if node has the val argument.
  val in node.args

proc contains*(node: KdlNode, child: KdlNode): bool =
  ## Checks if node has the child children.
  child in node.children

proc contains*(doc: KdlDoc, name: string): bool =
  ## Checks if doc has a node called name
  for node in doc:
    if node.name == name:
      return true

proc add*(node: var KdlNode, val: KdlVal) =
  ## Adds val to node's arguments.

  node.args.add(val)

proc add*(node: var KdlNode, child: KdlNode) =
  ## Adds child to node's children.

  node.children.add(child)

proc findFirst*(doc: KdlDoc, name: string): int =
  ## Returns the index of the first node called name.
  ## Returns -1 when it doesn't exist
  result = -1

  for e, node in doc:
    if node.name == name:
      return e

proc findLast*(doc: KdlDoc, name: string): int =
  ## Returns the index of the last node called name.
  ## Returns -1 when it doesn't exist
  result = -1
  for e in countdown(doc.high, 0):
    if doc[e].name == name:
      return e

proc find*(doc: KdlDoc, name: string): seq[KdlNode] =
  ## Returns all the nodes called name.
  for node in doc:
    if node.name == name:
      result.add node

# ----- Macros -----

const identNodes = {nnkStrLit, nnkRStrLit, nnkTripleStrLit, nnkIdent}

proc strIdent(node: NimNode): NimNode =
  node.expectKind(identNodes)
  newStrLitNode(node.strVal)

proc withTag(body: NimNode): tuple[body, tag: NimNode] =
  result.tag = newCall("none", ident"string")

  if body.kind == nnkBracketExpr:
    result.body = body[0]
    result.tag = newCall("some", body[1].strIdent)
  else:
    result.body = body

  result.tag = newTree(nnkExprEqExpr, ident"tag", result.tag)

proc toKdlValImpl(body: NimNode): NimNode =
  let (value, tag) = body.withTag()

  newCall("initKVal", value, tag)

proc toKdlNodeImpl(body: NimNode): NimNode =
  var body = body

  if body.kind in identNodes + {nnkBracketExpr}:
    let (name, tag) = body.withTag()
    return newCall("initKNode", name.strIdent, tag)
  elif body.kind == nnkStmtList: # When a node has children it ends up being nnkStmtList
    body.expectLen(1)
    body = body[0]

  body.expectKind(nnkCall)
  body.expectMinLen(2)

  let (name, tag) = body[0].withTag()

  result = newCall("initKNode", name.strIdent, tag)

  var i = 1 # Index to start parsing args and props from (1 by default because )

  let args = newNimNode(nnkBracket)
  let props = newNimNode(nnkTableConstr)

  while i < body.len and body[i].kind != nnkStmtList:
    if body[i].kind == nnkExprEqExpr:
      props.add newTree(nnkExprColonExpr, body[i][0].strIdent, toKdlValImpl(body[i][1]))
    else:
      args.add newCall("initKVal", toKdlValImpl(body[i]))

    inc i

  result.add newTree(nnkExprEqExpr, ident"args", args)

  if props.len > 0:
    result.add newTree(nnkExprEqExpr, ident"props", newDotExpr(props, ident"toTable"))

  if i < body.len: # Children
    body[i].expectKind(nnkStmtList)
    result.add newTree(nnkExprEqExpr, ident"children", newCall("toKdlDoc", body[i]))

macro toKdlVal*(body: untyped): KdlVal =
  ## Generate a KdlVal from Nim's AST that is somehat similar to KDL's syntax.
  ## - For type annotations use a bracket expresion: `node[tag]` instead of `(tag)node`.

  toKdlValImpl(body)

macro toKdlNode*(body: untyped): KdlNode =
  ## Generate a KdlNode from Nim's AST that is somewhat similar to KDL's syntax.
  ## - For nodes use call syntax: `node(args, props)`.
  ## - For properties use an equal expression: `key=val`.
  ## - For children pass a block to a node: `node(args, props): ...`
  runnableExamples:
    let node = toKdlNode:
      numbers(10[u8], 20[i32], myfloat = 1.5[f32]):
        strings(
          "123e4567-e89b-12d3-a456-426614174000"[uuid],
          "2021-02-03"[date],
          filter = r"$\d+"[regex],
        )
        person[author](name = "Alex")
    # It is the same as:
    # numbers (u8)10 (i32)20 myfloat=(f32)1.5 {
    #   strings (uuid)"123e4567-e89b-12d3-a456-426614174000" (date)"2021-02-03" filter=(regex)r"$\d+"
    #   (author)person name="Alex"
    # }

  toKdlNodeImpl(body)

macro toKdlDoc*(body: untyped): KdlDoc =
  ## Generate a KdlDoc from Nim's AST that is somewhat similar to KDL's syntax.
  ## body has to be an statement list
  ##
  ## See also [toKdlNode](#toKdlNode.m,untyped).
  runnableExamples:
    let doc = toKdlDoc:
      node
      numbers(10[u8], 20[i32], myfloat = 1.5[f32]):
        strings(
          "123e4567-e89b-12d3-a456-426614174000"[uuid],
          "2021-02-03"[date],
          filter = r"$\d+"[regex],
        )
        person[author](name = "Alex")
      "i am also a node"
      color[RGB](r = 200, b = 100, g = 100)

  body.expectKind nnkStmtList

  let doc = newNimNode(nnkBracket)

  for call in body:
    doc.add toKdlNodeImpl(call)

  result = prefix(doc, "@")

macro toKdlArgs*(args: varargs[untyped]): untyped =
  ## Creates an array of `KdlVal`s by calling `initKVal` through `args`.
  runnableExamples:
    assert toKdlArgs(1, 2, "a"[tag]) ==
      [1.initKVal, 2.initKVal, "a".initKVal("tag".some)]
    assert initKNode("name", args = toKdlArgs(nil, true, "b")) ==
      initKNode("name", args = [initKNull(), true.initKVal, "b".initKVal])

  args.expectKind nnkArgList
  result = newNimNode(nnkBracket)
  for arg in args:
    result.add toKdlValImpl(arg)

macro toKdlProps*(props: untyped): Table[string, KdlVal] =
  ## Creates a `Table[string, KdlVal]` from a array-of-tuples/table-constructor by calling `initKVal` through the values.
  runnableExamples:
    assert toKdlProps({"a": 1[i8], "b": 2}) ==
      {"a": 1.initKVal("i8".some), "b": 2.initKVal}.toTable
    assert initKNode("name", props = toKdlProps({"c": nil, "d": true})) ==
      initKNode("name", props = {"c": initKNull(), "d": true.initKVal}.toTable)

  props.expectKind nnkTableConstr

  result = newNimNode(nnkTableConstr)
  for i in props:
    i.expectKind nnkExprColonExpr
    result.add newTree(nnkExprColonExpr, i[0], toKdlValImpl(i[1]))

  result = newCall("toTable", result)
