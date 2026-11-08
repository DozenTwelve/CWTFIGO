# Debian / Ubuntu

- Upgrade with `apt-get upgrade --with-new-pkgs` (what `apt upgrade` does): plain `apt-get upgrade` keeps back anything needing a new dependency and can split a library from its daemon (fwupd vs libfwupd2). `dist-upgrade` may remove packages: list first.
- `apt-mark showhold` before upgrading. Holds are usually deliberate (kernel and NVIDIA driver moving together); respect them.
- `apt list --upgradable` is only as fresh as the last `apt-get update`, which needs root.
- `autoremove` cascades; show `apt-get -s autoremove` before confirming.
- Ubuntu security notices: https://ubuntu.com/security/notices
