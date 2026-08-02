# 6. A module owns its whole vertical

Date: 2026-08-02 · Status: accepted

## Context

The first executable seed grew into a router and a replayable mock resource.
Keeping both under a global `seed/`, with contracts somewhere else, made the
repository's horizontal layers more visible than its bounded contexts. A
third feature would have had to guess which directory owned its public
surface, its pure rules, its adapters, and its tests.

The pinned `modular-monolith-with-ddd` study found the useful part of its .NET
assembly layout: a bounded context owns its entire vertical, and other modules
can depend on a declared integration contract but cannot reach into its
implementation. We do not copy its container, mutable aggregates, or one-test
method-per-architecture-rule approach.

## Decision

Every application module lives at `modules/<name>/` and owns four directories:

```text
contract/   public command, query, and integration-event values
core/       pure domain state and transitions
shell/      capability interpreters, adapters, and composition entry point
tests/      the module's suites and recorded evidence
```

Another module may name only `modules/<name>/contract` (or the equivalent
dotted/relative import). It may not name another module's core, shell, or
tests. Global integration gates aggregate evidence; they do not take ownership
of module-specific tests.

Domain refusal is a closed sum in the public contract, not an exception. The
mock module is the executable example: its canonical `MockOutcome` and Stage 2
seed have the same seven constructors, and every constructor carries what was
observed.

One data-driven architecture gate discovers module directories and checks the
rule. Its own test adds an `orders` module without changing the router or mock,
then injects a relative reference to `router/core` and requires a diagnostic
containing the source path, line, and allowed contract target.

## Consequences

`router` and `mock` now move as coherent bounded contexts. Adding a module
does not add a name to the gate or to the test runner; filesystem discovery is
the registry.

The executable Kofun slice does not yet import modules. Build and test adapters
therefore assemble core plus shell, or core plus module-owned tests, into a
temporary unit in a deterministic order. Those adapters are compatibility
seams, not a second ownership model, and generated units never enter the
worktree.

The gate recognizes canonical, dotted, and layer-relative contract paths so a
future import spelling cannot silently weaken today's dependency rule. Once
the language exposes one import grammar, the compatibility spellings can be
removed and the same break test retained.

The previous all-in-one `seed/router/router.kofun` duplicated the split core
and shell and had no caller. It is removed; Git history remains the recovery
path.
