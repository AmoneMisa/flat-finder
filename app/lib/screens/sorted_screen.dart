import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/settings.dart';
import '../state/sorted.dart';
import '../widgets/listing_card.dart';
import 'listing_detail.dart';

class SortedScreen extends StatelessWidget {
  const SortedScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final sorted = context.watch<SortedState>();
    final settings = context.watch<SettingsState>();
    final ru = settings.lang == 'ru';
    return Scaffold(
      appBar: AppBar(title: Text(ru ? 'Отсортированные' : 'Sorted')),
      body: sorted.collections.isEmpty
          ? Center(
              child: Text(
                ru
                    ? 'Здесь появятся квартиры после свайпа вправо'
                    : 'Apartments sorted with a right swipe will appear here',
                textAlign: TextAlign.center,
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.only(bottom: 24),
              itemCount: sorted.collections.length,
              itemBuilder: (context, collectionIndex) {
                final collection = sorted.collections[collectionIndex];
                return Card(
                  margin: const EdgeInsets.fromLTRB(8, 8, 8, 0),
                  clipBehavior: Clip.antiAlias,
                  child: ExpansionTile(
                    initiallyExpanded: collectionIndex == 0,
                    leading: Icon(
                      collection.isPreset
                          ? Icons.bookmark_added_outlined
                          : Icons.done_all,
                    ),
                    title: Text(
                      collection.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(
                      collection.isPreset
                          ? (ru
                              ? 'Пресет · ${collection.items.length} квартир'
                              : 'Preset · ${collection.items.length} apartments')
                          : (ru
                              ? '${collection.items.length} квартир'
                              : '${collection.items.length} apartments'),
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (collection.isPreset)
                          Padding(
                            padding: const EdgeInsets.only(right: 4),
                            child: Chip(
                              visualDensity: VisualDensity.compact,
                              label: Text(ru ? 'Пресет' : 'Preset'),
                            ),
                          ),
                        IconButton(
                          tooltip: ru ? 'Удалить список' : 'Delete collection',
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () =>
                              sorted.removeCollection(collection.id),
                        ),
                        const Icon(Icons.expand_more),
                      ],
                    ),
                    children: [
                      for (final listing in collection.items)
                        Dismissible(
                          key: ValueKey(
                            '${collection.id}:${listing.source}:${listing.country}:${listing.id}',
                          ),
                          direction: DismissDirection.endToStart,
                          onDismissed: (_) => sorted.remove(
                            listing,
                            collectionId: collection.id,
                          ),
                          background: Container(
                            alignment: Alignment.centerRight,
                            padding: const EdgeInsets.symmetric(horizontal: 24),
                            color: Colors.red,
                            child: const Icon(
                              Icons.delete_outline,
                              color: Colors.white,
                            ),
                          ),
                          child: ListingCard(
                            listing: listing,
                            onTap: () => Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) =>
                                    ListingDetailScreen(listing: listing),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                );
              },
            ),
    );
  }
}
