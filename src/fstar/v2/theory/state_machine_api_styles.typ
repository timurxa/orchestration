// Reusable, dependency-free components for the state-machine design note.
// Import with: #import "state_machine_api_styles.typ": *

#let status-panel(kind, body, title: none, number: none) = {
  let accent = if kind == "Decided" { rgb("28634A") }
    else if kind == "Proposed" { rgb("315D83") }
    else if kind == "Open" { rgb("765B20") }
    else if kind == "Derived" { rgb("66538A") }
    else { panic("status-panel kind must be Decided, Proposed, Open, or Derived") }
  let wash = if kind == "Decided" { rgb("F1F7F3") }
    else if kind == "Proposed" { rgb("F1F5F9") }
    else if kind == "Open" { rgb("FAF7EE") }
    else { rgb("F5F2F9") }
  rect(
    width: 100%,
    fill: wash,
    stroke: (left: 2pt + accent, rest: 0.5pt + rgb("D7DCE0")),
    inset: 9pt,
    radius: 3pt,
  )[
    #text(size: 8pt, weight: "bold", fill: accent)[#kind]
    #if number != none [
      #h(0.4em)
      #text(size: 8pt, weight: "bold", fill: accent)[#number]
    ]
    #if title != none [
      #h(0.5em)
      #text(weight: "semibold")[#title]
    ]
    #v(3pt)
    #body
  ]
}

#let definition-card(title, body, label: "Definition") = rect(
  width: 100%,
  fill: rgb("FFFFFF"),
  stroke: 0.6pt + rgb("AEB8C2"),
  inset: 9pt,
  radius: 3pt,
)[
  #text(size: 8pt, weight: "bold", fill: rgb("455766"))[#label]
  #h(0.5em)
  #text(weight: "semibold")[#title]
  #v(3pt)
  #body
]

#let theorem-card(title, body, label: "Theorem") = rect(
  width: 100%,
  fill: rgb("F4F7FA"),
  stroke: 0.8pt + rgb("607D96"),
  inset: 9pt,
  radius: 3pt,
)[
  #text(size: 8pt, weight: "bold", fill: rgb("315D83"))[#label]
  #h(0.5em)
  #text(weight: "semibold")[#title]
  #v(3pt)
  #body
]

#let observable-behavior(body, title: "Observable behavior") = rect(
  width: 100%,
  fill: rgb("F7F7F6"),
  stroke: (left: 2pt + rgb("626C73"), rest: 0.5pt + rgb("D7DCE0")),
  inset: 9pt,
  radius: 3pt,
)[
  #text(weight: "semibold", fill: rgb("38434A"))[#title]
  #v(3pt)
  #body
]

// Render each directed dependency as a compact, readable row:
// (("history", "determines", "represented state"), ...)
#let dependency-diagram(edges, caption: none) = block(
  width: 100%,
  breakable: false,
  fill: rgb("FAFBFC"),
  stroke: 0.5pt + rgb("D7DCE0"),
  inset: 7pt,
)[
  #if caption != none [
    #text(size: 8pt, weight: "bold", fill: rgb("455766"))[#caption]
    #v(4pt)
  ]
  #for edge in edges [
    #grid(
      columns: (1fr, auto, 1fr),
      column-gutter: 6pt,
      align: (right, center, left),
      text(size: 8.5pt)[#edge.at(0)],
      text(size: 8pt, fill: rgb("596873"))[#edge.at(1)],
      text(size: 8.5pt, weight: "medium")[#edge.at(2)],
    )
  ]
]
