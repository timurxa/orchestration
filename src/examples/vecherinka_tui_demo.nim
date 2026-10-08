## Small local planning workflow for monitoring in vecherinka-tui.
## One draft feeds two parallel reviews, then a final synthesis.

{.experimental: "callOperator".}

import std/[os, paths]
import ../api/vecherinka

type
  CleanupRequest = object
    goal: string
    constraints: string

  CleanupDraft = object
    schedule: seq[string]
    supplies: seq[string]
    safety_notes: seq[string]

  CleanupReview = object
    schedule: seq[string]
    supplies: seq[string]
    observations: seq[string]

  CleanupPlan = object
    summary: string
    schedule: seq[string]
    supplies: seq[string]
    safety_checklist: seq[string]

const profile = luna.low

vecherinka(solve_tui_demo, default_agent_prompt_templates):
  > draft_plan CleanupRequest ~> CleanupDraft:
    profile[CleanupRequest, CleanupDraft](
      "Draft a practical cleanup plan from the request. Include a short schedule, " &
      "supplies, and safety notes. Respect the stated volunteer count, time, and " &
      "area. Keep the plan concise and do not create files.")

  > review_safety CleanupDraft ~> CleanupReview:
    profile[CleanupDraft, CleanupReview](
      "Review the draft only for safety and volunteer wellbeing. Improve its " &
      "schedule and supplies where safety requires it. Put concrete safety " &
      "observations in observations. Do not create files.")

  > review_logistics CleanupDraft ~> CleanupReview:
    profile[CleanupDraft, CleanupReview](
      "Review the draft only for practical logistics: volunteer roles, coverage " &
      "of the area, timing, and supplies. Improve the schedule and supplies. " &
      "Put concrete logistics observations in observations. Do not create files.")

  > synthesize_plan (CleanupReview, CleanupReview) ~> CleanupPlan:
    profile[(CleanupReview, CleanupReview), CleanupPlan](
      "Combine the safety review and logistics review into one concise final " &
      "cleanup plan. Resolve conflicts, preserve feasible improvements, and " &
      "make the schedule coherent and practical. Include a summary, schedule, " &
      "supplies, and safety checklist. " &
      "Do not create files.")

  > cleanup_entry CleanupRequest ~> CleanupPlan {.entry.}:
    draft_plan >>> fan(review_safety, review_logistics) >>> synthesize_plan

if paramCount() != 1:
  quit("Usage: vecherinka_tui_demo DATABASE_PATH", 2)

let database_path = Path(paramStr(1))
let request = CleanupRequest(
  goal: "Organize a neighborhood litter cleanup across three residential blocks.",
  constraints: "Eight volunteers; two hours total; work in pairs; keep pedestrian " &
    "paths open; do not handle hazardous waste; set aside time for bag pickup.")

echo "SQLite database: ", database_path
let plan = solve_tui_demo(request, 5.0, default_agent_prompt_templates,
  database_path = database_path)
echo "PLAN: ", plan.summary
for item in plan.schedule:
  echo "SCHEDULE: ", item
for item in plan.supplies:
  echo "SUPPLY: ", item
for item in plan.safety_checklist:
  echo "SAFETY: ", item
