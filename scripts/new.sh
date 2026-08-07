#!/bin/sh
set -eu

# boot new — scaffold a project that already has the boundary.
#
# The scaffold's whole job is to make the first compile land on the right side
# of the core/shell line, because a project that starts without the boundary
# never grows one. What it emits is not a template that hopes to still be
# valid: `tests/scaffold/check.sh` generates a project, builds it, and runs its
# tests on every CI run, so a scaffold that has rotted fails this repository's
# build rather than someone else's afternoon.
#
# usage: scripts/new.sh DIRECTORY [--name NAME]

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)

fail() {
    printf 'boot new: %s\n' "$*" >&2
    exit 1
}

target=${1:-}
test -n "$target" || fail 'usage: scripts/new.sh DIRECTORY [--name NAME]'
shift

name=$(basename -- "$target")
while test "$#" -gt 0; do
    case $1 in
        --name)
            shift
            name=${1:-}
            test -n "$name" || fail '--name needs a value'
            ;;
        *) fail "unknown option: $1" ;;
    esac
    shift
done

test ! -e "$target" || fail "$target already exists"

# The pinned language checkout. A scaffolded project must reach a toolchain,
# and reaching *this* one means the project it generates is reproducible for
# the same reason this repository is.
KOFUN_DIR=${KOFUN_DIR:-"$ROOT/vendor/kofun"}
test -d "$KOFUN_DIR" ||
    fail "no language checkout at $KOFUN_DIR; set KOFUN_DIR or run: git submodule update --init vendor/kofun"
KOFUN_ABS=$(CDPATH= cd -- "$KOFUN_DIR" && pwd)

mkdir -p "$target/core" "$target/shell" "$target/tests"

# ------------------------------------------------------------------ core

cat >"$target/core/core.kofun" <<'CORE'
# The functional core.
#
# Everything here is a pure function. This file may receive a capability as an
# argument and may not construct one, and it may not own an entry point —
# `tests/check.sh` reads it with comments stripped and fails on either. That
# is not a house style: it is what makes every function below testable without
# a server, a clock, or a network.

type Capabilities = {
    now_seconds: Int,
}

type Greeting = {
    audience: Int,
    at_seconds: Int,
}

# A closed result. Each case carries what was observed, so a caller never has
# to guess why: `TooLoud` says what the limit was, not merely that one exists.
type GreetResult =
    | Greeted(audience: Int)
    | Silent(reason: Int)
    | TooLoud(limit: Int)

fn audience_limit() -> Int {
    return 100
}

fn reason_empty() -> Int {
    return 1
}

fn greet_result_kind(result: GreetResult) -> Int {
    let mut kind = 0
    match result {
        Greeted(_) => { kind = 1 },
        Silent(_) => { kind = 2 },
        TooLoud(_) => { kind = 3 },
    }
    return kind
}

fn greet_result_payload(result: GreetResult) -> Int {
    let mut payload = 0
    match result {
        Greeted(audience) => { payload = audience },
        Silent(reason) => { payload = reason },
        TooLoud(limit) => { payload = limit },
    }
    return payload
}

# The one decision this application makes. Size is checked before anything
# else, the way the framework's own dispatcher checks it, so a caller cannot
# learn about the rest by sending something oversized.
#
# It takes no capability, because it needs none — and the compiler enforces
# that honesty: a parameter this function ignored would fail the build with
# `unused parameter`. A signature here is therefore a true statement about
# what the decision depends on, which is the property that makes the core
# worth testing on its own.
fn greet(audience: Int) -> GreetResult {
    if audience > audience_limit() {
        return TooLoud(audience_limit())
    }
    if audience == 0 {
        return Silent(reason_empty())
    }
    return Greeted(audience)
}

fn greeting_at(audience: Int, capabilities: Capabilities) -> Greeting {
    let value: Greeting = Greeting(
        audience: audience,
        at_seconds: capabilities.now_seconds
    )
    return value
}
CORE

# ----------------------------------------------------------------- shell

cat >"$target/shell/shell.kofun" <<'SHELL'
# The imperative shell.
#
# Everything the core is forbidden to name lives here, in one place a reader
# can hold: the capability record, and what gets printed. The core decides;
# this decides what the outside world sees.

