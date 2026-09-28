import 'package:flutter/material.dart';

/// Muestra un error que invalida la acción que la persona intentaba hacer.
///
/// Un `SnackBar` se pasa en un segundo, se va solo y encima la lista o el
/// formulario siguen ahí como si nada. Para un error que cancela lo que se
/// estaba haciendo (un QR que no es válido, una promoción que ya no se puede
/// reclamar) eso no alcanza: la persona se queda sin saber qué pasó. Por eso
/// estos errores van en un `AlertDialog` con un botón "Entendido", que no se
/// cierra solo y hay que reconocer.
///
/// Las confirmaciones de que algo sí salió bien siguen siendo `SnackBar`: no
/// interrumpen, y ese es el comportamiento que se quiere ahí.
///
/// Devuelve el futuro que cierra el diálogo, para que quien llama pueda
/// esperar a que la persona lo haya entendido.
Future<void> mostrarErrorDialog(
  BuildContext context, {
  required String titulo,
  required String mensaje,
}) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (context) => AlertDialog(
      title: Text(titulo),
      content: SingleChildScrollView(child: Text(mensaje)),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Entendido'),
        ),
      ],
    ),
  );
}
