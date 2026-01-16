import 'dart:async';
import 'dart:io';
import 'dart:math'; 
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:location/location.dart'; 
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image/image.dart' as img; 
import 'package:gal/gal.dart'; 
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:dio/dio.dart';
import 'package:dio_cache_interceptor/dio_cache_interceptor.dart';
import 'package:dio_cache_interceptor_file_store/dio_cache_interceptor_file_store.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const GeoModernApp());
}

class GeoModernApp extends StatelessWidget {
  const GeoModernApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'GeoColombia Ultra',
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF1A1F2C),
        primaryColor: const Color(0xFF00D4FF), 
        cardColor: const Color(0xFF2D3446),
        textTheme: GoogleFonts.rajdhaniTextTheme(ThemeData.dark().textTheme),
      ),
      home: const MainScreen(),
    );
  }
}

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  final MapController _mapController = MapController();
  final ImagePicker _picker = ImagePicker();
  final Location _locationEngine = Location();
  StreamSubscription<LocationData>? _locationSubscription;
  
  late CacheStore _cacheStore;
  late DioCacheTileProvider _tileProvider;
  bool _isCacheReady = false;

  LatLng _currentPos = const LatLng(4.5709, -74.2973); 
  double _currentZoom = 15.0; 
  double _accuracy = 0.0;
  double _altitude = 0.0;
  bool _isTracking = false;
  bool _hasPosition = false;
  
  String _statusText = "SISTEMA EN ESPERA";
  List<LatLng> _route = [];
  bool _isSavingPhoto = false;
  
  bool _isSatellite = false; 
  bool _isDownloadingMap = false;
  String _downloadProgress = "";
  double _progressValue = 0.0;

  @override
  void initState() {
    super.initState();
    _initCache();
  }

  Future<void> _initCache() async {
    final dir = await getTemporaryDirectory();
    _cacheStore = FileCacheStore('${dir.path}/map_v_pro_fix');
    _tileProvider = DioCacheTileProvider(cacheStore: _cacheStore);
    setState(() => _isCacheReady = true);
  }

  @override
  void dispose() {
    _locationSubscription?.cancel();
    _mapController.dispose();
    _cacheStore.close();
    super.dispose();
  }

  String get _currentMapUrl => _isSatellite 
      ? 'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}' 
      : 'https://tile.openstreetmap.org/{z}/{x}/{y}.png'; 

  void _toggleMapType() => setState(() => _isSatellite = !_isSatellite);

  void _zoomIn() {
    setState(() { _currentZoom++; _mapController.move(_mapController.camera.center, _currentZoom); });
  }

  void _zoomOut() {
    setState(() { _currentZoom--; _mapController.move(_mapController.camera.center, _currentZoom); });
  }

  Future<void> _downloadMap() async {
    if (_isDownloadingMap) return;
    bool? confirm = await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF2D3446),
        title: const Text("Descargar Zona", style: TextStyle(color: Colors.white)),
        content: Text("Se descargará el mapa (${_isSatellite ? 'SATÉLITE' : 'CALLES'}) offline.", style: const TextStyle(color: Colors.white70)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Cancelar", style: TextStyle(color: Colors.grey))),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text("DESCARGAR", style: TextStyle(color: Color(0xFF00D4FF), fontWeight: FontWeight.bold))),
        ],
      )
    );

    if (confirm != true) return;
    setState(() { _isDownloadingMap = true; _downloadProgress = "Iniciando..."; _progressValue = 0.0; });

    try {
      const double minLat = -4.2; const double maxLat = 12.5; const double minLng = -79.0; const double maxLng = -67.0; 
      final dio = Dio();
      List<int> zooms = [7, 8, 9]; 
      List<String> urlsToDownload = [];
      for (int z in zooms) {
        var p1 = _coordsToTile(maxLat, minLng, z);
        var p2 = _coordsToTile(minLat, maxLng, z);
        for (int x = p1.x; x <= p2.x; x++) {
          for (int y = p1.y; y <= p2.y; y++) {
            String url = _currentMapUrl.replaceAll('{z}', z.toString()).replaceAll('{x}', x.toString()).replaceAll('{y}', y.toString());
            urlsToDownload.add(url);
          }
        }
      }
      int total = urlsToDownload.length;
      int done = 0;
      for (String url in urlsToDownload) {
        try { await dio.get(url, options: Options(responseType: ResponseType.bytes)); } catch (_) {}
        done++;
        if (done % 10 == 0) { 
          setState(() { _progressValue = done / total; _downloadProgress = "${(done/total*100).toStringAsFixed(0)}%"; });
          await Future.delayed(Duration.zero);
        }
      }
      _msg("✅ Mapa descargado");
    } catch (e) { _msg("Error: $e"); } 
    finally { setState(() => _isDownloadingMap = false); }
  }

  Point<int> _coordsToTile(double lat, double lng, int zoom) {
    var n = pow(2, zoom);
    var x = ((lng + 180) / 360 * n).floor();
    var latRad = lat * pi / 180;
    var y = ((1 - (log(tan(latRad) + 1 / cos(latRad)) / pi)) / 2 * n).floor();
    return Point(x, y);
  }

  Future<void> _toggleGps() async {
    if (_isTracking) {
      _locationSubscription?.cancel();
      try { await _locationEngine.enableBackgroundMode(enable: false); } catch(e){}
      setState(() { _isTracking = false; _statusText = "GPS DETENIDO"; });
      return;
    }
    setState(() => _statusText = "INICIANDO...");
    bool s = await _locationEngine.serviceEnabled();
    if (!s) { s = await _locationEngine.requestService(); if (!s) return; }
    PermissionStatus p = await _locationEngine.hasPermission();
    if (p == PermissionStatus.denied) { p = await _locationEngine.requestPermission(); if (p != PermissionStatus.granted) return; }

    await _locationEngine.changeSettings(accuracy: LocationAccuracy.navigation, interval: 1000, distanceFilter: 0);
    try { await _locationEngine.enableBackgroundMode(enable: true); } catch (e) {}

    setState(() { _isTracking = true; _statusText = "BUSCANDO SEÑAL..."; });

    _locationSubscription = _locationEngine.onLocationChanged.listen((LocationData loc) {
      if (loc.latitude == null) return;
      setState(() {
        _hasPosition = true;
        _currentPos = LatLng(loc.latitude!, loc.longitude!);
        _accuracy = loc.accuracy ?? 0.0;
        _altitude = loc.altitude ?? 0.0;
        _route.add(_currentPos);
        _statusText = _accuracy < 15 ? "✅ GPS FIJO (±${_accuracy.toStringAsFixed(1)}m)" : "⚠️ SEÑAL DÉBIL (±${_accuracy.toStringAsFixed(0)}m)";
      });
      _mapController.move(_currentPos, _mapController.camera.zoom);
    });
  }

  // --- FOTO CORREGIDA ---
  Future<void> _takeGeoPhoto() async {
    if (!_hasPosition) { _msg("Sin coordenadas"); return; }
    
    String? imgName = await showDialog<String>(
      context: context,
      builder: (ctx) {
        String tempName = "";
        return AlertDialog(
          backgroundColor: const Color(0xFF2D3446),
          title: const Text("Nombre de la Evidencia", style: TextStyle(color: Colors.white)),
          content: TextField(
            style: const TextStyle(color: Colors.white),
            decoration: const InputDecoration(
              hintText: "Ej: Poste 01, Lote A...",
              hintStyle: TextStyle(color: Colors.grey),
              enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFF00D4FF))),
            ),
            onChanged: (val) => tempName = val,
          ),
          actions: [
            TextButton(onPressed: ()=>Navigator.pop(ctx, null), child: const Text("Cancelar", style: TextStyle(color: Colors.grey))),
            TextButton(onPressed: ()=>Navigator.pop(ctx, tempName.isEmpty ? "Sin Nombre" : tempName), 
              child: const Text("TOMAR FOTO", style: TextStyle(color: Color(0xFF00D4FF), fontWeight: FontWeight.bold))),
          ],
        );
      }
    );

    if (imgName == null) return; 

    bool access = await Gal.hasAccess();
    if (!access) await Gal.requestAccess();
    final XFile? photo = await _picker.pickImage(source: ImageSource.camera);
    if (photo == null) return;
    
    setState(() => _isSavingPhoto = true);
    
    try {
      final File imageFile = File(photo.path);
      final List<int> imageBytes = await imageFile.readAsBytes();
      img.Image? originalImage = img.decodeImage(Uint8List.fromList(imageBytes));

      if (originalImage != null) {
        int w = originalImage.width;
        int h = originalImage.height;
        int footerH = (h * 0.15).toInt();

        // Footer Negro
        img.fillRect(originalImage, x1: 0, y1: h - footerH, x2: w, y2: h, color: img.ColorRgb8(0, 0, 0));

        // MIRA TELESCÓPICA (CORREGIDA: Sin parámetro thickness)
        int cx = w ~/ 2;
        int cy = h ~/ 2;
        int size = 50;
        
        // Líneas
        img.drawLine(originalImage, x1: cx - size, y1: cy, x2: cx + size, y2: cy, color: img.ColorRgb8(255, 0, 0), thickness: 3);
        img.drawLine(originalImage, x1: cx, y1: cy - size, x2: cx, y2: cy + size, color: img.ColorRgb8(255, 0, 0), thickness: 3);
        
        // Círculo Central (Grueso simulado con múltiples círculos)
        img.drawCircle(originalImage, x: cx, y: cy, radius: 30, color: img.ColorRgb8(255, 0, 0));
        img.drawCircle(originalImage, x: cx, y: cy, radius: 29, color: img.ColorRgb8(255, 0, 0));
        img.drawCircle(originalImage, x: cx, y: cy, radius: 28, color: img.ColorRgb8(255, 0, 0));

        // Textos
        String date = DateFormat('dd/MM/yyyy HH:mm').format(DateTime.now());
        String coord = "LAT: ${_currentPos.latitude.toStringAsFixed(7)}   LNG: ${_currentPos.longitude.toStringAsFixed(7)}";
        String technical = "ALT: ${_altitude.toStringAsFixed(1)}m   PRECISIÓN: ±${_accuracy.toStringAsFixed(1)}m";
        
        int textX = 40;
        int basePath = h - footerH + 40;
        int lineHeight = 60; 

        img.drawString(originalImage, imgName.toUpperCase(), font: img.arial48, x: textX, y: basePath, color: img.ColorRgb8(255, 215, 0));
        img.drawString(originalImage, date, font: img.arial48, x: w - 500, y: basePath, color: img.ColorRgb8(255, 255, 255));
        img.drawString(originalImage, coord, font: img.arial48, x: textX, y: basePath + lineHeight, color: img.ColorRgb8(0, 255, 255));
        img.drawString(originalImage, technical, font: img.arial24, x: textX, y: basePath + (lineHeight * 2), color: img.ColorRgb8(0, 255, 0));

        final Directory tempDir = await getTemporaryDirectory();
        String cleanName = imgName.replaceAll(RegExp(r'[^\w\s]+'), '');
        final String newPath = '${tempDir.path}/GEO_${cleanName}_${DateTime.now().millisecondsSinceEpoch}.jpg';
        
        File(newPath).writeAsBytesSync(img.encodeJpg(originalImage));
        await Gal.putImage(newPath, album: 'GeoColombia');
        _msg("✅ FOTO GUARDADA: $imgName");
      }
    } catch (e) { _msg("Error: $e"); } 
    finally { setState(() => _isSavingPhoto = false); }
  }

  void _msg(String txt) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(txt), behavior: SnackBarBehavior.floating, backgroundColor: Colors.black87));
  }

  Widget _buildGlassButton({required IconData icon, VoidCallback? onTap, Color color = Colors.white}) {
    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(15),
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 5, sigmaY: 5),
          child: Container(
            width: 50, height: 50,
            color: Colors.black.withOpacity(0.5),
            child: Icon(icon, color: color),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          if (_isCacheReady)
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: const LatLng(4.5709, -74.2973),
              initialZoom: _currentZoom,
              onPositionChanged: (pos, hasGesture) {
                if (hasGesture && pos.zoom != null) _currentZoom = pos.zoom!;
              },
            ),
            children: [
              TileLayer(
                urlTemplate: _currentMapUrl, 
                userAgentPackageName: 'com.colombia.ultra',
                tileProvider: _tileProvider,
              ),
              PolylineLayer(polylines: [
                Polyline(points: _route, color: const Color(0xFF00D4FF), strokeWidth: 4),
              ]),
              if (_hasPosition)
                MarkerLayer(markers: [
                  Marker(
                    point: _currentPos,
                    width: 60, height: 60,
                    child: Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFF00D4FF).withOpacity(0.3),
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2)
                      ),
                      child: const Icon(Icons.navigation, color: Colors.white, size: 30),
                    ),
                  )
                ]),
            ],
          )
          else 
            const Center(child: CircularProgressIndicator(color: Color(0xFF00D4FF))),

          Positioned(
            top: 50, left: 15, right: 15,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: BackdropFilter(
                filter: ui.ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                child: Container(
                  padding: const EdgeInsets.all(15),
                  color: Colors.black.withOpacity(0.6),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(_statusText, style: const TextStyle(color: Color(0xFF00D4FF), fontWeight: FontWeight.bold, fontSize: 16)),
                          if (_hasPosition)
                            Text("${_currentPos.latitude.toStringAsFixed(5)}, ${_currentPos.longitude.toStringAsFixed(5)}", 
                              style: const TextStyle(color: Colors.white70, fontSize: 12)),
                        ],
                      ),
                      if(_isTracking) const Icon(Icons.satellite_alt, color: Colors.greenAccent, size: 30)
                    ],
                  ),
                ),
              ),
            ),
          ),

          Positioned(
            right: 15, bottom: 150,
            child: Column(
              children: [
                _buildGlassButton(icon: _isSatellite ? Icons.map : Icons.satellite, color: Colors.amber, onTap: _toggleMapType),
                const SizedBox(height: 15),
                _buildGlassButton(icon: Icons.cloud_download, color: Colors.purpleAccent, onTap: _downloadMap),
                const SizedBox(height: 15),
                _buildGlassButton(icon: Icons.add, onTap: _zoomIn),
                const SizedBox(height: 10),
                _buildGlassButton(icon: Icons.remove, onTap: _zoomOut),
              ],
            ),
          ),

          Positioned(
            bottom: 30, left: 20, right: 20,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(25),
              child: BackdropFilter(
                filter: ui.ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                child: Container(
                  height: 70, color: Colors.black.withOpacity(0.7),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      GestureDetector(
                        onTap: _toggleGps,
                        child: Container(
                          width: 140, height: 50,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(colors: _isTracking ? [Colors.redAccent, Colors.red] : [const Color(0xFF00D4FF), Colors.blueAccent]),
                            borderRadius: BorderRadius.circular(25),
                          ),
                          child: Center(child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                            Icon(_isTracking ? Icons.stop : Icons.play_arrow, color: Colors.white),
                            const SizedBox(width: 5),
                            Text(_isTracking ? "DETENER" : "INICIAR", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                          ])),
                        ),
                      ),
                      GestureDetector(
                        onTap: (_isTracking && _hasPosition) ? _takeGeoPhoto : null,
                        child: Container(
                          width: 50, height: 50,
                          decoration: BoxDecoration(
                            color: (_isTracking && _hasPosition) ? Colors.white : Colors.grey.withOpacity(0.3),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.camera, color: Colors.black, size: 30),
                        ),
                      )
                    ],
                  ),
                ),
              ),
            ),
          ),

          if (_isDownloadingMap)
            Container(color: Colors.black87, child: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.downloading, color: Colors.purpleAccent, size: 50),
              const SizedBox(height: 20),
              Text("DESCARGANDO...", style: GoogleFonts.rajdhani(color: Colors.white, fontSize: 20)),
              const SizedBox(height: 10),
              SizedBox(width: 200, child: LinearProgressIndicator(value: _progressValue, color: Colors.purpleAccent, backgroundColor: Colors.grey)),
              const SizedBox(height: 10),
              Text(_downloadProgress, style: const TextStyle(color: Colors.white70)),
            ]))),
          
          if (_isSavingPhoto)
            Container(color: Colors.black54, child: const Center(child: CircularProgressIndicator(color: Color(0xFF00D4FF)))),
        ],
      ),
    );
  }
}

