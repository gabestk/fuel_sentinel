// Mapa com o trajeto percorrido, usado no Abastecimento, no Scanner e na
// visualização do CSV.
//
// Os blocos do mapa vêm direto do OpenStreetMap, que não pede chave de API.
// O OpenStreetMap só bloqueia apps sem identificação ou com a identificação de
// exemplo do flutter_map, por isso o app se identifica como br.inmetro.fuelsentinel.
// No modo escuro os mesmos blocos são escurecidos no próprio aparelho.
// Sem internet os blocos não carregam, mas o trajeto continua desenhado sobre
// um fundo liso.

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

const _verde = Color(0xFF008355);

class MapaTrajeto extends StatefulWidget {
  final List<LatLng> pontos;

  /// Pontos onde uma volta terminou (bandeiras no mapa).
  final List<LatLng> fimDeVolta;

  /// true: acompanha o último ponto (coleta ao vivo).
  /// false: enquadra o trajeto inteiro (arquivo salvo).
  final bool seguir;

  const MapaTrajeto({
    super.key,
    required this.pontos,
    this.fimDeVolta = const [],
    this.seguir = true,
  });

  @override
  State<MapaTrajeto> createState() => _MapaTrajetoState();
}

class _MapaTrajetoState extends State<MapaTrajeto> {
  final MapController _controle = MapController();
  bool _pronto = false;
  LatLng? _ultimoMovido;

  @override
  void didUpdateWidget(covariant MapaTrajeto antigo) {
    super.didUpdateWidget(antigo);
    // a lista de pontos costuma ser a mesma, só com pontos novos no fim:
    // compara com o último ponto para onde o mapa já foi movido
    if (widget.seguir && _pronto && widget.pontos.isNotEmpty) {
      final ultimo = widget.pontos.last;
      if (ultimo != _ultimoMovido) {
        _ultimoMovido = ultimo;
        _controle.move(ultimo, _controle.camera.zoom);
      }
    }
  }

  Marker _marcador(LatLng p, IconData icone, Color cor) => Marker(
        point: p,
        width: 30,
        height: 30,
        child: Icon(icone, color: cor, size: 26, shadows: const [Shadow(blurRadius: 4)]),
      );

  @override
  Widget build(BuildContext context) {
    final pts = widget.pontos;
    if (pts.isEmpty) {
      return Container(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        alignment: Alignment.center,
        child: const Text('Aguardando o GPS...', style: TextStyle(color: Colors.grey)),
      );
    }
    final escuro = Theme.of(context).brightness == Brightness.dark;
    final limites = pts.length > 1 ? LatLngBounds.fromPoints(pts) : null;
    final enquadrar = !widget.seguir && limites != null && limites.north != limites.south;
    return FlutterMap(
      mapController: _controle,
      options: MapOptions(
        initialCenter: pts.last,
        initialZoom: 16,
        backgroundColor: escuro ? const Color(0xFF1E2227) : const Color(0xFFEDEFF2),
        maxZoom: 19,
        initialCameraFit: enquadrar
            ? CameraFit.bounds(bounds: limites, padding: const EdgeInsets.all(28))
            : null,
        onMapReady: () {
          _pronto = true;
          _ultimoMovido = pts.last;
        },
      ),
      children: [
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'br.inmetro.fuelsentinel',
          tileBuilder: escuro ? darkModeTileBuilder : null,
          maxZoom: 19,
        ),
        PolylineLayer(polylines: [
          Polyline(points: pts, strokeWidth: 4, color: escuro ? const Color(0xFF4FD1A0) : _verde),
        ]),
        MarkerLayer(markers: [
          for (final p in widget.fimDeVolta) _marcador(p, Icons.flag, Colors.orange),
          _marcador(pts.first, Icons.trip_origin, Colors.green),
          if (pts.length > 1) _marcador(pts.last, widget.seguir ? Icons.navigation : Icons.stop_circle, Colors.red),
        ]),
        RichAttributionWidget(
          attributions: [
            TextSourceAttribution('OpenStreetMap contributors'),
          ],
        ),
      ],
    );
  }
}

/// Mantido para o código que já usava o mapa antigo.
class MapWidget extends StatelessWidget {
  final List<LatLng> points;
  const MapWidget({super.key, required this.points});

  @override
  Widget build(BuildContext context) => MapaTrajeto(pontos: points);
}
