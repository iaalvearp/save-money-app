import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../services/comercios_service.dart';
import 'login_screen.dart';
import 'mi_comercio_form_screen.dart';

class NegocioHomeScreen extends StatefulWidget {
  final ComerciosService? servicio;
  final AuthService? auth;

  const NegocioHomeScreen({super.key, this.servicio, this.auth});

  @override
  State<NegocioHomeScreen> createState() => _NegocioHomeScreenState();
}

class _NegocioHomeScreenState extends State<NegocioHomeScreen> {
  late final ComerciosService _servicio;
  late final AuthService _auth;

  List<Comercio> _comercios = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _servicio = widget.servicio ?? ComerciosService();
    _auth = widget.auth ?? AuthService();
    _cargarMisComercios();
  }

  Future<void> _cargarMisComercios() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final token = await _auth.getAccessToken();
      final comercios = await _servicio.misComercios(token: token);
      if (!mounted) return;
      setState(() {
        _comercios = comercios;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'No se pudieron cargar tus comercios';
        _loading = false;
      });
    }
  }

  Future<void> _abrirFormulario({Comercio? comercio}) async {
    final guardado = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => MiComercioFormScreen(
          comercio: comercio,
          servicio: _servicio,
          auth: _auth,
        ),
      ),
    );

    if (guardado == true) {
      _cargarMisComercios();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Mi negocio'),
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
        onPressed: () => _abrirFormulario(),
        icon: const Icon(Icons.add),
        label: const Text('Nuevo comercio'),
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
                onPressed: _cargarMisComercios,
                child: const Text('Reintentar'),
              ),
            ],
          ),
        ),
      );
    }

    if (_comercios.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.store_outlined, size: 48, color: Colors.grey[400]),
              const SizedBox(height: 16),
              const Text(
                'Aún no tienes comercios',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                'Crea tu primer comercio para empezar a recibir clientes',
                style: TextStyle(fontSize: 14, color: Colors.grey[500]),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: () => _abrirFormulario(),
                icon: const Icon(Icons.add),
                label: const Text('Crear mi comercio'),
              ),
            ],
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _cargarMisComercios,
      child: ListView.separated(
        padding: const EdgeInsets.only(bottom: 88),
        itemCount: _comercios.length,
        separatorBuilder: (_, _) => const Divider(height: 1),
        itemBuilder: (context, index) {
          final comercio = _comercios[index];
          return ListTile(
            leading: CircleAvatar(child: Text(comercio.nombre[0].toUpperCase())),
            title: Text(comercio.nombre),
            subtitle: Text(
              comercio.categoria ?? 'Sin categoría',
            ),
            trailing: IconButton(
              icon: const Icon(Icons.edit),
              tooltip: 'Editar',
              onPressed: () => _abrirFormulario(comercio: comercio),
            ),
          );
        },
      ),
    );
  }
}