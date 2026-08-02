#!/bin/sh
set -eu

# boot dev — the inner loop.
#
# One command, three modes, no daemon and no state directory:
#
#   scripts/dev.sh            build, run the seed, run the unit suite, once
#   scripts/dev.sh --watch    re-run the unit suite on every save
#   scripts/dev.sh --test     the unit suite only (fastest useful loop)
#   scripts/dev.sh --serve    the integration test: a real server, real sockets
#   scripts/dev.sh --check    everything CI runs, in CI's order
#   scripts/dev.sh --openapi  print the document the route table projects
#
# The design rule is that the loop a developer runs and the loop CI runs are
# the same commands, so a green terminal and a green pipeline mean the same
# thing. `scripts/dev.sh --check` is exactly what CI calls.

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
KOTEST="$ROOT/vendor/kofun/tooling/kotest/run.sh"

usage() {
    sed -n '3,14p' "$0" | sed 's/^# \{0,1\}//'
}

banner() {
    printf '\033[1m%s\033[0m\n' "$*" 2>/dev/null || printf '%s\n' "$*"
}

elapsed() {
    # Whole seconds is enough resolution to notice a loop getting slow, and
    # it needs no dependency beyond the shell.
    printf '%ss' "$(( $(date +%s) - $1 ))"
}

run_tests() {
    banner "unit"
    sh "$KOTEST" "$ROOT/seed/router/core_test.kofun" \
        "$ROOT/seed/mock/core_test.kofun" "$@"
}

run_seed() {
    banner "seed"
    started=$(date +%s)
    binary=$(sh "$ROOT/scripts/build-seed.sh" "$ROOT/build/router")
    printf 'built in %s\n' "$(elapsed "$started")"
    "$binary" >"$ROOT/build/router.out"
    if cmp -s "$ROOT/seed/router/router.stdout" "$ROOT/build/router.out"; then
        printf 'golden matches (%s lines)\n' \
            "$(wc -l <"$ROOT/build/router.out" | tr -d ' ')"
    else
        printf 'golden DIFFERS — review, then re-record if intended:\n'
        diff "$ROOT/seed/router/router.stdout" "$ROOT/build/router.out" |
            head -20
        return 1
    fi
}

once() {
    started=$(date +%s)
    run_tests "$@" || return 1
    run_seed || return 1
    banner "ok in $(elapsed "$started")"
}

case "${1:-}" in
    --help|-h)
        usage
        ;;
    --test)
        shift
        run_tests "$@"
        ;;
    --openapi)
        sh "$ROOT/scripts/openapi.sh"
        ;;
    --serve)
        banner "serve"
        sh "$ROOT/tests/integration/serve.sh"
        ;;
    --check)
        # What CI runs, in CI's order. Kept here so a developer's green and a
        # pipeline's green cannot come to mean different things.
        run_tests
        sh "$ROOT/tests/boot/check.sh"
        sh "$ROOT/tests/integration/serve.sh"
        ;;
    --watch)
        shift
        # kotest owns watching for the unit loop; it already re-runs on save
        # and prints the same protocol. Delegating means one watcher, one set
        # of semantics, and no second implementation to keep honest.
        banner "watching seed/ — save to re-run"
        sh "$KOTEST" --watch "$ROOT/seed/router/core_test.kofun" \
            "$ROOT/seed/mock/core_test.kofun" "$@"
        ;;
    "")
        once
        ;;
    *)
        usage
        exit 2
        ;;
esac
