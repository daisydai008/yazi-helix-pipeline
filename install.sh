#!/usr/bin/env bash
# install.sh — set up the Yazi + Helix + video-visualization pipeline between
# this Mac and any SSH-reachable Linux host.
#
#   bash install.sh <user@host>
#
# Idempotent: re-running only overwrites this pipeline's own files.
set -euo pipefail
cd "$(dirname "$0")"

target="${1:-}"
if [[ -z "$target" ]]; then
  echo "Usage: bash install.sh <user@host>   e.g. you@100.x.y.z" >&2
  exit 2
fi
echo "== Target host: $target"

# ---------- 0. prerequisites ----------
ssh -o BatchMode=yes -o ConnectTimeout=10 "$target" true \
  || { echo "FAIL: cannot SSH to $target (check VPN/Tailscale and keys)"; exit 1; }
ssh "$target" 'command -v ffmpeg ffprobe python3 >/dev/null' \
  || { echo "FAIL: remote needs ffmpeg, ffprobe, python3"; exit 1; }
ssh "$target" 'test -x ~/.local/bin/yazi && test -x ~/.local/bin/hx' \
  || echo "NOTE: yazi/hx not found in ~/.local/bin on remote (install them yourself; config still deployed)"

# ---------- 1. remote: yazi config + helpers ----------
echo "== Deploy remote yazi config and helpers"
ssh "$target" 'mkdir -p ~/.config/yazi ~/.local/bin'
scp -q remote/yazi.toml remote/keymap.toml remote/REMOTE_USAGE.md "$target":~/.config/yazi/
scp -q remote/remote-video-info remote/chafa "$target":~/.local/bin/
ssh "$target" 'chmod 755 ~/.local/bin/remote-video-info ~/.local/bin/chafa'

# ---------- 2. remote: chafa user-space deps (no sudo; tested on Ubuntu noble) ----------
if ssh "$target" '~/.local/bin/chafa --version >/dev/null 2>&1'; then
  echo "== chafa already works, skipping deps"
else
  echo "== Install chafa user-space deps (apt download + extract, no sudo)"
  ssh "$target" 'set -e
    d=$(mktemp -d ~/.cache/yazi-deps.XXXXXX); cd "$d"
    apt-get download chafa libchafa0t64 libavif16 libgav1-1 libyuv0
    mkdir -p ~/.local/opt/yazi-preview
    for p in ./*.deb; do dpkg-deb -x "$p" ~/.local/opt/yazi-preview; done
    ~/.local/bin/chafa --version >/dev/null'
fi

# ---------- 3. remote: EDITOR in .bashrc (dedup + backup) ----------
ssh "$target" 'set -e
  if ! grep -q "local/bin/hx" ~/.bashrc; then
    cp -p ~/.bashrc ~/.bashrc.bak-$(date +%Y%m%d-%H%M%S)
    printf "\nexport EDITOR=\"\$HOME/.local/bin/hx\"\nexport VISUAL=\"\$EDITOR\"\n" >> ~/.bashrc
    echo "   .bashrc: EDITOR appended (backup saved)"
  else
    echo "   .bashrc: EDITOR already set, skipping"
  fi'

# ---------- 4. local Mac: ssh-play + default host + compat ----------
echo "== Install local ssh-play"
mkdir -p ~/.local/bin ~/.config/ssh-play
cp local/ssh-play ~/.local/bin/ssh-play
chmod 755 ~/.local/bin/ssh-play
printf '%s\n' "$target" > ~/.config/ssh-play/default-host
chmod 600 ~/.config/ssh-play/default-host
# backward compatibility for the older command name

if ! command -v mpv >/dev/null; then
  echo "== Install mpv (brew)"
  brew install mpv
fi

echo
echo "✅ Done. Verify:"
echo "  1) ssh $target, run yazi, press e on a text file -> Helix -> :wq"
echo "  2) press Enter on an .mp4 -> command copied to clipboard"
echo "  3) in a LOCAL Mac terminal: paste -> mpv streams the video"
echo "     (clipboard needs iTerm2: Applications in terminal may access clipboard)"
