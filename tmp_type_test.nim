type
  Error = object
    msg: string
  Outcome[T] = object
    value: T
  Consumer[T] = proc (x: Outcome[T]) {.closure.}
  Request[A, B] = object
    data: A
  SubmitProc = proc [A, B](request: Request[A, B]; consumer: Consumer[B])
  Context = object
    submit: SubmitProc

proc submitImpl[A, B](request: Request[A, B]; consumer: Consumer[B]) =
  consumer(Outcome[B]())

let ctx = Context(submit: submitImpl)
ctx.submit(Request[int, string](data: 1), proc(x: Outcome[string]) = discard)
