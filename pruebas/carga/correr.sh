#!/bin/bash
# Prueba de carga con 10 usuarios simultáneos (Linux/macOS, requiere sqlcmd).
# Uso: SERVIDOR=localhost USUARIO=sa CLAVE='...' ./correr.sh [operaciones por usuario, 100 por omisión]
set -e
cd "$(dirname "$0")"
N=${1:-100}
SERVIDOR=${SERVIDOR:-localhost}
if [ -n "$USUARIO" ]; then AUTH=(-U "$USUARIO" -P "$CLAVE"); else AUTH=(-E); fi
sql() { sqlcmd -S "$SERVIDOR" "${AUTH[@]}" -C -I -f 65001 -b "$@"; }

echo "1. Preparar (usuarios prueba01-10, caja 2, foto de existencias)"
sql -i 01_preparar.sql -o preparar.log

usuario() { sql -i 02_usuario.sql -v CORRIDA="$1" U="$2" N="$3" -o /dev/null; }

echo "2. Línea base: cada perfil solo, uno tras otro (30 operaciones)"
t0=$(date +%s); for u in $(seq 1 10); do usuario solo "$u" 30; done; echo "   $(( $(date +%s) - t0 )) s"

echo "3. Los 10 usuarios al mismo tiempo ($N operaciones cada uno)"
t0=$(date +%s); for u in $(seq 1 10); do usuario simultaneo "$u" "$N" & done; wait; echo "   $(( $(date +%s) - t0 )) s"

echo "4. Sobreventa: los 10 piden a la vez las últimas unidades de un producto"
PRO=$(sql -h -1 -W -Q "SET NOCOUNT ON; SELECT TOP 1 pro_id FROM erp_db.dbo.inv_producto_existencia_bodega WHERE bod_id = 1 AND existencia >= 10 ORDER BY existencia" | tr -d '[:space:]')
EXI=$(sql -h -1 -W -Q "SET NOCOUNT ON; SELECT CAST(existencia AS INT) FROM erp_db.dbo.inv_producto_existencia_bodega WHERE bod_id = 1 AND pro_id = $PRO" | tr -d '[:space:]')
CANT=$(( (EXI + 4) / 5 ))
HORA=$(sql -h -1 -W -Q "SET NOCOUNT ON; SELECT CONVERT(VARCHAR(8), DATEADD(SECOND, 5, GETDATE()), 108)" | tr -d '[:space:]')
echo "   producto $PRO con $EXI unidades; cada usuario pide $CANT"
for u in $(seq 1 10); do sql -i 03_ultimas_unidades.sql -v U="$u" PRO="$PRO" CANT="$CANT" HORA="$HORA" -o /dev/null & done; wait

echo "5. Verificación → resultado.txt"
sql -i 04_verificar.sql -W -s ' | ' -o resultado.txt
cat resultado.txt
