import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../services/comercios_service.dart';
import 'comercio_detail_screen.dart';
import 'login_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _comerciosService = ComerciosService();
  List<Comercio> _comercios = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _cargarComercios();
  }

  Future<void> _cargarComercios() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final comercios = await _comerciosService.listar();
      if (!mounted) return;
      setState(() {
        _comercios = comercios;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'No se pudieron cargar los comercios';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Save Money'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () async {
              await AuthService().logout();
              if (!context.mounted) return;
              Navigator.of(context).pushReplacement(
                MaterialPageRoute(builder: (_) => const LoginScreen()),
              );
            },
          ),
        ],
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
                onPressed: _cargarComercios,
                child: const Text('Reintentar'),
              ),
            ],
          ),
        ),
      );
    }

    if (_comercios.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.store_outlined, size: 48, color: Colors.grey[400]),
            const SizedBox(height: 16),
            const Text(
              'No hay comercios disponibles',
              style: TextStyle(fontSize: 16),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _cargarComercios,
      child: ListView.builder(
        itemCount: _comercios.length,
        itemBuilder: (context, index) {
          final comercio = _comercios[index];
          return _ComercioTile(
            comercio: comercio,
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => ComercioDetailScreen(comercioId: comercio.id),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class _ComercioTile extends StatelessWidget {
  final Comercio comercio;
  final VoidCallback onTap;

  const _ComercioTile({required this.comercio, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: _buildAvatar(),
      title: Row(
        children: [
          Expanded(
            child: Text(
              comercio.nombre,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (comercio.esPatrocinado) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.amber[700],
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Text(
                'Patrocinado',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ],
      ),
      subtitle: Text(comercio.categoria ?? 'Sin categoría'),
      trailing: const Icon(Icons.chevron_right),
      onTap: onTap,
    );
  }

  Widget _buildAvatar() {
    if (comercio.fotoUrl != null && comercio.fotoUrl!.isNotEmpty) {
      return CircleAvatar(
        backgroundImage: NetworkImage(comercio.fotoUrl!),
        onBackgroundImageError: (_, _) {},
        child: Text(comercio.nombre[0].toUpperCase()),
      );
    }
    return CircleAvatar(child: Text(comercio.nombre[0].toUpperCase()));
  }
}
