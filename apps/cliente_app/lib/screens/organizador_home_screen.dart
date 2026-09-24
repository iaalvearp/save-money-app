import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../services/hunt_service.dart';
import 'crear_evento_screen.dart';
import 'evento_detalle_screen.dart';
import 'login_screen.dart';

class OrganizadorHomeScreen extends StatefulWidget {
  final HuntService? servicio;
  final AuthService? auth;

  const OrganizadorHomeScreen({super.key, this.servicio, this.auth});

  @override
  State<OrganizadorHomeScreen> createState() => _OrganizadorHomeScreenState();
}

class _OrganizadorHomeScreenState extends State<OrganizadorHomeScreen> {
  late final HuntService _servicio;
  late final AuthService _auth;

  List<Evento> _eventos = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _servicio = widget.servicio ?? HuntService();
    _auth = widget.auth ?? AuthService();
    _cargarEventosPropios();
  }

  Future<void> _cargarEventosPropios() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final token = await _auth.getAccessToken();
      final userId = await _auth.userId();
      final todos = await _servicio.listarEventos(token: token);
      if (!mounted) return;
      setState(() {
        _eventos = todos.where((e) => e.organizadorId == userId).toList();
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'No se pudieron cargar tus eventos';
        _loading = false;
      });
    }
  }

  Future<void> _crearEvento() async {
    final creado = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => CrearEventoScreen(
          servicio: _servicio,
          auth: _auth,
        ),
      ),
    );

    if (creado == true) {
      _cargarEventosPropios();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Organizador'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () async {
              await _auth.logout();
              if (!context.mounted) return;
              Navigator.of(context).pushReplacement(
                MaterialPageRoute(builder: (_) => const LoginScreen()),
              );
            },
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _crearEvento,
        icon: const Icon(Icons.add),
        label: const Text('Nuevo evento'),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline, size: 48, color: Colors.grey[400]),
              const SizedBox(height: 16),
              Text(
                _error!,
                style: const TextStyle(fontSize: 16),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _cargarEventosPropios,
                child: const Text('Reintentar'),
              ),
            ],
          ),
        ),
      );
    }

    if (_eventos.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.event, size: 48, color: Colors.grey[400]),
              const SizedBox(height: 16),
              const Text(
                'Aún no creas eventos de búsqueda',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                'Crea tu primer evento de Hunt para empezar',
                style: TextStyle(fontSize: 14, color: Colors.grey[500]),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: _crearEvento,
                icon: const Icon(Icons.add),
                label: const Text('Crear evento'),
              ),
            ],
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _cargarEventosPropios,
      child: ListView.builder(
        padding: const EdgeInsets.only(bottom: 88),
        itemCount: _eventos.length,
        itemBuilder: (context, index) {
          final evento = _eventos[index];
          return ListTile(
            leading: const CircleAvatar(child: Icon(Icons.event)),
            title: Text(evento.nombre),
            subtitle: Text(
              '${evento.fechaInicio.split(' ').first} - '
              '${evento.fechaFin.split(' ').first}',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () async {
              await Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => EventoDetalleScreen(
                    eventoId: evento.id,
                    servicio: _servicio,
                    auth: _auth,
                  ),
                ),
              );
              _cargarEventosPropios();
            },
          );
        },
      ),
    );
  }
}