#!/usr/bin/env bash
# Short test files for the web player engine, one per container/codec case.
# Usage: scripts/make-media-fixtures.sh [out-dir]   (default: .media-fixtures, git-ignored)
set -euo pipefail
OUT="${1:-.media-fixtures}"
mkdir -p "$OUT"
D=40   # seconds: long enough to test seeking
V="testsrc=size=640x360:rate=24:duration=$D"
GOP=(-g 48 -keyint_min 48 -sc_threshold 0)   # a key frame every 2 s
q() { ffmpeg -hide_banner -loglevel error -y "$@"; }
tone() { echo "sine=frequency=$1:sample_rate=48000:duration=$D"; }

# Plays directly everywhere.
q -f lavfi -i "$V" -f lavfi -i "$(tone 440)" -c:v libx264 -pix_fmt yuv420p "${GOP[@]}" -c:a aac -ac 2 -movflags +faststart "$OUT/h264-aac.mp4"
# Plays directly in Chrome; Safari needs a remux.
q -f lavfi -i "$V" -f lavfi -i "$(tone 440)" -c:v libx264 -pix_fmt yuv420p "${GOP[@]}" -c:a aac -ac 2 "$OUT/h264-aac.mkv"
# Audio browsers can't decode: remux converts it to AAC.
q -f lavfi -i "$V" -f lavfi -i "$(tone 523)" -c:v libx264 -pix_fmt yuv420p "${GOP[@]}" -c:a truehd -strict -2 -ac 2 "$OUT/h264-truehd.mkv"
q -f lavfi -i "$V" -f lavfi -i "$(tone 587)" -c:v libx264 -pix_fmt yuv420p "${GOP[@]}" -c:a dca -strict -2 -ac 2 "$OUT/h264-dts.mkv"
q -f lavfi -i "$V" -f lavfi -i "$(tone 659)" -c:v libx264 -pix_fmt yuv420p "${GOP[@]}" -c:a eac3 -ac 6 "$OUT/h264-eac3-51.mkv"
# AVI: no browser plays it directly.
q -f lavfi -i "$V" -f lavfi -i "$(tone 698)" -c:v libx264 -pix_fmt yuv420p "${GOP[@]}" -c:a libmp3lame -ac 2 "$OUT/h264-mp3.avi"
# HDR10 HEVC Main10: direct/remux where HEVC decodes, converted (tone-mapped) elsewhere.
q -f lavfi -i "$V" -f lavfi -i "$(tone 784)" -c:v libx265 -pix_fmt yuv420p10le \
  -x265-params "keyint=48:min-keyint=48:hdr10=1:colorprim=bt2020:transfer=smpte2084:colormatrix=bt2020nc:master-display=G(13250,34500)B(7500,3000)R(34000,16000)WP(15635,16450)L(10000000,1):max-cll=1000,400:log-level=error" \
  -color_primaries bt2020 -color_trc smpte2084 -colorspace bt2020nc -c:a aac -ac 2 "$OUT/hevc-main10-hdr10.mkv"
# AV1 + Opus WebM.
q -f lavfi -i "$V" -f lavfi -i "$(tone 880)" -c:v libsvtav1 -preset 10 -g 48 -c:a libopus -ac 2 "$OUT/av1-opus.webm"
# Two audio tracks (AAC English, AC3 Spanish) and two SRT subtitle tracks.
printf '1\n00:00:01,000 --> 00:00:04,000\nEnglish line one\n\n2\n00:00:20,000 --> 00:00:24,000\nEnglish line at twenty\n\n3\n00:00:33,000 --> 00:00:36,000\nEnglish line at thirty-three\n' > "$OUT/en.srt"
printf '1\n00:00:02,000 --> 00:00:05,000\nLinea uno\n\n2\n00:00:21,000 --> 00:00:25,000\nLinea a los veintiuno\n' > "$OUT/es.srt"
q -f lavfi -i "$V" -f lavfi -i "$(tone 440)" -f lavfi -i "$(tone 330)" -i "$OUT/en.srt" -i "$OUT/es.srt" \
  -map 0:v -map 1:a -map 2:a -map 3:s -map 4:s \
  -c:v libx264 -pix_fmt yuv420p "${GOP[@]}" -c:a:0 aac -ac:a:0 2 -c:a:1 ac3 -ac:a:1 2 -c:s srt \
  -metadata:s:a:0 language=eng -metadata:s:a:0 title="English" -metadata:s:a:1 language=spa -metadata:s:a:1 title="Spanish" \
  -metadata:s:s:0 language=eng -metadata:s:s:1 language=spa -disposition:a:0 default -disposition:s:0 0 \
  "$OUT/multi-audio-subs.mkv"
# Image subtitles (PGS/VobSub) can't be made from text with FFmpeg. For the burn-in
# test, cut a clip from any Blu-ray MKV yourself:
#   ffmpeg -ss 600 -t 30 -i movie.mkv -map 0:v:0 -map 0:s:<pgs> -c copy "$OUT/h264-pgs.mkv"
rm -f "$OUT/en.srt" "$OUT/es.srt"
ls -la "$OUT"
