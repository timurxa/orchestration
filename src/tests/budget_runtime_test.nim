import std/unittest
import ../api/vecherinka

suite "budget runtime":
  test "profile cost is fixed by model and effort":
    check profile_cost(luna, none(luna).effort) == 0.41
    check profile_cost(astra, max(astra).effort) == 54.87
    expect ValueError:
      discard profile_cost(astra, none(astra).effort)

  test "pool capacities and signed local remainder":
    let ledger = new_budget_ledger(100.0, @[
      (name: "default", weight: 3.0),
      (name: "implementation", weight: 1.0)])
    check ledger.budget_context(0).pool_capacity == 75.0
    check ledger.budget_context(1).pool_capacity == 25.0
    ledger.admit_model(1, 30.0, "test")
    check ledger.global_remaining == 70.0
    check ledger.budget_context(0).pool_capacity == 71.25
    check ledger.budget_context(1).pool_capacity == 23.75
    check ledger.budget_context(1).pool_remaining == -6.25
    check ledger.budget_context(1).global_remaining == 70.0

  test "global admission is hard and atomic":
    let ledger = new_budget_ledger(2.0, @[(name: "default", weight: 1.0)])
    ledger.admit_model(0, 2.0, "first")
    expect ValueError:
      ledger.admit_model(0, 0.1, "second")
    check ledger.global_remaining == 0.0
    check ledger.budget_context(0).pool_spent == 2.0

  test "invalid weights and budgets are rejected":
    expect ValueError:
      discard new_budget_ledger(-1.0, @[(name: "default", weight: 1.0)])
    expect ValueError:
      discard new_budget_ledger(1.0, @[(name: "default", weight: 0.0)])
    expect ValueError:
      discard new_budget_ledger(1.0, @[
        (name: "default", weight: 1.0),
        (name: "DEFAULT", weight: 1.0)])
    expect ValueError:
      discard new_budget_ledger(1.0, @[
        (name: "default", weight: 1.0),
        (name: "proc", weight: 1.0)])
    expect ValueError:
      discard new_budget_ledger(high(float64), @[
        (name: "default", weight: 1e-300),
        (name: "large", weight: 1e-300)])
