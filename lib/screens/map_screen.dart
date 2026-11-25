import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import 'package:geolocator/geolocator.dart';

import '../models/spot.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import 'spot_detail_screen.dart';

/// Map screen — optimized, no rotation, accurate pins, proper tile loading.
class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  final _mapController = MapController();
  final _searchController = TextEditingController();

  Spot? _selected;
  String _filter = 'All';
  bool _mapReady = false;

  static const _filters = ['All', 'Date', 'Friends', 'Sunset', 'Photo'];
  static const _fallbackCenter = LatLng(38.7128, -9.1393);

  @override
  void dispose() {
    _searchController.dispose();
    _mapController.dispose();
    super.dispose();
  }

  Future<void> _goToMyLocation() async {
    bool serviceEnabled;
    LocationPermission permission;

    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Location services are disabled')),
      );
      return;
    }

    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Location permission denied')),
        );
        return;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Location permission permanently denied')),
      );
      return;
    }

    final position = await Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.high,
    );
    _mapController.move(LatLng(position.latitude, position.longitude), 14);
  }

  List<Spot> _visible(AppState state) {
    var list = List<Spot>.from(state.spots);
    if (_filter != 'All') {
      list = list.where((s) => s.tags.any((t) =>
          t.toLowerCase().contains(_filter.toLowerCase()))).toList();
    }
    final q = _searchController.text.toLowerCase();
    if (q.isNotEmpty) {
      list = list.where((s) =>
          s.title.toLowerCase().contains(q) ||
          s.city.toLowerCase().contains(q)).toList();
    }
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final spots = _visible(state);

    return Stack(
      children: [
        FlutterMap(
          mapController: _mapController,
          options: MapOptions(
            initialCenter: _fallbackCenter,
            initialZoom: 12.5,
            minZoom: 4,
            maxZoom: 17,
            backgroundColor: AppColors.mapBackground,
            interactionOptions: const InteractionOptions(
              flags: InteractiveFlag.drag |
                  InteractiveFlag.pinchZoom |
                  InteractiveFlag.doubleTapZoom |
                  InteractiveFlag.flingAnimation,
            ),
            onMapReady: () => setState(() => _mapReady = true),
            onTap: (_, __) {
              setState(() => _selected = null);
              FocusManager.instance.primaryFocus?.unfocus();
            },
          ),
          children: [
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'com.photospot.app',
              maxZoom: 17,
              errorTileCallback: (tile, error, stackTrace) {
                // Silent fail — keep showing existing tiles
              },
            ),
            MarkerLayer(
              markers: spots.map((spot) {
                final selected = _selected?.id == spot.id;
                return Marker(
                  point: spot.location,
                  width: selected ? 64 : 48,
                  height: selected ? 64 : 48,
                  alignment: Alignment.center,
                  child: GestureDetector(
                    onTap: () {
                      setState(() => _selected = spot);
                      _mapController.move(spot.location, 15);
                    },
                    child: Container(
                      padding: const EdgeInsets.all(3),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.5),
                            blurRadius: 12,
                            offset: const Offset(0, 5),
                          ),
                        ],
                      ),
                      child: ClipOval(
                        child: Image.network(
                          spot.coverUrl,
                          width: selected ? 52 : 38,
                          height: selected ? 52 : 38,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Container(
                            width: 38,
                            height: 38,
                            color: AppColors.surfaceElevated,
                            child: const Icon(Icons.place_rounded,
                                color: AppColors.textFaint, size: 18),
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ],
        ),

        // Top bar: search + filters.
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
              child: Column(
                children: [
                  TextField(
                    controller: _searchController,
                    onChanged: (_) => setState(() {}),
                    style: const TextStyle(color: AppColors.textPrimary),
                    decoration: InputDecoration(
                      hintText: 'Search places...',
                      filled: true,
                      fillColor: const Color(0xF2161618),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 14),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: const BorderSide(color: AppColors.hairline),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: const BorderSide(color: AppColors.hairline),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 38,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: _filters.length,
                      separatorBuilder: (_, _) => const SizedBox(width: 8),
                      itemBuilder: (_, i) {
                        final f = _filters[i];
                        final selected = f == _filter;
                        return GestureDetector(
                          onTap: () => setState(() => _filter = f),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 160),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 8),
                            decoration: BoxDecoration(
                              color: selected
                                  ? AppColors.action
                                  : const Color(0xF2161618),
                              borderRadius: BorderRadius.circular(999),
                              border: Border.all(
                                color: selected
                                    ? AppColors.action
                                    : AppColors.hairline,
                              ),
                            ),
                            child: Text(
                              f,
                              style: TextStyle(
                                color: selected
                                    ? AppColors.onAction
                                    : AppColors.textSecondary,
                                fontSize: 13.5,
                                fontWeight: selected
                                    ? FontWeight.w800
                                    : FontWeight.w600,
                                fontFamily: 'Inter',
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),

        // My location button.
        Positioned(
          right: 16,
          bottom: 128,
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: _goToMyLocation,
              borderRadius: BorderRadius.circular(14),
              child: Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: AppColors.surfaceElevated,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.hairline),
                ),
                child: const Icon(Icons.my_location_rounded,
                    color: AppColors.textPrimary, size: 24),
              ),
            ),
          ),
        ),

        // Floating place card.
        if (_selected != null)
          Positioned(
            left: 16,
            right: 16,
            bottom: 196,
            child: _PlaceCard(spot: _selected!, saved: state.isSaved(_selected!.id)),
          ),
      ],
    );
  }
}

class _PlaceCard extends StatelessWidget {
  const _PlaceCard({required this.spot, required this.saved});

  final Spot spot;
  final bool saved;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        context.read<AppState>().recordView(spot);
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => SpotDetailScreen(spotId: spot.id),
          ),
        );
      },
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: const Color(0xF2161618),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.hairline),
        ),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.network(
                spot.coverUrl,
                width: 62,
                height: 62,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => Container(
                  width: 62,
                  height: 62,
                  color: AppColors.surfaceElevated,
                  child: const Icon(Icons.landscape_rounded,
                      color: AppColors.textFaint),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    spot.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 15.5,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.3,
                      fontFamily: 'Inter',
                    ),
                  ),
                  const SizedBox(height: 5),
                  Row(
                    children: [
                      const Icon(Icons.star_rounded,
                          color: AppColors.star, size: 14),
                      const SizedBox(width: 3),
                      Text(
                        spot.rating.toStringAsFixed(1),
                        style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w800,
                          fontFamily: 'Inter',
                        ),
                      ),
                      Text(
                        ' (${spot.reviewCount >= 1000 ? '${(spot.reviewCount / 1000).toStringAsFixed(1)}k' : spot.reviewCount})',
                        style: const TextStyle(
                            color: AppColors.textFaint, fontSize: 12, fontFamily: 'Inter'),
                      ),
                      const SizedBox(width: 8),
                      const Icon(Icons.place_rounded,
                          color: AppColors.textFaint, size: 13),
                      const Text(
                        '3.2 km',
                        style: TextStyle(
                            color: AppColors.textFaint,
                            fontSize: 12,
                            fontFamily: 'Inter'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    spot.bestTime != null
                        ? 'Best view in ${spot.city} · ${spot.bestTime}'
                        : 'Best view in ${spot.city}',
                    style: const TextStyle(
                        color: AppColors.textSecondary, fontSize: 12.5, fontFamily: 'Inter'),
                  ),
                ],
              ),
            ),
            GestureDetector(
              onTap: () {
                context.read<AppState>().toggleSave(spot);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                        saved ? 'Removed from Saved' : 'Saved to your list'),
                    duration: const Duration(seconds: 1),
                  ),
                );
              },
              child: Icon(
                saved ? Icons.bookmark_rounded : Icons.bookmark_outline_rounded,
                color: saved ? AppColors.star : AppColors.textSecondary,
                size: 22,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
