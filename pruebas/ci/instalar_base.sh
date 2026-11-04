#!/usr/bin/env bash
# Levanta un SQL Server 2022 en Docker, crea erp_db e instala del 01 al NN
# (instalar_01_al_NN.sql) con los datos de prueba. Lo usa la integración
# continua (.github/workflows/ci.yml) y sirve igual en una computadora con
# Docker para correr las pruebas de integración desde cero.
#
# Uso: pruebas/ci/instalar_base.sh [nombre_contenedor] [puerto]
# Al terminar escribe la cadena de conexión en la salida y, si existe
# $GITHUB_ENV, la deja en ERP_PRUEBAS_BD para los pasos siguientes.
#
# La contraseña de sa se genera al azar en cada corrida: el contenedor es
# desechable y no hay ninguna clave guardada en el repositorio.
set -euo pipefail

CONTENEDOR="${1:-erp-pruebas}"
PUERTO="${2:-1433}"
RAIZ="$(cd "$(dirname "$0")/../.." && pwd)"
CLAVE="Ci#$(openssl rand -hex 12)Aa1"
SQLCMD="/opt/mssql-tools18/bin/sqlcmd"

docker rm -f "$CONTENEDOR" >/dev/null 2>&1 || true
docker run -d --name "$CONTENEDOR" -e ACCEPT_EULA=Y -e MSSQL_SA_PASSWORD="$CLAVE" -e MSSQL_PID=Developer \
	-p "$PUERTO:1433" mcr.microsoft.com/mssql/server:2022-latest >/dev/null

echo "Esperando a SQL Server..."
for _ in $(seq 1 90); do
	if docker exec "$CONTENEDOR" "$SQLCMD" -C -S localhost -U sa -P "$CLAVE" -Q "SELECT 1" >/dev/null 2>&1; then
		break
	fi
	sleep 2
done
docker exec "$CONTENEDOR" "$SQLCMD" -C -S localhost -U sa -P "$CLAVE" -Q "SELECT @@VERSION" >/dev/null

# Copia los scripts y apunta :setvar RUTA a la carpeta dentro del contenedor.
docker exec "$CONTENEDOR" mkdir -p /tmp/scripts
docker cp "$RAIZ/database/." "$CONTENEDOR:/tmp/scripts/"
INSTALADOR="$(cd "$RAIZ/database" && ls instalar_01_al_*.sql | sort -V | tail -1)"
docker exec -u 0 "$CONTENEDOR" sed -i 's|^:setvar RUTA .*|:setvar RUTA "/tmp/scripts/"|' "/tmp/scripts/$INSTALADOR"

echo "Creando erp_db..."
docker exec "$CONTENEDOR" "$SQLCMD" -C -S localhost -U sa -P "$CLAVE" -f 65001 -b -I -i /tmp/scripts/00_crear_base_datos.sql >/dev/null
echo "Instalando con $INSTALADOR..."
inicio=$(date +%s)
if ! docker exec "$CONTENEDOR" "$SQLCMD" -C -S localhost -U sa -P "$CLAVE" -f 65001 -b -I -i "/tmp/scripts/$INSTALADOR" > instalacion.log 2>&1; then
	echo "La instalación falló. Últimas líneas:"
	tail -40 instalacion.log
	exit 1
fi
echo "Instalación terminada en $(( $(date +%s) - inicio )) s."

CADENA="Server=localhost,$PUERTO;Database=erp_db;User Id=sa;Password=$CLAVE;TrustServerCertificate=True;"
if [[ -n "${GITHUB_ENV:-}" ]]; then
	echo "::add-mask::$CLAVE"
	echo "ERP_PRUEBAS_BD=$CADENA" >> "$GITHUB_ENV"
fi
echo "ERP_PRUEBAS_BD=$CADENA"
