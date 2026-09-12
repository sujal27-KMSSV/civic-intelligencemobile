import '../../core/constants/api_constants.dart';
import '../../core/network/api_client.dart';
import '../../core/network/auth_storage.dart';
import '../../models/user.dart';
import 'auth_models.dart';

/// Handles authentication business logic: login, register, logout and
/// secure persistence/restoration of the session.
///
/// Kept separate from UI and Riverpod state so it can be reused and tested
/// independently.
class AuthRepository {
  final ApiClient _api;
  final AuthStorage _storage;

  AuthRepository({
    required ApiClient api,
    required AuthStorage storage,
  })  : _api = api,
        _storage = storage;

  /// Authenticates against `POST /api/auth/login/` and persists the session.
  Future<AuthResponse> login(LoginRequest request) async {
    final json = await _api.post(ApiConstants.login, body: request.toJson());
    final response = AuthResponse.fromJson(json);
    await _persistSession(response);
    return response;
  }

  /// Registers against `POST /api/auth/register/` and persists the session.
  Future<AuthResponse> register(RegisterRequest request) async {
    final json = await _api.post(ApiConstants.register, body: request.toJson());
    final response = AuthResponse.fromJson(json);
    await _persistSession(response);
    return response;
  }

  /// Clears every stored session credential.
  Future<void> logout() => _storage.clear();

  /// Reads previously persisted credentials back from secure storage.
  ///
  /// Returns `null` when no valid session exists.
  Future<User?> restoreSession() async {
    final token = await _storage.readToken();
    if (token == null || token.isEmpty) return null;

    final email = await _storage.readUserEmail();
    final userId = await _storage.readUserId();
    if (email == null || userId == null) return null;

    return User(id: userId, email: email);
  }

  /// Returns the current auth token, or `null` when signed out.
  Future<String?> getToken() => _storage.readToken();

  Future<void> _persistSession(AuthResponse response) async {
    await _storage.saveSession(
      token: response.token,
      tokenScheme: response.tokenScheme,
      refreshToken: response.refreshToken,
      userId: response.user?.id,
      email: response.user?.email,
    );
  }
}