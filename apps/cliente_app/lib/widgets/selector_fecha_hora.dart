import 'package:flutter/material.dart';

/// Abre el calendario. Se sustituye en pruebas para no depender del sistema.
typedef PedirFecha = Future<DateTime?> Function(
  BuildContext context,
  DateTime inicial,
  DateTime primero,
  DateTime ultimo,
);

/// Abre el reloj. Se sustituye en pruebas.
typedef PedirHora = Future<TimeOfDay?> Function(
  BuildContext context,
  TimeOfDay inicial,
);

/// Selector de fecha y hora, en un solo campo.
///
/// Se eligió con el calendario y con el reloj del sistema, y guarda el texto en
/// `AAAA-MM-DD HH:MM:SS`, que es lo que espera el backend.
///
/// Sobre la hora: el texto se arma con la hora del reloj, sin convertirla. El
/// backend interpreta ese texto como hora de Ecuador, que es lo mismo que quiere
/// decir "la ronda abre a las 10:00": las 10 donde está la gente. Convertir a
/// UTC aquí dejaría todos los eventos corridos cinco horas.
///
/// Este widget no reemplaza la validación del servidor: solo evita que se pueda
/// elegir algo que el servidor va a rechazar.
class SelectorFechaHora extends StatefulWidget {
  /// Texto mostrado y editable por el formulario. El widget escribe aquí el
  /// valor en `AAAA-MM-DD HH:MM:SS`.
  final TextEditingController controller;

  final String label;
  final String? hintText;
  final String? Function(String?)? validator;

  /// Avisa del valor elegido, ya acotado, para que la pantalla pueda ajustar
  /// los límites de otro selector. Recibe `null` si se eligió algo anterior al
  /// mínimo y por tanto se corrigió.
  final ValueChanged<DateTime?>? onCambiado;

  /// No se puede elegir un instante anterior a este. En el campo de fin se le
  /// pasa el inicio, para que el error aparezca al elegir y no al enviar.
  final DateTime? minimo;

  /// No se puede elegir un instante posterior a este.
  final DateTime? maximo;

  final bool habilitado;

  /// Se inyectan en pruebas para no depender del calendario del sistema.
  final PedirFecha? pedirFecha;
  final PedirHora? pedirHora;

  const SelectorFechaHora({
    super.key,
    required this.controller,
    required this.label,
    this.hintText = 'AAAA-MM-DD HH:MM:SS',
    this.validator,
    this.onCambiado,
    this.minimo,
    this.maximo,
    this.habilitado = true,
    this.pedirFecha,
    this.pedirHora,
  });

  /// Texto que el backend espera: `AAAA-MM-DD HH:MM:SS`.
  static String formatear(DateTime valor) {
    final anio = valor.year.toString().padLeft(4, '0');
    final mes = valor.month.toString().padLeft(2, '0');
    final dia = valor.day.toString().padLeft(2, '0');
    final hora = valor.hour.toString().padLeft(2, '0');
    final minuto = valor.minute.toString().padLeft(2, '0');
    final segundo = valor.second.toString().padLeft(2, '0');
    return '$anio-$mes-$dia $hora:$minuto:$segundo';
  }

  /// Lee un texto `AAAA-MM-DD HH:MM:SS`. Devuelve `null` si no tiene esa forma.
  static DateTime? leer(String? texto) {
    if (texto == null) return null;
    return DateTime.tryParse(texto.trim());
  }

  @override
  State<SelectorFechaHora> createState() => _SelectorFechaHoraState();
}

class _SelectorFechaHoraState extends State<SelectorFechaHora> {
  bool _abierto = false;

  /// Un valor por defecto al abrir: el actual, o el mínimo si no hay nada.
  DateTime _valorInicial() {
    final actual = SelectorFechaHora.leer(widget.controller.text);
    if (actual != null) return actual;
    if (widget.minimo != null) return widget.minimo!;
    return DateTime.now();
  }

  /// Acota una fecha al rango permitido, para que el calendario no ofrezca días
  /// que el backend va a rechazar.
  DateTime _acotar(DateTime fecha) {
    var valor = fecha;
    if (widget.minimo != null && valor.isBefore(widget.minimo!)) {
      valor = widget.minimo!;
    }
    if (widget.maximo != null && valor.isAfter(widget.maximo!)) {
      valor = widget.maximo!;
    }
    return valor;
  }

  Future<void> _elegir() async {
    if (!widget.habilitado || _abierto) return;

    final ahora = DateTime.now();
    // El mínimo solo acota hacia atrás si ya pasó; un evento puede empezar en
    // el pasado (por ejemplo, uno que se está organizando a media carrera).
    var primero = _acotar(
      DateTime(ahora.year - 1, ahora.month, ahora.day),
    );
    final ultimo = _acotar(
      widget.maximo ?? DateTime(ahora.year + 5, 12, 31),
    );
    // El calendario real no admite un rango al revés; si los límites se
    // cruzaran, se deja un solo día en lugar de reventar la pantalla.
    if (primero.isAfter(ultimo)) primero = ultimo;

    setState(() => _abierto = true);

    final inicial = _acotar(_valorInicial());

    try {
      final fecha = await (widget.pedirFecha?.call(context, inicial, primero, ultimo) ??
          showDatePicker(
            context: context,
            initialDate: inicial,
            firstDate: primero,
            lastDate: ultimo,
          ));
      if (fecha == null || !mounted) return;

      // Si se eligió el mismo día que el mínimo, el reloj no puede arrancar
      // antes de esa hora. Si no, arranca a las 9 de la mañana, que es lo
      // primero que alguien elige para un evento.
      final relojInicial = _horaInicial(fecha);

      final hora = await (widget.pedirHora?.call(context, relojInicial) ??
          showTimePicker(context: context, initialTime: relojInicial));
      if (hora == null || !mounted) return;

      final elegido = DateTime(
        fecha.year,
        fecha.month,
        fecha.day,
        hora.hour,
        hora.minute,
      );
      final acotado = _acotar(elegido);

      widget.controller.text = SelectorFechaHora.formatear(acotado);
      // El campo es de solo lectura: sin esto el cursor se escondería dentro.
      widget.controller.selection = TextSelection.collapsed(
        offset: widget.controller.text.length,
      );
      widget.onCambiado?.call(acotado);
    } finally {
      if (mounted) setState(() => _abierto = false);
    }
  }

  TimeOfDay _horaInicial(DateTime fecha) {
    final actual = SelectorFechaHora.leer(widget.controller.text);
    if (actual != null &&
        actual.year == fecha.year &&
        actual.month == fecha.month &&
        actual.day == fecha.day) {
      return TimeOfDay(hour: actual.hour, minute: actual.minute);
    }

    if (widget.minimo != null &&
        fecha.year == widget.minimo!.year &&
        fecha.month == widget.minimo!.month &&
        fecha.day == widget.minimo!.day) {
      return TimeOfDay(hour: widget.minimo!.hour, minute: widget.minimo!.minute);
    }

    return const TimeOfDay(hour: 9, minute: 0);
  }

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: widget.controller,
      readOnly: true,
      enabled: widget.habilitado,
      onTap: _elegir,
      validator: widget.validator,
      decoration: InputDecoration(
        labelText: widget.label,
        hintText: widget.hintText,
        border: const OutlineInputBorder(),
        suffixIcon: Icon(
          _abierto ? Icons.hourglass_top : Icons.event,
          size: 20,
        ),
      ),
    );
  }
}
