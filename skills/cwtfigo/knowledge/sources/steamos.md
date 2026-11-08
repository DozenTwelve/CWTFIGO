# SteamOS (Steam Deck)

- Patch notes: https://store.steampowered.com/news/app/1675200
- The root filesystem is a read-only image. Anything installed with pacman or changed under `/` is wiped by the next system update. Only `$HOME` persists: use Flatpak (`--user`), AppImage, distrobox, or tools that install into `$HOME`.
- System updates come through the Steam client, not pacman.
- Big space users live under `~/.local/share/Steam/steamapps/`: `shadercache/` and `compatdata/` (Proton prefixes, often left behind after a game is uninstalled; saves may live inside them, so check before deleting).
