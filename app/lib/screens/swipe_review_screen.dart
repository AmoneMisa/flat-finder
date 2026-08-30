import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/listing.dart';
import '../state/hidden.dart';
import '../state/sorted.dart';
import '../widgets/listing_card.dart';

/// Dating-style review for the currently selected search result set.
class SwipeReviewScreen extends StatefulWidget {
  const SwipeReviewScreen({super.key, required this.listings});

  final List<Listing> listings;

  @override
  State<SwipeReviewScreen> createState() => _SwipeReviewScreenState();
}

class _SwipeReviewScreenState extends State<SwipeReviewScreen> {
  var _index = 0;

  Future<void> _decide(DismissDirection direction) async {
    if (_index >= widget.listings.length) return;
    final listing = widget.listings[_index];
    if (direction == DismissDirection.endToStart) {
      final hidden = context.read<HiddenState>();
      if (!hidden.isHidden(listing.id)) await hidden.toggle(listing);
    } else {
      await context.read<SortedState>().add(listing);
    }
    if (mounted) setState(() => _index++);
  }

  @override
  Widget build(BuildContext context) {
    final remaining = widget.listings.length - _index;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Просмотр подборки'),
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Center(child: Text('$remaining')),
          ),
        ],
      ),
      body: SafeArea(
        child: remaining <= 0
            ? const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.done_all, size: 56),
                    SizedBox(height: 12),
                    Text('Подборка просмотрена'),
                  ],
                ),
              )
            : Column(
                children: [
                  const Padding(
                    padding: EdgeInsets.fromLTRB(16, 10, 16, 4),
                    child: Text(
                      '← скрыть   •   вправо сохранить →',
                      textAlign: TextAlign.center,
                    ),
                  ),
                  Expanded(
                    child: Dismissible(
                      key: ValueKey(
                        '${widget.listings[_index].source}:${widget.listings[_index].id}',
                      ),
                      direction: DismissDirection.horizontal,
                      confirmDismiss: (direction) async {
                        await _decide(direction);
                        return false;
                      },
                      background: const _DecisionBackground(
                        alignment: Alignment.centerLeft,
                        color: Color(0xFF159957),
                        icon: Icons.favorite,
                        label: 'Отсортировать',
                      ),
                      secondaryBackground: const _DecisionBackground(
                        alignment: Alignment.centerRight,
                        color: Color(0xFFB23A48),
                        icon: Icons.visibility_off,
                        label: 'Скрыть',
                      ),
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
                        child: ListingCard(
                          listing: widget.listings[_index],
                          onTap: () {},
                        ),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        FloatingActionButton(
                          heroTag: 'swipe-hide',
                          backgroundColor: const Color(0xFFB23A48),
                          onPressed: () => _decide(DismissDirection.endToStart),
                          child: const Icon(Icons.close),
                        ),
                        FloatingActionButton(
                          heroTag: 'swipe-save',
                          backgroundColor: const Color(0xFF159957),
                          onPressed: () => _decide(DismissDirection.startToEnd),
                          child: const Icon(Icons.favorite),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

class _DecisionBackground extends StatelessWidget {
  const _DecisionBackground({
    required this.alignment,
    required this.color,
    required this.icon,
    required this.label,
  });

  final Alignment alignment;
  final Color color;
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => Container(
        alignment: alignment,
        padding: const EdgeInsets.symmetric(horizontal: 28),
        color: color,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Colors.white, size: 38),
            Text(label, style: const TextStyle(color: Colors.white)),
          ],
        ),
      );
}
