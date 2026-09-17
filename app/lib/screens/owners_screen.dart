import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/listing_line.dart';
import '../models/listing_owner.dart';
import '../services/api_service.dart';
import '../state/settings.dart';

/// Owners: advertisers with two or more different listings in a country,
/// largest first. Tapping one returns it to the home screen, which then shows
/// only that owner's listings.
class OwnersScreen extends StatefulWidget {
  const OwnersScreen({super.key, required this.country});

  final String country;

  @override
  State<OwnersScreen> createState() => _OwnersScreenState();
}

class _OwnersScreenState extends State<OwnersScreen> {
  final List<ListingOwner> _owners = [];
  String? _next;
  bool _loading = false;
  bool _failed = false;
  bool _loadedOnce = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      final page = await context
          .read<ApiService>()
          .fetchOwners(widget.country, cursor: _next);
      if (!mounted) return;
      setState(() {
        _owners.addAll(page.owners);
        _next = page.next;
      });
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
          _loadedOnce = true;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<SettingsState>().s;
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(s.t('ownersTab'))),
      body: ListView.builder(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
        itemCount: _owners.length + 2,
        itemBuilder: (context, index) {
          if (index == 0) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Text(
                s.t('ownersIntro'),
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.hintColor),
              ),
            );
          }
          if (index == _owners.length + 1) {
            if (_loading) {
              return const Padding(
                padding: EdgeInsets.all(20),
                child: Center(child: CircularProgressIndicator()),
              );
            }
            if (_failed) {
              return _Note(text: s.t('ownersFailed'));
            }
            if (_loadedOnce && _owners.isEmpty) {
              return _Note(text: s.t('ownersEmpty'));
            }
            if (_next != null) {
              return Center(
                child: OutlinedButton(
                  onPressed: _load,
                  child: Text(s.t('ownersMore')),
                ),
              );
            }
            return const SizedBox.shrink();
          }
          final owner = _owners[index - 1];
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _OwnerCard(
              owner: owner,
              countLabel: s.t('ownerListings', {'n': '${owner.properties}'}),
              onTap: () => Navigator.of(context).pop(owner),
            ),
          );
        },
      ),
    );
  }
}

class _OwnerCard extends StatelessWidget {
  const _OwnerCard({
    required this.owner,
    required this.countLabel,
    required this.onTap,
  });

  final ListingOwner owner;
  final String countLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: BrandColors.bgPanel,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            width: 1.5,
            color: owner.line == null
                ? BrandColors.line
                : ListingLineColors.of(owner.line),
          ),
        ),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(
                width: 72,
                height: 56,
                child: owner.samplePhoto == null
                    ? const ColoredBox(
                        color: BrandColors.bgPanel2,
                        child: Icon(Icons.person_outline),
                      )
                    : CachedNetworkImage(
                        imageUrl: owner.samplePhoto!,
                        fit: BoxFit.cover,
                        errorWidget: (_, __, ___) =>
                            const ColoredBox(color: BrandColors.bgPanel2),
                      ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    owner.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  Text(countLabel),
                  if (owner.city != null)
                    Text(
                      owner.city!,
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: theme.hintColor),
                    ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right),
          ],
        ),
      ),
    );
  }
}

class _Note extends StatelessWidget {
  const _Note({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Center(child: Text(text, textAlign: TextAlign.center)),
    );
  }
}
