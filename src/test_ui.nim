import termbox2

type
  Pane = enum
    actionsPane, logPane

const
  Actions = ["build project", "run tests", "package release", "deploy staging"]
  Logs = [
    "09:41:02  started build project",
    "09:41:03  compiling src/app.nim",
    "09:41:04  compiled 42 files",
    "09:41:05  tests: 18 passed, 0 failed",
    "09:41:05  artifact written: dist/app",
    "09:41:06  action complete"
  ]

proc put(x, y: int; text: string; fg, bg: uint16) =
  discard tbPrint(x.cint, y.cint, fg, bg, text.cstring)

proc cell(x, y: int; value: char; fg, bg: uint16) =
  discard tbSetCell(x.cint, y.cint, value.uint32, fg, bg)

proc drawBox(x, y, width, height: int; title: string; focused: bool) =
  let border = if focused: TbCyan or TbBold else: TbWhite
  let right = x + width - 1
  let bottom = y + height - 1
  for px in x + 1 ..< right:
    cell(px, y, '-', border, TbDefault)
    cell(px, bottom, '-', border, TbDefault)
  for py in y + 1 ..< bottom:
    cell(x, py, '|', border, TbDefault)
    cell(right, py, '|', border, TbDefault)
  cell(x, y, '+', border, TbDefault)
  cell(right, y, '+', border, TbDefault)
  cell(x, bottom, '+', border, TbDefault)
  cell(right, bottom, '+', border, TbDefault)
  put(x + 2, y, "[" & title & "]", border, TbDefault)

proc draw(actionsIndex, logOffset: int; active: Pane) =
  let width = tbWidth().int
  let height = tbHeight().int
  discard tbClear()
  if width < 30 or height < 8:
    put(0, 0, "terminal too small", TbYellow or TbBold, TbDefault)
    discard tbPresent()
    return

  let leftWidth = max(22, width div 3)
  let bodyHeight = height - 3
  drawBox(0, 0, leftWidth, bodyHeight, "actions", active == actionsPane)
  drawBox(leftWidth, 0, width - leftWidth, bodyHeight, "log", active == logPane)

  for i, action in Actions:
    let fg = if i == actionsIndex: TbBlack else: TbWhite
    let bg = if i == actionsIndex: TbCyan else: TbDefault
    put(2, i + 2, action, fg, bg)

  for i in 0 ..< min(Logs.len - logOffset, bodyHeight - 2):
    put(leftWidth + 2, i + 2, Logs[logOffset + i], TbWhite, TbDefault)

  put(0, height - 1, "Tab/h,l pane  j,k/arrows move  Enter select  q quit", TbGreen, TbDefault)
  discard tbPresent()

proc main() =
  if tbInit() != 0:
    quit("termbox2 initialization failed")
  defer: discard tbShutdown()

  discard tbHideCursor()
  discard tbSetInputMode(TbInputEsc)
  discard tbSetOutputMode(TbOutputNormal)

  var active = actionsPane
  var actionsIndex = 0
  var logOffset = 0
  var event: TbEvent
  draw(actionsIndex, logOffset, active)

  while true:
    if tbPollEvent(event.addr) != 0:
      continue
    if event.eventType == TbEventResize:
      draw(actionsIndex, logOffset, active)
      continue
    if event.eventType != TbEventKey:
      continue

    if event.ch == uint32('q') or event.key == TbKeyEsc or event.key == TbKeyCtrlC:
      break
    case event.key
    of TbKeyTab, TbKeyArrowRight, TbKeyArrowLeft:
      active = if active == actionsPane: logPane else: actionsPane
    of TbKeyArrowUp:
      if active == actionsPane:
        actionsIndex = max(0, actionsIndex - 1)
      else:
        logOffset = max(0, logOffset - 1)
    of TbKeyArrowDown:
      if active == actionsPane:
        actionsIndex = min(Actions.high, actionsIndex + 1)
      else:
        logOffset = min(max(0, Logs.len - 1), logOffset + 1)
    else:
      if event.ch == uint32('k'):
        if active == actionsPane: actionsIndex = max(0, actionsIndex - 1)
        else: logOffset = max(0, logOffset - 1)
      elif event.ch == uint32('j'):
        if active == actionsPane: actionsIndex = min(Actions.high, actionsIndex + 1)
        else: logOffset = min(max(0, Logs.len - 1), logOffset + 1)
      elif event.ch == uint32('h') or event.ch == uint32('l'):
        active = if active == actionsPane: logPane else: actionsPane
    draw(actionsIndex, logOffset, active)

when isMainModule:
  main()
