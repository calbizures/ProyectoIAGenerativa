#!/usr/bin/env bash
# Instala la base desde cero, la vuelve a instalar encima (todos los scripts
# deben poder correrse otra vez) y corre todas las pruebas, unitarias y de
# integración. Es lo mismo que hace la integración continua.
#
# Uso: pruebas/ci/pruebas_completas.sh [nombre_contenedor] [puerto]
set -euo pipefail

CONTENEDOR="${1:-erp-pruebas}"
PUERTO="${2:-1433}"
RAIZ="$(cd "$(dirname "$0")/../.." && pwd)"

salida="$(bash "$RAIZ/pruebas/ci/instalar_base.sh" "$CONTENEDOR" "$PUERTO")"
echo "$salida" | grep -v '^ERP_PRUEBAS_BD='
export ERP_PRUEBAS_BD="$(echo "$salida" | grep '^ERP_PRUEBAS_BD=' | cut -d= -f2-)"
CLAVE="$(echo "$ERP_PRUEBAS_BD" | sed -E 's/.*Password=([^;]*);.*/\1/')"

echo "Segunda instalación sobre la misma base..."
INSTALADOR="$(cd "$RAIZ/database" && ls instalar_01_al_*.sql | sort -V | tail -1)"
if ! docker exec "$CONTENEDOR" /opt/mssql-tools18/bin/sqlcmd -C -S localhost -U sa -P "$CLAVE" -f 65001 -b -I \
	-i "/tmp/scripts/$INSTALADOR" > instalacion_segunda.log 2>&1; then
	echo "La segunda instalación falló. Últimas líneas:"
	tail -40 instalacion_segunda.log
	exit 1
fi
echo "Segunda instalación terminada."

dotnet test "$RAIZ/src/Erp.Tests/Erp.Tests.csproj" --nologo
