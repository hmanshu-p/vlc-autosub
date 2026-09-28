# AutoSub for VLC

Generate subtitles for any movie in VLC with one click. It works offline and is powered by [whisper.cpp](https://github.com/ggml-org/whisper.cpp).

AutoSub doesn't play the movie through. It transcribes the audio track on your Mac's GPU, much faster than real time: a 2-hour film takes about 10 minutes on Apple Silicon. When it's done, the subtitles appear in the movie you're watching, at the spot where you left off.

## Install

You need **macOS**, [**VLC**](https://www.videolan.org) and [**Homebrew**](https://brew.sh). Then paste this into Terminal:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/hmanshu-p/vlc-autosub/main/install.sh)
```

The installer asks you to pick **one** speech model. Only that model is downloaded:

| # | Model | Size | |
|---|---|---|---|
| 1 | tiny | 74 MB | Fastest, rough |
| 2 | base | 141 MB | Fast; fine for clear speech |
| 3 | small-q5_1 | 181 MB | Good balance for small disks |
| 4 | medium-q5_0 | 514 MB | Accurate, slower |
| 5 | **large-v3-turbo-q5_0** | 547 MB | **Recommended**, and the default |
| 6 | large-v3-turbo | 1.5 GB | Slightly more accurate |
| 7 | large-v3 | 2.9 GB | Most accurate, slowest |

It also installs `whisper-cpp` and `ffmpeg` with Homebrew if they're missing.

## Use

1. Restart VLC and open a movie.
2. From the menu bar, choose **VLC → Extensions → AutoSub - Generate Subtitles**.
3. Pick the spoken language (or leave it on Auto-detect), then click **Generate subtitles**.

A small window shows progress and has a Cancel button. You can keep watching while it works. When it's done, VLC reloads the movie with the subtitles at the same spot. They're saved as `<movie>.autosub.srt` next to the video, so VLC picks them up next time too.

**Translate to English** turns speech in any language into English subtitles.

## Update

Installed copies don't update themselves. To get the latest version, run:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/hmanshu-p/vlc-autosub/main/install.sh) --update
```

This keeps your current model, so nothing big is downloaded. Then restart VLC. [Watch the repo](https://github.com/hmanshu-p/vlc-autosub) (Watch → Custom → Releases) to hear about new versions.

## Change model or uninstall

Run the installer again and pick a different number. The old model is deleted, so only one is ever kept. You can also skip the menu:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/hmanshu-p/vlc-autosub/main/install.sh) --model base
bash <(curl -fsSL https://raw.githubusercontent.com/hmanshu-p/vlc-autosub/main/install.sh) --uninstall
```

If you cloned the repo, `git pull && ./install.sh --update` updates, and `./install.sh` does the rest.

## Troubleshooting

- **AutoSub isn't in the Extensions menu:** quit VLC completely (⌘Q) and reopen it.
- **The movie shows its old subtitles:** choose the `autosub` track from VLC's **Subtitles** menu.
- **Something failed:** the details are in `~/Library/Application Support/vlc-autosub/last.log`.

## Privacy and security

- Audio never leaves your Mac. The only network use is the one-time install.
- Models are downloaded from the official whisper.cpp repository on Hugging Face, and each file is checked against a SHA-256 checksum pinned in `install.sh`.
- Everything installs into your user folder, with no `sudo`. The installer is short, so read it before running it: [`install.sh`](install.sh).

## How it works

| File | What it does |
|---|---|
| [`autosub.lua`](autosub.lua) | The VLC extension: a dialog that starts the job |
| [`autosub.sh`](autosub.sh) | Pulls out the audio (ffmpeg), transcribes it (whisper.cpp), saves the `.srt` and asks VLC to reload |
| [`progress.swift`](progress.swift) | The floating progress window |

VLC 3 extensions can't run timers or be woken from outside. So progress is shown in a separate window, and the finished subtitles are loaded by re-opening the movie. That causes a one-second blip.

## License

MIT
