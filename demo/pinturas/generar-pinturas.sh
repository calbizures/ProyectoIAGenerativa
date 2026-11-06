#!/usr/bin/env bash
# Video comercial para una tienda de pinturas, listo para WhatsApp (720p,
# menos de 16 MB, unos 3 minutos): graba las tomas, compone la música y
# comprime en dos pasadas.
#
# Requisitos: una base de demostración recién instalada (01 al 86) en un
# contenedor de SQL Server DESECHABLE con datos-pinturas.sql aplicado (ver
# README.md), la aplicación corriendo en ERP_URL contra esa base, ffmpeg,
# Node.js con Playwright y Python 3 con numpy y scipy.
#
#   SA_PASSWORD=... SQL_CONTENEDOR=erp-pinturas ./pinturas/generar-pinturas.sh
#
# SOLO_MONTAJE=1 vuelve a montar sin grabar. Si el navegador muestra las fechas como mm/dd/aaaa, corra con LANGUAGE=es.
set -euo pipefail
cd "$(dirname "$0")/.."

: "${SA_PASSWORD:?Defina SA_PASSWORD con la clave de sa del contenedor de SQL Server}"
export SALIDA="${SALIDA:-$PWD/salida}"
export LANGUAGE="${LANGUAGE:-es}"
FFMPEG="${FFMPEG:-ffmpeg}"
PYTHON="${PYTHON:-python3}"
DIR="$SALIDA/pinturas"
VELOCIDAD="${VELOCIDAD:-1.1}"     # se acelera un poco para quedar en ~3 minutos
MB_MAXIMO="${MB_MAXIMO:-15}"      # WhatsApp acepta hasta 16 MB
mkdir -p "$DIR"
ERP_URL="${ERP_URL:-http://localhost:5273}"
curl -sf -o /dev/null "$ERP_URL/login" || { echo "La aplicación no responde en $ERP_URL." >&2; exit 1; }

echo "1/4 Grabando el recorrido..."
if [ -z "${SOLO_MONTAJE:-}" ]; then   # SOLO_MONTAJE=1 reutiliza las tomas ya grabadas
  rm -rf "$DIR/tomas"
  node pinturas/grabar-pinturas.js
fi
if ls "$DIR"/tomas/error_*.png >/dev/null 2>&1; then
  echo "Alguna sección falló (ver $DIR/tomas/error_*.png); prepare la base de nuevo y vuelva a correr." >&2
  exit 1
fi

echo "2/4 Uniendo tomas..."
ls "$DIR"/tomas/*.mp4 | sort | sed "s/'/'\\\\''/g; s/^/file '/; s/$/'/" > "$DIR/lista.txt"
"$FFMPEG" -loglevel error -y -f concat -safe 0 -i "$DIR/lista.txt" \
  -vf "setpts=PTS/$VELOCIDAD,scale=1280:720:flags=lanczos,fps=30" -c:v libx264 -preset veryfast -crf 16 -an "$DIR/video_sin_audio.mp4"
SEG=$({ "$FFMPEG" -i "$DIR/video_sin_audio.mp4" 2>&1 || true; } | sed -n 's/.*Duration: \([0-9:.]*\).*/\1/p' | awk -F: '{print $1*3600+$2*60+$3}')

echo "3/4 Música original ($SEG s)..."
"$PYTHON" musica.py "$SEG" "$DIR/musica.wav"

echo "4/4 Comprimiendo para WhatsApp..."
AUDIO_K=64
VIDEO_K=$(awk -v s="$SEG" -v mb="$MB_MAXIMO" -v a="$AUDIO_K" 'BEGIN { printf "%d", (mb * 8192 / s) * 0.96 - a }')
FINAL="$DIR/Pinturas del Valle - demo ERP (WhatsApp).mp4"
(cd "$DIR" \
  && "$FFMPEG" -loglevel error -y -i video_sin_audio.mp4 -c:v libx264 -preset slow -tune stillimage -b:v "${VIDEO_K}k" \
       -pix_fmt yuv420p -profile:v high -pass 1 -an -f mp4 /dev/null \
  && "$FFMPEG" -loglevel error -y -i video_sin_audio.mp4 -i musica.wav -map 0:v -map 1:a \
       -c:v libx264 -preset slow -tune stillimage -b:v "${VIDEO_K}k" -maxrate "$((VIDEO_K * 2))k" -bufsize "$((VIDEO_K * 4))k" \
       -pix_fmt yuv420p -profile:v high -pass 2 \
       -af "afade=t=in:d=1,afade=t=out:st=$(awk -v s="$SEG" 'BEGIN{print s-3}'):d=3,loudnorm=I=-18:TP=-2:LRA=7" -c:a aac -b:a "${AUDIO_K}k" -ar 44100 -ac 2 \
       -shortest -movflags +faststart "$FINAL" \
  && rm -f ffmpeg2pass-0.log* video_sin_audio.mp4 lista.txt)

echo "Listo: $FINAL ($(du -h "$FINAL" | cut -f1))"
