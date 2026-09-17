import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/strings.dart';
import '../models/listing.dart';
import '../models/listing_line.dart';
import '../state/app_state.dart';
import '../state/settings.dart';

/// "More from this contact" tab on the listing screen: the same contact's
/// other listings, one per property, loaded once when the tab is first shown.
class ContactListingsView extends StatefulWidget {
  const ContactListingsView({
    super.key,
    required this.listing,
    required this.s,
    required this.onOpen,
  });

  final Listing listing;
  final AppStrings s;
  final ValueChanged<Listing> onOpen;

  @override
  State<ContactListingsView> createState() => _ContactListingsViewState();
}

class _ContactListingsViewState extends State<ContactListingsView> {
  late Future<List<Listing>> _future =
      context.read<AppState>().contactListings(widget.listing);

  @override
  void didUpdateWidget(ContactListingsView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.listing.publicId != widget.listing.publicId) {
      _future = context.read<AppState>().contactListings(widget.listing);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return FutureBuilder<List<Listing>>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return _State(text: widget.s.t('contactListingsFailed'));
        }
        final listings = snapshot.data ?? const <Listing>[];
        if (listings.isEmpty) {
          return _State(text: widget.s.t('contactListingsEmpty'));
        }
        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
          itemCount: listings.length,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (context, index) {
            final item = listings[index];
            final line = item.listingLine;
            final price = item.price == null
                ? ''
                : '${item.price!.round()} ${item.currency}'.trim();
            final place = [item.city, item.district ?? '']
                .where((part) => part.trim().isNotEmpty)
                .join(', ');
            return InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: () => widget.onOpen(item),
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  color: BrandColors.bgPanel,
                  border: Border.all(
                    color: line == null
                        ? BrandColors.line
                        : ListingLineColors.of(line),
                  ),
                ),
                child: Row(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(7),
                      child: SizedBox(
                        width: 88,
                        height: 64,
                        child: item.photo == null
                            ? const ColoredBox(
                                color: BrandColors.bgPanel2,
                                child: Icon(Icons.image_not_supported_outlined),
                              )
                            : CachedNetworkImage(
                                imageUrl: item.photo!,
                                fit: BoxFit.cover,
                                errorWidget: (_, __, ___) => const ColoredBox(
                                  color: BrandColors.bgPanel2,
                                ),
                              ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (price.isNotEmpty)
                            Text(
                              price,
                              style: theme.textTheme.titleSmall
                                  ?.copyWith(fontWeight: FontWeight.w700),
                            ),
                          Text(
                            item.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          if (place.isNotEmpty)
                            Text(
                              place,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodySmall
                                  ?.copyWith(color: theme.hintColor),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _State extends StatelessWidget {
  const _State({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(text, textAlign: TextAlign.center),
      ),
    );
  }
}
