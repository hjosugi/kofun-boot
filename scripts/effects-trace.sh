#!/bin/sh
set -eu

# Record and replay the Cmd/Msg sequence owned by modules/effects.
#
#   scripts/effects-trace.sh record [FILE]
#   scripts/effects-trace.sh replay FILE

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
KOFUN="$ROOT/vendor/kofun/bin/kofun"
FORMAT=kofun-boot.effects-trace/v1
CONTRACT="$ROOT/modules/effects/contract/effects.kofun"
CORE="$ROOT/modules/effects/core"

fail() {
    printf 'effects-trace: FAIL: %s\n' "$*" >&2
    exit 1
}

sha256_of() {
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$1" | cut -d' ' -f1
    elif command -v shasum >/dev/null 2>&1; then
        shasum -a 256 "$1" | cut -d' ' -f1
    else
        fail 'no sha256sum or shasum available'
    fi
}

record_steps() {
    work=$1
    binary=$(SEED=effects sh "$ROOT/scripts/build-seed.sh" "$work/effects")
    if test "${EFFECTS_TRACE_RUNNER:-c11}" = reference; then
        "$KOFUN" run "$work/effects.unit.kofun"
    else
        "$binary"
    fi | paste - - - - - - |
        awk 'BEGIN { OFS="\t" } { print NR, $1, $2, $3, $4, $5, $6 }'
}

validate_steps() {
    awk '
        NF != 7 { exit 1 }
        $1 != NR { exit 1 }
        {
            for (field = 1; field <= 7; field++) {
                if ($field !~ /^-?[0-9]+$/) exit 1
            }
        }
        END { if (NR == 0) exit 1 }
    ' "$1" || fail 'trace rows must be sequential seven-integer records'
}

