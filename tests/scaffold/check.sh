#!/bin/sh
set -eu

# The scaffold is a tested fixture, not a template.
#
# `boot new` emits a project; this generates one into a temporary directory,
# runs *its* gate, and then checks the two properties the scaffold exists to
# guarantee. A scaffold verified only by having been written once rots the
# first time the language moves, and rots in someone else's afternoon rather
# than in this build.

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)

WORK=$(mktemp -d "${TMPDIR:-/tmp}/kofun-boot-scaffold.XXXXXX")
trap 'rm -rf "$WORK"' 0 1 2 15

fail() {
    printf 'scaffold: FAIL: %s\n' "$*" >&2
    exit 1
}

project="$WORK/acme"
sh "$ROOT/scripts/new.sh" "$project" --name acme >"$WORK/new.log" 2>&1 ||
    fail "boot new failed:
$(sed 's/^/    /' "$WORK/new.log")"

for expected in core/core.kofun core/core_test.kofun shell/shell.kofun \
    tests/check.sh build.sh README.md
do
    test -f "$project/$expected" || fail "boot new did not emit $expected"
done

# The generated project's own gate: its boundary, its unit suite, its recorded
# output, and its determinism under an empty environment.
(cd "$project" && sh tests/check.sh) >"$WORK/gate.log" 2>&1 ||
    fail "the generated project did not pass its own gate:
$(sed 's/^/    /' "$WORK/gate.log")"
grep -q 'PASS' "$WORK/gate.log" ||
    fail "the generated project's gate produced no PASS line:
$(sed 's/^/    /' "$WORK/gate.log")"

suites=$(sed -n 's/.*Tests  \([0-9][0-9]*\) passed.*/\1/p' "$WORK/gate.log" | head -1)
test -n "$suites" && test "$suites" -ge 6 ||
    fail "the scaffold's suite shrank: expected at least 6 tests, saw '${suites:-none}'"

# The scaffold's reason to exist: a new project starts on the right side of the
# boundary. Prove the generated gate actually enforces it rather than only
# printing about it — break the generated core and require its own gate to
# refuse.
cp "$project/core/core.kofun" "$WORK/core.bak"
printf '\nfn smuggle() -> Int {\n    let c: Capabilities = Capabilities(now_seconds: 0)\n    return c.now_seconds\n}\n' \
    >>"$project/core/core.kofun"
if (cd "$project" && sh tests/check.sh) >"$WORK/broken.log" 2>&1; then
    fail 'the generated gate accepted a core that constructs a capability'
fi
grep -q 'constructs a capability' "$WORK/broken.log" ||
    fail "the generated gate refused for the wrong reason:
$(sed 's/^/    /' "$WORK/broken.log")"
cp "$WORK/core.bak" "$project/core/core.kofun"

printf 'scaffold: boot new emits a project that passes its own gate: PASS\n'
printf 'scaffold: and that gate refuses a core which reaches for a capability: PASS\n'