class DioCacheTileProvider extends TileProvider {
  final CacheStore cacheStore;
  late final Dio _dio;
  DioCacheTileProvider({required this.cacheStore}) { _dio = Dio()..interceptors.add(DioCacheInterceptor(options: CacheOptions(store: cacheStore, policy: CachePolicy.forceCache, hitCacheOnErrorExcept: [401, 403], maxStale: const Duration(days: 365), priority: CachePriority.normal))); }
  @override ImageProvider getImage(TileCoordinates coordinates, TileLayer options) {
    final url = options.urlTemplate!.replaceAll('{z}', coordinates.z.toString()).replaceAll('{x}', coordinates.x.toString()).replaceAll('{y}', coordinates.y.toString());
    return DioImageProvider(_dio, url);
  }
}
class DioImageProvider extends ImageProvider<DioImageProvider> {
  final Dio dio; final String url;
  DioImageProvider(this.dio, this.url);
  @override Future<DioImageProvider> obtainKey(ImageConfiguration configuration) { return Future.value(this); }
  @override ImageStreamCompleter loadImage(DioImageProvider key, ImageDecoderCallback decode) {
    final StreamController<ImageChunkEvent> chunkEvents = StreamController<ImageChunkEvent>();
    return MultiFrameImageStreamCompleter(codec: _loadAsync(key, decode, chunkEvents), chunkEvents: chunkEvents.stream, scale: 1.0);
  }
  Future<ui.Codec> _loadAsync(DioImageProvider key, ImageDecoderCallback decode, StreamController<ImageChunkEvent> chunkEvents) async {
    try {
      final response = await dio.get<List<int>>(url, options: Options(responseType: ResponseType.bytes));
      final bytes = Uint8List.fromList(response.data!);
      final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
      return decode(buffer);
    } catch (e) { throw Exception('Error: $e'); }
  }
  @override bool operator ==(Object other) => other is DioImageProvider && other.url == url;
  @override int get hashCode => url.hashCode;
}