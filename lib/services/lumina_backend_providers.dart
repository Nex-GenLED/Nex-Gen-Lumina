import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexgen_command/app_providers.dart';
import 'lumina_backend_service.dart';
import 'connectivity_service.dart';

/// Singleton instance of the Lumina backend service.
final luminaBackendServiceProvider = Provider<LuminaBackendService>((ref) {
  final service = LuminaBackendService();
  ref.onDispose(() => service.dispose());
  return service;
});

// Note: connectivityServiceProvider is defined in app_providers.dart

/// Current connectivity status stream.
/// [homeSsid] should come from user settings (stored home network name).
final connectivityStatusProvider =
    StreamProvider.family<ConnectivityStatus, String?>((ref, homeSsid) {
  final service = ref.watch(connectivityServiceProvider);
  return service.watchConnectivity(homeSsid);
});

/// Whether the user is authenticated with the Lumina backend.
final isBackendAuthenticatedProvider = StateProvider<bool>((ref) {
  return ref.watch(luminaBackendServiceProvider).isAuthenticated;
});

/// Backend health status (checked periodically).
final backendHealthProvider = FutureProvider<BackendHealthStatus>((ref) async {
  final service = ref.watch(luminaBackendServiceProvider);
  return service.checkHealth();
});

/// List of devices registered with the backend.
final backendDevicesProvider =
    FutureProvider<List<BackendDevice>>((ref) async {
  final service = ref.watch(luminaBackendServiceProvider);
  if (!service.isAuthenticated) {
    return [];
  }
  final result = await service.listDevices();
  return result.devices ?? [];
});

/// Notifier for backend authentication state.
class BackendAuthNotifier extends StateNotifier<BackendAuthState> {
  final LuminaBackendService _service;
  final Ref _ref;

  BackendAuthNotifier(this._service, this._ref)
      : super(const BackendAuthState.initial());

  Future<void> init() async {
    state = const BackendAuthState.loading();
    await _service.init();
    if (_service.isAuthenticated) {
      state = BackendAuthState.authenticated(userId: _service.userId!);
    } else {
      state = const BackendAuthState.unauthenticated();
    }
  }

  Future<bool> login(String email, String password) async {
    state = const BackendAuthState.loading();
    final result = await _service.login(email, password);
    if (result.success) {
      state = BackendAuthState.authenticated(userId: result.userId!);
      _ref.invalidate(backendDevicesProvider);
      return true;
    }
    state = BackendAuthState.error(result.error ?? 'Login failed');
    return false;
  }

  Future<bool> register(String email, String password) async {
    state = const BackendAuthState.loading();
    final result = await _service.register(email, password);
    if (result.success) {
      state = BackendAuthState.authenticated(userId: result.userId!);
      return true;
    }
    state = BackendAuthState.error(result.error ?? 'Registration failed');
    return false;
  }

  Future<void> logout() async {
    await _service.logout();
    state = const BackendAuthState.unauthenticated();
    _ref.invalidate(backendDevicesProvider);
  }
}

final backendAuthProvider =
    StateNotifierProvider<BackendAuthNotifier, BackendAuthState>((ref) {
  final service = ref.watch(luminaBackendServiceProvider);
  return BackendAuthNotifier(service, ref);
});

/// Authentication state for the backend.
class BackendAuthState {
  final bool isLoading;
  final bool isAuthenticated;
  final String? userId;
  final String? error;

  const BackendAuthState._({
    this.isLoading = false,
    this.isAuthenticated = false,
    this.userId,
    this.error,
  });

  const BackendAuthState.initial() : this._();
  const BackendAuthState.loading() : this._(isLoading: true);
  const BackendAuthState.authenticated({required String userId})
      : this._(isAuthenticated: true, userId: userId);
  const BackendAuthState.unauthenticated() : this._();
  const BackendAuthState.error(String error) : this._(error: error);
}

/// Notifier for managing remote commands.
/// This decides whether to use local HTTP or backend relay based on connectivity.
class RemoteCommandNotifier extends StateNotifier<RemoteCommandState> {
  final LuminaBackendService _backendService;
  final ConnectivityService _connectivityService;
  final String? _homeSsid;

  RemoteCommandNotifier(
    this._backendService,
    this._connectivityService,
    this._homeSsid,
  ) : super(const RemoteCommandState.idle());

  /// Determine if we should use remote (backend) or local (direct HTTP) control.
  Future<bool> shouldUseRemote() async {
    // If not authenticated with backend, always use local
    if (!_backendService.isAuthenticated) {
      return false;
    }

    // Check current network status
    final isOnHome = await _connectivityService.isOnHomeNetwork(_homeSsid);
    return !isOnHome;
  }

  /// Send a command, automatically choosing local or remote based on connectivity.
  Future<CommandResult> sendCommand(
    String deviceId, {
    required String action,
    Map<String, dynamic>? payload,
  }) async {
    state = const RemoteCommandState.sending();

    final useRemote = await shouldUseRemote();

    if (useRemote) {
      final result = await _backendService.sendCommand(
        deviceId,
        action: action,
        payload: payload,
      );
      state = result.success
          ? const RemoteCommandState.success()
          : RemoteCommandState.error(result.error ?? 'Command failed');
      return result;
    }

    // Return a "use local" result - the caller should use WledService directly
    state = const RemoteCommandState.useLocal();
    return const CommandResult(success: false, error: 'Use local control');
  }
}

final remoteCommandProvider = StateNotifierProvider.family<
    RemoteCommandNotifier, RemoteCommandState, String?>((ref, homeSsid) {
  final backend = ref.watch(luminaBackendServiceProvider);
  final connectivity = ref.watch(connectivityServiceProvider);
  return RemoteCommandNotifier(backend, connectivity, homeSsid);
});

/// State for remote command operations.
class RemoteCommandState {
  final bool isSending;
  final bool success;
  final bool useLocal;
  final String? error;

  const RemoteCommandState._({
    this.isSending = false,
    this.success = false,
    this.useLocal = false,
    this.error,
  });

  const RemoteCommandState.idle() : this._();
  const RemoteCommandState.sending() : this._(isSending: true);
  const RemoteCommandState.success() : this._(success: true);
  const RemoteCommandState.useLocal() : this._(useLocal: true);
  const RemoteCommandState.error(String error) : this._(error: error);
}
