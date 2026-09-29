import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../services/comercios_service.dart';
import '../services/notificaciones_service.dart';
import '../services/permiso_ubicacion_service.dart';
import '../widgets/aviso_ubicacion.dart';
import '../widgets/icono_cuadrado.dart';
import 'ajustes_sheet.dart';
import 'bandeja_notificaciones_screen.dart';
import 'comercio_detail_screen.dart';
import 'flash_screen.dart';
import 'hunt_screen.dart';

class HomeScreen extends StatefulWidget {
  /// Inyecta el servicio de comercios en vez de crear uno. Solo se usa en
  /// pruebas.
  final ComerciosService? servicio;

  /// Inyecta el permiso de ubicación en vez de consultar el sistema. Solo se
  /// usa en pruebas.
  final Future<ResultadoUbicacion> Function()? permisoUbicacion;

  /// Comprueba el permiso sin mostrar ningún diálogo. Solo se usa en pruebas.
  final Future<ResultadoUbicacion> Function()? comprobarPermiso;

  /// Inyecta la lectura de la posición. Solo se usa en pruebas.
  final Future<Position> Function()? leerPosicion;

  /// Inyecta la apertura de los ajustes. Solo se usa en pruebas.
  final Future<void> Function()? abrirConfiguracion;
  final Future<void> Function()? abrirGps;

