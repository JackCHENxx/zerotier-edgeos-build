# ZeroTier One for Ubiquiti EdgeOS (ER-4 / MIPS64)

Self-contained `.deb` packages for EdgeRouter 4 / 6P / 12, rebuilt from upstream ZeroTier One releases by GitHub Actions and verified on real hardware.

| Asset | Target |
| --- | --- |
| `zerotier-one-edgeos_<tag>_all.deb` | ER-4 / ER-6P / ER-12 (Octeon, MIPS64 n64) |

Each release ships a `.sha256` next to the package.

## Install

```sh
sudo curl -fLO https://github.com/JackCHENxx/zerotier-edgeos-build/releases/latest/download/zerotier-one-edgeos_1.16.2_all.deb
sudo dpkg -i zerotier-one-edgeos_1.16.2_all.deb
```

The package installs to `/config/zerotier-one` (binary + bundled glibc runtime), writes an auto-start hook to `/config/scripts/post-config.d/zerotier-one-start.sh`, and starts the daemon. It does not touch `/usr/sbin` or the router's system libc.

Verify:

```sh
sudo netstat -lnup 2>/dev/null | grep 9993
```

Join a network (the virtual interface only appears after joining):

```sh
sudo /config/zerotier-one/lib64/ld.so.1 --library-path /config/zerotier-one/lib \
  /config/zerotier-one/zerotier-one -q -p9993 -T$(cat /config/zerotier-one/home/authtoken.secret) join <network-id>
```

## Lifecycle

- `sudo dpkg -r zerotier-one-edgeos` — stop, remove auto-start hook, **keep** identity in `/config/zerotier-one/home`
- `sudo dpkg -P zerotier-one-edgeos` — purge, removes `/config/zerotier-one` entirely
- Firmware upgrade: copy the deb to `/config/data/firstboot/install-packages/`; EdgeOS replays it after upgrading

## Why dynamic, not static

Upstream stopped shipping MIPS packages at 1.12 citing "problems building against libraries that require atomic memory access operations"; the last 32-bit MIPS build is 1.8.4 (2022-03).

Static rebuilds of 1.16.x compile and link fine, but **crash on real hardware** right after `Starting V6 Control Plane`:

```
do_page_fault(): sending SIGSEGV for invalid read access from 0000000000000000
epc = 0000000000000000
ra  = 0000000120203ea8   # inside std::condition_variable::wait
```

The cause is the cross toolchain, not ZeroTier One: a 20-line `std::thread` + `std::condition_variable` program built statically with Ubuntu 22.04's GCC 10.3 / glibc 2.35 MIPS compiler crashes identically, while the dynamic build runs. `-O0`, `-fPIC`, `-no-pie`, `-fno-optimize-sibling-calls` and `--no-relax` all fail.

So this repo builds **dynamically** and bundles the runtime, starting the binary through its own loader (paths relative to `/config/zerotier-one`):

```sh
lib64/ld.so.1 --library-path lib zerotier-one -p9993 -d /config/zerotier-one/home
```

Verified on a Shanghai ER-4: `ZeroTier One version 1.16.2 build 0 (platform 1 arch 6)`, `join` → `200 join OK`, a `zt`-prefixed tap interface, address assigned by the network, UDP 9993 listening on all interfaces.

## How it is built

CI (`.github/workflows/build.yml`, daily + manual): resolves the upstream tag → installs `g++-mips64-linux-gnuabi64` → builds dynamic (`ZT_UBIQUITI=1`, `LDFLAGS="-no-pie -Wl,-z,noexecstack"`, no `-static`) → collects the 5 runtime libraries from the cross sysroot → packages with `deb/build-deb.sh`.

Local reproduction:

```sh
make -j"$(nproc)" ZT_UBIQUITI=1 \
  CC=mips64-linux-gnuabi64-gcc CXX=mips64-linux-gnuabi64-g++ \
  CFLAGS="-O2 -fstack-protector" CXXFLAGS="-O2" \
  LDFLAGS="-no-pie -Wl,-z,noexecstack" zerotier-one
```

Then follow `deb/build-deb.sh` for the layout (`lib64/ld.so.1` + `lib/{libc,libm,libstdc++,libgcc_s}.so*`).

## Limitations

- **ER-X (MT7621, 32-bit little-endian) is not covered** — it needs a separate `mipsel` dynamic build, not yet produced or tested.
- ZeroTier One is single-threaded with software crypto; MIPS has no AES acceleration. A newer version does not fix throughput.
- If you already use Tailscale for remote access and WireGuard for site-to-site, ZeroTier One is a third optional path.

## License

ZeroTier One 1.16.0+ core (`node/`, `include/`) and service (`service/`, `osdep/`) are **MPL 2.0**; the network controller is under a separate commercial license and is not included (`ZT_UBIQUITI=1` builds exclude it). Source: <https://github.com/zerotier/ZeroTierOne>.
