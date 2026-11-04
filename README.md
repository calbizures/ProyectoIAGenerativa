# ERP para PYMEs de Guatemala

Sistema administrativo y contable en Blazor Server (.NET 8), Dapper y SQL
Server 2022: ventas con factura electrónica (FEL), compras, inventario,
cuentas por cobrar y por pagar, caja y bancos con conciliación,
contabilidad, activos fijos y recursos humanos (IGSS), en español e inglés.

## Estructura

| Carpeta | Contenido |
|---|---|
| `src/Erp.Web` | Aplicación web (pantallas, reportes, FEL, seguridad). |
| `src/Erp.Data` | Acceso a datos: repositorios Dapper sobre procedimientos almacenados. |
| `src/Erp.Tests` | Pruebas automáticas (xUnit). |
| `database` | Scripts numerados de la base y el instalador `instalar_01_al_NN.sql`; ver `database/README.md`. |
| `database/servidor` | Scripts del servidor para producción: respaldo, login de la aplicación, usuarios de demostración. |
| `pruebas/ci` | Instalación de la base en Docker y corrida completa de pruebas. |
| `pruebas/carga` | Pruebas de carga. |
| `demo` | Guion y herramientas de los videos de demostración. |

## Pruebas

```bash
dotnet test src/Erp.Tests
```

- **Unitarias** (siempre corren): contraseñas PBKDF2, validación de NIT y
  CUI, armado del XML de FEL (montos con IVA, frase de exención, largos de
  SAT, Adenda) y paginación.
- **De integración** (contra una base instalada): controles de integridad,
  Cuentas por cobrar y por pagar cuadradas con su cuenta contable, plan de
  pagos de compras al contado y al crédito, inicio de sesión y bloqueo por
  intentos. Corren cuando la variable `ERP_PRUEBAS_BD` tiene la cadena de
  conexión; sin ella se saltan. Las que cambian datos lo hacen dentro de una
  transacción que se revierte.

Corrida completa, como en la integración continua (requiere Docker): instala
la base desde cero en un SQL Server desechable, la vuelve a instalar encima y
corre todas las pruebas.

```bash
bash pruebas/ci/pruebas_completas.sh
```

## Integración continua

`.github/workflows/ci.yml` corre en cada push y pull request: compila con
las advertencias como errores, revisa que ningún paquete tenga
vulnerabilidades conocidas y hace la corrida completa de pruebas.
