# 1. Record architecture decisions

Date: 2026-08-02 · Status: accepted

## Context

`docs/DESIGN.md` holds the architecture, but a single document answers "what
is the design" and not "why is it this rather than that, and what did we give
up". Six months on, the second question is the one that matters, and its
answer is usually lost.

`kgrzybek/modular-monolith-with-ddd` keeps a numbered decision log — seventeen
entries covering module count, CQRS, rich domain models, event-driven module
communication, and architecture tests. Reading them is how a newcomer learns
that repository faster than reading its code.

## Decision

Every load-bearing decision gets a numbered file here: context, the decision,
and its consequences including what it costs. `docs/DESIGN.md` stays the map;
these are the reasons.

A decision that cannot name what it gave up has not been made yet — it has
been assumed.

## Consequences

Design review happens on a file with a number, so it can be cited and
superseded rather than silently reversed. The cost is that a genuine decision
now needs a file before it needs code.