fn main() -> Int {
    # The only clock this program has is the one written here. A test replaces
    # this line and the whole application becomes deterministic — there is no
    # ambient time for the core to reach instead.
    let clock: Capabilities = Capabilities(now_seconds: 1700000000)

    let welcomed: GreetResult = greet(3)
    print(greet_result_kind(welcomed))
    print(greet_result_payload(welcomed))

    let silent: GreetResult = greet(0)
    print(greet_result_kind(silent))
    print(greet_result_payload(silent))

    let loud: GreetResult = greet(101)
    print(greet_result_kind(loud))
    print(greet_result_payload(loud))

    let stamped: Greeting = greeting_at(3, clock)
    print(stamped.audience)
    print(stamped.at_seconds)
    return 0
}
SHELL

# ----------------------------------------------------------------- tests

cat >"$target/core/core_test.kofun" <<'TEST'
# Unit tests for the core. No server, no clock, no network — the core is pure,
# so its tests are arithmetic. kotest pairs this file with `core.kofun`
# automatically, by name.
#
# A test returns its failed-assertion count, so 0 is a pass. Assertions
# accumulate with `+` rather than aborting, so a broken change reports
# everything that is wrong at once.

fn test_a_normal_audience_is_greeted() -> Int {
    let result: GreetResult = greet(3)
    let mut failures = 0
    failures = failures + expect_eq_int(greet_result_kind(result), 1)
    failures = failures + expect_eq_int(greet_result_payload(result), 3)
    return failures
}

fn test_an_empty_audience_is_silent_and_says_why() -> Int {
    let result: GreetResult = greet(0)
    let mut failures = 0
    failures = failures + expect_eq_int(greet_result_kind(result), 2)
    failures = failures + expect_eq_int(greet_result_payload(result), reason_empty())
    return failures
}

# The refusal carries the limit, so a caller learns the bound rather than
# being told "no".
fn test_an_oversized_audience_names_the_limit() -> Int {
    let result: GreetResult = greet(101)
    let mut failures = 0
    failures = failures + expect_eq_int(greet_result_kind(result), 3)
    failures = failures + expect_eq_int(greet_result_payload(result), audience_limit())
    return failures
}

# Half-open at the top: the limit itself is inside the limit. An off-by-one
# here refuses a caller the contract accepts.
fn test_the_limit_itself_is_accepted() -> Int {
    let at_limit: GreetResult = greet(100)
    let over: GreetResult = greet(101)
    let mut failures = 0
    failures = failures + expect_eq_int(greet_result_kind(at_limit), 1)
    failures = failures + expect_eq_int(greet_result_kind(over), 3)
    return failures
}

# The core is a function of its capabilities: the same input and the same
# record give the same answer, and the only thing that moves the timestamp is
# the injected clock. This is what makes a recorded run replayable.
fn test_the_core_is_a_function_of_its_capability() -> Int {
    let early: Capabilities = Capabilities(now_seconds: 42)
    let late: Capabilities = Capabilities(now_seconds: 43)
    let a: Greeting = greeting_at(3, early)
    let b: Greeting = greeting_at(3, early)
    let c: Greeting = greeting_at(3, late)
    let mut failures = 0
    failures = failures + expect_eq_int(a.at_seconds, b.at_seconds)
    failures = failures + expect_ne_int(a.at_seconds, c.at_seconds)
    failures = failures + expect_eq_int(c.at_seconds - a.at_seconds, 1)
    return failures
}

# Every input produces one of the three cases, including inputs the surface
# never emits. A decision with an undefined case is a decision that will one
# day be made by accident.
fn test_greet_is_total() -> Int {
    let mut failures = 0
    failures = failures + expect_between_int(greet_result_kind(greet(0)), 1, 3)
    failures = failures + expect_between_int(greet_result_kind(greet(1)), 1, 3)
    failures = failures + expect_between_int(greet_result_kind(greet(0 - 5)), 1, 3)
    failures = failures + expect_between_int(greet_result_kind(greet(999999)), 1, 3)
    return failures
}
TEST

# ------------------------------------------------------------ build/check

cat >"$target/build.sh" <<BUILD
#!/bin/sh
set -eu

# Concatenate the core with the shell and build. The executable slice has no
# module imports, so a two-layer application is assembled by text in a fixed
# order — and that order is the dependency direction, which is the only one
# that compiles.

