# Subscriptions

A SapoHub util module for tracking recurring subscriptions billed every X
months or every X years. Groups subscriptions by billing cadence, showing
each one's cost and cost-per-month plus a per-group subtotal, and rolls up
a grand total monthly cost across everything.

Implements the `SapoKit.Module` contract in `lib/subscriptions/module.ex` —
see `modules/recipes` for a similarly-shaped real module and
`docs/module-authoring.md` for the contract reference.

Money is stored as `cost_cents` (integer); the API/CLI accept a dollar
string (e.g. `"9.99"`) for cost, parsed to cents in the changeset.
