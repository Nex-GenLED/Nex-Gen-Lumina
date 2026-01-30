import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:nexgen_command/models/user_model.dart';
import 'package:nexgen_command/app_providers.dart';
import 'package:nexgen_command/services/user_service.dart';
import 'package:nexgen_command/features/installer/customer_lookup_service.dart';
import 'package:nexgen_command/features/installer/installer_providers.dart';
import 'package:nexgen_command/features/site/user_profile_providers.dart';

/// Singleton instance of CustomerLookupService
final customerLookupServiceProvider = Provider<CustomerLookupService>((ref) {
  return CustomerLookupService();
});

/// The customer ID currently being viewed in "View As" mode
/// When null, the user is viewing their own account
final viewAsCustomerIdProvider = StateProvider<String?>((ref) => null);

/// Whether the app is currently in "View As" mode (viewing another customer)
final isViewingAsCustomerProvider = Provider<bool>((ref) {
  return ref.watch(viewAsCustomerIdProvider) != null;
});

/// The logged-in user's profile (for checking media access)
/// Different from currentUserProfileProvider which is a stream
final loggedInUserProfileProvider = FutureProvider<UserModel?>((ref) async {
  final authState = ref.watch(authStateProvider);
  final userId = authState.valueOrNull?.uid;
  if (userId == null) return null;
  return UserService().getUser(userId);
});

/// Whether the current user has media access privileges
final hasMediaAccessProvider = Provider<bool>((ref) {
  final userProfile = ref.watch(loggedInUserProfileProvider).valueOrNull;
  if (userProfile == null) return false;
  return userProfile.userRole.canViewCustomerSystems;
});

/// The profile being viewed - either the viewed customer (in View As mode) or the current user
/// Use this provider in views that need to display the active profile data
final viewedUserProfileProvider = FutureProvider<UserModel?>((ref) async {
  final viewAsId = ref.watch(viewAsCustomerIdProvider);

  // If viewing another customer, load their profile
  if (viewAsId != null) {
    final lookupService = ref.read(customerLookupServiceProvider);
    return lookupService.getUserById(viewAsId);
  }

  // Otherwise return the current user's profile
  return ref.watch(loggedInUserProfileProvider.future);
});

/// Stream-based provider for the viewed profile (matches currentUserProfileProvider interface)
/// Use this in places that expect a StreamProvider like the dashboard
final activeUserProfileProvider = StreamProvider<UserModel?>((ref) {
  final viewAsId = ref.watch(viewAsCustomerIdProvider);
  final svc = ref.watch(userServiceProvider);

  // If viewing another customer, stream their profile
  if (viewAsId != null) {
    return svc.streamUser(viewAsId);
  }

  // Otherwise stream the current user's profile (delegate to existing provider)
  final user = ref.watch(authStateProvider).maybeWhen(data: (u) => u, orElse: () => null);
  if (user == null) return const Stream.empty();
  return svc.streamUser(user.uid);
});

/// The effective user ID to use for data queries
/// Returns the viewed customer ID if in View As mode, otherwise the current user ID
final effectiveUserIdProvider = Provider<String?>((ref) {
  final viewAsId = ref.watch(viewAsCustomerIdProvider);
  if (viewAsId != null) return viewAsId;

  final authState = ref.watch(authStateProvider);
  return authState.valueOrNull?.uid;
});

/// Installation records for the current dealer (when in installer mode)
final dealerInstallationsProvider = FutureProvider<List<InstallationRecord>>((ref) async {
  final session = ref.watch(installerSessionProvider);
  if (session == null) return [];

  final lookupService = ref.read(customerLookupServiceProvider);
  return lookupService.getInstallationsByDealer(session.dealer.dealerCode);
});

/// Search results for customer lookup
class CustomerSearchState {
  final String query;
  final List<UserModel> results;
  final bool isLoading;
  final String? error;

  const CustomerSearchState({
    this.query = '',
    this.results = const [],
    this.isLoading = false,
    this.error,
  });

  CustomerSearchState copyWith({
    String? query,
    List<UserModel>? results,
    bool? isLoading,
    String? error,
  }) {
    return CustomerSearchState(
      query: query ?? this.query,
      results: results ?? this.results,
      isLoading: isLoading ?? this.isLoading,
      error: error,
    );
  }
}

/// Notifier for managing customer search state
class CustomerSearchNotifier extends StateNotifier<CustomerSearchState> {
  final CustomerLookupService _lookupService;

  CustomerSearchNotifier(this._lookupService) : super(const CustomerSearchState());

  /// Perform a search for customers
  Future<void> search(String query) async {
    if (query.isEmpty) {
      state = const CustomerSearchState();
      return;
    }

    state = state.copyWith(query: query, isLoading: true, error: null);

    try {
      final results = await _lookupService.search(query);
      state = state.copyWith(results: results, isLoading: false);
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: 'Search failed: $e',
        results: [],
      );
    }
  }

  /// Clear the search results
  void clear() {
    state = const CustomerSearchState();
  }
}

/// Provider for customer search functionality
final customerSearchProvider = StateNotifierProvider<CustomerSearchNotifier, CustomerSearchState>((ref) {
  final lookupService = ref.read(customerLookupServiceProvider);
  return CustomerSearchNotifier(lookupService);
});

/// Helper class for managing View As mode
class ViewAsController {
  final Ref _ref;

  ViewAsController(this._ref);

  /// Enter View As mode for a specific customer
  void viewAsCustomer(String customerId) {
    // Verify the user has media access
    final hasAccess = _ref.read(hasMediaAccessProvider);
    if (!hasAccess) {
      throw Exception('User does not have media access privileges');
    }

    _ref.read(viewAsCustomerIdProvider.notifier).state = customerId;
  }

  /// Exit View As mode (return to viewing own account)
  void exitViewAsMode() {
    _ref.read(viewAsCustomerIdProvider.notifier).state = null;
  }

  /// Check if currently viewing a specific customer
  bool isViewing(String customerId) {
    return _ref.read(viewAsCustomerIdProvider) == customerId;
  }
}

/// Provider for View As controller
final viewAsControllerProvider = Provider<ViewAsController>((ref) {
  return ViewAsController(ref);
});

/// Recent customers viewed by the media user (stored locally for quick access)
final recentViewedCustomersProvider = StateProvider<List<String>>((ref) => []);

/// Add a customer to the recent list
void addToRecentCustomers(WidgetRef ref, String customerId) {
  final recent = List<String>.from(ref.read(recentViewedCustomersProvider));

  // Remove if already exists to move to front
  recent.remove(customerId);

  // Add to front of list
  recent.insert(0, customerId);

  // Keep only last 10
  if (recent.length > 10) {
    recent.removeLast();
  }

  ref.read(recentViewedCustomersProvider.notifier).state = recent;
}
