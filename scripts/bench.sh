#!/bin/sh
set -eu

# Record a benchmark measurement, or refuse to.
#
#   scripts/bench.sh record [FILE]   measure and record, if the machine is quiet
#   scripts/bench.sh check FILE      compare a fresh measurement to a baseline
#   scripts/bench.sh --force ...     record anyway, and say so in the record
#
# The refusal is the feature. A benchmark harness that always produces a number
# produces a number even when the machine is compiling something else in twelve
# parallel jobs, and that number then sits in a README looking exactly like a
# real one. This repository's rule is that no number appears without the gate
# that measured it; load is part of what a measurement is, so a run under load
# is not a measurement and is recorded as such or not at all.
#
# The underlying harness is the language's own `benchmarks/http`, which
# compares the Kofun-configured server against a minimal direct-C front end to
# the same event loop. It isolates the cost of entering the framework — it is
# not a comparison with another web framework, and this script does not
# pretend otherwise.

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
KOFUN_DIR="$ROOT/vendor/kofun"

# One busy core's worth of headroom. Below this the samples on this harness
# stay inside their own noise; above it they do not, which is why the small
# smoke run and the full run disagreed the first time this was tried.
LOAD_LIMIT=${LOAD_LIMIT:-2.0}

force=0
if test "${1:-}" = "--force"; then
    force=1
    shift
fi

fail() {
    printf 'bench: %s\n' "$*" >&2
    exit 1
}

load_now() {
    if test -r /proc/loadavg; then
        cut -d' ' -f1 </proc/loadavg
    else
        uptime | sed 's/.*average[s]*: *\([0-9.]*\).*/\1/'
    fi
}

machine() {
    printf '%s %s' "$(uname -s)" "$(uname -m)"
}

cores() {
    if command -v nproc >/dev/null 2>&1; then nproc; else printf 'unknown'; fi
}

require_quiet() {
    load=$(load_now)
    quiet=$(awk -v l="$load" -v m="$LOAD_LIMIT" 'BEGIN { print (l < m) ? 1 : 0 }')
    if test "$quiet" -ne 1; then
        if test "$force" -eq 1; then
            printf 'bench: WARNING: load %s exceeds %s; recording as untrusted\n' \
                "$load" "$LOAD_LIMIT" >&2
            return 1
        fi
        printf '%s\n' \
            "bench: the machine is busy (load $load, limit $LOAD_LIMIT)." \
            "" \
            "  A number measured under load is not a measurement, and this" \
            "  repository does not publish one. Wait for the machine to settle," \
            "  or pass --force to record it marked untrusted." >&2
        exit 1
    fi
    return 0
}

measure() {
    (cd "$KOFUN_DIR" && sh benchmarks/http/benchmark.sh) 2>"$1"
}

case "${1:-}" in
    record)
        out=${2:-"$ROOT/contracts/bench.baseline"}
        trusted=trusted
        require_quiet || trusted=untrusted

        work=$(mktemp -d "${TMPDIR:-/tmp}/kofun-boot-bench.XXXXXX")
        trap 'rm -rf "$work"' 0 1 2 15

        load_before=$(load_now)
        measure "$work/err" >"$work/raw" || {
            printf 'bench: the harness failed:\n' >&2
            sed 's/^/    /' "$work/err" >&2
            exit 1
        }
        load_after=$(load_now)

        {
            printf '# format: kofun-boot.bench/v1\n'
            printf '# harness: vendor/kofun/benchmarks/http\n'
            printf '# measures: cost of entering the framework, not a cross-framework comparison\n'
            printf '# machine: %s, %s cores\n' "$(machine)" "$(cores)"
            printf '# language: %s\n' \
                "$(git -C "$KOFUN_DIR" rev-parse --short HEAD 2>/dev/null || printf unknown)"
            printf '# load_before: %s\n' "$load_before"
            printf '# load_after: %s\n' "$load_after"
            printf '# trust: %s\n' "$trusted"
            cat "$work/raw"
        } >"$out"

        printf 'bench: recorded (%s) to %s\n' "$trusted" "$out"
        grep -E 'requests_per_second' "$out" | sed 's/^/  /'
        ;;

    check)
        baseline=${2:-}
        test -n "$baseline" || fail 'usage: scripts/bench.sh check FILE'
        test -f "$baseline" || fail "no baseline at $baseline"

        recorded_trust=$(sed -n 's/^# trust: //p' "$baseline" | head -1)
        test "$recorded_trust" = trusted ||
            fail "the baseline is marked '$recorded_trust'; a regression cannot be
  measured against a number that was not a measurement"

        require_quiet
        work=$(mktemp -d "${TMPDIR:-/tmp}/kofun-boot-bench.XXXXXX")
        trap 'rm -rf "$work"' 0 1 2 15
        measure "$work/err" >"$work/raw" || {
            printf 'bench: the harness failed:\n' >&2
            sed 's/^/    /' "$work/err" >&2
            exit 1
        }

        was=$(sed -n 's/^kofun_requests_per_second=//p' "$baseline" | head -1)
        now=$(sed -n 's/^kofun_requests_per_second=//p' "$work/raw" | head -1)
        test -n "$was" && test -n "$now" ||
            fail 'the harness did not report requests_per_second'

        # A budget wide enough to survive this harness's own sample variation
        # and narrow enough to catch a real regression. Both directions, the
        # way the language's assertion budget works: an unexplained improvement
        # is unrecorded information, not a free win.
        printf 'bench: baseline %s r/s, measured %s r/s\n' "$was" "$now"
        awk -v was="$was" -v now="$now" 'BEGIN {
            ratio = now / was
            if (ratio < 0.85) {
                printf "bench: FAIL: %.1f%% slower than the baseline\n",
                    (1 - ratio) * 100 > "/dev/stderr"
                exit 1
            }
            if (ratio > 1.20) {
                printf "bench: FAIL: %.1f%% faster than the baseline — re-record it,\n  an unexplained improvement is unrecorded information\n",
                    (ratio - 1) * 100 > "/dev/stderr"
                exit 1
            }
            printf "bench: within budget (%.1f%% of baseline)\n", ratio * 100
        }'
        ;;

    *)
        sed -n '3,8p' "$0" | sed 's/^# \{0,1\}//'
        exit 2
        ;;
esac
