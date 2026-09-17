import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/strings.dart';
import '../models/listing_owner.dart';
import '../services/api_service.dart';
import '../state/settings.dart';

/// Breadcrumbs above one owner's listings: Listings › Owners › owner.
class OwnerBreadcrumbs extends StatefulWidget {
  const OwnerBreadcrumbs({
    super.key,
    required this.ownerKey,
    required this.s,
    required this.onAllListings,
    required this.onOwners,
  });

  final String ownerKey;
  final AppStrings s;
  final VoidCallback onAllListings;
  final VoidCallback onOwners;

  @override
  State<OwnerBreadcrumbs> createState() => _OwnerBreadcrumbsState();
}

class _OwnerBreadcrumbsState extends State<OwnerBreadcrumbs> {
  late Future<ListingOwner?> _owner =
      context.read<ApiService>().fetchOwner(widget.ownerKey);

  @override
  void didUpdateWidget(OwnerBreadcrumbs oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.ownerKey != widget.ownerKey) {
      _owner = context.read<ApiService>().fetchOwner(widget.ownerKey);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(color: BrandColors.textMuted);
    final s = widget.s;
    return Semantics(
      container: true,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
        child: Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 6,
          children: [
            _Crumb(label: s.t('breadcrumbListings'), onTap: widget.onAllListings),
            Text('›', style: muted),
            _Crumb(label: s.t('ownersTab'), onTap: widget.onOwners),
            Text('›', style: muted),
            FutureBuilder<ListingOwner?>(
              future: _owner,
              builder: (context, snapshot) {
                final owner = snapshot.data;
                final text = owner == null
                    ? s.t('ownerFallback')
                    : '${owner.label} · ${s.t('ownerListings', {'n': '${owner.properties}'})}';
                return Semantics(
                  selected: true,
                  child: Text(
                    text,
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _Crumb extends StatelessWidget {
  const _Crumb({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 2),
        child: Text(
          label,
          style: Theme.of(context)
              .textTheme
              .bodyMedium
              ?.copyWith(color: BrandColors.textMuted),
        ),
      ),
    );
  }
}
