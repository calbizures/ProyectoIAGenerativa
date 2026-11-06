#!/usr/bin/env bash
# Genera el video corto de las novedades de la Fase 4: tomas, música, video
# final (alta calidad y versión liviana), guion y presentación.
#
# Requisitos (ver README.md): base erp_db recién instalada (00 a 71) en un
# contenedor de SQL Server, la aplicación corriendo en ERP_URL, ffmpeg,
# Node.js y Python 3 con numpy y scipy.
#
#   SA_PASSWORD=... ./generar-fase4.sh
set -euo pipefail
cd "$(dirname "$0")"

: "${SA_PASSWORD:?Defina SA_PASSWORD con la clave de sa del contenedor de SQL Server}"
export SALIDA="${SALIDA:-$PWD/salida}"
export FFMPEG="${FFMPEG:-ffmpeg}"
F4="$SALIDA/fase4"
mkdir -p "$F4"
ERP_URL="${ERP_URL:-http://localhost:5273}"
curl -sf -o /dev/null "$ERP_URL/login" || { echo "La aplicación no responde en $ERP_URL." >&2; exit 1; }

[ -d node_modules ] || npm install --no-audit --no-fund

echo "1/5 Grabando el recorrido..."
rm -rf "$F4/tomas"
node grabar-fase4.js
if ls "$F4"/tomas/error_*.png >/dev/null 2>&1; then
  echo "Alguna sección falló (ver $F4/tomas/error_*.png); reinstale la base y vuelva a correr." >&2
  exit 1
fi

echo "2/5 Uniendo tomas y componiendo la música..."
ls "$F4"/tomas/*.mp4 | sort | sed "s/'/'\\\\''/g; s/^/file '/; s/$/'/" > "$F4/lista.txt"
"$FFMPEG" -loglevel error -y -f concat -safe 0 -i "$F4/lista.txt" -c copy "$F4/video_sin_audio.mp4"
# (ffmpeg -i sin salida termina con código 1: solo interesa su reporte)
SEG=$({ "$FFMPEG" -i "$F4/video_sin_audio.mp4" 2>&1 || true; } | sed -n 's/.*Duration: \([0-9:.]*\).*/\1/p' | awk -F: '{print $1*3600+$2*60+$3}')
python3 musica.py "$SEG" "$F4/musica.wav"

echo "3/5 Montando el video..."
FINAL="$F4/ERP - Novedades Fase 4.mp4"
"$FFMPEG" -loglevel error -y -i "$F4/video_sin_audio.mp4" -i "$F4/musica.wav" -map 0:v -map 1:a -c:v copy \
  -af "loudnorm=I=-18:TP=-2:LRA=7" -c:a aac -b:a 192k -ar 48000 -shortest -movflags +faststart "$FINAL"
# Versión liviana para compartir por correo o chat.
(cd "$F4" && "$FFMPEG" -loglevel error -y -i "$FINAL" -c:v libx264 -preset slow -b:v 330k -pass 1 -an -f mp4 /dev/null \
  && "$FFMPEG" -loglevel error -y -i "$FINAL" -c:v libx264 -preset slow -b:v 330k -pass 2 -c:a aac -b:a 128k \
     -movflags +faststart "ERP - Novedades Fase 4 (liviano).mp4" && rm -f ffmpeg2pass-0.log*)
rm -f "$F4/video_sin_audio.mp4"

echo "4/5 Guion..."
python3 guion.py fase4

echo "5/5 Capturas y presentación..."
node capturas-fase4.js
node deck-fase4.js

echo "Listo. Archivos en $F4"
