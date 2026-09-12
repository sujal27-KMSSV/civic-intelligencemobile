import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_client.dart';
import '../../core/network/auth_storage.dart';
import '../../models/user.dart';
import 'auth_models.dart';
import 'auth_repository.dart';

// ---------------------------------------------------------------------------
// Providers — low-level infrastructure to top-level state
// ---------------------------------------------------------------------------

/// Singleton secure-storage instance shared by `ApiClient` and `AuthRepository`.
final authStorageProvider = Provider<AuthStorage>(
  (_) => const SecureAuthStorage(),
);

/// The shared HTTP client.  Wires the 401 callback lazily so there is no
/// circular dependency with [authProvider].
final apiClientProvider = Provider<ApiClient>((ref) {
  final client = ApiClient(authStorage: ref.watch(authStorageProvider));

  // Auth layer hooks into 401 responses to trigger automatic logout.
  // `ref.read` is used deliberately: the dependency is resolved lazily only
  // when a 401 actually arrives, not at provider-creation time.
  client.onUnauthorized = () => ref.read(authProvider.notifier).logout();

  return client;
});

/// Business-logic layer that talks to the Django auth endpoints.
final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return AuthRepository(
    api: ref.watch(apiClientProvider),
    storage: ref.watch(authStorageProvider),
  );
});

// ---------------------------------------------------------------------------
// Auth state
// ---------------------------------------------------------------------------

enum AuthStatus { unknown, authenticated, unauthenticated }

class AuthState {
  final AuthStatus status;
  final User? user;

  const AuthState.unknown() : status = AuthStatus.unknown, user = null;
  const AuthState.authenticated(this.user)
      : status = AuthStatus.authenticated;
  const AuthState.unauthenticated()
      : status = AuthStatus.unauthenticated,
        user = null;
}

/// Manages authentication lifecycle.
///
/// - On creation, restores a previously stored session from secure storage.
/// - Provides [login], [register] and [logout] that the UI calls directly.
/// - [logout] is also called automatically by [ApiClient] when a 401 arrives.
class AuthNotifier extends AsyncNotifier<AuthState> {
  @override
  Future<AuthState> build() async {
    final repo = ref.read(authRepositoryProvider);
    final user = await repo.restoreSession();
    if (user != null) return AuthState.authenticated(user);
    return const AuthState.unauthenticated();
  }

  /// Authenticates with the backend.  Throws on invalid credentials so the
  /// caller can display the error – the [authProvider] state will hold the
  /// [AsyncError] as well.
  ///
  /// The state is left untouched while the request is in flight: setting
  /// `AsyncLoading` here would make the router (which recreates itself from
  /// [authProvider]) tear down the login/register form mid-request and the
  /// real error would never be visible. Each screen shows its own spinner.
  Future<void> login(String email, String password) async {
    try {
      final repo = ref.read(authRepositoryProvider);
      final response = await repo.login(LoginRequest(
        email: email,
        password: password,
      ));
      state = AsyncData(AuthState.authenticated(response.user));
    } catch (e, st) {
      state = AsyncError<AuthState>(e, st);
    }
  }

  /// Registers a new account and signs in automatically.
  Future<void> register(RegisterRequest request) async {
    try {
      final repo = ref.read(authRepositoryProvider);
      final response = await repo.register(request);
      state = AsyncData(AuthState.authenticated(response.user));
    } catch (e, st) {
      state = AsyncError<AuthState>(e, st);
    }
  }

  /// Clears the session and returns to the unauthenticated state.
  Future<void> logout() async {
    final repo = ref.read(authRepositoryProvider);
    await repo.logout();
    state = const AsyncData(AuthState.unauthenticated());
  }
}

/// The single source of truth for whether the user is logged in.
///
/// - `AsyncLoading` → session being restored (splash screen).
/// - `AsyncData(AuthState.authenticated)` → user is signed in.
/// - `AsyncData(AuthState.unauthenticated)` → user is signed out.
/// - `AsyncError` → the last auth operation failed (the caller should
///   extract the error for display).
final authProvider =
    AsyncNotifierProvider<AuthNotifier, AuthState>(AuthNotifier.new);