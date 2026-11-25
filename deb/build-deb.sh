#!/bin/sh
# Build the self-contained EdgeOS .deb from a directory containing
# zt-dyn, ztlib/lib and ztlib/lib64.
#
# usage: ./build-deb.sh <source-dir> [output.deb]
set -e

SRC=${1:?usage: build-deb.sh <dir with zt-dyn and ztlib>}
OUT=${2:-zerotier-one-edgeos_1.16.2_all.deb}

[ -x "$SRC/zt-dyn" ] || { echo "missing $SRC/zt-dyn" >&2; exit 1; }
[ -f "$SRC/ztlib/lib64/ld.so.1" ] || { echo "missing $SRC/ztlib/lib64/ld.so.1" >&2; exit 1; }

HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(mktemp -d)
trap 'rm -rf "$ROOT"' EXIT

mkdir -p "$ROOT/DEBIAN" "$ROOT/config/zt"
cp -a "$SRC/zt-dyn" "$SRC/ztlib" "$ROOT/config/zt/"
cp "$HERE/DEBIAN/control" "$HERE/DEBIAN/postinst" "$HERE/DEBIAN/prerm" "$HERE/DEBIAN/postrm" "$ROOT/DEBIAN/"

chmod 755 "$ROOT/config/zt/zt-dyn" "$ROOT/config/zt/ztlib/lib64/ld.so.1"
chmod 755 "$ROOT/DEBIAN/postinst" "$ROOT/DEBIAN/prerm" "$ROOT/DEBIAN/postrm"
chmod 644 "$ROOT/DEBIAN/control"

dpkg-deb --build --root-owner-group "$ROOT" "$OUT"
dpkg-deb -I "$OUT" | head -5
sha256sum "$OUT"
