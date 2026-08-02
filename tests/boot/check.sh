#!/bin/sh
set -eu

# The kofun-boot gate.
#
# Three things are checked, in this order:
#
#   1. the canonical surface in contracts/ still declares the framework
#      contract, and still stops at the documented compiler boundary rather
#      than pretending to be executable;
#   2. the executable seed runs identically on the reference interpreter and
#      the C11 backend, and specific dispatch decisions are read from its
#      output rather than accepted wholesale from a golden file;
#   3. nothing in the seed reaches ambient state — asserted against the code
#      with comments stripped, and demonstrated by re-running under a hostile
#      environment and comparing bytes.

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
KOFUN="$ROOT/vendor/kofun/bin/kofun"

WORK=$(mktemp -d "${TMPDIR:-/tmp}/kofun-boot.XXXXXX")
trap 'rm -rf "$WORK"' 0 1 2 15

fail() {
    printf 'boot: FAIL: %s\n' "$*" >&2
    exit 1
}

require_line() {
    label=$1
    needle=$2
    file=$3
    grep -Fq -- "$needle" "$file" ||
        fail "$label: no line matching: $needle"
}

test -x "$KOFUN" || test -f "$KOFUN" ||
    fail 'vendor/kofun is missing; run: git submodule update --init vendor/kofun'

# ---------------------------------------------------- canonical surface

canonical="$ROOT/contracts/boot.kofun"
test -f "$canonical" || fail 'canonical surface is missing'

for declaration in \
    'type Method =' \
    'type Path = {' \
    'type Route = {' \
    'type RouteTable = {' \
    'type Request = {' \
    'type RouteResult =' \
    'type Capabilities = {' \
    'type Response = {' \
    'fn boot_compile(' \
    'fn boot_dispatch(' \
    'fn boot_handle(' \
    'fn boot_openapi(' \
    'fn boot_client('
do
    require_line 'canonical surface lost a declaration' \
        "$declaration" "$canonical"
done

# The contract's spine: failures carry what was observed, and the capability
# record is the only door to the outside.
require_line 'canonical MethodNotAllowed no longer carries the Allow set' \
    '| MethodNotAllowed(allowed: List[Method])' "$canonical"
require_line 'canonical PayloadTooLarge no longer carries the limit' \
    '| PayloadTooLarge(limit: Int, observed: Int)' "$canonical"
require_line 'canonical Capabilities lost the injected clock' \
    '    clock: MonotonicClock,' "$canonical"

# Still ahead of the compiler, on purpose. The executable evidence is the
# seed, not this file.
if "$KOFUN" check "$canonical" \
    >"$WORK/canonical.stdout" 2>"$WORK/canonical.stderr"
then
    fail 'canonical surface unexpectedly claimed executable codegen'
fi
require_line 'canonical surface did not stop at the documented boundary' \
    'error[E2S02]: expected top-level `fn` or `type`' "$WORK/canonical.stderr"

# ------------------------------------------------------------------ seed

core="$ROOT/seed/router/core.kofun"
shell="$ROOT/seed/router/shell.kofun"
expected="$ROOT/seed/router/router.stdout"
test -f "$core" || fail 'core source is missing'
test -f "$shell" || fail 'shell source is missing'
test -f "$expected" || fail 'seed golden is missing'

# The core/shell boundary, enforced rather than described.
#
# Read with comments stripped: both files spend paragraphs explaining what the
# core refuses to reach, and a grep over the whole text cannot tell that
# explanation from a violation. The core may *name* the Capabilities type in a
# signature — receiving a capability is the whole point — but it may not
# construct one, because constructing is how a pure function would smuggle in
# an authority nobody handed it.
sed 's/[[:space:]]*#.*$//' "$core" >"$WORK/core.code"
if grep -qE 'Capabilities\(' "$WORK/core.code"; then
    printf '%s\n' \
        'boot: FAIL: the functional core constructs a capability instead of receiving one:' >&2
    grep -nE 'Capabilities\(' "$WORK/core.code" >&2
    exit 1
fi
if grep -qE '^fn main' "$WORK/core.code"; then
    fail 'the functional core owns an entry point; emission belongs to the shell'
fi
if ! grep -qE 'Capabilities\(' "$(sed 's/[[:space:]]*#.*$//' "$shell" >"$WORK/shell.code"; echo "$WORK/shell.code")"; then
    fail 'the shell no longer builds the capability record; the boundary has moved without being moved'
fi

# The seed the rest of this gate exercises is the two layers concatenated, the
# way scripts/build-seed.sh assembles them for a developer.
seed="$WORK/router.unit.kofun"
cat "$core" >"$seed"
printf '\n' >>"$seed"
cat "$shell" >>"$seed"

