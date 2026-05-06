import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:nexgen_command/app_router.dart';
import 'package:nexgen_command/features/installer/installer_access_providers.dart';
import 'package:nexgen_command/theme.dart';

/// Search/select screen for installers entering an existing customer's
/// account. Selection sets [installerAccessingCustomerProvider] (and the
/// display-name provider used by the banner) to the chosen UID and
/// navigates to the main customer dashboard. The [InstallerModeBanner]
/// stays visible until the installer taps Exit.
class ExistingCustomerScreen extends ConsumerStatefulWidget {
  const ExistingCustomerScreen({super.key});

  @override
  ConsumerState<ExistingCustomerScreen> createState() =>
      _ExistingCustomerScreenState();
}

class _ExistingCustomerScreenState
    extends ConsumerState<ExistingCustomerScreen> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  Timer? _debounce;
  String _query = '';
  bool _searching = false;
  Object? _searchError;
  List<CustomerSearchHit> _results = const [];

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onQueryChanged(String value) {
    setState(() {
      _query = value;
    });
    _debounce?.cancel();
    if (value.trim().isEmpty) {
      setState(() {
        _results = const [];
        _searchError = null;
        _searching = false;
      });
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 400), () {
      _runSearch(value.trim());
    });
  }

  Future<void> _runSearch(String value) async {
    setState(() {
      _searching = true;
      _searchError = null;
    });
    try {
      final hits = await searchCustomers(value);
      if (!mounted || _query.trim() != value) return;
      setState(() {
        _results = hits;
        _searching = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _searchError = e;
        _searching = false;
        _results = const [];
      });
    }
  }

  void _clearSearch() {
    _controller.clear();
    _debounce?.cancel();
    setState(() {
      _query = '';
      _results = const [];
      _searchError = null;
      _searching = false;
    });
    _focusNode.requestFocus();
  }

  void _accessCustomer(CustomerSearchHit hit) {
    ref.read(installerAccessingCustomerProvider.notifier).state = hit.uid;
    ref.read(installerAccessingCustomerNameProvider.notifier).state =
        hit.displayName.isNotEmpty ? hit.displayName : hit.email;
    context.go(AppRoutes.dashboard);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: NexGenPalette.matteBlack,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text(
          'Existing Customer',
          style: TextStyle(color: NexGenPalette.textHigh),
        ),
        iconTheme: const IconThemeData(color: NexGenPalette.textHigh),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: TextField(
                controller: _controller,
                focusNode: _focusNode,
                autofocus: true,
                style: const TextStyle(color: NexGenPalette.textHigh),
                onChanged: _onQueryChanged,
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  hintText: 'Search by name, email, or address...',
                  hintStyle:
                      const TextStyle(color: NexGenPalette.textMedium),
                  filled: true,
                  fillColor: NexGenPalette.gunmetal90,
                  prefixIcon:
                      const Icon(Icons.search, color: NexGenPalette.cyan),
                  suffixIcon: _query.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear,
                              color: NexGenPalette.textMedium),
                          onPressed: _clearSearch,
                        )
                      : null,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: NexGenPalette.line),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: NexGenPalette.line),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(
                        color: NexGenPalette.cyan.withValues(alpha: 0.6)),
                  ),
                ),
              ),
            ),
            Expanded(child: _buildBody(context)),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_searching) {
      return const Center(
        child: CircularProgressIndicator(color: NexGenPalette.cyan),
      );
    }
    if (_searchError != null) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline,
                  size: 40, color: NexGenPalette.amber),
              const SizedBox(height: 12),
              Text(
                'Search failed. Pull to retry or check connection.',
                textAlign: TextAlign.center,
                style: TextStyle(color: NexGenPalette.textMedium),
              ),
              const SizedBox(height: 8),
              Text(
                '$_searchError',
                textAlign: TextAlign.center,
                style: const TextStyle(
                    color: NexGenPalette.textMedium, fontSize: 11),
              ),
            ],
          ),
        ),
      );
    }

    final query = _query.trim();
    if (query.isEmpty) {
      return _InitialState();
    }

    if (_results.isEmpty) {
      return _EmptyState(query: query);
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 24),
      itemCount: _results.length,
      separatorBuilder: (_, __) => const SizedBox(height: 4),
      itemBuilder: (context, index) {
        final hit = _results[index];
        return _CustomerResultTile(
          hit: hit,
          onTap: () => _accessCustomer(hit),
        );
      },
    );
  }
}

class _InitialState extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.manage_accounts,
                size: 48, color: NexGenPalette.cyan.withValues(alpha: 0.5)),
            const SizedBox(height: 16),
            Text(
              'Find a Customer',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    color: NexGenPalette.textHigh,
                    fontWeight: FontWeight.w600,
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              'Search by name, email, or address to access their Lumina account.',
              textAlign: TextAlign.center,
              style: TextStyle(color: NexGenPalette.textMedium, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.query});
  final String query;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.person_search,
                size: 48, color: NexGenPalette.textMedium),
            const SizedBox(height: 16),
            Text(
              'No customers found for "$query"',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: NexGenPalette.textHigh,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Try searching by email or address',
              textAlign: TextAlign.center,
              style: TextStyle(color: NexGenPalette.textMedium, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}

class _CustomerResultTile extends StatelessWidget {
  const _CustomerResultTile({required this.hit, required this.onTap});
  final CustomerSearchHit hit;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      tileColor: NexGenPalette.gunmetal90,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: NexGenPalette.line),
      ),
      leading: CircleAvatar(
        backgroundColor: NexGenPalette.cyan.withValues(alpha: 0.2),
        child: Text(
          hit.initials,
          style: const TextStyle(
            color: NexGenPalette.cyan,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      title: Text(
        hit.displayName.isNotEmpty ? hit.displayName : '(No name)',
        style: const TextStyle(
          color: NexGenPalette.textHigh,
          fontWeight: FontWeight.w600,
        ),
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (hit.email.isNotEmpty)
            Text(
              hit.email,
              style: const TextStyle(
                color: NexGenPalette.textMedium,
                fontSize: 12,
              ),
            ),
          Text(
            hit.address?.isNotEmpty == true
                ? hit.address!
                : 'No address on file',
            style: const TextStyle(
              color: NexGenPalette.textMedium,
              fontSize: 12,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
      trailing: const Icon(Icons.chevron_right, color: NexGenPalette.cyan),
      onTap: onTap,
    );
  }
}
