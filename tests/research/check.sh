#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
PACK_NAME=kofun-boot-framework-research-2026-08-02

for tool in unzip cmp sha256sum mktemp; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        printf 'research-pack: FAIL: required tool not found: %s\n' "$tool" >&2
        exit 1
    fi
done

TMP_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/kofun-boot-research-check.XXXXXX")
trap 'rm -rf "$TMP_ROOT"' EXIT HUP INT TERM
FIRST="$TMP_ROOT/first"
SECOND="$TMP_ROOT/second"
EXTRACTED="$TMP_ROOT/extracted"
mkdir -p "$FIRST" "$SECOND" "$EXTRACTED"

sh "$ROOT/scripts/build-research-pack.sh" "$FIRST" >/dev/null
env -i PATH="$PATH" LC_ALL=C TZ=Pacific/Kiritimati \
    sh "$ROOT/scripts/build-research-pack.sh" "$SECOND" >/dev/null

cmp "$FIRST/$PACK_NAME.zip" "$SECOND/$PACK_NAME.zip" || {
    printf 'research-pack: FAIL: ZIP changed under hostile environment\n' >&2
    exit 1
}
cmp "$FIRST/$PACK_NAME.zip.sha256" "$SECOND/$PACK_NAME.zip.sha256" || {
    printf 'research-pack: FAIL: ZIP digest changed under hostile environment\n' >&2
    exit 1
}

(
    cd "$FIRST"
    sha256sum -c "$PACK_NAME.zip.sha256" >/dev/null
)
unzip -tqq "$FIRST/$PACK_NAME.zip"
unzip -qq "$FIRST/$PACK_NAME.zip" -d "$EXTRACTED"

for file in \
    README.md \
    MANIFEST.sha256 \
    docs/research/SPRING_FASTAPI_GIN.md \
    docs/research/MODULAR_MONOLITH_DDD.md \
    docs/architecture/FDDD.md \
    docs/ROADMAP.md; do
    if [ ! -f "$EXTRACTED/$PACK_NAME/$file" ]; then
        printf 'research-pack: FAIL: ZIP omitted %s\n' "$file" >&2
        exit 1
    fi
done

(
    cd "$EXTRACTED/$PACK_NAME"
    sha256sum -c MANIFEST.sha256 >/dev/null
)

# Prove the manifest rejects a changed dossier. This is deliberately confined
# to the mktemp tree and verifies the failure direction of the evidence gate.
printf '\ncorrupted\n' >>"$EXTRACTED/$PACK_NAME/docs/research/SPRING_FASTAPI_GIN.md"
if (
    cd "$EXTRACTED/$PACK_NAME"
    sha256sum -c MANIFEST.sha256 >/dev/null 2>&1
); then
    printf 'research-pack: FAIL: manifest accepted a changed dossier\n' >&2
    exit 1
fi

printf 'research-pack: PASS: deterministic ZIP, hostile env, manifest, break test\n'
