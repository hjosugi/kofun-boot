# 3. A mutation returns the new state, never edits in place

Date: 2026-08-02 · Status: accepted

## Context

`typicode/json-server` gives a developer a full REST API from a JSON file in
seconds, which is why it is reached for so often. It writes that file in
place. A run therefore depends on every run before it: the same requests
against the same "seed" give different answers on the second afternoon, and
"it worked yesterday" is not a reproducible claim.

kofun-boot needs the same convenience — `boot mock` — without inheriting that.

## Decision

An operation is

```
apply : Store -> Operation -> StoreStep
```

where `StoreStep` carries both the resource after and what happened. There is
no other way to obtain the next store, so a caller cannot advance the resource
and drop the result. A session is a fold over the operations.

Identity allocation lives in the value: `Store.next_id` is carried, so `POST`
allocates deterministically with no clock and no entropy source. A deleted id
is spent and never reissued — two resources sharing an id would be
indistinguishable in a replay.

## Consequences

Three properties follow, and none of them were available before:

- a request sequence replays byte-identically from the same seed;
- a test can assert the resource *between* any two requests, which a
  file-mutating mock cannot be asked;
- the mock and the replay lane are the same mechanism, so `boot mock` and
  `boot test --replay` do not need separate stories.

The cost is that a session is a chain of bindings rather than a mutated
variable. In the current executable slice record bindings are immutable
anyway, so the language charged this cost already and the design is spending
it deliberately.
