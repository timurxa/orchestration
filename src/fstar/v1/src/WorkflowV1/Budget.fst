module WorkflowV1.Budget
open FStar.List.Tot
open WorkflowV1.Base
open WorkflowV1.JournalTypes
open WorkflowV1.OperationFacts
open WorkflowV1.JournalFacts

let ledger_after_reservation (b:budget) (maximum:nat) : budget =
  { b with budget_reserved=b.budget_reserved + maximum }

let ledger_after_settlement (b:budget) (maximum amount:nat)
    : option budget =
  if b.budget_reserved < maximum then None else
  let reserved_after = b.budget_reserved - maximum in
  if amount <= maximum then
    Some { b with budget_spent=b.budget_spent + amount;
                  budget_reserved=reserved_after }
  else
    Some { b with budget_spent=b.budget_spent + amount;
                  budget_reserved=reserved_after;
                  budget_overage=b.budget_overage +
                    (if amount >= maximum then amount - maximum else 0);
                  budget_quarantined=true }

let budget_eq (left right:budget) : bool =
  left.budget_limit = right.budget_limit &&
  left.budget_spent = right.budget_spent &&
  left.budget_reserved = right.budget_reserved &&
  left.budget_overage = right.budget_overage &&
  left.budget_quarantined = right.budget_quarantined

let initial_budget (header:run_header) : budget = {
  budget_limit=header.header_budget_limit;
  budget_spent=0;
  budget_reserved=0;
  budget_overage=0;
  budget_quarantined=false
}

let rec budget_project_from (header:run_header) (current:budget)
    (prefix rest:list event) : Tot (option budget) (decreases rest) =
  match rest with
  | [] -> Some current
  | event::tail ->
      let next = match event.body with
        | CallReserved call maximum ->
            if call_reserved call prefix || current.budget_quarantined ||
               current.budget_spent + current.budget_reserved + maximum >
                 current.budget_limit
            then None
            else Some (ledger_after_reservation current maximum)
        | CallSettled call amount _ ->
            if call_settled call prefix then None else
            (match reservation_maximum call prefix with
             | None -> None
             | Some maximum ->
                 ledger_after_settlement current maximum amount)
        | _ -> Some current in
      (match next with
       | None -> None
       | Some updated ->
           if budget_valid updated then
             budget_project_from header updated (prefix @ [event]) tail
           else None)

let budget_project (header:run_header) (events:list event)
    : option budget =
  budget_project_from header (initial_budget header) [] events

let ledger_matches_history (header:run_header) (events:list event)
    (ledger:budget) : bool =
  match budget_project header events with
  | None -> false
  | Some projected -> budget_eq projected ledger