ROOT=\$(CDPATH= cd -- "\$(dirname -- "\$0")" && pwd)
KOFUN=\${KOFUN:-"$KOFUN_ABS/bin/kofun"}
OUT=\${1:-"\$ROOT/build/$name"}
if test "\$#" -gt 0; then shift; fi

mkdir -p "\$(dirname -- "\$OUT")"
UNIT="\$(dirname -- "\$OUT")/$name.unit.kofun"

cat "\$ROOT/core/core.kofun" >"\$UNIT"
printf '\\n' >>"\$UNIT"
cat "\$ROOT/shell/shell.kofun" >>"\$UNIT"

"\$KOFUN" build "\$UNIT" -o "\$OUT" "\$@" >/dev/null
printf '%s\\n' "\$OUT"
BUILD
chmod +x "$target/build.sh"

cat >"$target/tests/check.sh" <<CHECK
#!/bin/sh
set -eu

# The project gate: the boundary holds, the unit suite passes, and the built
# program still prints what it printed.

ROOT=\$(CDPATH= cd -- "\$(dirname -- "\$0")/.." && pwd)
KOFUN_DIR=\${KOFUN_DIR:-"$KOFUN_ABS"}
KOTEST="\$KOFUN_DIR/tooling/kotest/run.sh"

WORK=\$(mktemp -d "\${TMPDIR:-/tmp}/$name.XXXXXX")
trap 'rm -rf "\$WORK"' 0 1 2 15

fail() {
    printf '$name: FAIL: %s\\n' "\$*" >&2
    exit 1
}

# The boundary, read with comments stripped: the core may receive a capability
# and may not construct one, and may not own an entry point. Both files talk
# about the boundary at length, and a grep over the whole text cannot tell an
# explanation from a violation.
sed 's/[[:space:]]*#.*\$//' "\$ROOT/core/core.kofun" >"\$WORK/core.code"
if grep -qE 'Capabilities\\(' "\$WORK/core.code"; then
    printf '%s\\n' '$name: FAIL: the core constructs a capability instead of receiving one:' >&2
    grep -nE 'Capabilities\\(' "\$WORK/core.code" >&2
    exit 1
fi
grep -qE '^fn main' "\$WORK/core.code" &&
    fail 'the core owns an entry point; emission belongs to the shell'

sh "\$KOTEST" "\$ROOT/core/core_test.kofun"

binary=\$(sh "\$ROOT/build.sh" "\$WORK/$name")
"\$binary" >"\$WORK/out"
if test -f "\$ROOT/tests/expected.stdout"; then
    cmp "\$ROOT/tests/expected.stdout" "\$WORK/out" ||
        fail "output differs from tests/expected.stdout:
\$(diff "\$ROOT/tests/expected.stdout" "\$WORK/out" | head -10)"
else
    cp "\$WORK/out" "\$ROOT/tests/expected.stdout"
    printf '$name: recorded tests/expected.stdout\\n'
fi

# Deterministic means deterministic. If this ever fails, something ambient got
# in — which is exactly what the boundary above exists to prevent.
env -i "\$binary" >"\$WORK/bare"
cmp "\$WORK/out" "\$WORK/bare" ||
    fail 'output changed with an empty environment'

printf '$name: the boundary holds, the suite passes, the bytes do not move: PASS\\n'
CHECK
chmod +x "$target/tests/check.sh"

cat >"$target/README.md" <<README
# $name

Built with [kofun-boot](https://github.com/kofun-lang/kofun-boot).

\`\`\`sh
sh tests/check.sh    # the boundary, the unit suite, and the recorded output
sh build.sh          # build, printing the path
\`\`\`

## The shape

\`core/\` is pure. It may receive a capability as an argument and may not
construct one, and it may not own an entry point — \`tests/check.sh\` enforces
both, and prints the offending line when it does not hold.

\`shell/\` owns the capability record and every print. It is the only place
that decides what the outside world sees.

That split is why \`core/core_test.kofun\` needs no server, no clock, and no
network: the core is a function, so its tests are arithmetic.

## Adding a decision

Put it in \`core/\`, return a closed sum whose every case carries what was
observed, and add a test that reads each case by name. If the decision needs
something from outside, take it as an argument — the shell will hand it in.
README

printf '%s\n' \
    "boot new: created $target" \
    "" \
    "  cd $target" \
    "  sh tests/check.sh"
