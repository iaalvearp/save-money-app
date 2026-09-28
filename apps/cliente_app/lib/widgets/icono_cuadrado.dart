import 'package:flutter/material.dart';

/// Cuadrado con esquinas redondeadas para los íconos de las listas.
///
/// Antes estos lugares usaban `CircleAvatar`, que es un círculo: sirve para una
/// foto de persona, pero un comercio, una promoción o un evento no tienen cara,
/// y el círculo se leía como "avatar de usuario". Con esquinas de radio 8 la
/// lista se ve como el resto de la app, que usa rectángulos redondeados en los
/// botones.
class IconoCuadrado extends StatelessWidget {
  /// Contenido centrado: una inicial, un ícono o un porcentaje.
  final Widget child;

  /// Lado del cuadrado.
  final double tamano;

  /// Color de fondo. Si no se pasa, se usa el del tema.
  final Color? color;

  /// URL de una imagen a mostrar de fondo. Si falla, se ve el color y el
  /// contenido, igual que antes con `CircleAvatar`.
  final String? imagen;

  static const double radio = 8;

  const IconoCuadrado({
    super.key,
    required this.child,
    this.tamano = 40,
    this.color,
    this.imagen,
  });

  @override
  Widget build(BuildContext context) {
    final fondo = color ?? Theme.of(context).colorScheme.secondaryContainer;

    return Container(
      width: tamano,
      height: tamano,
      decoration: BoxDecoration(
        color: fondo,
        borderRadius: BorderRadius.circular(radio),
        image: imagen == null || imagen!.isEmpty
            ? null
            : DecorationImage(
                image: NetworkImage(imagen!),
                fit: BoxFit.cover,
                onError: (_, _) {},
              ),
      ),
      alignment: Alignment.center,
      child: child,
    );
  }
}