case "${1:-}" in
    record)
        out=${2:-"$ROOT/modules/effects/tests/effects.trace"}
        work=$(mktemp -d "${TMPDIR:-/tmp}/kofun-boot-effects-record.XXXXXX")
        trap 'rm -rf "$work"' 0 1 2 15
        record_steps "$work" >"$work/steps"
        validate_steps "$work/steps"
        test "$(wc -l <"$work/steps" | tr -d ' ')" -eq 10 ||
            fail 'the effect trace must contain exactly ten named steps'
        {
            printf '# format: %s\n' "$FORMAT"
            printf '# contract-sha256: %s\n' "$(sha256_of "$CONTRACT")"
            printf '# columns: step source effect argument continuation message observed\n'
            cat "$work/steps"
        } >"$out"
        printf 'effects-trace: recorded 10 Cmd/Msg steps to %s\n' "$out"
        ;;

    replay)
        trace=${2:-}
        test -n "$trace" || fail 'usage: scripts/effects-trace.sh replay FILE'
        test -f "$trace" || fail "no trace at $trace"
        work=$(mktemp -d "${TMPDIR:-/tmp}/kofun-boot-effects-replay.XXXXXX")
        trap 'rm -rf "$work"' 0 1 2 15

        recorded_format=$(sed -n 's/^# format: //p' "$trace" | head -1)
        test "$recorded_format" = "$FORMAT" ||
            fail "trace format mismatch: recorded '$recorded_format', current '$FORMAT'"
        recorded_contract=$(sed -n 's/^# contract-sha256: //p' "$trace" | head -1)
        current_contract=$(sha256_of "$CONTRACT")
        test "$recorded_contract" = "$current_contract" ||
            fail "contract digest mismatch: recorded $recorded_contract, current $current_contract"

        grep -v '^#' "$trace" >"$work/recorded"
        validate_steps "$work/recorded"

        : >"$work/replay.kofun"
        for source in "$CORE"/*.kofun; do
            cat "$source" >>"$work/replay.kofun"
            printf '\n' >>"$work/replay.kofun"
        done
        {
            printf '%s\n' 'fn emit_replay_cmd(command: ReplayCmd) -> Int {'
            printf '%s\n' '    print(command.source)'
            printf '%s\n' '    print(command.effect)'
            printf '%s\n' '    print(command.argument)'
            printf '%s\n' '    print(command.continuation)'
            printf '%s\n' '    return 0'
            printf '%s\n' '}' 'fn main() -> Int {'
            printf '%s\n' \
                '    let touch_none: EffectStep = trace_none()' \
                '    if touch_none.source == 0 { return 1 }' \
                '    let touch_batch: EffectStep = trace_batch(2)' \
                '    if touch_batch.source == 0 { return 1 }' \
                '    let touch_http: EffectStep = interpret_http(1, 1, 1, 0, 200)' \
                '    if touch_http.source == 0 { return 1 }' \
                '    let touch_clock: EffectStep = trace_clock(1, 1)' \
                '    if touch_clock.source == 0 { return 1 }' \
                '    let touch_persist: EffectStep = trace_persist(1, 1)' \
                '    if touch_persist.source == 0 { return 1 }' \
                '    let touch_custom_cmd: EffectStep = trace_custom_cmd(1, 1)' \
                '    if touch_custom_cmd.source == 0 { return 1 }' \
                '    let touch_tick: EffectStep = trace_tick(1, 1, 1)' \
                '    if touch_tick.source == 0 { return 1 }' \
                '    let touch_signal: EffectStep = trace_signal(1, 1)' \
                '    if touch_signal.source == 0 { return 1 }' \
                '    let touch_custom_sub: EffectStep = trace_custom_sub(1, 1)' \
                '    if touch_custom_sub.source == 0 { return 1 }'
            awk '
                BEGIN { print "    emit_replay_cmd(replay_initial())" }
                NR > 1 {
                    printf "    emit_replay_cmd(replay_after(%d, %s, %s))\n", NR - 1, message, observed
                }
                { message = $6; observed = $7 }
                END { print "    return 0"; print "}" }
            ' "$work/recorded"
        } >>"$work/replay.kofun"

        "$KOFUN" check "$work/replay.kofun" >/dev/null 2>"$work/check.stderr" ||
            fail "generated replay did not check: $(cat "$work/check.stderr")"
        "$KOFUN" build "$work/replay.kofun" -o "$work/replay" \
            --emit-c "$work/replay.c" >/dev/null 2>"$work/build.stderr" ||
            fail "generated replay did not build: $(cat "$work/build.stderr")"

        "$work/replay" >"$work/c11"
        "$KOFUN" run "$work/replay.kofun" >"$work/reference" 2>"$work/run.stderr" ||
            fail "reference replay failed: $(cat "$work/run.stderr")"
        cmp "$work/c11" "$work/reference" || fail 'reference and C11 replay differ'
        "$work/replay" >"$work/second"
        cmp "$work/c11" "$work/second" || fail 'two replay runs differ'
        TZ=Pacific/Kiritimati LC_ALL=C LANG=C "$work/replay" >"$work/hostile"
        cmp "$work/c11" "$work/hostile" || fail 'replay changed under hostile TZ or locale'
        env -i "$work/replay" >"$work/bare"
        cmp "$work/c11" "$work/bare" || fail 'replay changed with an empty environment'
        if grep -qE 'time\.h|clock_gettime|gettimeofday|localtime|getenv|fopen|socket' \
            "$work/replay.c"
        then
            fail 'emitted replay C reaches ambient state'
        fi

        paste - - - - <"$work/c11" |
            awk 'BEGIN { OFS="\t" } { print NR, $1, $2, $3, $4 }' \
            >"$work/emitted"
        awk 'BEGIN { OFS="\t" } { print $1, $2, $3, $4, $5 }' \
            "$work/recorded" >"$work/expected"

        if ! cmp -s "$work/expected" "$work/emitted"; then
            line=$(awk '
                NR == FNR { expected[NR] = $0; count = NR; next }
                $0 != expected[FNR] { print FNR; exit }
                END { if (FNR < count) print FNR + 1 }
            ' "$work/expected" "$work/emitted" | head -1)
            line=${line:-1}
            expected=$(sed -n "${line}p" "$work/expected" | tr '\t' ' ')
            emitted=$(sed -n "${line}p" "$work/emitted" | tr '\t' ' ')
            if test "$line" -eq 1; then
                fed='<init>'
            else
                previous=$((line - 1))
                fed=$(sed -n "${previous}p" "$work/recorded" |
                    awk '{ printf "step=%s message=%s observed=%s", $1, $6, $7 }')
            fi
            printf 'effects-trace: FAIL: replay diverged at step %s\n' "$line" >&2
            printf '  fed Msg:      %s\n' "$fed" >&2
            printf '  expected Cmd: %s\n' "$expected" >&2
            printf '  emitted Cmd:  %s\n' "$emitted" >&2
            exit 1
        fi
        printf 'effects-trace: %s steps replayed byte-identically on reference and C11\n' \
            "$(wc -l <"$work/recorded" | tr -d ' ')"
        ;;

    *)
        sed -n '3,7p' "$0" | sed 's/^# \{0,1\}//'
        exit 2
        ;;
esac
