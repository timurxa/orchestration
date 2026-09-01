## Small Nim binding for the public termbox2 C API.

{.pragma: tb2header, header: "termbox2.h".}
{.emit: """
#define TB_IMPL
#include "termbox2.h"
#undef TB_IMPL
""".}

type
  TbEvent* {.importc: "struct tb_event", bycopy, tb2header.} = object
    eventType* {.importc: "type".}: uint8
    modifier* {.importc: "mod".}: uint8
    key*: uint16
    ch*: uint32
    width*: int32
    height*: int32
    x*: int32
    y*: int32

  TbCell* {.importc: "struct tb_cell", bycopy, tb2header.} = object
    ch*: uint32
    fg*: uint16
    bg*: uint16

const
  TbDefault* = 0'u16
  TbBlack* = 0x0001'u16
  TbRed* = 0x0002'u16
  TbGreen* = 0x0003'u16
  TbYellow* = 0x0004'u16
  TbBlue* = 0x0005'u16
  TbMagenta* = 0x0006'u16
  TbCyan* = 0x0007'u16
  TbWhite* = 0x0008'u16

  TbBold* = 0x0100'u16
  TbUnderline* = 0x0200'u16
  TbReverse* = 0x0400'u16
  TbBright* = 0x4000'u16

  TbKeyCtrlC* = 0x03'u16
  TbKeyTab* = 0x09'u16
  TbKeyEnter* = 0x0d'u16
  TbKeyEsc* = 0x1b'u16
  TbKeyArrowUp* = 0xffff'u16 - 18'u16
  TbKeyArrowDown* = 0xffff'u16 - 19'u16
  TbKeyArrowLeft* = 0xffff'u16 - 20'u16
  TbKeyArrowRight* = 0xffff'u16 - 21'u16
  TbKeyHome* = 0xffff'u16 - 14'u16
  TbKeyEnd* = 0xffff'u16 - 15'u16
  TbKeyPgup* = 0xffff'u16 - 16'u16
  TbKeyPgdn* = 0xffff'u16 - 17'u16

  TbEventKey* = 1'u8
  TbEventResize* = 2'u8

  TbInputEsc* = 1.cint
  TbOutputNormal* = 1.cint

proc tbInit*(): cint {.importc: "tb_init", tb2header.}
proc tbShutdown*(): cint {.importc: "tb_shutdown", tb2header.}
proc tbWidth*(): cint {.importc: "tb_width", tb2header.}
proc tbHeight*(): cint {.importc: "tb_height", tb2header.}
proc tbClear*(): cint {.importc: "tb_clear", tb2header.}
proc tbSetClearAttrs*(fg, bg: uint16): cint {.importc: "tb_set_clear_attrs", tb2header.}
proc tbPresent*(): cint {.importc: "tb_present", tb2header.}
proc tbHideCursor*(): cint {.importc: "tb_hide_cursor", tb2header.}
proc tbSetCell*(x, y: cint; ch: uint32; fg, bg: uint16): cint {.importc: "tb_set_cell", tb2header.}
proc tbSetInputMode*(mode: cint): cint {.importc: "tb_set_input_mode", tb2header.}
proc tbSetOutputMode*(mode: cint): cint {.importc: "tb_set_output_mode", tb2header.}
proc tbPollEvent*(event: ptr TbEvent): cint {.importc: "tb_poll_event", tb2header.}
proc tbPrint*(x, y: cint; fg, bg: uint16; text: cstring): cint {.importc: "tb_print", tb2header.}
proc tbPrintf*(x, y: cint; fg, bg: uint16; format: cstring): cint {.importc: "tb_printf", varargs, tb2header.}
proc tbStrerror*(errorCode: cint): cstring {.importc: "tb_strerror", tb2header.}
