import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../models/listing.dart';
import '../utils/format.dart';

class MapView extends StatefulWidget {
  const MapView({
    super.key,
    required this.listings,
    required this.center,
    required this.onTapListing,
  });

  final List<Listing> listings;
  final LatLng center;
  final void Function(Listing) onTapListing;

  @override
  State<MapView> createState() => _MapViewState();
}

class _MapViewState extends State<MapView> {
  final MapController _controller = MapController();

  @override
  void didUpdateWidget(covariant MapView old) {
    super.didUpdateWidget(old);
    // Recenter when the country selection changes the center noticeably.
    if (old.center != widget.center) {
      _controller.move(widget.center, 6);
    }
  }

  @override
  Widget build(BuildContext context) {
    final located = widget.listings.where((l) => l.hasLocation).toList();
    return FlutterMap(
      mapController: _controller,
      options: MapOptions(
        initialCenter: widget.center,
        initialZoom: 6,
        minZoom: 2,
        maxZoom: 18,
      ),
      children: [
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'com.example.flat_finder',
          maxZoom: 19,
        ),
        MarkerLayer(
          markers: [
            for (final l in located)
              Marker(
                point: LatLng(l.lat!, l.lng!),
                width: 78,
                height: 34,
                child: GestureDetector(
                  onTap: () => widget.onTapListing(l),
                  child: _PricePin(listing: l),
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
    );
  }
}

class _PricePin extends StatelessWidget {
  const _PricePin({required this.listing});
  final Listing listing;

  @override
  Widget build(BuildContext context) {
    final color =
        listing.byAgency ? Colors.orange.shade700 : Theme.of(context).colorScheme.primary;
    final label = listing.price != null ? _short(listing.price!) : '—';
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
        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
      ),
    );
  }

  static String _short(num v) {
    if (v >= 1000000) return '${(v / 1000000).toStringAsFixed(1)}M';
    if (v >= 1000) return '${(v / 1000).toStringAsFixed(0)}K';
    return v.toString();
  }
}
