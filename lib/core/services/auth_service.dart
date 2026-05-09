import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

class AuthService {
  AuthService({String? baseUrl})
      : baseUrl = baseUrl ?? 'https://one-piece-tcg-server-production.up.railway.app';

  final String baseUrl;
  final _storage = const FlutterSecureStorage();

  static const _keyAccess  = 'access_token';
  static const _keyRefresh = 'refresh_token';
  static const _keyUser    = 'user_json';

  // ── Tokens ────────────────────────────────────────────────────────────────

  Future<String?> getAccessToken() => _storage.read(key: _keyAccess);
  Future<String?> getRefreshToken() => _storage.read(key: _keyRefresh);
  Future<bool> get isLoggedIn async => (await getAccessToken()) != null;

  Future<void> _saveTokens(Map<String, dynamic> body) async {
    await _storage.write(key: _keyAccess,  value: body['access_token']);
    await _storage.write(key: _keyRefresh, value: body['refresh_token']);
    await _storage.write(key: _keyUser,    value: jsonEncode(body['user']));
  }

  Future<Map<String, dynamic>?> getCachedUser() async {
    final raw = await _storage.read(key: _keyUser);
    if (raw == null) return null;
    return jsonDecode(raw) as Map<String, dynamic>;
  }

  // ── Register ──────────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> register({
    required String username,
    required String email,
    required String password,
  }) async {
    final res = await http.post(
      Uri.parse('$baseUrl/auth/register'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'username': username, 'email': email, 'password': password}),
    ).timeout(const Duration(seconds: 30)); 
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    if (res.statusCode == 201) {
      await _saveTokens(body);
      return body;
    }
    // detail puede ser string o lista (errores de validación 422)
    final detail = body['detail'];
    String message;
    if (detail is List && detail.isNotEmpty) {
      // Toma el primer error de validación y lo muestra al usuario
      final first = detail.first as Map<String, dynamic>;
      message = first['msg']?.toString().replaceFirst('Value error, ', '') 
                ?? 'Error al registrarse';
    } else {
      message = detail?.toString() ?? 'Error al registrarse';
    }
    throw AuthException(message);
  }

  // ── Login ─────────────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> login({
    required String emailOrUsername,
    required String password,
  }) async {
    final res = await http.post(
      Uri.parse('$baseUrl/auth/login'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'email_or_username': emailOrUsername, 'password': password}),
    ).timeout(const Duration(seconds: 30));
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    if (res.statusCode == 200) {
      await _saveTokens(body);
      return body;
    }
    throw AuthException(body['detail'] ?? 'Credenciales incorrectas');
  }

  // ── Refresh ───────────────────────────────────────────────────────────────

  Future<bool> refreshToken() async {
    final refresh = await getRefreshToken();
    if (refresh == null) return false;

    final res = await http.post(
      Uri.parse('$baseUrl/auth/refresh'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'refresh_token': refresh}),
    );
    if (res.statusCode == 200) {
      await _saveTokens(jsonDecode(res.body));
      return true;
    }
    await logout();
    return false;
  }

  // ── Me ────────────────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> getMe() async {
    final token = await getAccessToken();
    final res = await http.get(
      Uri.parse('$baseUrl/auth/me'),
      headers: {'Authorization': 'Bearer $token'},
    );
    if (res.statusCode == 200) {
      return jsonDecode(res.body) as Map<String, dynamic>;
    }
    if (res.statusCode == 401) {
      final ok = await refreshToken();
      if (ok) return getMe();
    }
    throw AuthException('Sesión expirada');
  }

  // ── Logout ────────────────────────────────────────────────────────────────

  Future<void> logout() async {
    await _storage.deleteAll();
  }
}

class AuthException implements Exception {
  const AuthException(this.message);
  final String message;

  @override
  String toString() => message;
}