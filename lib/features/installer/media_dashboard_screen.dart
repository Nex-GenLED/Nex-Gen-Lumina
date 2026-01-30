import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:nexgen_command/theme.dart';
import 'package:nexgen_command/models/user_model.dart';
import 'package:nexgen_command/features/installer/media_access_providers.dart';
import 'package:nexgen_command/features/installer/installer_providers.dart';
import 'package:nexgen_command/nav.dart';

/// Dashboard screen for media professionals to find and view customer systems
class MediaDashboardScreen extends ConsumerStatefulWidget {
  const MediaDashboardScreen({super.key});

  @override
  ConsumerState<MediaDashboardScreen> createState() => _MediaDashboardScreenState();
}

class _MediaDashboardScreenState extends ConsumerState<MediaDashboardScreen> {
  final _searchController = TextEditingController();
  bool _showInstallations = true;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(installerSessionProvider);
    final searchState = ref.watch(customerSearchProvider);
    final installationsAsync = ref.watch(dealerInstallationsProvider);
    final isViewingCustomer = ref.watch(isViewingAsCustomerProvider);
    final viewedProfile = ref.watch(viewedUserProfileProvider);

    return Scaffold(
      backgroundColor: NexGenPalette.matteBlack,
      body: SafeArea(
        child: Column(
          children: [
            // Header
            _buildHeader(context, session, isViewingCustomer, viewedProfile),

            // Search bar
            Padding(
              padding: const EdgeInsets.all(16),
              child: _buildSearchBar(),
            ),

            // Tab selector
            _buildTabSelector(),

            // Content
            Expanded(
              child: _showInstallations
                  ? _buildInstallationsList(installationsAsync)
                  : _buildSearchResults(searchState),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(
    BuildContext context,
    InstallerSession? session,
    bool isViewingCustomer,
    AsyncValue<UserModel?> viewedProfile,
  ) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: NexGenPalette.gunmetal90,
        border: Border(
          bottom: BorderSide(color: NexGenPalette.line, width: 1),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back, color: NexGenPalette.textHigh),
                onPressed: () => context.pop(),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Media Dashboard',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            color: NexGenPalette.textHigh,
                          ),
                    ),
                    if (session != null)
                      Text(
                        session.displayName,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: NexGenPalette.textMedium,
                            ),
                      ),
                  ],
                ),
              ),
              // View As indicator
              if (isViewingCustomer)
                _buildViewingAsChip(viewedProfile),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildViewingAsChip(AsyncValue<UserModel?> viewedProfile) {
    return viewedProfile.when(
      data: (user) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: NexGenPalette.cyan.withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: NexGenPalette.cyan, width: 1),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.visibility, size: 16, color: NexGenPalette.cyan),
            const SizedBox(width: 6),
            Text(
              'Viewing: ${user?.displayName ?? 'Customer'}',
              style: const TextStyle(
                color: NexGenPalette.cyan,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(width: 6),
            GestureDetector(
              onTap: () {
                ref.read(viewAsControllerProvider).exitViewAsMode();
              },
              child: const Icon(Icons.close, size: 16, color: NexGenPalette.cyan),
            ),
          ],
        ),
      ),
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
    );
  }

  Widget _buildSearchBar() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          decoration: BoxDecoration(
            color: NexGenPalette.gunmetal90,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: NexGenPalette.line, width: 1),
          ),
          child: TextField(
            controller: _searchController,
            style: const TextStyle(color: NexGenPalette.textHigh),
            decoration: InputDecoration(
              hintText: 'Search by email or address...',
              hintStyle: const TextStyle(color: NexGenPalette.textMedium),
              prefixIcon: const Icon(Icons.search, color: NexGenPalette.textMedium),
              suffixIcon: _searchController.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear, color: NexGenPalette.textMedium),
                      onPressed: () {
                        _searchController.clear();
                        ref.read(customerSearchProvider.notifier).clear();
                        setState(() {});
                      },
                    )
                  : null,
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            ),
            onChanged: (value) {
              setState(() {});
              if (value.length >= 3) {
                ref.read(customerSearchProvider.notifier).search(value);
                setState(() => _showInstallations = false);
              }
            },
            onSubmitted: (value) {
              if (value.isNotEmpty) {
                ref.read(customerSearchProvider.notifier).search(value);
                setState(() => _showInstallations = false);
              }
            },
          ),
        ),
      ),
    );
  }

  Widget _buildTabSelector() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          _buildTab('Installations', _showInstallations, () {
            setState(() => _showInstallations = true);
          }),
          const SizedBox(width: 12),
          _buildTab('Search Results', !_showInstallations, () {
            setState(() => _showInstallations = false);
          }),
        ],
      ),
    );
  }

  Widget _buildTab(String label, bool isSelected, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? NexGenPalette.cyan.withValues(alpha: 0.15) : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected ? NexGenPalette.cyan : NexGenPalette.line,
            width: 1,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? NexGenPalette.cyan : NexGenPalette.textMedium,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
      ),
    );
  }

  Widget _buildInstallationsList(AsyncValue<List<InstallationRecord>> installationsAsync) {
    return installationsAsync.when(
      data: (installations) {
        if (installations.isEmpty) {
          return _buildEmptyState(
            icon: Icons.assignment,
            title: 'No Installations Yet',
            subtitle: 'Completed installations will appear here',
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: installations.length,
          itemBuilder: (context, index) {
            final installation = installations[index];
            return _buildInstallationCard(installation);
          },
        );
      },
      loading: () => const Center(
        child: CircularProgressIndicator(color: NexGenPalette.cyan),
      ),
      error: (error, _) => _buildEmptyState(
        icon: Icons.error_outline,
        title: 'Error Loading Installations',
        subtitle: error.toString(),
      ),
    );
  }

  Widget _buildInstallationCard(InstallationRecord installation) {
    return GestureDetector(
      onTap: () => _viewCustomer(installation.customerId),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: NexGenPalette.gunmetal90,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: NexGenPalette.line, width: 1),
        ),
        child: Row(
          children: [
            // House icon
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: NexGenPalette.cyan.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.home, color: NexGenPalette.cyan),
            ),
            const SizedBox(width: 12),
            // Customer info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    installation.customerInfo.name,
                    style: const TextStyle(
                      color: NexGenPalette.textHigh,
                      fontWeight: FontWeight.w600,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    installation.customerInfo.address.isNotEmpty
                        ? installation.customerInfo.address
                        : installation.customerInfo.email,
                    style: const TextStyle(
                      color: NexGenPalette.textMedium,
                      fontSize: 13,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Installed: ${_formatDate(installation.installedAt)}',
                    style: const TextStyle(
                      color: NexGenPalette.textMedium,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
            // Arrow
            const Icon(Icons.chevron_right, color: NexGenPalette.textMedium),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchResults(CustomerSearchState searchState) {
    if (searchState.isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: NexGenPalette.cyan),
      );
    }

    if (searchState.error != null) {
      return _buildEmptyState(
        icon: Icons.error_outline,
        title: 'Search Error',
        subtitle: searchState.error!,
      );
    }

    if (searchState.query.isEmpty) {
      return _buildEmptyState(
        icon: Icons.search,
        title: 'Search for Customers',
        subtitle: 'Enter an email address or street address',
      );
    }

    if (searchState.results.isEmpty) {
      return _buildEmptyState(
        icon: Icons.person_search,
        title: 'No Results',
        subtitle: 'No customers found matching "${searchState.query}"',
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: searchState.results.length,
      itemBuilder: (context, index) {
        final user = searchState.results[index];
        return _buildCustomerCard(user);
      },
    );
  }

  Widget _buildCustomerCard(UserModel user) {
    return GestureDetector(
      onTap: () => _viewCustomer(user.id),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: NexGenPalette.gunmetal90,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: NexGenPalette.line, width: 1),
        ),
        child: Row(
          children: [
            // House photo thumbnail
            ClipRRect(
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(11),
                bottomLeft: Radius.circular(11),
              ),
              child: SizedBox(
                width: 80,
                height: 80,
                child: user.housePhotoUrl != null
                    ? Image.network(
                        user.housePhotoUrl!,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => _buildHousePlaceholder(),
                      )
                    : _buildHousePlaceholder(),
              ),
            ),
            const SizedBox(width: 12),
            // Customer info
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      user.displayName,
                      style: const TextStyle(
                        color: NexGenPalette.textHigh,
                        fontWeight: FontWeight.w600,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 2),
                    if (user.address != null && user.address!.isNotEmpty)
                      Text(
                        user.address!,
                        style: const TextStyle(
                          color: NexGenPalette.textMedium,
                          fontSize: 13,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    Text(
                      user.email,
                      style: const TextStyle(
                        color: NexGenPalette.textMedium,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            // View button
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: NexGenPalette.cyan.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: NexGenPalette.cyan, width: 1),
                ),
                child: const Text(
                  'View',
                  style: TextStyle(
                    color: NexGenPalette.cyan,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHousePlaceholder() {
    return Container(
      color: NexGenPalette.gunmetal,
      child: const Center(
        child: Icon(Icons.home, color: NexGenPalette.textMedium, size: 32),
      ),
    );
  }

  Widget _buildEmptyState({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 64, color: NexGenPalette.textMedium),
            const SizedBox(height: 16),
            Text(
              title,
              style: const TextStyle(
                color: NexGenPalette.textHigh,
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              style: const TextStyle(
                color: NexGenPalette.textMedium,
                fontSize: 14,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  void _viewCustomer(String customerId) {
    // Add to recent customers
    addToRecentCustomers(ref, customerId);

    // Enter View As mode
    ref.read(viewAsControllerProvider).viewAsCustomer(customerId);

    // Navigate to the main dashboard to view the customer's system
    context.go(AppRoutes.dashboard);
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);

    if (diff.inDays == 0) {
      return 'Today';
    } else if (diff.inDays == 1) {
      return 'Yesterday';
    } else if (diff.inDays < 7) {
      return '${diff.inDays} days ago';
    } else {
      return '${date.month}/${date.day}/${date.year}';
    }
  }
}
