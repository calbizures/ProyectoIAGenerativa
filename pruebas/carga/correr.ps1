# Prueba de carga con 10 usuarios simultáneos (Windows, requiere sqlcmd).
# Uso (autenticación de SQL):     .\correr.ps1 -Servidor localhost -Usuario sa -Clave '...'
#     (autenticación de Windows): .\correr.ps1 -Servidor localhost
param(
	[string]$Servidor = 'localhost',
	[string]$Usuario = '',
	[string]$Clave = '',
	[int]$Operaciones = 100
)
$ErrorActionPreference = 'Stop'
Set-Location $PSScriptRoot
$auth = if ($Usuario) { @('-U', $Usuario, '-P', $Clave) } else { @('-E') }
$base = @('-S', $Servidor) + $auth + @('-C', '-I', '-f', '65001', '-b')

function Sql([string[]]$argumentos) { & sqlcmd @base @argumentos; if ($LASTEXITCODE) { throw "sqlcmd terminó con error $LASTEXITCODE" } }
function Valor([string]$consulta) { (& sqlcmd @base -h -1 -W -Q "SET NOCOUNT ON; $consulta" | Out-String).Trim() }
function EnParalelo([scriptblock]$argumentosDe) {
	$procesos = 1..10 | ForEach-Object {
		Start-Process sqlcmd -ArgumentList ($base + (& $argumentosDe $_)) -NoNewWindow -PassThru
	}
	$procesos | Wait-Process
}

Write-Host '1. Preparar (usuarios prueba01-10, caja 2, foto de existencias)'
Sql @('-i', '01_preparar.sql', '-o', 'preparar.log')

Write-Host '2. Línea base: cada perfil solo, uno tras otro (30 operaciones)'
$t = Measure-Command { 1..10 | ForEach-Object { Sql @('-i', '02_usuario.sql', '-v', 'CORRIDA=solo', "U=$_", 'N=30', '-o', 'NUL') } }
Write-Host ("   {0:N1} s" -f $t.TotalSeconds)

Write-Host "3. Los 10 usuarios al mismo tiempo ($Operaciones operaciones cada uno)"
$t = Measure-Command { EnParalelo { param($u) @('-i', '02_usuario.sql', '-v', 'CORRIDA=simultaneo', "U=$u", "N=$Operaciones", '-o', 'NUL') } }
Write-Host ("   {0:N1} s" -f $t.TotalSeconds)

Write-Host '4. Sobreventa: los 10 piden a la vez las últimas unidades de un producto'
$pro = Valor 'SELECT TOP 1 pro_id FROM erp_db.dbo.inv_producto_existencia_bodega WHERE bod_id = 1 AND existencia >= 10 ORDER BY existencia'
$exi = [int](Valor "SELECT CAST(existencia AS INT) FROM erp_db.dbo.inv_producto_existencia_bodega WHERE bod_id = 1 AND pro_id = $pro")
$cant = [math]::Ceiling($exi / 5)
$hora = Valor 'SELECT CONVERT(VARCHAR(8), DATEADD(SECOND, 5, GETDATE()), 108)'
Write-Host "   producto $pro con $exi unidades; cada usuario pide $cant"
EnParalelo { param($u) @('-i', '03_ultimas_unidades.sql', '-v', "U=$u", "PRO=$pro", "CANT=$cant", "HORA=$hora", '-o', 'NUL') }

Write-Host '5. Verificación -> resultado.txt'
Sql @('-i', '04_verificar.sql', '-W', '-s', ' | ', '-o', 'resultado.txt')
Get-Content resultado.txt
