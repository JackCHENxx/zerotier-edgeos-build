#!/bin/sh
# Build the self-contained EdgeOS .deb from a directory containing
# zerotier-one, lib/ and lib64/ (lib64 holds ld.so.1).
#
# usage: ./build-deb.sh <source-dir> [output.deb]
set -e

SRC=${1:?usage: build-deb.sh <dir with zerotier-one, lib and lib64>}
OUT=${2:-zerotier-one-edgeos_1.16.2_all.deb}

[ -x "$SRC/zerotier-one" ] || { echo "missing $SRC/zerotier-one" >&2; exit 1; }
[ -f "$SRC/lib64/ld.so.1" ] || { echo "missing $SRC/lib64/ld.so.1" >&2; exit 1; }
[ -f "$SRC/lib/libc.so.6" ] || { echo "missing $SRC/lib/libc.so.6" >&2; exit 1; }

HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(mktemp -d)
trap 'rm -rf "$ROOT"' EXIT

mkdir -p "$ROOT/DEBIAN" "$ROOT/config/zerotier-one"
cp -a "$SRC/zerotier-one" "$SRC/lib" "$SRC/lib64" "$ROOT/config/zerotier-one/"
cp "$HERE/DEBIAN/control" "$HERE/DEBIAN/postinst" "$HERE/DEBIAN/prerm" "$HERE/DEBIAN/postrm" "$ROOT/DEBIAN/"

chmod 755 "$ROOT/config/zerotier-one/zerotier-one" "$ROOT/config/zerotier-one/lib64/ld.so.1"
chmod 755 "$ROOT/DEBIAN/postinst" "$ROOT/DEBIAN/prerm" "$ROOT/DEBIAN/postrm"
chmod 644 "$ROOT/DEBIAN/control"

dpkg-deb --build --root-owner-group "$ROOT" "$OUT"
dpkg-deb -I "$OUT" | head -5
sha256sum "$OUT"
