# Backlog structure

[`docs/ROADMAP.md`](ROADMAP.md) says the tracker is expected to pass four
digits of issues. That is a statement about *granularity*, not ambition: at one
reviewable change per issue with one gate each, a production application
framework is a four-digit amount of work, and the only way that stays
navigable is if the decomposition is written down before the issues are.

This document is that decomposition, and it is also the contract for how
issues are written here.

## The unit of work

One issue = **one reviewable change, one gate, one honest boundary
statement.** An issue that cannot state what will be false after it lands is
not ready; an issue whose change cannot be reviewed in one sitting needs a
split, and producing that split is itself the refinement work.

This is the discipline the language repository documents in
[`docs/ISSUE_READINESS.md`](https://github.com/hjosugi/kofun/blob/main/docs/ISSUE_READINESS.md),
and kofun-boot adopts it wholesale rather than inventing a second one.

## Issue shape

Every issue carries these sections. The gate on them is human until the
tracker is large enough to justify automating it, at which point the
language repository's `task backlog` pattern is the model.

```markdown
## Goal
One deliverable, stated as the artifact that exists afterwards.

## Scope
What is deliberately *out*. An issue whose scope is only stated positively
grows during implementation, because nothing says where to stop.

## Current behavior and evidence
The command, its result, and the commit it was measured on. An unstamped
claim is true the day it is written and silently false afterwards.

## Design direction
The decision and the reason, with links to the dossier that produced it.

## Acceptance criteria
A checkbox list. Each line is decidable by running something or reading a
named file.

## Validation
A table of check / command / expected result, naming the gate that holds
the work afterwards.

## Dependencies
Blockers by number, including language-repository issues. "Blocked by:
none" is written explicitly when true, because its absence is ambiguous.

## Metadata
State, lane, epic, size.
```

## Lanes → epics

The lanes are `docs/ROADMAP.md`'s. This is the epic layer beneath them, with
an order-of-magnitude estimate of the bounded children each epic decomposes
into. The estimates are for planning the *shape* of the tracker; they are not
commitments and no issue exists because an estimate wanted one.

| lane | epics | ~children |
|---|---|---|
| **L0** governance & evidence | issue discipline; claims manifest; evidence pack; benchmark provenance; release process | 20–30 |
| **L1** contract | endpoint-as-value ADT; validation sums; compiled dispatch; OpenAPI projection; typed client projection; four-way drift gates; content negotiation; versioning | 80–120 |
| **L2** serve | dispatch → `framework/http` registry; config as one printed record; TLS as a capability; drain semantics; streaming bodies; multipart; compression; error surface | 60–100 |
| **L3** capabilities | the record shapes; scoped capabilities; printed effective manifest; FCIS gate; the fake kit; capability auditing | 40–70 |
| **L4** replay | trace format v1; record mode; replay mode; hostile-environment gate; trace diffing; fixture management | 30–50 |
| **L5** speed | benchmark harness; recorded baselines; regression gate; allocation accounting; published same-box comparisons | 30–50 |
| **L6** concurrency | scoped spawn/join; cancellation as a typed result; deterministic schedule replay; timers; backpressure | 40–60 |
| **L7** data | schema-as-contract; typed queries; migrations as replayable traces; connection capability; outbox; interop | 80–130 |
| **L8** cli & dx | `new` / `dev` / `test` / `bench` / `openapi` / `gen`; scaffolds; watch-reload; diagnostics quality | 50–80 |
| **L9** desktop | webview backend; the render-tree ADT; diff and patch stream; native backend rungs 1–6; IME; accessibility; platform integration; packaging and signing | 120–200 |
| **L10** site & docs | tutorial where every snippet is a gated fixture; comparison pages that show their measurement; API reference as a projection | 40–70 |
| **L11** effects & TEA | `Cmd`/`Sub` contract; the interpreter surface; `Result` and railway combinators; the TEA runtime; shell parity gate; effect-row migration | 70–110 |
| **L12** domain kit | constrained types; deriver and outcome discipline; the outcome lint; bounded-context layout; outbox pattern; secret types | 50–80 |

Sum of midpoints: roughly 900–1,100 bounded children. That is where the
four-digit expectation comes from, and it is arithmetic rather than optimism.

L11 and L12 are new in this document; they are the lanes the research
dossiers produced, and `docs/ROADMAP.md` carries them in its lane table.

### The R-series is orthogonal

[R0 #15](https://github.com/hjosugi/kofun-boot/issues/15) and its children
R1–R10 are a **research programme**, not a lane. Each R issue produces a
decision that lands in one or more lanes, and the lane's epics carry the
implementation. An R issue closes when its decision is recorded and its
minimal artifact is reproducible under a gate — not when the reading is done.

The two structures meet in one place: a lane epic that implements an R
decision links it, and an R decision that no lane has picked up is a gap in
this table rather than a finished piece of research.

## How the tracker grows

Not by filing a thousand issues. By filing, for each epic, **one epic issue
that names its children and the order they unblock in**, and then filing
children only when the epic is next. An issue filed a year before anyone can
start it is a stamp that will be stale on the day it is read, and this
repository's whole evidence discipline exists to stop exactly that.

The rule:

1. An **epic** may exist as soon as its lane is named. It states the outcome,
   the research that justifies it, and its child list as prose.
2. A **child** is filed when its epic is the current or next epic in its lane,
   and it is filed with a measured, stamped evidence section.
3. A child whose evidence is older than the change it describes is re-measured
   before anyone starts, never on faith.

## Labels

| label | meaning |
|---|---|
| `lane:L0`…`lane:L12` | the lane |
| `epic` | an outcome with children, not a reviewable change |
| `research` | the deliverable is a dossier or a measurement, not code |
| `ready` | Definition of Ready satisfied — startable by someone who has not seen the discussion |
| `needs-detail` | outcome known, scope or validation needs refinement |
| `needs-decision` | blocked on an explicit design or product decision, with a named owner |
| `blocked` | blocked on something open, named by number in `## Dependencies` |
| `blocked:language` | blocked on a `hjosugi/kofun` capability, tracked by that issue number |
| `size:S` / `size:M` / `size:L` | one sitting / one day / needs a split unless genuinely one change |
