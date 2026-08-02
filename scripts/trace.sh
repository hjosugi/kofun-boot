#!/bin/sh
set -eu

# Record and replay a session trace.
#
#   scripts/trace.sh record [FILE]    run the session, write the trace
#   scripts/trace.sh replay FILE      run it again, compare, name any divergence
#
# A trace is the list of steps in the fold the core already performs, so
# recording costs nothing: `apply` returns every number in it. Replay is
# running the fold again and comparing — which is only meaningful because
# nothing in the core can reach a clock, an id source, or a file.
#
# The header pins what the trace is *of*. A trace replayed against a different
# seed, a different session, or a different build of the language is not a
# replay, and the digest is what makes that detectable rather than a confusing
# diff twenty steps in.

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)

FORMAT=kofun-boot.trace/v1
COLUMNS='step op arg_id arg_value outcome payload live next_id'

fail() {
    printf 'trace: %s\n' "$*" >&2
    exit 1
}

digest_of() {
    # sha256 of the step lines only, so a header change is a header change and
    # a behaviour change is a behaviour change.
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum <"$1" | cut -d' ' -f1
    elif command -v shasum >/dev/null 2>&1; then
        shasum -a 256 <"$1" | cut -d' ' -f1
    else
        fail 'no sha256sum or shasum available'
    fi
}

run_session() {
    binary=$(SEED=mock sh "$ROOT/scripts/build-seed.sh" "$ROOT/build/mock")
    # An empty environment, because a trace recorded under one environment and
    # replayed under another must not be able to differ for that reason. If it
    # ever does, the divergence is real and the gate should see it.
    env -i "$binary" | paste - - - - - - - -
}

language_revision() {
    git -C "$ROOT/vendor/kofun" rev-parse --short HEAD 2>/dev/null || printf 'unknown'
}

case "${1:-}" in
    record)
        out=${2:-"$ROOT/contracts/session.trace"}
        work=$(mktemp -d "${TMPDIR:-/tmp}/kofun-boot-trace.XXXXXX")
        trap 'rm -rf "$work"' 0 1 2 15
        run_session >"$work/steps"
        {
            printf '# format: %s\n' "$FORMAT"
            printf '# columns: %s\n' "$COLUMNS"
            printf '# seed: seeded_store\n'
            printf '# language: %s\n' "$(language_revision)"
            printf '# digest: %s\n' "$(digest_of "$work/steps")"
            cat "$work/steps"
        } >"$out"
        printf 'trace: recorded %s steps to %s\n' \
            "$(wc -l <"$work/steps" | tr -d ' ')" "$out"
        ;;

    replay)
        trace=${2:-}
        test -n "$trace" || fail 'usage: scripts/trace.sh replay FILE'
        test -f "$trace" || fail "no trace at $trace"
        work=$(mktemp -d "${TMPDIR:-/tmp}/kofun-boot-trace.XXXXXX")
        trap 'rm -rf "$work"' 0 1 2 15

        recorded_format=$(sed -n 's/^# format: //p' "$trace" | head -1)
        test "$recorded_format" = "$FORMAT" ||
            fail "trace format is '$recorded_format', this tool speaks '$FORMAT'"

        recorded_digest=$(sed -n 's/^# digest: //p' "$trace" | head -1)
        grep -v '^#' "$trace" >"$work/recorded"
        actual_digest=$(digest_of "$work/recorded")
        test "$recorded_digest" = "$actual_digest" ||
            fail "the trace file's own digest does not match its steps;
  header says $recorded_digest
  steps are  $actual_digest
  the file has been edited by hand"

        run_session >"$work/replayed"

        # Name the first divergence by step, with both values, rather than
        # printing a diff and leaving the reader to find the step number. A
        # replay that says only "differs" is a replay nobody debugs.
        if ! cmp -s "$work/recorded" "$work/replayed"; then
            line=$(cmp "$work/recorded" "$work/replayed" 2>/dev/null |
                sed -n 's/.*line \([0-9][0-9]*\).*/\1/p' | head -1)
            line=${line:-1}
            recorded_step=$(sed -n "${line}p" "$work/recorded")
            replayed_step=$(sed -n "${line}p" "$work/replayed")
            printf 'trace: FAIL: the session diverged at step %s\n' "$line" >&2
            printf '  columns:  %s\n' "$COLUMNS" >&2
            printf '  recorded: %s\n' "$(printf '%s' "$recorded_step" | tr '\t' ' ')" >&2
            printf '  replayed: %s\n' "$(printf '%s' "$replayed_step" | tr '\t' ' ')" >&2
            exit 1
        fi

        recorded_language=$(sed -n 's/^# language: //p' "$trace" | head -1)
        current_language=$(language_revision)
        if test "$recorded_language" != "$current_language"; then
            printf 'trace: replayed identically across language revisions %s -> %s\n' \
                "$recorded_language" "$current_language"
        fi
        printf 'trace: %s steps replayed byte-identically\n' \
            "$(wc -l <"$work/recorded" | tr -d ' ')"
        ;;

    *)
        sed -n '3,9p' "$0" | sed 's/^# \{0,1\}//'
        exit 2
        ;;
esac