# Nothing ambient, asserted against code rather than prose: both files spend
# comments explaining what they refuse to reach, and a grep over the whole
# text cannot tell that explanation from a violation.
sed 's/[[:space:]]*#.*$//' "$seed" >"$WORK/seed.code"
if grep -qE 'clock_gettime|gettimeofday|getenv|fopen|socket\(|__linux_syscall|import ' \
    "$WORK/seed.code"
then
    fail 'the seed names ambient state'
fi

"$KOFUN" check "$seed" >"$WORK/check.stdout" 2>"$WORK/check.stderr" ||
    fail "seed did not check: $(cat "$WORK/check.stderr")"

"$KOFUN" build "$seed" -o "$WORK/router" --emit-c "$WORK/router.c" \
    >"$WORK/build.stdout" 2>"$WORK/build.stderr" ||
    fail "seed did not build: $(cat "$WORK/build.stderr")"

"$WORK/router" >"$WORK/backend.stdout"
cmp "$expected" "$WORK/backend.stdout" ||
    fail 'C11 backend output differs from the recorded dispatch decisions'

"$KOFUN" run "$seed" >"$WORK/reference.stdout" 2>"$WORK/run.stderr" ||
    fail "seed did not run on the reference executor: $(cat "$WORK/run.stderr")"
cmp "$expected" "$WORK/reference.stdout" ||
    fail 'reference executor and C11 backend disagree'

"$WORK/router" >"$WORK/backend.second"
cmp "$WORK/backend.stdout" "$WORK/backend.second" ||
    fail 'two executions of the same router binary differ'

# Replayable means replayable: hostile time zone, hostile locale, and an
# empty environment must not move one byte.
TZ=Pacific/Kiritimati LC_ALL=C LANG=C "$WORK/router" >"$WORK/hostile.stdout"
cmp "$WORK/backend.stdout" "$WORK/hostile.stdout" ||
    fail 'output changed under TZ=Pacific/Kiritimati'
env -i "$WORK/router" >"$WORK/bare.stdout"
cmp "$WORK/backend.stdout" "$WORK/bare.stdout" ||
    fail 'output changed with an empty environment'

# The emitted C reaches nothing the source did not name.
if grep -qE 'time\.h|clock_gettime|gettimeofday|localtime|getenv|fopen|socket' \
    "$WORK/router.c"
then
    fail 'the emitted C reaches for ambient state'
fi

# ------------------------------------------- recorded dispatch decisions
#
# Twelve table lines, then four lines per dispatch (method, path, kind,
# payload), then five handler lines. Kind 1 Matched, 2 NotFound,
# 3 MethodNotAllowed, 4 PayloadTooLarge. Each assertion names the rule it
# reads, so a failure says which decision moved.

field() {
    sed -n "$1,$2p" "$expected" | tr '\n' ' '
}

assert_field() {
    label=$1
    from=$2
    to=$3
    want=$4
    got=$(field "$from" "$to")
    test "$got" = "$want" ||
        fail "$label: expected '$want', got '$got'"
}

assert_field 'the compiled table is the four declared routes' \
    1 12 '1 101 1 2 102 2 1 103 3 2 103 4 '
assert_field 'a matched route names its handler' \
    13 16 '1 101 1 1 '
assert_field 'a second route matches independently' \
    17 20 '2 102 1 2 '
assert_field 'a wrong method names the method that would have worked' \
    21 24 '1 102 3 2 '
assert_field 'a path with two methods matches the right one' \
    25 28 '2 103 1 4 '
assert_field 'an unknown path is NotFound carrying the path' \
    29 32 '1 999 2 999 '
assert_field 'an oversized body is refused before the table is consulted' \
    33 36 '1 101 4 4096 '
assert_field 'an oversized body to an unknown path reports the same thing' \
    37 40 '1 999 4 4096 '
assert_field 'the limit itself is inside the limit' \
    41 44 '1 101 1 1 '
assert_field 'the Allow set does not depend on the request method' \
    45 48 '9 103 3 3 '
assert_field 'a handler is pure and its clock is the injected field' \
    49 53 '200 101042 200 106 101043 '

lines=$(wc -l <"$expected" | tr -d ' ')
test "$lines" -eq 53 ||
    fail "recorded decisions cover the whole golden: expected 53 lines, got $lines"

# The table refuses duplicates by construction today: prove the four pairs
# are distinct rather than trusting the comment that says so.
dupes=$(sed -n '1,12p' "$expected" | paste - - - | awk '{print $1, $2}' | sort | uniq -d)
test -z "$dupes" || fail "duplicate (method, path) pair in the table: $dupes"

printf 'boot: the core cannot construct a capability, and does not own main: PASS\n'
printf 'boot: canonical contract pinned at its boundary: PASS\n'
printf 'boot: fixed-rank dispatch, every closed outcome read by name: PASS\n'
printf 'boot: handlers are pure and time is an injected capability: PASS\n'
printf 'boot: reference and C11 agree; bytes hold under hostile TZ, locale, env -i: PASS\n'
