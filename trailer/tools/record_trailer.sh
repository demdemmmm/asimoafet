#!/bin/zsh
# Fragmanı Godot Movie Maker ile 1920x1080 / 30 FPS kaydeder ve MP4'e (H.264 + AAC) çevirir.
# Kullanım: trailer/tools/record_trailer.sh [Godot yolu]
set -e
GODOT="${1:-/Applications/Godot.app/Contents/MacOS/Godot}"
PROJ="$(cd "$(dirname "$0")/../.." && pwd)"
OUT="$PROJ/trailer/export"
mkdir -p "$OUT"
# Kayıt süresince geçici ayar: pencere 1920x1080, MJPEG kalitesi yüksek (sonra silinir).
printf '[editor]\n\nmovie_writer/mjpeg_quality=0.92\n\n[display]\n\nwindow/size/window_width_override=1920\nwindow/size/window_height_override=1080\n' > "$PROJ/override.cfg"
trap 'rm -f "$PROJ/override.cfg"' EXIT
"$GODOT" --path "$PROJ" --write-movie "$OUT/asimo_afet_trailer.avi" --fixed-fps 30 --always-on-top res://trailer/trailer_main.tscn
swiftc -O "$PROJ/trailer/tools/avi2mp4.swift" -o "$OUT/avi2mp4"
"$OUT/avi2mp4" "$OUT/asimo_afet_trailer.avi" "$OUT/asimo_afet_trailer.mp4"
rm -f "$OUT/avi2mp4" "$OUT/asimo_afet_trailer.avi"
echo "Hazır: $OUT/asimo_afet_trailer.mp4"
