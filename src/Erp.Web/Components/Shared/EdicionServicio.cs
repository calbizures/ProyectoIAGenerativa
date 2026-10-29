namespace Erp.Web.Components.Shared;

// Avisa a los botones Guardar bloqueados (después de grabar) que el usuario
// pulsó Editar o Nuevo en la pantalla: se vuelven a habilitar. Uno por circuito.
public sealed class EdicionServicio
{
	public event Action? Reabierta;

	public void Reabrir() => Reabierta?.Invoke();
}
