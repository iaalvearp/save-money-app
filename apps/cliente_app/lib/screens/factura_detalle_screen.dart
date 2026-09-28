import 'package:flutter/material.dart';

import '../services/facturas_service.dart';

/// Detalle de una factura, de solo lectura.
///
/// Antes, tocar una factura no hacia nada, pero la fila tenia una flecha que
/// prometia que habia algo mas. Esta hoja es ese "algo mas": enseña lo que el
/// servidor ya sabe de la factura y no deja cambiar nada, porque la factura no
/// se edita: o la aprueba el SRI o la rechaza, y el cliente no decide.
class FacturaDetalleSheet extends StatelessWidget {
  const FacturaDetalleSheet({super.key, required this.factura});

  final Factura factura;

  /// Los estados que el backend usa se agrupan en tres, que es lo que el
  /// usuario entiende. "Pendiente de verificación SRI" y "pendiente de
  /// revisión del comprobante" son el mismo asunto desde fuera: todavía se
  /// está mirando.
  static String estadoSimple(String estado) {
    switch (estado) {
      case 'aprobada':
        return 'Aprobada';
      case 'rechazada':
        return 'Rechazada';
      case 'pendiente_verificacion_sri':
      case 'pendiente_revision_nombre':
      case 'pendiente_revision_comprobante':
      case 'pendiente_pago':
        return 'En revisión';
      default:
        return estado;
    }
  }

  Color _colorEstado(String estado) {
    switch (estado) {
      case 'aprobada':
        return Colors.green;
      case 'rechazada':
        return Colors.red;
      default:
        return Colors.orange;
    }
  }

  IconData _iconoEstado(String estado) {
    switch (estado) {
      case 'aprobada':
        return Icons.check_circle;
      case 'rechazada':
        return Icons.cancel;
      default:
        return Icons.hourglass_top;
    }
  }

  String get _nivelVerificacion {
    final nivel = factura.nivelVerificacion;
    if (nivel == null) return 'Sin nivel';
    return switch (nivel) {
      1 => 'Nivel 1 · Clave de acceso',
      2 => 'Nivel 2 · Comprobante',
      3 => 'Nivel 3 · Challenge',
      _ => 'Nivel $nivel',
    };
  }

  @override
  Widget build(BuildContext context) {
    final esquema = Theme.of(context).colorScheme;
    final color = _colorEstado(factura.estado);

    return SafeArea(
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: esquema.outlineVariant,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Icon(_iconoEstado(factura.estado), color: color, size: 28),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Factura #${factura.id}',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _Fila(
                rotulo: 'Estado',
                valor: estadoSimple(factura.estado),
                color: color,
              ),
              if (factura.estado == 'rechazada' &&
                  factura.motivoRechazo != null &&
                  factura.motivoRechazo!.isNotEmpty)
                _Fila(
                  rotulo: 'Motivo',
                  valor: factura.motivoRechazo!,
                  color: Colors.red,
                ),
              _Fila(
                rotulo: 'Comercio (RUC emisor)',
                valor: factura.rucEmisor ?? 'No informado',
              ),
              _Fila(
                rotulo: 'Número de factura',
                valor: factura.numeroFactura ?? 'Sin número',
              ),
              _Fila(
                rotulo: 'Fecha de emisión',
                valor: factura.fechaFactura ?? 'Sin fecha',
              ),
              _Fila(
                rotulo: 'Monto total',
                valor: factura.montoTotal == null
                    ? 'Sin monto'
                    : '\$${factura.montoTotal!.toStringAsFixed(2)}',
              ),
              if (factura.descuentoAplicado != null)
                _Fila(
                  rotulo: 'Descuento aplicado',
                  valor:
                      '\$${factura.descuentoAplicado!.toStringAsFixed(2)}',
                ),
              _Fila(rotulo: 'Verificación', valor: _nivelVerificacion),
              const SizedBox(height: 20),
              Text(
                'Este detalle es de solo lectura.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: esquema.onSurfaceVariant,
                    ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cerrar'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Una fila etiqueta / valor. Se oculta si no hay valor, para no enseñar
/// líneas vacías.
class _Fila extends StatelessWidget {
  const _Fila({required this.rotulo, required this.valor, this.color});

  final String rotulo;
  final String valor;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    if (valor.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            rotulo,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 2),
          Text(
            valor,
            style: Theme.of(context)
                .textTheme
                .bodyLarge
                ?.copyWith(color: color),
          ),
        ],
      ),
    );
  }
}
