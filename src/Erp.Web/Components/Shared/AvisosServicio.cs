namespace Erp.Web.Components.Shared;

// Avisos flotantes de la sesión (uno por circuito). Los usa BotonIcono para
// informar un error que la pantalla no atrapó, en lugar de dejar que la
// excepción cierre la conexión interactiva y obligue a recargar la página.
public sealed class AvisosServicio
{
	public event Action<Aviso>? Nuevo;

	public void MostrarError(string texto) => Nuevo?.Invoke(new Aviso(Guid.NewGuid(), texto, true));

	public void MostrarOk(string texto) => Nuevo?.Invoke(new Aviso(Guid.NewGuid(), texto, false));
}

public sealed record Aviso(Guid Id, string Texto, bool EsError);
