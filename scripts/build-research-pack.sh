#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
OUT=${1:-"$ROOT/dist"}
PACK_NAME=kofun-boot-framework-research-2026-08-02
FIXED_MTIME=202608020000.00

for tool in zip sha256sum mktemp; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        printf 'research-pack: FAIL: required tool not found: %s\n' "$tool" >&2
        exit 1
    fi
done

mkdir -p "$OUT"
OUT=$(CDPATH= cd -- "$OUT" && pwd)
TMP_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/kofun-boot-research.XXXXXX")
trap 'rm -rf "$TMP_ROOT"' EXIT HUP INT TERM
STAGE="$TMP_ROOT/$PACK_NAME"
mkdir -p "$STAGE/docs/research" "$STAGE/docs/architecture" "$STAGE/docs/adr"

cp "$ROOT/docs/research/PACKAGE.md" "$STAGE/README.md"
cp "$ROOT/LICENSE-APACHE" "$STAGE/LICENSE-APACHE"
cp "$ROOT/LICENSE-MIT" "$STAGE/LICENSE-MIT"

FILES='
docs/DESIGN.md
docs/ROADMAP.md
docs/BACKLOG.md
docs/research/README.md
docs/research/PACKAGE.md
docs/research/WEB_FRAMEWORKS.md
docs/research/SPRING_FASTAPI_GIN.md
docs/research/MODULAR_MONOLITH_DDD.md
docs/research/DESKTOP_FRAMEWORKS.md
docs/research/RENDER_BACKENDS.md
docs/research/EFFECT_SYSTEMS.md
docs/architecture/EFFECTS.md
docs/architecture/FDDD.md
docs/architecture/TEA.md
docs/adr/0001-record-architecture-decisions.md
docs/adr/0002-enforce-boundaries-by-gate-not-by-named-test.md
docs/adr/0003-mutations-return-a-new-state.md
docs/adr/0004-projections-read-the-table-the-dispatcher-printed.md
docs/adr/0005-a-trace-is-the-fold-the-core-already-performs.md
docs/adr/0006-a-module-owns-its-whole-vertical.md
'

printf '%s\n' "$FILES" | while IFS= read -r file; do
    [ -n "$file" ] || continue
    if [ ! -f "$ROOT/$file" ]; then
        printf 'research-pack: FAIL: missing input: %s\n' "$file" >&2
        exit 1
    fi
    cp "$ROOT/$file" "$STAGE/$file"
done

(
    cd "$STAGE"
    find . -type f ! -name MANIFEST.sha256 -print |
        LC_ALL=C sort |
        while IFS= read -r file; do
            sha256sum "$file"
        done
) >"$STAGE/MANIFEST.sha256"

# ZIP stores file timestamps and optional platform metadata by default. Fix the
# former and strip the latter so two builds of one source tree are identical.
# Normalize permissions as well; the caller's umask is not package content.
find "$STAGE" -type d -exec chmod 0755 {} +
find "$STAGE" -type f -exec chmod 0644 {} +
find "$STAGE" -exec touch -t "$FIXED_MTIME" {} +
ZIP_TMP="$TMP_ROOT/$PACK_NAME.zip"
(
    cd "$TMP_ROOT"
    find "$PACK_NAME" -type f -print |
        LC_ALL=C sort |
        zip -X -q "$ZIP_TMP" -@
)

ZIP_HASH=$(sha256sum "$ZIP_TMP" | cut -d ' ' -f 1)
HASH_TMP="$TMP_ROOT/$PACK_NAME.zip.sha256"
printf '%s  %s.zip\n' "$ZIP_HASH" "$PACK_NAME" >"$HASH_TMP"

mv "$ZIP_TMP" "$OUT/$PACK_NAME.zip"
mv "$HASH_TMP" "$OUT/$PACK_NAME.zip.sha256"
printf '%s\n' "$OUT/$PACK_NAME.zip" "$OUT/$PACK_NAME.zip.sha256"
