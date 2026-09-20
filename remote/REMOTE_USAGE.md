# Yazi + Helix over SSH

Quick reference deployed by ~/tools/yazi-helix-pipeline/install.sh.

## Edit text

Highlight a text file, press `e` (explicit Helix binding), or Enter for
recognized text files. Helix: `i` insert, `Esc` normal, `:w` save,
`:wq` save+quit. The preview pane is read-only. Don't edit binary files
(.h5, .mp4, .usd) in Helix.

## Video: stream, don't download

Select a video, press Enter. You get ffprobe metadata and a ready command,
auto-copied to the local clipboard (OSC 52):

    ~/.local/bin/ssh-play /abs/path/video.mp4

Paste it into a LOCAL terminal, Enter -> mpv opens and plays.

How it works: remote ffmpeg remuxes the MP4 into a streamable fragmented
stream on stdout -> SSH pipe -> local mpv. Nothing is written to disk on
either side; the remote file is never modified. Any MP4 works.

Requirements: `mpv` on the local machine; `~/.config/ssh-play/default-host`
(created by install.sh) or `--host user@host`. Clipboard copy needs the
terminal's OSC-52 permission (iTerm2: Settings > General > Selection).
Fallback: `ssh-play --download /abs/path/video.mp4` keeps a local copy.

Yazi's right pane shows a static frame thumbnail (ffmpeg -> chafa); that's
a preview, not playback.

## Files / rollback

Remote: ~/.config/yazi/{yazi,keymap}.toml + this file,
~/.local/bin/{remote-video-info,chafa}, ~/.local/opt/yazi-preview/,
two EDITOR lines in ~/.bashrc (backup: ~/.bashrc.bak-*).

~/.config/ssh-play/default-host, mpv via brew.

No sudo, no system changes, no network ports opened.
