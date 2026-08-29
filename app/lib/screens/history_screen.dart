import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/listing.dart';
import '../state/history.dart';
import '../state/settings.dart';
import '../widgets/listing_card.dart';
import 'listing_detail.dart';

/// Recently viewed listings, newest first (capped by [HistoryState.maxItems]).
class HistoryScreen extends StatelessWidget {
  const HistoryScreen({super.key});

  void _open(BuildContext context, Listing l) {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => ListingDetailScreen(listing: l)));
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsState>();
    final history = context.watch<HistoryState>();
    final s = settings.s;
    final items = history.items;

    return Scaffold(
      appBar: AppBar(
        title: Text(s.t('history')),
        actions: [
          if (!history.isEmpty)
            IconButton(
              tooltip: s.t('clearHistory'),
              icon: const Icon(Icons.delete_sweep_outlined),
              onPressed: history.clear,
            ),
        ],
      ),
      body: history.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.history, size: 48),
                    const SizedBox(height: 12),
                    Text(s.t('noHistory'), textAlign: TextAlign.center),
                  ],
                ),
              ),
            )
          : LayoutBuilder(
              builder: (context, constraints) {
                final columns = _columnsFor(constraints.maxWidth);
                if (columns == 1) {
                  return ListView.builder(
                    padding: const EdgeInsets.only(bottom: 24, top: 4),
                    itemCount: items.length,
                    itemBuilder: (_, i) => ListingCard(
                      listing: items[i],
                      onTap: () => _open(context, items[i]),
                    ),
                  );
                }
                return GridView.builder(
                  padding: const EdgeInsets.fromLTRB(6, 4, 6, 24),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: columns,
                    childAspectRatio: 0.82,
                    mainAxisSpacing: 2,
                    crossAxisSpacing: 2,
                  ),
                  itemCount: items.length,
                  itemBuilder: (_, i) => ListingCard(
                    listing: items[i],
                    grid: true,
                    onTap: () => _open(context, items[i]),
                  ),
                );
              },
            ),
    );
  }

  /// Column count from the available width: 1 on phones, up to 4 on wide
  /// desktop windows (mirrors the home grid).
  int _columnsFor(double width) {
    if (width >= 1500) return 4;
    if (width >= 1100) return 3;
    if (width >= 700) return 2;
    return 1;
  }
}
