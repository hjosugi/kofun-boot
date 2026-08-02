#!/bin/sh
set -eu

# Integration: the vendored HTTP runtime actually serves.
#
# The unit suite proves the core decides correctly; this proves a real process
# binds a port, answers over a socket, and drains on a signal. Nothing here is
# mocked and nothing is installed: the server is built from the pinned
# `vendor/kofun` checkout with its own build helper, and the client is the
# shell.
#
# Two rules make an integration test something a developer will actually run:
#
#   it must not need a fixed port — port 0 is asked for, and the process
#   prints `READY <port>` with the one it got, so parallel runs cannot collide;
#
#   it must clean up even when it fails — the trap kills the server on every
#   exit path, so a failed assertion does not leave a listener behind.

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
KOFUN_DIR="$ROOT/vendor/kofun"

WORK=$(mktemp -d "${TMPDIR:-/tmp}/kofun-boot-serve.XXXXXX")
SERVER_PID=""
cleanup() {
    if test -n "$SERVER_PID"; then
        kill "$SERVER_PID" 2>/dev/null || true
        wait "$SERVER_PID" 2>/dev/null || true
    fi
    rm -rf "$WORK"
}
trap cleanup 0 1 2 15

fail() {
    printf 'serve: FAIL: %s\n' "$*" >&2
    if test -s "$WORK/server.log"; then
        printf '%s\n' '--- server log ---' >&2
        cat "$WORK/server.log" >&2
    fi
    exit 1
}

pass() {
    printf 'serve: %s: PASS\n' "$*"
}

# A response assertion that says what it wanted and what it got. An
# integration test whose failure is "exit 1" is a test a developer stops
# running.
expect_contains() {
    label=$1
    needle=$2
    file=$3
    grep -Fq -- "$needle" "$file" ||
        fail "$label: expected a response containing '$needle', got:
$(sed 's/^/    /' "$file")"
    pass "$label"
}

# ------------------------------------------------------------- the server

test -f "$KOFUN_DIR/framework/http/build.sh" ||
    fail 'vendor/kofun has no framework/http; run: git submodule update --init vendor/kofun'

command -v curl >/dev/null 2>&1 || fail 'curl is required for the serve test'

printf 'serve: building the example server from the pinned checkout\n'
(cd "$KOFUN_DIR" && sh framework/http/build.sh examples/api_server.kofun \
    "$WORK/api-server") >"$WORK/build.log" 2>&1 ||
    fail "the example server did not build:
$(sed 's/^/    /' "$WORK/build.log")"

"$WORK/api-server" >"$WORK/server.log" 2>&1 &
SERVER_PID=$!

# Wait for READY rather than sleeping: a fixed sleep is either flaky or slow,
# and on a loaded CI box it is both.
PORT=""
attempt=0
while test "$attempt" -lt 100; do
    if test -s "$WORK/server.log"; then
        PORT=$(sed -n 's/^READY \([0-9][0-9]*\).*/\1/p' "$WORK/server.log" |
            head -1)
        test -n "$PORT" && break
    fi
    kill -0 "$SERVER_PID" 2>/dev/null ||
        fail 'the server exited before printing READY'
    attempt=$((attempt + 1))
    sleep 0.1
done
test -n "$PORT" || fail 'the server never printed READY'
pass "bound an ephemeral port ($PORT)"

BASE="http://127.0.0.1:$PORT"
get() {
    curl -sS --max-time 5 -o "$WORK/body" -w '%{http_code}' "$@" 2>"$WORK/curl.err" ||
        fail "curl failed: $(cat "$WORK/curl.err")"
}

# -------------------------------------------------------------- requests

status=$(get "$BASE/hello/world")
test "$status" = 200 || fail "GET /hello/world: expected 200, got $status"
expect_contains 'a path capture reaches the handler' 'world' "$WORK/body"

status=$(get -X POST -H 'Content-Type: application/json' \
    -d '{"left": 40, "right": 2}' "$BASE/sum")
test "$status" = 200 || fail "POST /sum: expected 200, got $status"
expect_contains 'a JSON body is decoded and answered' '42' "$WORK/body"

status=$(get "$BASE/no-such-route")
test "$status" = 404 ||
    fail "an unknown path: expected 404, got $status"
pass 'an unknown path is 404'

status=$(get -X POST -H 'Content-Type: application/json' \
    -d '{"left": "not a number", "right": 2}' "$BASE/sum")
test "$status" = 400 ||
    fail "malformed JSON: expected 400, got $status"
pass 'malformed JSON is 400, not a crash'

# Keep-alive is the default; two requests over one connection must both
# answer, which is the property a load test depends on. Each response needs
# its own -o: with one -o and two URLs, curl writes the first body to the file
# and the rest to stdout, so a single-file assertion silently checks one
# response twice.
curl -sS --max-time 5 \
    -o "$WORK/keepalive.1" "$BASE/hello/one" \
    -o "$WORK/keepalive.2" "$BASE/hello/two" 2>"$WORK/curl.err" ||
    fail "keep-alive requests failed: $(cat "$WORK/curl.err")"
expect_contains 'two requests share one connection (first)' 'one' "$WORK/keepalive.1"
expect_contains 'two requests share one connection (second)' 'two' "$WORK/keepalive.2"

# ---------------------------------------------------------------- drain

kill -TERM "$SERVER_PID"
waited=0
while kill -0 "$SERVER_PID" 2>/dev/null; do
    waited=$((waited + 1))
    test "$waited" -lt 100 || fail 'the server did not exit within 10s of SIGTERM'
    sleep 0.1
done
wait "$SERVER_PID" 2>/dev/null || true
SERVER_PID=""
pass 'SIGTERM drains and exits'

printf 'serve: the pinned runtime binds, answers, and drains: PASS\n'
