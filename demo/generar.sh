#!/usr/bin/env bash
# Genera la demo completa: tomas del recorrido, música, video final (alta
# calidad y versión liviana < 30 MB), guion y presentación.
#
# Requisitos (ver README.md): base erp_db recién instalada (00 a 74) en un
# contenedor de SQL Server, la aplicación corriendo en ERP_URL, ffmpeg,
# Node.js y Python 3 con numpy y scipy.
#
#   SA_PASSWORD=... ./generar.sh
set -euo pipefail
cd "$(dirname "$0")"

: "${SA_PASSWORD:?Defina SA_PASSWORD con la clave de sa del contenedor de SQL Server}"
export SALIDA="${SALIDA:-$PWD/salida}"
export FFMPEG="${FFMPEG:-ffmpeg}"
mkdir -p "$SALIDA"
ERP_URL="${ERP_URL:-http://localhost:5273}"
curl -sf -o /dev/null "$ERP_URL/login" || { echo "La aplicación no responde en $ERP_URL." >&2; exit 1; }

[ -d node_modules ] || npm install --no-audit --no-fund

# SIN_GRABAR=1 reutiliza las tomas ya grabadas (por ejemplo, después de
# regrabar una sección con «node grabar.js rrhh») y solo vuelve a montar.
if [ -z "${SIN_GRABAR:-}" ]; then
  echo "1/5 Grabando el recorrido..."
  rm -rf "$SALIDA/tomas"
  node grabar.js
fi
if ls "$SALIDA"/tomas/error_*.png >/dev/null 2>&1; then
  echo "Alguna sección falló (ver $SALIDA/tomas/error_*.png); reinstale la base y vuelva a correr." >&2
  exit 1
fi

echo "2/5 Uniendo tomas y componiendo la música..."
ls "$SALIDA"/tomas/*.mp4 | sort | sed "s/'/'\\\\''/g; s/^/file '/; s/$/'/" > "$SALIDA/lista.txt"
"$FFMPEG" -loglevel error -y -f concat -safe 0 -i "$SALIDA/lista.txt" -c copy "$SALIDA/video_sin_audio.mp4"
# (ffmpeg -i sin salida termina con código 1: solo interesa su reporte)
SEG=$({ "$FFMPEG" -i "$SALIDA/video_sin_audio.mp4" 2>&1 || true; } | sed -n 's/.*Duration: \([0-9:.]*\).*/\1/p' | awk -F: '{print $1*3600+$2*60+$3}')
python3 musica.py "$SEG" "$SALIDA/musica.wav"

echo "3/5 Montando el video..."
FINAL="$SALIDA/Demo ERP - Servicios Informaticos Integrados.mp4"
"$FFMPEG" -loglevel error -y -i "$SALIDA/video_sin_audio.mp4" -i "$SALIDA/musica.wav" -map 0:v -map 1:a -c:v copy \
  -af "loudnorm=I=-18:TP=-2:LRA=7" -c:a aac -b:a 192k -ar 48000 -shortest -movflags +faststart "$FINAL"
# Versión liviana para compartir (≈ 330 kb/s de video).
(cd "$SALIDA" && "$FFMPEG" -loglevel error -y -i "$FINAL" -c:v libx264 -preset slow -b:v 330k -pass 1 -an -f mp4 /dev/null \
  && "$FFMPEG" -loglevel error -y -i "$FINAL" -c:v libx264 -preset slow -b:v 330k -pass 2 -c:a aac -b:a 128k \
     -movflags +faststart "Demo ERP - liviano.mp4" && rm -f ffmpeg2pass-0.log*)
# Versión 720p, nítida y de tamaño moderado, para enviar.
"$FFMPEG" -loglevel error -y -i "$FINAL" -vf scale=1280:720 -c:v libx264 -preset slow -crf 26 -c:a aac -b:a 128k \
  -movflags +faststart "$SALIDA/Demo ERP - para enviar (720p).mp4"
# Versión de menos de 30 MB para adjuntar o subir donde hay límite de tamaño.
(cd "$SALIDA" && "$FFMPEG" -loglevel error -y -i "$FINAL" -vf scale=1280:720 -c:v libx264 -preset slow -b:v 140k -pass 1 -an -f mp4 /dev/null \
  && "$FFMPEG" -loglevel error -y -i "$FINAL" -vf scale=1280:720 -c:v libx264 -preset slow -b:v 140k -pass 2 -c:a aac -b:a 56k \
     -movflags +faststart "Demo ERP - completo (para compartir).mp4" && rm -f ffmpeg2pass-0.log*)
rm -f "$SALIDA/video_sin_audio.mp4"

echo "4/5 Guion..."
python3 guion.py

echo "5/5 Capturas y presentación..."
node capturas.js
node deck.js

echo "Listo. Archivos en $SALIDA"
