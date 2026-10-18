module WorkflowV1.Recovery
open FStar.List.Tot
open WorkflowV1.JournalTypes
open WorkflowV1.Contracts
open WorkflowV1.Reducer

type load_result =
  | Loaded : list event -> load_result
  | StorageUnavailable
  | StorageCorrupt

type restore_result =
  | Restored : journal_state -> restore_result
  | RestoreUnavailable
  | RestoreCorrupt

let restore_from_events (initial:journal_state) (rules:admission_contract)
    (loaded:load_result) : restore_result =
  match loaded with
  | Loaded events ->
      (match replay_events initial rules events with
       | Some state -> Restored state
       | None -> RestoreCorrupt)
  | StorageUnavailable -> RestoreUnavailable
  | StorageCorrupt -> RestoreCorrupt
