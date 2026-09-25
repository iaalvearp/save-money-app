import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../services/auth_service.dart';
import '../services/comercios_service.dart';
import '../services/notificaciones_service.dart';
import 'comercio_detail_screen.dart';
import 'flash_screen.dart';
import 'historial_facturas_screen.dart';
import 'hunt_screen.dart';
import 'login_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _comerciosService = ComerciosService();
  final _searchController = TextEditingController();
  Timer? _debounce;

  List<Comercio> _comercios = [];
  List<Comercio> _cercanos = [];
  List<String> _categorias = [];
  String? _categoriaSeleccionada;
  bool _soloConPromociones = false;
  bool _loading = true;
  bool _loadingCercanos = false;
  String? _error;
  Position? _ubicacionActual;
  String? _errorUbicacion;

  @override
  void initState() {
    super.initState();
    _cargarComercios();
    _obtenerUbicacion();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> _obtenerUbicacion() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        setState(() => _errorUbicacion = 'Servicios de ubicación desactivados');
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          setState(() => _errorUbicacion = 'Permiso de ubicación denegado');
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        setState(
            () => _errorUbicacion = 'Permiso de ubicación denegado permanentemente');
        return;
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 10),
        ),
      );

      if (!mounted) return;
      setState(() {
        _ubicacionActual = position;
        _errorUbicacion = null;
      });

      _cargarCercanos(position.latitude, position.longitude);
      _cargarComercios(lat: position.latitude, lng: position.longitude);
    } catch (e) {
      if (!mounted) return;
      setState(() => _errorUbicacion = 'No se pudo obtener la ubicación');
    }
  }

  Future<void> _cargarCercanos(double lat, double lng) async {
    setState(() => _loadingCercanos = true);
    try {
      final cercanos = await _comerciosService.cercanos(lat: lat, lng: lng);
      if (!mounted) return;
      setState(() {
        _cercanos = cercanos;
        _loadingCercanos = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loadingCercanos = false);
    }
  }

  Future<void> _cargarComercios({double? lat, double? lng}) async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final comercios = await _comerciosService.listar(
        categoria: _categoriaSeleccionada,
        busqueda: _searchController.text.isEmpty
            ? null
            : _searchController.text,
        conPromociones: _soloConPromociones ? true : null,
        lat: lat ?? _ubicacionActual?.latitude,
        lng: lng ?? _ubicacionActual?.longitude,
      );

      final categorias = <String>{};
      for (final c in comercios) {
        if (c.categoria != null && c.categoria!.isNotEmpty) {
          categorias.add(c.categoria!);
        }
      }

      if (!mounted) return;
      setState(() {
        _comercios = comercios;
        _categorias = categorias.toList()..sort();
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

  void _onSearchChanged() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), () {
      _cargarComercios();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Save Money'),
        actions: [
          IconButton(
            icon: const Icon(Icons.flash_on),
            tooltip: 'Flash',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const FlashScreen()),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.celebration),
            tooltip: 'Hunt',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const HuntScreen()),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.receipt_long),
            tooltip: 'Mis facturas',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const HistorialFacturasScreen(),
                ),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.notifications_active),
            tooltip: 'Probar notificación',
            onPressed: () async {
              try {
                await NotificacionesService().probarNotificacion();
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Notificación de prueba enviada'),
                  ),
                );
              } catch (e) {
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('No se pudo enviar la notificación'),
                  ),
                );
              }
            },
          ),
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
      body: Column(
        children: [
          _buildSearchBar(),
          _buildFilterChips(),
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: TextField(
        controller: _searchController,
        decoration: InputDecoration(
          hintText: 'Buscar comercios...',
          prefixIcon: const Icon(Icons.search),
          suffixIcon: _searchController.text.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear),
                  onPressed: () {
                    _searchController.clear();
                    _cargarComercios();
                  },
                )
              : null,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16),
        ),
        onChanged: (_) {
          setState(() {});
          _onSearchChanged();
        },
      ),
    );
  }

  Widget _buildFilterChips() {
    return SizedBox(
      height: 56,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        children: [
          FilterChip(
            label: const Text('Todos'),
            selected: _categoriaSeleccionada == null && !_soloConPromociones,
            onSelected: (_) {
              setState(() {
                _categoriaSeleccionada = null;
                _soloConPromociones = false;
              });
              _cargarComercios();
            },
          ),
          const SizedBox(width: 8),
          FilterChip(
            label: const Text('Con promociones'),
            selected: _soloConPromociones,
            avatar: Icon(
              Icons.local_offer,
              size: 18,
              color: _soloConPromociones ? Colors.white : Colors.grey,
            ),
            onSelected: (selected) {
              setState(() => _soloConPromociones = selected);
              _cargarComercios();
            },
          ),
          const SizedBox(width: 8),
          for (final cat in _categorias) ...[
            FilterChip(
              label: Text(cat),
              selected: _categoriaSeleccionada == cat,
              onSelected: (selected) {
                setState(() =>
                    _categoriaSeleccionada = selected ? cat : null);
                _cargarComercios();
              },
            ),
            const SizedBox(width: 8),
          ],
        ],
      ),
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
                onPressed: () => _cargarComercios(),
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
              'No se encontraron comercios',
              style: TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 8),
            Text(
              'Intenta con otros filtros de búsqueda',
              style: TextStyle(fontSize: 14, color: Colors.grey[500]),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () async {
        await _obtenerUbicacion();
        await _cargarComercios();
      },
      child: ListView(
        children: [
          if (_errorUbicacion != null) _buildUbicacionBanner(),
          if (_cercanos.isNotEmpty) ...[
            _buildSeccionCercanos(),
            const Divider(height: 1),
          ],
          if (_comercios.isNotEmpty) ...[
            _buildSeccionDescubiertos(),
          ],
        ],
      ),
    );
  }

  Widget _buildUbicacionBanner() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      color: Colors.orange.shade50,
      child: Row(
        children: [
          Icon(Icons.location_off, size: 20, color: Colors.orange[700]),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _errorUbicacion!,
              style: TextStyle(fontSize: 13, color: Colors.orange[700]),
            ),
          ),
          TextButton(
            onPressed: _obtenerUbicacion,
            child: const Text('Reintentar'),
          ),
        ],
      ),
    );
  }

  Widget _buildSeccionCercanos() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Row(
            children: [
              Icon(Icons.near_me, size: 20, color: Colors.blue[600]),
              const SizedBox(width: 8),
              Text(
                'Cercanos a ti',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.blue[600],
                ),
              ),
            ],
          ),
        ),
        SizedBox(
          height: 160,
          child: _loadingCercanos
              ? const Center(child: CircularProgressIndicator())
              : ListView.builder(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  itemCount: _cercanos.length,
                  itemBuilder: (context, index) {
                    final c = _cercanos[index];
                    return _ComercioCercanoCard(
                      comercio: c,
                      onTap: () => _abrirDetalle(c.id),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildSeccionDescubiertos() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Row(
            children: [
              Icon(Icons.explore, size: 20, color: Colors.green[600]),
              const SizedBox(width: 8),
              Text(
                'Descubiertos',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.green[600],
                ),
              ),
            ],
          ),
        ),
        ListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: _comercios.length,
          itemBuilder: (context, index) {
            final comercio = _comercios[index];
            return _ComercioTile(
              comercio: comercio,
              onTap: () => _abrirDetalle(comercio.id),
            );
          },
        ),
      ],
    );
  }

  void _abrirDetalle(int comercioId) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ComercioDetailScreen(comercioId: comercioId),
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
                color: Colors.blue[700],
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Text(
                'Descubierto',
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
      subtitle: Row(
        children: [
          Text(comercio.categoria ?? 'Sin categoría'),
          if (comercio.distanciaKm != null) ...[
            const SizedBox(width: 8),
            Icon(Icons.location_on, size: 12, color: Colors.grey[500]),
            const SizedBox(width: 2),
            Text(
              '${comercio.distanciaKm} km',
              style: TextStyle(fontSize: 12, color: Colors.grey[500]),
            ),
          ],
        ],
      ),
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

class _ComercioCercanoCard extends StatelessWidget {
  final Comercio comercio;
  final VoidCallback onTap;

  const _ComercioCercanoCard({required this.comercio, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Card(
        margin: const EdgeInsets.symmetric(horizontal: 4),
        child: SizedBox(
          width: 140,
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (comercio.fotoUrl != null &&
                    comercio.fotoUrl!.isNotEmpty)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.network(
                      comercio.fotoUrl!,
                      height: 60,
                      width: double.infinity,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => Container(
                        height: 60,
                        color: Colors.grey[200],
                        child: const Icon(Icons.store),
                      ),
                    ),
                  )
                else
                  Container(
                    height: 60,
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: Colors.grey[200],
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.store, size: 30),
                  ),
                const SizedBox(height: 8),
                Text(
                  comercio.nombre,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  comercio.categoria ?? 'Sin categoría',
                  style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                ),
                if (comercio.distanciaKm != null) ...[
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(Icons.location_on,
                          size: 12, color: Colors.blue[600]),
                      const SizedBox(width: 2),
                      Text(
                        '${comercio.distanciaKm} km',
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.blue[600],
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
