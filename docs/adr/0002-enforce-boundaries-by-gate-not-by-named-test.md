# 2. Enforce boundaries by one gate that names the violation

Date: 2026-08-02 · Status: accepted

## Context

kofun-boot's core/shell boundary needs enforcement, not description. The
obvious model is architecture tests: `kgrzybek/modular-monolith-with-ddd` uses
NetArchTest with one test method per rule —
`DomainLayer_DoesNotHaveDependency_ToApplicationLayer`,
`ApplicationLayer_DoesNotHaveDependency_ToInfrastructureLayer`, and so on.

That model has a failure mode, and the reference implementation demonstrates
it. In `src/Modules/Meetings/Tests/ArchTests/Module/LayersTests.cs`:

```csharp
[Test]
public void DomainLayer_DoesNotHaveDependency_ToInfrastructureLayer()
{
    var result = Types.InAssembly(DomainAssembly)
        .Should()
        .NotHaveDependencyOn(ApplicationAssembly.GetName().Name)   // Application
        .GetResult();
```

The test named *Infrastructure* asserts against *Application* — a copy of the
method above it. Domain → Infrastructure is never checked, in a repository
with thirteen thousand stars whose ADR 0017 is titled "implement architecture
tests". Nothing failed, because a test that checks the wrong thing passes.

The lesson is not that they were careless. It is that when a rule's name and
its assertion are two separate pieces of text, they drift, and nothing
notices — the same shape as a comment describing what code does.

## Decision

One gate, reading the code, printing the violation it found.

`tests/boot/check.sh` reads the core with comments stripped and fails with the
offending line and its number:

```
boot: FAIL: the functional core constructs a capability instead of receiving one:
241:    let smuggled: Capabilities = Capabilities(now_seconds: 0)
```

The rule is not restated in a test name; the failure quotes the source. There
is no second text to drift from the first.

Comments are stripped before the grep because both layers spend paragraphs
explaining what the core refuses to reach, and a search over the whole text
cannot tell an explanation from a violation. That is not hypothetical: the
first version of the tzdb gate in the language repository failed on its own
comment.

## Consequences

Boundary rules are cheap to add and self-describing when they fire, and a rule
cannot silently check the wrong layer. The cost is that the rules are
textual — they see names, not resolved references — so a violation spelled
differently could slip through. Every rule added here must therefore be
verified in both directions: green as it stands, and failing on a deliberate
violation. Both directions are demonstrated in the commit that adds the rule.
