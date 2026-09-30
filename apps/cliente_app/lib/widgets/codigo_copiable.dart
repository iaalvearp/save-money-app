import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Muestra un código que la persona puede copiar con un toque.
///
/// El código va en grande porque hay que leerlo en el mostrador o pasarlo a
/// otra app. Copiarlo es el atajo para quien quiere mandarlo por mensaje o
/// pegarlo en otro lado, así que el ícono va justo al lado y no escondido en
/// un menú.
class CodigoCopiable extends StatelessWidget {
  /// El texto a mostrar y a copiar.
  final String codigo;

  /// Cómo se ve el código. El que se usa en el diálogo de Flash.
  final TextStyle? estiloCodigo;

  const CodigoCopiable({
    super.key,
    required this.codigo,
    this.estiloCodigo,
  });

  /// Copia [codigo] al portapapeles y avisa con un Snackbar.
  ///
  /// Va en un método aparte para poder ejercitarlo sin montar el widget.
  static Future<void> copiar(
    BuildContext context,
    String codigo, {
    String mensaje = 'Código copiado',
  }) async {
    await Clipboard.setData(ClipboardData(text: codigo));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(mensaje)));
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Flexible(
          child: Text(
            codigo,
            textAlign: TextAlign.center,
            style: estiloCodigo,
          ),
        ),
        const SizedBox(width: 8),
        IconButton(
          icon: const Icon(Icons.copy, size: 18),
          color: Colors.grey[700],
          tooltip: 'Copiar código',
          visualDensity: VisualDensity.compact,
          onPressed: () => copiar(context, codigo),
        ),
      ],
    );
  }
}