  const HomeScreen({
    super.key,
    this.servicio,
    this.permisoUbicacion,
    this.comprobarPermiso,
    this.leerPosicion,
    this.abrirConfiguracion,
    this.abrirGps,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  late final ComerciosService _comerciosService;
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

  /// Estado del permiso de ubicación. Mientras sea `null` no se ha comprobado
  /// todavía y no se carga nada.
  ResultadoUbicacion? _estadoUbicacion;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _comerciosService = widget.servicio ?? ComerciosService();
    _obtenerUbicacion();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _searchController.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState estado) {
    if (estado == AppLifecycleState.resumed) {
      _comprobarYRecargar();
    }
  }

  /// Vuelve a mirar el permiso sin pedirlo y, si lo hay, recarga la lista.
  ///
  /// Se usa en las tres vueltas desde fuera de la app: el segundo plano, los
  /// ajustes de la app y los ajustes del GPS. En las tres la persona acaba de
  /// resolver algo, y preguntar de nuevo metería un diálogo que no pidió. Volver
  /// a segundo plano no es consentir nada, y abrir los ajustes tampoco: si lo
  /// Activó, la lista aparece sola; si no lo Activó, la app se queda como está.
  ///
  /// El diálogo se queda para cuando toque "Activar ubicación" a propósito.
  Future<void> _comprobarYRecargar() async {
    final estado = await _comprobarPermisoUbicacion();
    if (!mounted) return;

    if (estado != ResultadoUbicacion.ok) {
      setState(() {
        _estadoUbicacion = estado;
        _ubicacionActual = null;
        _comercios = [];
        _cercanos = [];
        _loading = false;
      });
      return;
    }

    await _obtenerUbicacion(permisoYaComprobado: true);
  }

  /// [permisoYaComprobado] evita volver a mirar el permiso cuando quien llama
  /// acaba de comprobarlo y sabe que lo tiene.
  Future<void> _obtenerUbicacion({bool permisoYaComprobado = false}) async {
    // Sin coordenadas no hay lista. Se averigua primero si hay permiso y
    // posición, y solo entonces se pregunta al servidor.
    final estado = permisoYaComprobado
        ? ResultadoUbicacion.ok
        : await _pedirPermisoUbicacion();
    if (!mounted) return;

    if (estado != ResultadoUbicacion.ok) {
      setState(() {
        _estadoUbicacion = estado;
        _ubicacionActual = null;
        _comercios = [];
        _cercanos = [];
        _loading = false;
      });
      return;
    }

    try {
      final position = await _leerPosicionActual();
      if (!mounted) return;

      setState(() {
        _estadoUbicacion = ResultadoUbicacion.ok;
        _ubicacionActual = position;
      });

      await _cargarCercanos(position.latitude, position.longitude);
      await _cargarComercios(lat: position.latitude, lng: position.longitude);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _estadoUbicacion = ResultadoUbicacion.sinPosicion;
        _loading = false;
      });
    }
  }

  Future<ResultadoUbicacion> _pedirPermisoUbicacion() {
    return widget.permisoUbicacion?.call() ?? solicitarPermisoUbicacion();
  }

  /// Mira el permiso sin pedirlo. Al volver de segundo plano, o en el reporte
  /// periódico, preguntar ahí sería interrumpir a la persona sin que lo haya
  /// pedido.
  Future<ResultadoUbicacion> _comprobarPermisoUbicacion() {
    return widget.comprobarPermiso?.call() ?? comprobarPermisoUbicacion();
  }

  Future<Position> _leerPosicionActual() {
    return widget.leerPosicion?.call() ??
        Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
            timeLimit: Duration(seconds: 10),
          ),
        );
  }

  Future<void> _abrirConfiguracion() async {
    await (widget.abrirConfiguracion ?? abrirConfiguracionUbicacion)();
    await _comprobarYRecargar();
  }

  Future<void> _encenderGps() async {
    await (widget.abrirGps ?? abrirConfiguracionGps)();
    await _comprobarYRecargar();
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
              Navigator.of(
                context,
              ).push(MaterialPageRoute(builder: (_) => const FlashScreen()));
            },
          ),
          IconButton(
            icon: const Icon(Icons.celebration),
            tooltip: 'Hunt',
            onPressed: () {
              Navigator.of(
                context,
              ).push(MaterialPageRoute(builder: (_) => const HuntScreen()));
            },
          ),
          Builder(
            builder: (context) {
              // Sin buzón en el árbol (pantalla probada suelta) la campana se
              // dibuja igual, solo que sin contador.
              final buzon = NotificacionesScope.maybeOf(context);
              return Badge(
                label: Text('${buzon?.noLeidas ?? 0}'),
                isLabelVisible: (buzon?.noLeidas ?? 0) > 0,
                child: IconButton(
                  icon: const Icon(Icons.notifications_none),
                  tooltip: BandejaNotificacionesScreen.titulo,
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const BandejaNotificacionesScreen(),
                      ),
                    );
                  },
                ),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.settings),
            tooltip: 'Ajustes',
            onPressed: () => abrirAjustes(context),
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
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
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
                setState(() => _categoriaSeleccionada = selected ? cat : null);
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

    // Sin ubicacion no hay ni una lista de comercios. Antes se pedia la lista
    // igual y se mostraba todo el catalogo, que no es lo que quiere alguien
    // que entro a ver lo que hay cerca de su casa.
    final estado = _estadoUbicacion;
    if (estado != null && estado != ResultadoUbicacion.ok) {
      return AvisoUbicacion(
        estado: estado,
        onReintentar: _obtenerUbicacion,
        onAbrirConfiguracion: _abrirConfiguracion,
        onEncenderGps: _encenderGps,
      );
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
                onPressed: _obtenerUbicacion,
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
      onRefresh: _obtenerUbicacion,
      child: ListView(
        children: [
          if (_cercanos.isNotEmpty) ...[
            _buildSeccionCercanos(),
            const Divider(height: 1),
          ],
          if (_comercios.isNotEmpty) ...[_buildSeccionDescubiertos()],
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
            child: Text(comercio.nombre, overflow: TextOverflow.ellipsis),
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
    return IconoCuadrado(
      imagen: comercio.fotoUrl,
      child: Text(comercio.nombre[0].toUpperCase()),
    );
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
                if (comercio.fotoUrl != null && comercio.fotoUrl!.isNotEmpty)
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
                      Icon(
                        Icons.location_on,
                        size: 12,
                        color: Colors.blue[600],
                      ),
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
