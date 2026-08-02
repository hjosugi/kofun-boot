# Architecture: functional domain modelling

Decided 2026-08-02. The reference implementation this is drawn from is
[`hjosugi/fsharp-lab`](https://github.com/hjosugi/fsharp-lab), which is a
runnable Functional DDD sample built on Scott Wlaschin's *Domain Modeling Made
Functional* and the Functional Core / Imperative Shell decomposition.

kofun-boot's job here is narrow and worth stating up front: **the framework
supplies the shape and the gate, not the domain.** A domain kit that generates
entities is a code generator; what is needed instead is the small set of
vocabulary and constraints that make the core/shell boundary checkable.

## The five roles

fsharp-lab's `docs/03-functional-core-imperative-shell.md` names them, and
they map onto kofun-boot's layers without adjustment:

| role | what it is | where it lives | may hold a capability? |
|---|---|---|---|
| **Entity** | records and closed sums; illegal states unrepresentable | core | no |
| **Invariant** | a pure function deciding one business rule | core | no |
| **Deriver** | a pure function from all the data it needs to a **domain outcome sum** | core | no |
| **Controller** | fetches, calls the deriver, acts on the outcome | shell | yes |
| **Adapter** | the concrete repository, gateway, notifier | shell | yes — it *is* one |

And the composition root, which is the only place a capability record is
built.

The single most useful sentence in the reference material is its decision
rule, and it becomes normative here:

> "Can this be approved under these conditions?" is Core. "Save the approval
> result to the DB" is Shell. "The DB connection failed" is a system failure,
> not a domain outcome.

## Domain outcome ≠ error

This is the rule the framework enforces hardest, because getting it wrong is
what turns a domain model into a pile of exceptions.

A deriver returns a **closed sum whose every constructor carries what was
observed**. In the reference:

```fsharp
type UpgradeDecision =
    | UpgradeAllowed of UpgradeChange
    | AccountOverdrawn of balanceOwing: Money
    | InvalidSubscriptionStatus of current: SubscriptionStatus
    | PlanIsNotHigher of current: PlanLevel * requested: PlanLevel
```

`AccountOverdrawn` carries the balance. `PlanIsNotHigher` carries both plans.
Nothing is a bare `false`, and nothing is an exception — because a customer
being overdrawn is not a malfunction, it is an answer.

That is the identical rule `modules/router/contract/router.kofun` already applies to routing:
`MethodNotAllowed(allowed: List[Method])` carries the methods that would have
worked; `PayloadTooLarge(limit, observed)` carries both numbers. **The
framework's own contract and the applications built on it obey one rule**, and
that consistency is worth more than any individual helper the kit could ship.

`Result` is reserved for what the reference calls system failure: the socket
died, the disk is full, the JSON was not JSON. Those are `Err`. The
distinction is not stylistic — it decides which failures a domain test has to
cover and which belong to an adapter test.

## Constrained types, and what Kofun can check today

The reference makes illegal states unrepresentable with private single-case
unions plus a smart constructor:

```fsharp
type CustomerId = private CustomerId of Guid
module CustomerId =
    let create value = if value = Guid.Empty then Error CustomerIdError.Empty else Ok (CustomerId value)
```

Three properties matter and they should be separated, because Kofun supports
them to different degrees today:

1. **Nominal distinctness** — a `CustomerId` is not an `OrderId` even though
   both wrap a Guid. Kofun has nominal records; this works now.
2. **Construction through one door** — the only way to obtain the type is the
   validating constructor. This needs the visibility rules; Kofun has bounded
   `pub`/`internal`/`private` with a KIF leak-rejection gate, so the mechanism
   exists and the question is how much of it is executable for this shape.
   That is an issue, not an assumption.
3. **A validation failure that says what was wrong** — `CustomerIdError.Empty`
   versus `InvalidFormat of input`. A smart constructor returning `Option` has
   already thrown away the diagnosis, so the kit's constructors return a closed
   error sum.

Where Kofun cannot yet express one of these, the framework's contract declares
it and the gate pins the boundary — the pattern this repository already uses
for `modules/router/contract/router.kofun`.

## The controller is where FCIS becomes visible

fsharp-lab's controller is worth reading as a shape rather than as code: it
fetches, calls the deriver once, matches every outcome, and acts. Every
capability it uses arrives in a `UpgradeDependencies` record, including
`Today: unit -> DateOnly` — **the clock is a field**, which is the same
decision Kofun made at the language level.

In kofun-boot's terms the controller is a `Cmd` interpreter and the deriver is
called from `update`. That is not a different architecture wearing new words;
it is the same split with an explicit data type on the seam:

```
   FDDD          kofun-boot
   ─────────────────────────────────
   Deriver   →   pure fn called by update
   outcome   →   a Msg, or a Cmd
   Controller →  the Cmd interpreter
   Ports     →   the capability record
   Adapters  →   the shell's implementations
   Composition Root → where the record is built
```

The payoff the reference names explicitly should be inherited too: **test the
deriver's rules in domain tests, and test only which effects each outcome
triggers in controller tests.** Re-testing business rules through the
controller is the duplication that makes FCIS codebases slow to change.

## What the kit actually ships

Deliberately small. Vocabulary, constraints, and gates — not generated code.

| item | what |
|---|---|
| the vocabulary | Entity / Invariant / Deriver / Controller / Adapter, as documented module roles the scaffold emits |
| the layout | `core/` and `shell/` split by **bounded context**, with the dependency rule inside each — never a shared global `Customer`, because Billing's and Support's customers are different types |
| the FCIS gate | core modules, comments stripped, greped for capability names — the technique `tests/boot/check.sh` already applies to the seed |
| the outcome lint | a deriver whose sum has a constructor carrying nothing, where the rejection had an observable cause, is flagged |
| the fake kit | the same capability records with scripted fields; fake clock, scripted network, injected bytes |
| `boot new` output | a project whose first compile already has the split, so the boundary is never retrofitted |

## Transaction and credential boundaries

Two production concerns the reference raises that a framework must not leave
to each application:

**Distributed effects are not atomic.** Payment plus database write cannot be
made atomic by a database transaction. The reference lists the real options —
charge first and compensate, write first and drive payment from an outbox, or
model progress as a saga — and is explicit that its own sample takes the small
option and that production needs outbox, idempotency keys, retries and
compensation. kofun-boot should ship the *outbox* shape as a first-class
`Cmd` pattern with a replay gate, because an outbox whose delivery is not
replayable is a source of duplicate charges.

**Credentials must not reach a log or an outcome.** The reference redacts a
card token even in its console adapter. In kofun-boot this becomes a type
property: a secret-carrying type has no display projection, so it cannot be
formatted into a log line, an error message, or a metric label — the failure
is at compile time rather than in a log review.

## Open questions, filed rather than assumed

- How much of the smart-constructor pattern is executable under the current
  visibility slice, and what is the honest boundary statement for the rest?
- Does the outcome sum belong to the domain module or to the contract? The
  reference has both `UpgradeDecision` (domain) and `UpgradeOutcome`
  (application) and the duplication is deliberate — the framework should say
  whether it agrees before the scaffold hard-codes an answer.
- Event sourcing: TEA's `Msg` stream and an event log are suspiciously similar
  shapes. Whether that is a real unification or a coincidence needs a design
  pass, not an assumption.
