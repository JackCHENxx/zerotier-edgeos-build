# ZeroTier for Ubiquiti EdgeOS — 32-bit MIPS static builds

Cross-built, statically linked ZeroTier One binaries for EdgeOS routers, rebuilt from upstream releases by GitHub Actions.

| Asset | Devices | Architecture |
| --- | --- | --- |
| `zerotier-one-<tag>-mips64-be` | ER-4 / ER-6P / ER-12 (Octeon) — **preferred** | ELF 64-bit MSB, MIPS64 rel2, static |
| `zerotier-one-<tag>-mips-be` | same devices — 32-bit fallback | ELF 32-bit MSB, MIPS32 rel2, static |
| `zerotier-one-<tag>-mips-le` | ER-X (MT7621) | ELF 32-bit LSB, MIPS32 rel2, static |

ER-4 runs a **64-bit kernel with a 32-bit userland** (`uname -m` = `mips64`, `getconf LONG_BIT` = `32`), and the kernel does accept static MIPS64 (n64) executables — verified with ZeroTier's own mips64 package running on the device. The 64-bit build is preferred there: no `libatomic` relink, native 64-bit atomics, slightly better software-crypto throughput. The 32-bit `mips-be` stays as a fallback in case a firmware build rejects n64.

## Why this repo exists

EdgeOS 3.x runs a **32-bit userland** even on 64-bit MIPS hardware, and upstream stopped shipping 32-bit MIPS packages:

- the Debian `stretch` package repo has no MIPS build for 1.16.x (only `amd64`/`arm64`/`armhf`/`i386`/`ppc64el`);
- ZeroTier's Ubiquiti download page only offers `zerotier-one_mips64.deb`, which targets 64-bit userland devices (UDM/UXG-class), not ER-4/ER-X;
- the last 32-bit MIPS build published upstream is **1.8.4** (2022-03-10).

So anyone wanting a current ZeroTier on these routers has to compile it. This repo does that in CI and publishes the result.

## How it is built

- Source: `zerotier/ZeroTierOne` at the upstream release tag, submodules included.
- Toolchain: Ubuntu 22.04 `gcc-mips-linux-gnu` / `gcc-mipsel-linux-gnu` (GCC 10.3) + `libatomic1-*-cross`.
- Flags: `ZT_UBIQUITI=1 ZT_STATIC=1`, `-DZT_NO_TYPE_PUNNING` is added by upstream's Makefile for MIPS.
- 32-bit MIPS: upstream's link step fails (`__atomic_*_8` undefined), so the workflow relinks the objects manually with `-latomic -lpthread`. 64-bit MIPS links cleanly and needs no libatomic.
- Every build is checked with `file` / `readelf`: ELF32 MIPS32 rel2, **no `NEEDED` entries** (fully static, so the router's glibc version does not matter).

Builds run daily at 02:17 UTC, and on demand via **Actions → build → Run workflow**. A GitHub release is created only when the upstream tag has no release here yet.

## Install on the router

Pick the asset for your model. On the router:

```sh
# 1. back up the current binary
cp -p /usr/sbin/zerotier-one /config/zerotier-one.bak
zerotier-cli info          # note the node ID and version

# 2. upload and sanity-check the architecture
#    (from your workstation: scp zerotier-one-<tag>-mips-be jchen@<router>:/config/)
file /config/zerotier-one-<tag>-mips-be
#    must say: ELF 32-bit MSB executable, MIPS ... statically linked

# 3. swap it in
sudo /etc/init.d/zerotier-one stop        # or: service zerotier-one stop
sudo cp /config/zerotier-one-<tag>-mips-be /usr/sbin/zerotier-one
sudo chmod 755 /usr/sbin/zerotier-one
sudo ln -sf zerotier-one /usr/sbin/zerotier-cli
sudo ln -sf zerotier-one /usr/sbin/zerotier-idtool
sudo /etc/init.d/zerotier-one start
zerotier-cli info                         # should show the new version
zerotier-cli listnetworks                 # existing networks intact?

# 4. verify connectivity
zerotier-cli listpeers                    # DIRECT or RELAYER peers
ping <another member's ZeroTier IP>
```

**Rollback**: stop the service, copy `/config/zerotier-one.bak` back to `/usr/sbin/zerotier-one`, start it.

Notes:

- On **ER-X**, do not use the first free `ethN` as the ZeroTier interface name — community reports of switch breakage / losing the router. Use a high number such as `eth10`.
- The binary's default home directory may not match EdgeOS's `/var/lib/zerotier-one`; if identity/network config is not picked up, start it with `-D`: `zerotier-one -d -D/var/lib/zerotier-one`, or copy the old home directory contents to the new path.
- **Firmware upgrades** can restore the stock binary. Keep a copy in `/config` and re-apply after upgrades, or re-run this repo's install step.
- Verify the download against the `.sha256` / `.md5` published next to each asset.

## Status and caveats

- CI proves the binaries **compile, link statically and match the target architecture**. It does **not** boot them on a router. Test one device (ideally the one you can physically reach) before rolling out.
- ZeroTier is single-threaded with software crypto; neither ER-4 (Octeon, no AES-NI) nor ER-X (MT7621) is fast. A newer version does not fix throughput.
- If you already run Tailscale for remote access and WireGuard for site-to-site traffic, ZeroTier is a third, optional path — upgrading it is a housekeeping task, not a connectivity fix.

## License

ZeroTier One is distributed under the **Business Source License 1.1** (see `LICENSE.txt` upstream). The assets here are unmodified builds of that source; the same license applies. Source: <https://github.com/zerotier/ZeroTierOne>.
