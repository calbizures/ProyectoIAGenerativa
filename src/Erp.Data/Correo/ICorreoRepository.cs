namespace Erp.Data.Correo;

public interface ICorreoRepository
{
	Task<CorreoConfiguracion?> ConsultarConfiguracionAsync(int ciaId);
	// claveCifrada null conserva la guardada; borrarClave la quita.
	Task GuardarConfiguracionAsync(CorreoConfiguracion configuracion, string? claveCifrada, bool borrarClave, int? usuarioAccionId);
	Task RegistrarAsync(CorreoBitacora envio);
	Task<IReadOnlyList<CorreoEnviado>> ConsultarEnviosAsync(string? tipo, int? referenciaId, int cantidad = 20);
}
