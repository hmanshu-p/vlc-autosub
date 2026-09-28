#!/bin/bash
# AutoSub installer (macOS). From a clone:  ./install.sh
# Or without cloning:
#   bash <(curl -fsSL https://raw.githubusercontent.com/hmanshu-p/vlc-autosub/main/install.sh)
# Options:  --update         get the latest AutoSub, keeping your current model
#           --model <name>   install or switch to a model without the menu
#           --uninstall      remove AutoSub and its model
set -euo pipefail

REPO="https://raw.githubusercontent.com/hmanshu-p/vlc-autosub/main"
HF="https://huggingface.co"
DIR="$HOME/Library/Application Support/vlc-autosub"
EXT="$HOME/Library/Application Support/org.videolan.vlc/lua/extensions"

# name | size | notes | sha256 (downloads are verified against these)
MODELS=(
  "tiny|74 MB|Fastest, rough|be07e048e1e599ad46341c8d2a135645097a538221678b7acdd1b1919c6e1b21"
  "base|141 MB|Fast; fine for clear speech|60ed5bc3dd14eea856493d334349b405782ddcaf0028d4b5df4088345fba2efe"
  "small-q5_1|181 MB|Good balance for small disks|ae85e4a935d7a567bd102fe55afc16bb595bdb618e11b2fc7591bc08120411bb"
  "medium-q5_0|514 MB|Accurate, slower|19fea4b380c3a618ec4723c3eef2eb785ffba0d0538cf43f8f235e7b3b34220f"
  "large-v3-turbo-q5_0|547 MB|Best balance (recommended)|394221709cd5ad1f40c46e6031ca61bce88931e6e088c188294c6d5a55ffa7e2"
  "large-v3-turbo|1.5 GB|Slightly more accurate|1fc70f774d38eb169993ac391eea357ef47c88757ef72ee5943879b7e8e2bc69"
  "large-v3|2.9 GB|Most accurate, slowest|64d182b440b98d5203c4f9bd541544d84c605196c4f7b845dfa11fb23594d1e2"
)
DEFAULT=5
VAD_SHA=29940d98d42b91fbd05ce489f3ecf7c72f0a42f027e4875919a28fb4c04ea2cf

say() { printf '%s\n' "$*"; }
die() { say "✗ $*" >&2; exit 1; }
field() { cut -d'|' -f"$2" <<<"$1"; }

# Download $1 to $2 and check its SHA-256 is $3.
fetch() {
  curl -fL --progress-bar -o "$2.part" "$1" || { rm -f "$2.part"; die "Download failed: $1"; }
  [ "$(shasum -a 256 "$2.part" | cut -d' ' -f1)" = "$3" ] || { rm -f "$2.part"; die "Checksum mismatch: $1"; }
  mv "$2.part" "$2"
}

if [ "${1:-}" = "--uninstall" ]; then
  read -r -p "Remove AutoSub and its speech model? [y/N] " yn </dev/tty || yn=n
  [[ "$yn" = [yY]* ]] || exit 0
  rm -rf "$DIR" "$EXT/autosub.lua"
  say "Removed. (whisper-cpp and ffmpeg stay; remove with: brew uninstall whisper-cpp ffmpeg)"
  exit 0
fi

[ "$(uname)" = Darwin ] || die "AutoSub supports macOS only."
command -v brew >/dev/null || die "Homebrew is required: https://brew.sh"
[ -d /Applications/VLC.app ] || say "Note: VLC isn't in /Applications. Get it from https://www.videolan.org"

# --- Choose one model (--update keeps the installed one).
CHOICE=""
if [ "${1:-}" = "--update" ]; then
  for m in "${MODELS[@]}"; do [ -f "$DIR/models/ggml-$(field "$m" 1).bin" ] && CHOICE="$m"; done
  [ -n "$CHOICE" ] || say "No model installed yet, so let's pick one."
fi
if [ -n "$CHOICE" ]; then
  :
elif [ "${1:-}" = "--model" ]; then
  for m in "${MODELS[@]}"; do [ "$(field "$m" 1)" = "${2:-}" ] && CHOICE="$m"; done
  [ -n "$CHOICE" ] || die "Unknown model '${2:-}'. Choose one of: $(for m in "${MODELS[@]}"; do printf '%s ' "$(field "$m" 1)"; done)"
elif [ -r /dev/tty ]; then
  say "Choose a speech model (bigger = more accurate, slower). You can switch later."
  i=1
  for m in "${MODELS[@]}"; do
    printf '  %d) %-20s %7s  %s\n' $i "$(field "$m" 1)" "$(field "$m" 2)" "$(field "$m" 3)"
    i=$((i + 1))
  done
  while [ -z "$CHOICE" ]; do
    read -r -p "Number [$DEFAULT]: " n </dev/tty || n=""
    n="${n:-$DEFAULT}"
    if [[ "$n" =~ ^[1-7]$ ]]; then CHOICE="${MODELS[$((n - 1))]}"; else say "Enter a number from 1 to 7."; fi
  done
else
  CHOICE="${MODELS[$((DEFAULT - 1))]}"
fi
NAME="$(field "$CHOICE" 1)"

# --- Dependencies.
for pkg in whisper-cpp ffmpeg; do
  brew list --formula "$pkg" &>/dev/null || { say "Installing $pkg…"; brew install --quiet "$pkg"; }
done

# --- Model (only one is kept) and the small voice-activity model.
mkdir -p "$DIR/models" "$EXT"
MODEL_FILE="$DIR/models/ggml-$NAME.bin"
if [ ! -f "$MODEL_FILE" ]; then
  say "Downloading $NAME ($(field "$CHOICE" 2))…"
  fetch "$HF/ggerganov/whisper.cpp/resolve/main/ggml-$NAME.bin" "$MODEL_FILE" "$(field "$CHOICE" 4)"
fi
find "$DIR/models" -name 'ggml-*.bin' ! -name "ggml-$NAME.bin" ! -name 'ggml-silero-*' -delete
VAD="$DIR/models/ggml-silero-v5.1.2.bin"
[ -f "$VAD" ] || fetch "$HF/ggml-org/whisper-vad/resolve/main/ggml-silero-v5.1.2.bin" "$VAD" "$VAD_SHA"

# --- App files: use the ones next to this script, or fetch them from the repo.
SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd || true)"
if [ ! -f "$SRC/autosub.lua" ]; then
  SRC="$(mktemp -d)"
  trap 'rm -rf "$SRC"' EXIT
  for f in autosub.lua autosub.sh progress.swift; do curl -fsSL -o "$SRC/$f" "$REPO/$f"; done
fi
install -m 755 "$SRC/autosub.sh" "$DIR/autosub.sh"
install -m 644 "$SRC/autosub.lua" "$EXT/autosub.lua"
if xcrun --find swiftc &>/dev/null; then
  xcrun swiftc -O -o "$DIR/autosub-progress" "$SRC/progress.swift" 2>/dev/null \
    || say "Couldn't build the progress window; AutoSub works without it."
else
  say "Skipping the progress window (install Xcode tools with: xcode-select --install)"
fi

say ""
say "✓ AutoSub is up to date, using the $NAME model."
say "  Restart VLC, open a movie, then choose VLC → Extensions → AutoSub."
