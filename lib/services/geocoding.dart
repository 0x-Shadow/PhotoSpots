import 'dart:convert';

import 'package:http/http.dart' as http;

/// A place found by a geocoder. [city] may be empty for features that only
/// carry a country — the form falls back to a manual city in that case.
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

/// Search results plus whether the lookup itself broke (offline, blocked, or
/// every provider down) instead of simply having no matches. Screens use this
/// to tell "no places here" apart from "search is unavailable".
class PlaceSearchResult {
  const PlaceSearchResult({required this.results, required this.failed});

  static const empty = PlaceSearchResult(results: [], failed: false);

  final List<PlaceSuggestion> results;
  final bool failed;
}

/// Free, keyless geocoding via Photon (OpenStreetMap data), with Nominatim as
/// a second provider so one blocked or overloaded endpoint does not make place
/// search feel broken. Every lookup is best effort: an offline device keeps the
/// pin and reveals a manual city field rather than blocking publishing.
class GeocodingService {
  const GeocodingService({this.client});

  final http.Client? client;

  static const _photonSearch = 'https://photon.komoot.io/api/';
  static const _photonReverse = 'https://photon.komoot.io/reverse';
  static const _nominatimSearch = 'https://nominatim.openstreetmap.org/search';
  static const _nominatimReverse =
      'https://nominatim.openstreetmap.org/reverse';

  /// App identification required by the Nominatim usage policy.
  static const _userAgent = 'PhotoSpot/1.0 (community photo spot map)';

  Future<List<PlaceSuggestion>> search(String query, {int limit = 5}) async {
    final result = await searchPlaces(query, limit: limit);
    return result.results;
  }

  /// Searches Photon first, then Nominatim. [failed] is true only when both
  /// providers errored, so the UI can offer a clear recovery path.
  Future<PlaceSearchResult> searchPlaces(
    String query, {
    int limit = 5,
  }) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return PlaceSearchResult.empty;

    final owned = client ?? http.Client();
    var errored = false;
    try {
      try {
        final photon = await _searchPhoton(owned, trimmed, limit);
        if (photon.isNotEmpty) {
          return PlaceSearchResult(results: photon, failed: false);
        }
      } catch (_) {
        errored = true;
      }

      try {
        final nominatim = await _searchNominatim(owned, trimmed, limit);
        if (nominatim.isNotEmpty) {
          return PlaceSearchResult(results: nominatim, failed: false);
        }
      } catch (_) {
        errored = true;
      }

      return PlaceSearchResult(results: const [], failed: errored);
    } finally {
      if (client == null) owned.close();
    }
  }

  Future<List<PlaceSuggestion>> _searchPhoton(
    http.Client owned,
    String query,
    int limit,
  ) async {
    final uri = Uri.parse(_photonSearch).replace(
      queryParameters: {'q': query, 'limit': '$limit'},
    );
    final response = await owned.get(uri).timeout(const Duration(seconds: 6));
    // A rate limit or outage must fall through to the next provider and, if
    // every provider fails, reach the UI as "search unavailable" — not as an
    // empty result set that reads like "no such place".
    if (response.statusCode != 200) {
      throw StateError('Photon returned HTTP ${response.statusCode}');
    }
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
  }

  Future<List<PlaceSuggestion>> _searchNominatim(
    http.Client owned,
    String query,
    int limit,
  ) async {
    final uri = Uri.parse(_nominatimSearch).replace(
      queryParameters: {
        'q': query,
        'format': 'jsonv2',
        'limit': '$limit',
        'addressdetails': '1',
      },
    );
    final response = await owned
        .get(uri, headers: const {'User-Agent': _userAgent})
        .timeout(const Duration(seconds: 6));
    if (response.statusCode != 200) return const [];
    final data = jsonDecode(response.body);
    if (data is! List) return const [];

    final results = <PlaceSuggestion>[];
    for (final item in data) {
      if (item is! Map<String, dynamic>) continue;
      final lat = _number(item['lat']);
      final lng = _number(item['lon']);
      if (lat == null || lng == null) continue;
      final address = item['address'];
      final fields = address is Map
          ? Map<String, dynamic>.from(address)
          : const <String, dynamic>{};
      final city = _cityFromNominatim(fields);
      final name = _text(item['name']).isNotEmpty
          ? _text(item['name'])
          : _text(item['display_name']).split(',').first.trim();
      final country = _text(fields['country']);
      final parts = [
        name,
        city,
        country,
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
  }

  Future<ReversePlace?> reverse(double lat, double lng) async {
    final owned = client ?? http.Client();
    try {
      final uri = Uri.parse(_photonReverse).replace(
        queryParameters: {'lat': '$lat', 'lon': '$lng'},
      );
      final response = await owned.get(uri).timeout(const Duration(seconds: 6));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data is Map<String, dynamic> && data['features'] is List) {
          final features = data['features'] as List;
          if (features.isNotEmpty && features.first is Map<String, dynamic>) {
            final properties = features.first['properties'];
            if (properties is Map<String, dynamic>) {
              final city = _text(properties['city']);
              final parts = [
                _text(properties['name']),
                city,
                _text(properties['country']),
              ].where((part) => part.isNotEmpty).toList();
              if (parts.isNotEmpty) {
                return ReversePlace(label: parts.join(', '), city: city);
              }
            }
          }
        }
      }
    } catch (_) {
      // Fall through to Nominatim.
    }

    try {
      final uri = Uri.parse(_nominatimReverse).replace(
        queryParameters: {
          'lat': '$lat',
          'lon': '$lng',
          'format': 'jsonv2',
          'addressdetails': '1',
        },
      );
      final response = await owned
          .get(uri, headers: const {'User-Agent': _userAgent})
          .timeout(const Duration(seconds: 6));
      if (response.statusCode != 200) return null;
      final data = jsonDecode(response.body);
      if (data is! Map<String, dynamic>) return null;
      final address = data['address'];
      final fields = address is Map
          ? Map<String, dynamic>.from(address)
          : const <String, dynamic>{};
      final city = _cityFromNominatim(fields);
      final label = _text(data['display_name']);
      if (label.isEmpty && city.isEmpty) return null;
      return ReversePlace(
        label: label.isEmpty ? city : label,
        city: city,
      );
    } catch (_) {
      return null;
    } finally {
      if (client == null) owned.close();
    }
  }

  static String _cityFromNominatim(Map<String, dynamic> fields) {
    for (final key in const [
      'city',
      'town',
      'village',
      'municipality',
      'county',
      'state',
    ]) {
      final value = _text(fields[key]);
      if (value.isNotEmpty) return value;
    }
    return '';
  }

  static String _text(Object? value) =>
      value is String ? value.trim() : value?.toString().trim() ?? '';

  static double? _number(Object? value) => switch (value) {
        num() => value.toDouble(),
        String() => double.tryParse(value),
        _ => null,
      };
}