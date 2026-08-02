# 5. A trace is the fold the core already performs

Date: 2026-08-02 · Status: accepted

## Context

The replay lane needs a trace format. The usual approach is to design one:
choose a schema, write a recorder that instruments the runtime, write a player
that drives it back. That is a lot of machinery, and every piece of it can
disagree with the system it claims to describe.

## Decision

There is no format to design, because the core already produces it.

`apply : Store -> Operation -> StoreStep` returns the resource *and* what
happened, so a session is a fold and a trace is exactly the list of steps in
it. Recording costs nothing — every number in a step is a value the core
already returned. Replaying is running the fold again.

The format is eight integers per line: step, operation, its two arguments, the
outcome, its payload, and the two numbers that describe the resource
afterwards. A reader can diff it by eye; a script can compare it by line.

The header pins what the trace is *of*: the format version, the seed it
started from, the language revision that produced it, and a digest of the step
lines. A trace replayed against a different seed or a hand-edited file is not
a replay, and the digest makes that a clear refusal rather than a confusing
diff twenty steps in.

Replay runs under `env -i`. A trace recorded in one environment and replayed
in another must not be able to differ for that reason; if it ever does, the
divergence is real and the gate should see it.

## Consequences

The trace is as trustworthy as the core is pure, and no more — which is the
right coupling, because purity is what the boundary gate already enforces.
There is no separate recorder to drift from the system.

A divergence names the step and prints both rows:

```
trace: FAIL: the session diverged at step 5
  columns:  step op arg_id arg_value outcome payload live next_id
  recorded: 5 5 2 0 5 2 2 4
  replayed: 5 5 2 0 5 2 2 2
```

That example is not hypothetical: it is what making `delete` rewind the id
counter produces — the json-server behaviour [ADR 3](0003-mutations-return-a-new-state.md)
exists to avoid, caught by replay at the step where it happened rather than as
a mysterious id collision later.

The cost is that a trace describes one session. Recording a different session
means writing a different shell, because the shell is the only layer allowed
to decide what happens. That is the boundary doing its job, and it is why
traces are cheap enough to keep several of.
