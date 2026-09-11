{.experimental: "callOperator".}

import std/macros
import vecherinka

type
  First = object
  Second = object
  Third = object

let cheap = Profile()

vecherinka:
  > first_second First ~> Second:
    cheap[First, Second]("")

  > first_third First ~> Third:
    cheap[First, Third]("")

  > second_third Second ~> Third:
    cheap[Second, Third]("")
  
  > first_third_1 First ~> Third:
    first_second >>> cheap[Second, Third]("")

  > first_third_2 First ~> Third:
    first_second >>> second_third

  > first_second_third_fanout_2 First ~> (Second, Third):
    fan first_second, first_third

  > so_test First ~> Second:
    so(First, Second, input) do:
      let e = fan(first_second, first_third_1)
      echo "hi"
      discard input
      Second()
  
  > lens_identity First ~> First:
    it(First)
