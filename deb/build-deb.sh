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
chmod 755 "$ROOT"

ZT="$ROOT/config/zerotier-one"
mkdir -p "$ROOT/DEBIAN" "$ZT/bin" "$ROOT/etc/init.d"
cp -a "$SRC/zerotier-one" "$SRC/lib" "$SRC/lib64" "$ZT/"

# Upstream selects CLI / idtool mode by matching argv[0], so keep same-named
# entry points next to the real binary; the wrappers under bin/ drive them.
ln -s zerotier-one "$ZT/zerotier-cli"
ln -s zerotier-one "$ZT/zerotier-idtool"

cat > "$ZT/bin/zerotier-cli" <<'EOS'
#!/bin/sh
# Same arguments as official zerotier-cli; port and token default to this home.
ROOT=/config/zerotier-one
HOMED=$ROOT/home
has_p=0; has_t=0
for a in "$@"; do
    case "$a" in
        -p*) has_p=1 ;;
        -T*) has_t=1 ;;
    esac
done
port=-p9993
[ $has_p -eq 1 ] && port=""
[ -r "$HOMED/zerotier-one.port" ] && [ $has_p -eq 0 ] && port="-p$(cat "$HOMED/zerotier-one.port")"
token=""
if [ $has_t -eq 0 ] && [ -r "$HOMED/authtoken.secret" ]; then
    token="-T$(cat "$HOMED/authtoken.secret")"
fi
exec "$ROOT/lib64/ld.so.1" --library-path "$ROOT/lib" "$ROOT/zerotier-cli" \
    -q $port $token "$@"
EOS

cat > "$ZT/bin/zerotier-idtool" <<'EOS'
#!/bin/sh
# Same arguments as official zerotier-idtool.
ROOT=/config/zerotier-one
exec "$ROOT/lib64/ld.so.1" --library-path "$ROOT/lib" "$ROOT/zerotier-idtool" "$@"
EOS

cat > "$ZT/bin/zerotier-one" <<'EOS'
#!/bin/sh
# Same arguments as official zerotier-one; defaults to the /config data dir.
ROOT=/config/zerotier-one
has_d=0
for a in "$@"; do
    case "$a" in
        -d|-d*) has_d=1 ;;
    esac
done
if [ $has_d -eq 1 ]; then
    exec "$ROOT/lib64/ld.so.1" --library-path "$ROOT/lib" "$ROOT/zerotier-one" "$@"
fi
exec "$ROOT/lib64/ld.so.1" --library-path "$ROOT/lib" "$ROOT/zerotier-one" -d "$ROOT/home" "$@"
EOS

cat > "$ROOT/etc/init.d/zerotier-one" <<'EOS'
#!/bin/sh
# SysV-style service control, equivalent to `service zerotier-one <action>`
# on hosts that provide the `service` wrapper.
HOOK=/config/scripts/post-config.d/zerotier-one-start.sh
case "$1" in
    start)
        [ -x "$HOOK" ] && "$HOOK" || exit 1
        ;;
    stop)
        pkill -f "zerotier-one -p9993" >/dev/null 2>&1 || true
        ;;
    restart)
        pkill -f "zerotier-one -p9993" >/dev/null 2>&1 || true
        sleep 1
        [ -x "$HOOK" ] && "$HOOK" || exit 1
        ;;
    status)
        if ps ax 2>/dev/null | grep -v grep | grep -q "zerotier-one -p9993"; then
            echo "zerotier-one is running"
        else
            echo "zerotier-one is stopped"
            exit 3
        fi
        ;;
    *)
        echo "usage: $0 {start|stop|restart|status}" >&2
        exit 1
        ;;
esac
exit 0
EOS

chmod 755 "$ZT/bin/zerotier-cli" "$ZT/bin/zerotier-idtool" "$ZT/bin/zerotier-one"
chmod 755 "$ROOT/etc/init.d/zerotier-one"
cp "$HERE/DEBIAN/control" "$HERE/DEBIAN/postinst" "$HERE/DEBIAN/prerm" "$HERE/DEBIAN/postrm" "$ROOT/DEBIAN/"

chmod 755 "$ZT/zerotier-one" "$ZT/lib64/ld.so.1"
chmod 755 "$ROOT/DEBIAN/postinst" "$ROOT/DEBIAN/prerm" "$ROOT/DEBIAN/postrm"
chmod 644 "$ROOT/DEBIAN/control"

dpkg-deb --build --root-owner-group "$ROOT" "$OUT"
dpkg-deb -I "$OUT" | head -5
sha256sum "$OUT"
