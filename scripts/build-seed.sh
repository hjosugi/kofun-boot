#!/bin/sh
set -eu

# Concatenate the functional core with the imperative shell and build.
#
# The language's executable slice has no module imports, so a two-layer
# application is assembled the way framework/http assembles its own: text
# concatenation at build time, in a fixed order. The order is the dependency
# direction — core first, shell after — and it is the only direction that
# compiles, which is a pleasant accident of the boundary being real.

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
KOFUN="$ROOT/vendor/kofun/bin/kofun"
OUT=${1:-"$ROOT/build/router"}
# Consume the destination so any remaining arguments are the caller's, not a
# second copy of the path. Passing it twice made the builder echo the name and
# this script print two lines, which a caller capturing the output then read
# as one binary path.
if test "$#" -gt 0; then shift; fi

mkdir -p "$(dirname -- "$OUT")"
UNIT="$(dirname -- "$OUT")/router.unit.kofun"

cat "$ROOT/seed/router/core.kofun" >"$UNIT"
printf '\n' >>"$UNIT"
cat "$ROOT/seed/router/shell.kofun" >>"$UNIT"

# stdout belongs to this script: exactly one line, the path that was built.
"$KOFUN" build "$UNIT" -o "$OUT" "$@" >/dev/null
printf '%s\n' "$OUT"
