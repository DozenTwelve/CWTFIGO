# Arch Linux

- Read https://archlinux.org/news/ before `pacman -Syu`. Items there need manual intervention; skipping them is how upgrades break. `paru -Pw` (or `yay -Pw`) prints the items newer than the installed packages.
- Refresh the keyring first after a long gap: `pacman -Sy archlinux-keyring`, then `-Syu`.
- AUR packages are unreviewed: read the PKGBUILD diff on update (`paru -Sua --review`).
- After upgrading: merge `.pacnew` files; `paccache -rk2` keeps two versions in the cache.
- Orphan removal (`pacman -Qdtq | pacman -Rns -`) removes more than it lists once dependencies cascade. Show the full list before confirming.
- Arch Wiki (https://wiki.archlinux.org) is the reference for most Linux desktops, not only Arch.
