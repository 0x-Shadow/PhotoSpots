import 'dart:convert';

import 'package:http/http.dart' as http;

/// A place found by a Photon search. [city] may be empty for features that
/// only carry a country — the form falls back to a manual city in that case.
class PlaceSuggestion {
  const PlaceSuggestion({
    required this.label,
    required this.city,
    required this.lat,
    required this.lng,
  });

  final String label;
  final String city;
  final double lat;
  final double lng;
}

/// The reverse-geocoded address of a chosen pin.
class ReversePlace {
  const ReversePlace({required this.label, required this.city});

  final String label;
  final String city;
}

/// Free, keyless geocoding via Photon (OpenStreetMap data). Every lookup is
/// best effort: an offline device simply keeps the pin and reveals a manual
/// city field rather than blocking the publish flow.
class GeocodingService {
  const GeocodingService({this.client});

  final http.Client? client;

  static const _searchBase = 'https://photon.komoot.io/api/';
  static const _reverseBase = 'https://photon.komoot.io/reverse';

  Future<List<PlaceSuggestion>> search(String query, {int limit = 5}) async {
    if (query.trim().isEmpty) return const [];
    final owned = client ?? http.Client();
    try {
      final uri = Uri.parse(_searchBase).replace(
        queryParameters: {'q': query.trim(), 'limit': '$limit'},
      );
      final response = await owned.get(uri).timeout(const Duration(seconds: 6));
      if (response.statusCode != 200) return const [];
      final data = jsonDecode(response.body);
      if (data is! Map<String, dynamic> || data['features'] is! List) {
        return const [];
      }

      final results = <PlaceSuggestion>[];
      for (final feature in data['features'] as List) {
        if (feature is! Map<String, dynamic>) continue;
        final coordinates = feature['geometry'];
        if (coordinates is! Map || coordinates['coordinates'] is! List) {
          continue;
        }
        final pair = coordinates['coordinates'] as List;
        if (pair.length < 2) continue;
        final lng = _number(pair[0]);
        final lat = _number(pair[1]);
        if (lng == null || lat == null) continue;

        final props = feature['properties'];
        final properties = props is Map<String, dynamic> ? props : {};
        final city = _text(properties['city']);
        final parts = [
          _text(properties['name']),
          city,
          _text(properties['country']),
        ].where((part) => part.isNotEmpty).toList();
        if (parts.isEmpty) continue;
        results.add(
          PlaceSuggestion(
            label: parts.join(', '),
            city: city,
            lat: lat,
            lng: lng,
          ),
        );
      }
      return results;
    } catch (_) {
      return const [];
    } finally {
      if (client == null) owned.close();
    }
  }

  Future<ReversePlace?> reverse(double lat, double lng) async {
    final owned = client ?? http.Client();
    try {
      final uri = Uri.parse(_reverseBase).replace(
        queryParameters: {'lat': '$lat', 'lon': '$lng'},
      );
      final response = await owned.get(uri).timeout(const Duration(seconds: 6));
      if (response.statusCode != 200) return null;
      final data = jsonDecode(response.body);
      if (data is! Map<String, dynamic> || data['features'] is! List) {
        return null;
      }
      final features = data['features'] as List;
      if (features.isEmpty || features.first is! Map<String, dynamic>) {
        return null;
      }
      final properties = features.first['properties'];
      if (properties is! Map<String, dynamic>) return null;

      final city = _text(properties['city']);
      final parts = [
        _text(properties['name']),
        city,
        _text(properties['country']),
      ].where((part) => part.isNotEmpty).toList();
      if (parts.isEmpty) return null;
      return ReversePlace(label: parts.join(', '), city: city);
    } catch (_) {
      return null;
    } finally {
      if (client == null) owned.close();
    }
  }

  static String _text(Object? value) =>
      value is String ? value.trim() : value?.toString().trim() ?? '';

  static double? _number(Object? value) => switch (value) {
        num() => value.toDouble(),
        String() => double.tryParse(value),
        _ => null,
      };
}
