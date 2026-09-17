import 'listing_line.dart';

/// An owner collection: an advertiser with two or more distinct active
/// properties, identified by the backend's opaque owner key (never the phone
/// number in URLs or filters).
class ListingOwner {
  const ListingOwner({
    required this.ownerKey,
    required this.contact,
    required this.country,
    required this.properties,
    required this.listings,
    this.city,
    this.line,
    this.samplePhoto,
    this.sampleTitle,
  });

  final String ownerKey;
  final String contact;
  final String country;
  final String? city;
  final int properties;
  final int listings;
  final ListingLine? line;
  final String? samplePhoto;
  final String? sampleTitle;

  static final RegExp keyPattern = RegExp(r'^[0-9a-f]{24}$');

  static bool isKey(String? value) => value != null && keyPattern.hasMatch(value);

  factory ListingOwner.fromJson(Map<String, dynamic> j) {
    final sample = j['sample'];
    return ListingOwner(
      ownerKey: (j['ownerKey'] ?? '').toString(),
      contact: (j['contact'] ?? '').toString(),
      country: (j['country'] ?? '').toString(),
      city: j['city'] as String?,
      properties: (j['properties'] as num?)?.toInt() ?? 0,
      listings: (j['listings'] as num?)?.toInt() ?? 0,
      line: listingLineFromJson(j['listingLine']),
      samplePhoto: sample is Map ? sample['photo'] as String? : null,
      sampleTitle: sample is Map ? sample['title'] as String? : null,
    );
  }

  /// Readable contact, grouped like the website for the covered markets;
  /// other numbers are shown as plain E.164 rather than guessed at.
  String get label => ownerContactLabel(contact);
}

class OwnersPage {
  const OwnersPage({required this.owners, this.next});

  final List<ListingOwner> owners;
  final String? next;
}

const _phoneGroups = <(String, List<int>)>[
  ('998', [2, 3, 2, 2]),
  ('996', [3, 3, 3]),
  ('380', [2, 3, 2, 2]),
  ('40', [3, 3, 3]),
  ('7', [3, 3, 2, 2]),
];

String ownerContactLabel(String contact) {
  if (!RegExp(r'^\+\d{7,15}$').hasMatch(contact)) return contact;
  final digits = contact.substring(1);
  for (final (code, groups) in _phoneGroups) {
    if (!digits.startsWith(code)) continue;
    final national = digits.substring(code.length);
    if (national.length != groups.fold<int>(0, (sum, size) => sum + size)) {
      continue;
    }
    final parts = <String>[];
    var offset = 0;
    for (final size in groups) {
      parts.add(national.substring(offset, offset + size));
      offset += size;
    }
    return '+$code ${parts.join(' ')}';
  }
  return contact;
}
