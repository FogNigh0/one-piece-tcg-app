import 'dart:convert';
import 'package:http/http.dart' as http;
import 'auth_service.dart';

class ApiClient {
  ApiClient({String? baseUrl, AuthService? authService})
      : baseUrl = baseUrl ?? 'https://one-piece-tcg-server-production.up.railway.app',
        _auth = authService ?? AuthService();

  final String baseUrl;
  final AuthService _auth;

  // ── HTTP con token automático ─────────────────────────────────────────────

  static const _timeout = Duration(seconds: 15);

  Future<http.Response> get(String path) async {
    final res = await http.get(
      Uri.parse('$baseUrl$path'),
      headers: await _headers(),
    ).timeout(_timeout);
    return _handleUnauthorized(res, () => get(path));
  }

  Future<http.Response> post(String path, Map<String, dynamic> body) async {
    final res = await http.post(
      Uri.parse('$baseUrl$path'),
      headers: await _headers(),
      body: jsonEncode(body),
    ).timeout(_timeout);
    return _handleUnauthorized(res, () => post(path, body));
  }

  Future<http.Response> put(String path, Map<String, dynamic> body) async {
    final res = await http.put(
      Uri.parse('$baseUrl$path'),
      headers: await _headers(),
      body: jsonEncode(body),
    ).timeout(_timeout);
    return _handleUnauthorized(res, () => put(path, body));
  }

  Future<http.Response> patch(String path, Map<String, dynamic> body) async {
    final res = await http.patch(
      Uri.parse('$baseUrl$path'),
      headers: await _headers(),
      body: jsonEncode(body),
    ).timeout(_timeout);
    return _handleUnauthorized(res, () => patch(path, body));
  }

  Future<http.Response> delete(String path) async {
    final res = await http.delete(
      Uri.parse('$baseUrl$path'),
      headers: await _headers(),
    ).timeout(_timeout);
    return _handleUnauthorized(res, () => delete(path));
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  Future<Map<String, String>> _headers() async {
    final token = await _auth.getAccessToken();
    return {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  /// Si el servidor devuelve 401, intenta refresh y reintenta UNA vez.
  Future<http.Response> _handleUnauthorized(
    http.Response res,
    Future<http.Response> Function() retry,
  ) async {
    if (res.statusCode == 401) {
      final ok = await _auth.refreshToken();
      if (ok) return retry();
      throw AuthException('Sesión expirada. Inicia sesión de nuevo.');
    }
    return res;
  }

  /// Lanza excepción si el status no es 2xx, devuelve el body parseado.
  Map<String, dynamic> parseOrThrow(http.Response res) {
    final body = jsonDecode(res.body);
    if (res.statusCode >= 200 && res.statusCode < 300) {
      return body as Map<String, dynamic>;
    }
    final detail = (body is Map) ? body['detail'] ?? 'Error del servidor' : 'Error del servidor';
    throw ApiException(detail.toString(), res.statusCode);
  }

  List<dynamic> parseListOrThrow(http.Response res) {
    if (res.statusCode >= 200 && res.statusCode < 300) {
      return jsonDecode(res.body) as List<dynamic>;
    }
    final body = jsonDecode(res.body);
    final detail = (body is Map) ? body['detail'] ?? 'Error del servidor' : 'Error del servidor';
    throw ApiException(detail.toString(), res.statusCode);
  }
}

class ApiException implements Exception {
  const ApiException(this.message, this.statusCode);
  final String message;
  final int statusCode;

  @override
  String toString() => 'ApiException($statusCode): $message';
}