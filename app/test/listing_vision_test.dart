import 'package:flat_finder/models/listing.dart';
import 'package:flutter_test/flutter_test.dart';

Listing _listing({Object? vision}) => Listing.fromJson({
      'id': '1',
      'source': 'olx',
      'country': 'UZ',
      'title': 'listing',
      'propertyType': 'flat',
      'currency': 'USD',
      'city': 'Tashkent',
      'url': 'https://example.test/olx/UZ/1',
      'description': '',
      'tags': <String>[],
      if (vision != null) 'vision': vision,
    });

void main() {
  group('vision parsing', () {
    test('derivedFields drive which values are marked', () {
      final listing = _listing(
        vision: {
          'provider': 'llama-3.2-vision',
          'analyzedAt': '2026-09-04T10:00:00.000Z',
          'derivedFields': ['bedrooms', 'condition', 'tv'],
          // Per-field evidence is deliberately not modelled yet; its presence
          // must not break parsing.
          'data': {
            'bedrooms': {
              'value': 2,
              'confidence': 0.82,
              'evidence': ['two beds visible'],
            },
          },
        },
      );

      expect(listing.vision, isNotNull);
      expect(listing.vision!.provider, 'llama-3.2-vision');
      expect(listing.vision!.derived('bedrooms'), isTrue);
      expect(listing.vision!.derived('condition'), isTrue);
      expect(listing.vision!.derived('parking'), isFalse);
      expect(listing.vision!.isEmpty, isFalse);
    });

    test('a listing the backend never analyzed simply has no vision', () {
      expect(_listing().vision, isNull);
    });

    test('an empty or malformed payload never marks anything', () {
      expect(_listing(vision: {}).vision!.isEmpty, isTrue);
      expect(
        _listing(vision: {'derivedFields': <String>[]}).vision!.isEmpty,
        isTrue,
      );
      // A non-map vision value must not throw -- it is simply absent.
      expect(_listing(vision: 'nonsense').vision, isNull);
      // Blank entries are dropped rather than marking a field named "".
      expect(
        _listing(vision: {
          'derivedFields': ['', '  ', 'tv'],
        }).vision!.derivedFields,
        {'tv'},
      );
    });

    test('vision survives the round trip into favorites/history storage', () {
      final original = _listing(
        vision: {
          'provider': 'llama-3.2-vision',
          'derivedFields': ['balcony'],
        },
      );
      final restored = Listing.fromJson(original.toJson());

      expect(restored.vision!.derived('balcony'), isTrue);
      expect(restored.vision!.provider, 'llama-3.2-vision');
    });
  });
}
