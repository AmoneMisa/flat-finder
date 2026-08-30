import 'package:flutter_test/flutter_test.dart';
import 'package:flat_finder/models/listing.dart';

void main() {
  test('listing unwraps structured and stringified metro names', () {
    final structured = Listing.fromJson({
      'id': '1',
      'source': 'telegram',
      'country': 'UZ',
      'title': 'Flat',
      'metro': {'name': 'Novza', 'line': 'Chilanzar'},
      'city': 'Tashkent',
    });
    expect(structured.metro, 'Novza');

    final encoded = Listing.fromJson({
      'id': '2',
      'source': 'telegram',
      'country': 'UZ',
      'title': 'Flat',
      'metro': '{"name":"Novza","line":"Chilanzar"}',
      'city': 'Tashkent',
    });
    expect(encoded.metro, 'Novza');
  });
}
