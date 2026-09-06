import 'dart:convert';

import 'package:flat_finder/models/listing.dart';
import 'package:flat_finder/state/favorites.dart';
import 'package:flat_finder/state/hidden.dart';
import 'package:flat_finder/state/sorted.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Listing _listing(String id) => Listing.fromJson({
      'id': id,
      'source': 'olx',
      'country': 'UZ',
      'title': id,
      'propertyType': 'flat',
      'currency': 'USD',
      'city': 'Tashkent',
      'url': 'https://example.test/$id',
      'description': '',
      'tags': <String>[],
    });

void main() {
  test('favorites rebuild identity index from persisted snapshots', () async {
    final a = _listing('a');
    final b = _listing('b');
    SharedPreferences.setMockInitialValues({
      'favorites': jsonEncode([a.toJson(), b.toJson()]),
    });

    final state = FavoritesState();
    await state.load();

    expect(state.isFavorite(a), isTrue);
    expect(state.isFavorite(b), isTrue);
    await state.remove(a);
    expect(state.isFavorite(a), isFalse);
    expect(state.isFavorite(b), isTrue);
  });

  test('hidden load limit and identity index stay aligned', () async {
    final rows = List.generate(201, (index) => _listing('$index'));
    SharedPreferences.setMockInitialValues({
      'hiddenListings': jsonEncode(rows.map((row) => row.toJson()).toList()),
    });

    final state = HiddenState();
    await state.load();

    expect(state.items, hasLength(200));
    expect(state.isHidden(rows.first), isTrue);
    expect(state.isHidden(rows.last), isFalse);
  });

  test('sorted index survives duplicate legacy identities across collections',
      () async {
    final duplicate = _listing('same');
    SharedPreferences.setMockInitialValues({
      'sortedListings': jsonEncode({
        'version': 3,
        'collections': [
          {
            'id': 'one',
            'title': 'One',
            'items': [duplicate.toJson()],
          },
          {
            'id': 'two',
            'title': 'Two',
            'items': [duplicate.toJson()],
          },
        ],
      }),
    });

    final state = SortedState();
    await state.load();
    expect(state.contains(duplicate), isTrue);

    await state.remove(duplicate, collectionId: 'one');
    expect(
      state.contains(duplicate),
      isTrue,
      reason: 'the second persisted collection still owns this identity',
    );

    await state.remove(duplicate, collectionId: 'two');
    expect(state.contains(duplicate), isFalse);
  });
}
