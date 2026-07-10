import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../models/listing.dart';
import '../state/settings.dart';
import '../utils/format.dart';

class MapView extends StatefulWidget {
  const MapView({
    super.key,
    required this.listings,
    required this.center,
    required this.onTapListing,
    this.rates,
    this.displayCurrency,
  });

  final List<Listing> listings;
  final LatLng center;
  final void Function(Listing) onTapListing;
  final Map<String, double>? rates;
  final String? displayCurrency;

  @override
  State<MapView> createState() => _MapViewState();
}

class _MapViewState extends State<MapView> {
  final MapController _controller = MapController();

  // Freeform search area the user outlines by tapping the map.
  bool _drawing = false;
  final List<LatLng> _area = [];

  @override
  void didUpdateWidget(covariant MapView old) {
    super.didUpdateWidget(old);
    // Recenter when the country selection changes the center noticeably.
    if (old.center != widget.center) {
      _controller.move(widget.center, 6);
    }
  }

  /// Listings restricted to the drawn area (once it has at least 3 points).
  List<Listing> get _visible {
    final located = widget.listings.where((l) => l.hasLocation).toList();
    if (_area.length < 3) return located;
    return located
        .where((l) => _pointInPolygon(LatLng(l.lat!, l.lng!), _area))
        .toList();
  }

  // Ray-casting point-in-polygon test on lat/lng.
  bool _pointInPolygon(LatLng p, List<LatLng> poly) {
    bool inside = false;
    for (int i = 0, j = poly.length - 1; i < poly.length; j = i++) {
      final xi = poly[i].longitude, yi = poly[i].latitude;
      final xj = poly[j].longitude, yj = poly[j].latitude;
      final intersect = ((yi > p.latitude) != (yj > p.latitude)) &&
          (p.longitude < (xj - xi) * (p.latitude - yi) / (yj - yi) + xi);
      if (intersect) inside = !inside;
    }
    return inside;
  }

  void _onMapTap(LatLng point) {
    if (!_drawing) return;
    setState(() => _area.add(point));
  }

  void _clearArea() => setState(() => _area.clear());

  @override
  Widget build(BuildContext context) {
    final s = context.watch<SettingsState>().s;
    final visible = _visible;
    return Stack(
      children: [
        FlutterMap(
          mapController: _controller,
          options: MapOptions(
            initialCenter: widget.center,
            initialZoom: 6,
            minZoom: 2,
            maxZoom: 18,
            onTap: (_, point) => _onMapTap(point),
          ),
          children: [
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'com.example.flat_finder',
              maxZoom: 19,
            ),
            if (_area.length >= 3)
              PolygonLayer(
                polygons: [
                  Polygon(
                    points: _area,
                    borderStrokeWidth: 2,
                    borderColor: Theme.of(context).colorScheme.primary,
                    color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.15),
                  ),
                ],
              ),
            if (_area.length >= 2 && _area.length < 3)
              PolylineLayer(
                polylines: [
                  Polyline(
                    points: _area,
                    strokeWidth: 2,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ],
              ),
            if (_drawing)
              MarkerLayer(
                markers: [
                  for (final pt in _area)
                    Marker(
                      point: pt,
                      width: 14,
                      height: 14,
                      child: Container(
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.primary,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 2),
                        ),
                      ),
                    ),
                ],
              ),
            MarkerLayer(
              markers: [
                for (final l in visible)
                  Marker(
                    point: LatLng(l.lat!, l.lng!),
                    width: 96,
                    height: 34,
                    child: GestureDetector(
                      onTap: () => widget.onTapListing(l),
                      child: _PricePin(
                        listing: l,
                        rates: widget.rates,
                        displayCurrency: widget.displayCurrency,
                      ),
                    ),
                  ),
              ],
            ),
            const RichAttributionWidget(
              attributions: [
                TextSourceAttribution('© OpenStreetMap contributors'),
              ],
            ),
          ],
        ),
        // Draw controls.
        Positioned(
          top: 12,
          right: 12,
          child: Column(
            children: [
              FloatingActionButton.small(
                heroTag: 'draw',
                onPressed: () => setState(() => _drawing = !_drawing),
                backgroundColor: _drawing
                    ? Theme.of(context).colorScheme.primary
                    : Theme.of(context).colorScheme.surface,
                foregroundColor: _drawing
                    ? Theme.of(context).colorScheme.onPrimary
                    : Theme.of(context).colorScheme.onSurface,
                child: Icon(_drawing ? Icons.check : Icons.gesture),
              ),
              if (_area.isNotEmpty) ...[
                const SizedBox(height: 8),
                FloatingActionButton.small(
                  heroTag: 'clearArea',
                  onPressed: _clearArea,
                  backgroundColor: Theme.of(context).colorScheme.surface,
                  foregroundColor: Theme.of(context).colorScheme.onSurface,
                  child: const Icon(Icons.delete_outline),
                ),
              ],
            ],
          ),
        ),
        // Hint while drawing, or a count once an area is applied.
        if (_drawing || _area.length >= 3)
          Positioned(
            top: 12,
            left: 12,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Text(
                _area.length >= 3
                    ? s.t('inArea', {'n': '${visible.length}'})
                    : s.t('drawHint'),
                style: const TextStyle(color: Colors.white, fontSize: 12),
              ),
            ),
          ),
      ],
    );
  }
}

class _PricePin extends StatelessWidget {
  const _PricePin({required this.listing, this.rates, this.displayCurrency});
  final Listing listing;
  final Map<String, double>? rates;
  final String? displayCurrency;

  @override
  Widget build(BuildContext context) {
    final color =
        listing.byAgency ? Colors.orange.shade700 : Theme.of(context).colorScheme.primary;
    final label = pinPriceLabel(listing, rates: rates, displayCurrency: displayCurrency);
    return Container(
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 3)],
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
      ),
    );
  }
}
