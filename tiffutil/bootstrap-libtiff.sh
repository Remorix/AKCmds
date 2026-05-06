#!/bin/sh
set -eu

SCRIPT_DIR=$(
    CDPATH= cd -- "$(dirname -- "$0")" && pwd
)

GIT=${GIT:-git}
CMAKE=${CMAKE:-cmake}
LIBTIFF_REPO=${LIBTIFF_REPO:-https://gitlab.com/libtiff/libtiff.git}
LIBTIFF_COMMIT=${LIBTIFF_COMMIT:-b6a17e567f143fab49734a9e09e5bafeb6f97354}
LIBTIFF_SRC=${LIBTIFF_SRC:-$SCRIPT_DIR/.libtiff}
LIBTIFF_BUILD=${LIBTIFF_BUILD:-$SCRIPT_DIR/.libtiff-build}
PATCH_DIR=${PATCH_DIR:-$SCRIPT_DIR/patches}
OVERLAY_DIR=${OVERLAY_DIR:-$SCRIPT_DIR/overlay}
BUILD_TARGET=${BUILD_TARGET:-tiff}
JOBS=${JOBS:-}
CMAKE_ARGS=${CMAKE_ARGS:-}

say() {
    printf '%s\n' "$*"
}

die() {
    say "bootstrap-libtiff.sh: $*" >&2
    exit 1
}

DEFAULT_LIBTIFF_SRC=$SCRIPT_DIR/.libtiff
DEFAULT_LIBTIFF_BUILD=$SCRIPT_DIR/.libtiff-build

if ! command -v "$GIT" >/dev/null 2>&1; then
    die "git not found: $GIT"
fi

if ! command -v "$CMAKE" >/dev/null 2>&1; then
    die "cmake not found: $CMAKE"
fi

if [ ! -d "$PATCH_DIR" ]; then
    die "patch directory not found: $PATCH_DIR"
fi

if [ -e "$LIBTIFF_SRC" ] && [ ! -d "$LIBTIFF_SRC/.git" ]; then
    die "existing path is not a git checkout: $LIBTIFF_SRC"
fi

if [ -d "$LIBTIFF_SRC/.git" ]; then
    CURRENT_HEAD=$("$GIT" -C "$LIBTIFF_SRC" rev-parse HEAD)
    DIRTY_TREE=0
    if ! "$GIT" -C "$LIBTIFF_SRC" diff --quiet --ignore-submodules -- ||
       ! "$GIT" -C "$LIBTIFF_SRC" diff --cached --quiet --ignore-submodules --
    then
        DIRTY_TREE=1
    fi

    if [ "$CURRENT_HEAD" != "$LIBTIFF_COMMIT" ] || [ "$DIRTY_TREE" -ne 0 ]; then
        if [ "$LIBTIFF_SRC" = "$DEFAULT_LIBTIFF_SRC" ] &&
           [ "$LIBTIFF_BUILD" = "$DEFAULT_LIBTIFF_BUILD" ]; then
            say "Resetting generated LibTIFF tree at $LIBTIFF_SRC"
            rm -rf "$LIBTIFF_SRC" "$LIBTIFF_BUILD"
        else
            die "source tree is not a clean checkout of $LIBTIFF_COMMIT: $LIBTIFF_SRC"
        fi
    fi
fi

if [ ! -d "$LIBTIFF_SRC/.git" ]; then
    say "Cloning LibTIFF into $LIBTIFF_SRC"
    "$GIT" clone "$LIBTIFF_REPO" "$LIBTIFF_SRC"
fi

CURRENT_HEAD=$("$GIT" -C "$LIBTIFF_SRC" rev-parse HEAD)
if [ "$CURRENT_HEAD" != "$LIBTIFF_COMMIT" ]; then
    say "Checking out LibTIFF baseline $LIBTIFF_COMMIT"
    "$GIT" -C "$LIBTIFF_SRC" fetch --tags origin
    "$GIT" -C "$LIBTIFF_SRC" checkout --detach "$LIBTIFF_COMMIT"
fi

set -- "$PATCH_DIR"/*.patch
if [ ! -f "$1" ]; then
    die "no patch files found under $PATCH_DIR"
fi

if [ -d "$OVERLAY_DIR" ]; then
    say "Copying overlay files from $OVERLAY_DIR"
    (
        cd "$OVERLAY_DIR"
        find . -type f -print
    ) | while IFS= read -r rel; do
        src=$OVERLAY_DIR/$rel
        dst=$LIBTIFF_SRC/$rel
        mkdir -p "$(dirname "$dst")"
        cp "$src" "$dst"
    done
fi

for patch in "$@"; do
    patch_name=$(basename "$patch")

    if "$GIT" -C "$LIBTIFF_SRC" apply --reverse --check "$patch" >/dev/null 2>&1; then
        say "Patch already applied: $patch_name"
        continue
    fi

    say "Applying patch: $patch_name"
    "$GIT" -C "$LIBTIFF_SRC" apply --check "$patch"
    "$GIT" -C "$LIBTIFF_SRC" apply "$patch"
done

say "Configuring build tree at $LIBTIFF_BUILD"
"$CMAKE" \
    -S "$LIBTIFF_SRC" \
    -B "$LIBTIFF_BUILD" \
    -DBUILD_SHARED_LIBS=OFF \
    -DCMAKE_BUILD_TYPE=RelWithDebInfo \
    -Dccitt=ON \
    -Dpackbits=ON \
    -Dlzw=ON \
    -Dthunder=ON \
    -Dnext=ON \
    -Dlogluv=ON \
    -Dmdi=ON \
    -Dzlib=ON \
    -Dlibdeflate=OFF \
    -Dpixarlog=ON \
    -Djpeg=OFF \
    -Dold-jpeg=OFF \
    -Djpeg12=OFF \
    -Djbig=OFF \
    -Dlerc=OFF \
    -Dlzma=OFF \
    -Dzstd=OFF \
    -Dwebp=OFF \
    -Dcxx=OFF \
    ${CMAKE_ARGS}

say "Building target $BUILD_TARGET"
if [ -n "$JOBS" ]; then
    "$CMAKE" --build "$LIBTIFF_BUILD" --target "$BUILD_TARGET" --parallel "$JOBS"
else
    "$CMAKE" --build "$LIBTIFF_BUILD" --target "$BUILD_TARGET"
fi

say "Done."
say "  source: $LIBTIFF_SRC"
say "  build:  $LIBTIFF_BUILD"
