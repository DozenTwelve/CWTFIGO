# OpenWrt

- Don't mass-upgrade packages with `opkg upgrade`: it breaks ABI between kernel modules and packages and can fill the flash. Upgrade the whole firmware image (sysupgrade) instead.
- Flash is tiny and `/tmp` is RAM. Nothing is left on the router; scripts are piped over SSH.
- Release notes and security advisories: https://openwrt.org/releases/start , https://openwrt.org/advisory/start
