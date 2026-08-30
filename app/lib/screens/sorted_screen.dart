import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/sorted.dart';
import '../widgets/listing_card.dart';
import 'listing_detail.dart';

class SortedScreen extends StatelessWidget {
  const SortedScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final sorted = context.watch<SortedState>();
    return Scaffold(
      appBar: AppBar(title: const Text('Отсортированные')),
      body: sorted.items.isEmpty
          ? const Center(
              child: Text('Здесь появятся квартиры после свайпа вправо'))
          : ListView.builder(
              itemCount: sorted.items.length,
              itemBuilder: (context, index) {
                final listing = sorted.items[index];
                return Dismissible(
                  key: ValueKey('${listing.source}:${listing.id}'),
                  direction: DismissDirection.endToStart,
                  onDismissed: (_) => sorted.remove(listing.id),
                  background: Container(
                    alignment: Alignment.centerRight,
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    color: Colors.red,
                    child:
                        const Icon(Icons.delete_outline, color: Colors.white),
                  ),
                  child: ListingCard(
                    listing: listing,
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => ListingDetailScreen(listing: listing),
                      ),
                    ),
                  ),
                );
              },
            ),
    );
  }
}
