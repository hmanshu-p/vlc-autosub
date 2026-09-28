#!/bin/bash
# AutoSub helper: transcribe a video with whisper.cpp into <video>.autosub.srt,
# then have VLC reopen the video at the same spot so the subtitles show up.
# Usage: autosub.sh <video> <lang|auto> <translate:0|1>
# Progress goes to $DIR/status as "state|percent|message" (read by the progress window).

export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
DIR="$HOME/Library/Application Support/vlc-autosub"
STATUS="$DIR/status" LOG="$DIR/last.log" PIDFILE="$DIR/pid"
INPUT="$1" LANG_CODE="${2:-auto}" TRANSLATE="${3:-0}"
OUT="${INPUT%.*}.autosub.srt"

status() { printf '%s|%s|%s\n' "$1" "$2" "$3" > "$STATUS.tmp" && mv "$STATUS.tmp" "$STATUS"; }
fail() { echo "ERROR: $1" >> "$LOG"; status error 0 "$1"; exit 1; }

: > "$LOG"
echo $$ > "$PIDFILE"
WORK="$(mktemp -d)"
CHILD=""
trap 'rm -rf "$WORK" "$PIDFILE"' EXIT
trap '[ -n "$CHILD" ] && kill "$CHILD" 2>/dev/null; status cancelled 0 "Cancelled"; exit 130' TERM INT
status running 0 "Starting"
[ -x "$DIR/autosub-progress" ] && "$DIR/autosub-progress" "$STATUS" "$PIDFILE" "$(basename "$INPUT")" &>/dev/null &

[ -f "$INPUT" ] || fail "Not a local file"
[[ "$LANG_CODE" =~ ^([a-z]{2,3}|auto)$ ]] || fail "Bad language code"
[ -w "$(dirname "$INPUT")" ] || fail "Can't write next to the video"
MODEL="$(ls "$DIR"/models/ggml-*.bin 2>/dev/null | grep -v silero | head -1)"
[ -n "$MODEL" ] || fail "No speech model installed; run install.sh"

# Run a command in the background (so Cancel works promptly), polling its progress.
run_stage() {
  local label="$1" pct_fn="$2"; shift 2
  "$@" & CHILD=$!
  while kill -0 "$CHILD" 2>/dev/null; do status running "$($pct_fn)" "$label"; sleep 2; done
  wait "$CHILD"; local rc=$?; CHILD=""; return $rc
}

# 1. Extract 16 kHz mono audio. For surround mixes keep the centre (dialogue) channel.
DUR="$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$INPUT")"
CH="$(ffprobe -v error -select_streams a:0 -show_entries stream=channels -of csv=p=0 "$INPUT")"
AF=(); [ "${CH:-2}" -ge 6 ] 2>/dev/null && AF=(-af "pan=mono|c0=FC")
ffmpeg_pct() {
  local us; us="$(grep -o 'out_time_us=[0-9]*' "$WORK/ff" 2>/dev/null | tail -1 | cut -d= -f2)"
  awk -v us="${us:-0}" -v d="${DUR:-0}" 'BEGIN { p = d > 0 ? int(us / 1e4 / d) : 0; print (p > 100 ? 100 : p) }'
}
run_stage "Extracting audio" ffmpeg_pct \
  ffmpeg -nostdin -y -v error -i "$INPUT" -map 0:a:0 -vn "${AF[@]}" -ac 1 -ar 16000 \
    -progress "$WORK/ff" -nostats "$WORK/audio.wav" 2>>"$LOG" \
  || fail "Could not extract audio"

# 2. Transcribe. VAD skips music/silence: faster, and fewer made-up lines.
ARGS=(-m "$MODEL" -f "$WORK/audio.wav" -osrt -of "$WORK/subs" -l "$LANG_CODE"
      -pp -ml 84 -sow --suppress-nst -t "$(sysctl -n hw.perflevel0.physicalcpu 2>/dev/null || echo 4)")
[ "$TRANSLATE" = 1 ] && ARGS+=(-tr)
[ -f "$DIR/models/ggml-silero-v5.1.2.bin" ] && ARGS+=(--vad -vm "$DIR/models/ggml-silero-v5.1.2.bin")
whisper_pct() { grep -o 'progress = *[0-9]*' "$WORK/err" 2>/dev/null | tail -1 | grep -o '[0-9]*$' || echo 0; }
run_stage "Transcribing" whisper_pct whisper-cli "${ARGS[@]}" >>"$LOG" 2>"$WORK/err"
RC=$?; cat "$WORK/err" >> "$LOG"
[ $RC -eq 0 ] || fail "Transcription failed (see last.log)"
[ -s "$WORK/subs.srt" ] || fail "No speech found"
cp "$WORK/subs.srt" "$OUT" || fail "Could not save subtitles"
status done 100 "$OUT"

# 3. VLC extensions can't be woken from outside, so reopen the video (VLC picks up
#    the .srt beside it) and seek back, but only if VLC is still on this video.
if pgrep -x VLC >/dev/null; then
  osascript - "$INPUT" >>"$LOG" 2>&1 <<'APPLESCRIPT' &
on run argv
  tell application id "org.videolan.vlc"
    if (path of current item) is not (item 1 of argv) then return "VLC moved on; not reloading"
    set wasPlaying to playing
    set t to current time
    open (POSIX file (item 1 of argv))
    repeat 50 times
      delay 0.1
      if playing and (current time) < t then exit repeat
    end repeat
    set current time to t
    if not wasPlaying then play -- toggles back to paused
    return "Reloaded in VLC at " & t & "s"
  end tell
end run
APPLESCRIPT
  RELOAD=$!
  ( sleep 15; kill "$RELOAD" 2>/dev/null ) &
  wait "$RELOAD" 2>/dev/null
fi
exit 0
