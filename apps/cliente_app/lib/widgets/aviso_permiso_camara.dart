import 'package:flutter/material.dart';

import '../services/permiso_camara_service.dart';

/// Aviso de permiso de cámara denegado.
///
/// Cuando el permiso quedó denegado permanentemente el diálogo del sistema ya
/// no aparece, así que la única salida es ir a los ajustes de la app. Ese es
/// el mismo criterio que aplica el escáner de QR, compartido aquí para no
/// duplicar el texto ni los botones en cada pantalla de captura.
class AvisoPermisoCamara extends StatelessWidget {
  final EstadoPermisoCamara estado;
  final VoidCallback onReintentar;
  final String mensaje;
  final VoidCallback? onCerrar;

  const AvisoPermisoCamara({
    super.key,
    required this.estado,
    required this.onReintentar,
    this.onCerrar,
    this.mensaje = 'Sin acceso a la cámara no es posible tomar la foto.',
  });

  bool get _esPermanente => estado == EstadoPermisoCamara.denegadoPermanente;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.no_photography, size: 56, color: Colors.grey[500]),
            const SizedBox(height: 12),
            const Text(
              'Permiso de cámara requerido',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              _esPermanente
                  ? 'El permiso de cámara fue denegado permanentemente. '
                      'Habilítelo desde la configuración del dispositivo.'
                  : mensaje,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: Colors.grey[600]),
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (onCerrar != null) ...[
                  TextButton(
                    onPressed: onCerrar,
                    child: const Text('Volver'),
                  ),
                  const SizedBox(width: 8),
                ],
                ElevatedButton(
                  onPressed:
                      _esPermanente ? () => abrirConfiguracion() : onReintentar,
                  child: Text(
                    _esPermanente ? 'Abrir configuración' : 'Reintentar',
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
