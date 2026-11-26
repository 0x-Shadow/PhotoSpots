import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photospot/services/geocoding.dart';

void main() {
  const photonResponse = '''
  {
    "features": [
      {
        "properties": {
          "name": "Miradouro da Senhora do Monte",
          "city": "Lisbon",
          "state": "Lisbon",
          "country": "Portugal"
        },
        "geometry": {"coordinates": [-9.1335, 38.7223]}
      },
      {
        "properties": {"name": "Rio", "country": "Portugal"},
        "geometry": {"coordinates": [-9.14, 38.71]}
      }
    ]
  }
  ''';

  Future<http.Client> client(String body, {int status = 200}) async =>
      MockClient((request) async => http.Response(body, status));

  test('search parses photon features into suggestions', () async {
    final service = GeocodingService(client: await client(photonResponse));
    final results = await service.search('miradouro');

    expect(results, hasLength(2));
    expect(results.first.label,
        'Miradouro da Senhora do Monte, Lisbon, Portugal');
    expect(results.first.city, 'Lisbon');
    expect(results.first.lat, 38.7223);
    expect(results.first.lng, -9.1335);
    expect(results.last.city, isEmpty);
  });

  test('search returns empty when the client fails or the body is not a list',
      () async {
    final failing = GeocodingService(
      client: MockClient((_) async => throw http.ClientException('offline')),
    );
    expect(await failing.search('anything'), isEmpty);

    final wrongBody =
        GeocodingService(client: await client('{"features":"nope"}'));
    expect(await wrongBody.search('anything'), isEmpty);
  });

  test('reverse maps coordinates to a label and city', () async {
    const body = '''
    {"features": [{"properties": {
      "name": "Miradouro", "city": "Lisbon", "country": "Portugal"
    }}]}
    ''';
    final service = GeocodingService(client: await client(body));
    final place = await service.reverse(38.7223, -9.1335);

    expect(place, isNotNull);
    expect(place!.label, 'Miradouro, Lisbon, Portugal');
    expect(place.city, 'Lisbon');
  });

  test('reverse returns null for an empty feature list', () async {
    final service = GeocodingService(client: await client('{"features":[]}'));
    expect(await service.reverse(0, 0), isNull);
  });
}
