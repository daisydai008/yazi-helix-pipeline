# Yazi + Helix + 视频可视化管线

> 一套**与具体主机无关**的远程终端工作流，在任何 SSH 可达的 Linux 主机上复现：
> 用 Yazi 管理文件、Helix 直接编辑远端文本、终端缩略图预览视频、
> 本地播放器**流式**播放远端视频（不下载、不改源文件）。
>
> 一句话复现：`bash ~/tools/yazi-helix-pipeline/install.sh <user@host>`
>
> 记录于 2026-09-20；最初在一台实验室 Ubuntu 主机（Tailscale）上验证。

## 这条管线是什么

三个独立但组合使用的能力：

| 能力 | 链路 | 说明 |
|---|---|---|
| **编辑** | Yazi `e` → 远端 Helix | 直接编辑远端文件，不经本地中转 |
| **缩略图** | ffmpeg 抽帧 → chafa 终端渲染 | Yazi 右栏静态预览（用户态安装，无 sudo） |
| **播放** | 远端 ffmpeg 实时 remux → SSH stdout 管道 → 本地 mpv | 流式播放，任何 mp4 适用，双端零落盘 |

```text
本地终端 (iTerm2)                            远端 Linux 主机
┌─────────────────────┐   SSH             ┌──────────────────────────┐
│ yazi（远端 TUI）     │ ◄──────────────► │ ~/.config/yazi/*.toml    │
│   e → Helix 编辑    │   直接读写远端    │ ~/.local/bin/hx          │
│   Enter(视频)        │                  │ remote-video-info        │
│    └─ OSC52 ────────┼─► 本地剪贴板      │ ffmpeg/ffprobe           │
│ 本地终端粘贴回车      │                  │ chafa（用户态）           │
│ ssh-play             │ ◄─ stdout 管道 ─ │ ffmpeg 实时 remux        │
│   └─ mpv 窗口播放    │  （不落盘）       │ （源文件零改动）          │
└─────────────────────┘                  └──────────────────────────┘
```

## 安装

前置：本机（macOS + brew + mpv 可装）、远端（Linux + ffmpeg + python3 +
`~/.local/bin/` 下的 yazi 和 hx）、SSH 免密可达。

```bash
bash ~/tools/yazi-helix-pipeline/install.sh <user@host>
# 例: bash ~/tools/yazi-helix-pipeline/install.sh you@100.x.y.z
```

install.sh 做的事（幂等）：

| 侧 | 动作 |
|---|---|
| 远端 | `yazi.toml`/`keymap.toml`/`REMOTE_USAGE.md` → `~/.config/yazi/`；`remote-video-info`、`chafa` wrapper → `~/.local/bin/` |
| 远端 | chafa 用户态依赖：`apt-get download` + `dpkg-deb -x` → `~/.local/opt/yazi-preview/`（**无 sudo**，Ubuntu noble 验证） |
| 远端 | `.bashrc` 追加 `EDITOR=$HOME/.local/bin/hx`（备份 + 去重） |
| 本机 | `ssh-play` → `~/.local/bin/`；默认主机写入 `~/.config/ssh-play/default-host`；`brew install mpv`（若缺） |

## 使用速查

| 场景 | 操作 |
|---|---|
| 编辑文本 | Yazi 选中 → `e`；Helix 中 `i` / `Esc` / `:w` / `:wq` |
| 看视频 | Yazi 选中 → `Enter` → 本地终端粘贴回车（mpv 流式） |
| 换主机播放 | `ssh-play --host user@other /abs/path/x.mp4` |
| 留存副本 | `ssh-play --download /abs/path/x.mp4` |
| 改默认主机 | 重写 `~/.config/ssh-play/default-host` 或重跑 install.sh |

## 踩坑记录（管线本身的 10 条经验）

按实际遇到顺序，与主机无关：

1. **旧 TUI 会话不继承新环境变量**：后加的 `EDITOR` 对已运行的 Yazi 无效——
   opener 直接写死 hx 绝对路径，不依赖 `$EDITOR`；改配置后重启 Yazi。
2. **Yazi 默认视频 opener 是 `mpv`**：远端没装、装了也无法跨 SSH 显示窗口，
   必须替换 `play` opener 为自定义辅助脚本。
3. **chafa 无 sudo 安装**：`apt-get download` + `dpkg-deb -x` 到用户目录，
   wrapper 注入 `LD_LIBRARY_PATH`；缺库逐个补（libavif→libgav1/libyuv）。
4. **brew 版 mpv 不支持 `ssh://` 协议**（未编译 libssh）——
   不能 `mpv ssh://host/file`；走"远端输出到 stdout | mpv -"管道。
5. **`ssh cat file | mpv -` 对普通 mp4 失败**：moov atom 在文件尾，管道不可
   寻址，demuxer 报 partial file。解法：远端
   `ffmpeg -c copy -movflags frag_keyframe+empty_moov -f mp4 -` 实时转封装成
   分片流（无损、不解码、任意 mp4 适用、不留临时文件）。
6. **OSC52 剪贴板**：远端程序经 `\033]52;c;base64\a` 写本地剪贴板；
   iTerm2 需勾选 *Applications in terminal may access clipboard*；
   tmux 内需额外 passthrough 配置（当前链路无 tmux，未处理）。
7. **scp 远端路径**：用 `scp host:/abs/path` + `--`，防交互用 BatchMode。
8. **ffmpegthumbnailer 的库路径**：用户态安装时需 `LD_LIBRARY_PATH`
   指向 `~/.local/lib`（写在 .bashrc）。
9. **二进制文件别进编辑器**：`.h5/.mp4/.usd` 用 h5py/ffprobe 查。
10. **TUI 测试方法**：Python `pty` + `ssh -tt` 可自动化验证
    "Yazi→e→Helix→:wq→远端读回"全链路（无需人肉点屏）。

## 文件清单与回滚

**远端**（本包 `remote/` 与线上一致）：
`~/.config/yazi/{yazi,keymap}.toml + REMOTE_USAGE.md`、
`~/.local/bin/{remote-video-info,chafa}`、`~/.local/opt/yazi-preview/`、
`.bashrc` 两行 EDITOR。回滚：移走 toml、恢复 `~/.bashrc.bak-*`，其余可删。

**本机**（本包 `local/`）：`~/.local/bin/ssh-play`、
`~/.config/ssh-play/default-host`、brew 装的 mpv。回滚：删脚本与配置、
`brew uninstall mpv`。

**全程未做**：sudo 装包、改系统配置、动网络路由、开端口、改项目文件。

## 示例部署：一台 Tailscale 实验室主机

管线与主机无关；以下是首个部署实例的网络要点，换主机时可忽略：

- 用 Tailscale `100.x` 地址，不用校园 LAN `10.19.x.x`（跨网段不可达）。
- Mac App Store 版 Tailscale **没有 `tailscale ssh` 子命令**，普通 `ssh` 即可。
- 该主机有 exit-node 被反复开启的病史：校园网不通时先查
  `tailscale debug prefs | grep ExitNode`，`tailscale set --exit-node=` 修复。

## 验证记录（2026-09-20，首个实例通过）

- Yazi `e` → Helix → `:wq` 远端读回确认（自动化 PTY 测试）
- ffmpeg 抽帧 → chafa 渲染成功
- 流式播放 5.34s 视频完整退出（本地零文件）；`--download` SHA-256 一致
- install.sh 幂等重跑通过
