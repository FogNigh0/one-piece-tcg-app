// lib/core/services/sync_service.dart
//
// Sincroniza carpetas y colección entre SQLite local y el servidor Railway.
// Funciona en background — si no hay internet, los cambios quedan en local
// y se sincronizan la próxima vez que haya conexión.

import 'dart:convert';
import 'package:http/http.dart' as http;
import '../database/card_database.dart';
import 'auth_service.dart';

class SyncService {
  SyncService({String? baseUrl})
      : baseUrl = baseUrl ??
            'https://one-piece-tcg-server-production.up.railway.app';

  final String baseUrl;
  final _auth = AuthService();

  // ── Headers con token ─────────────────────────────────────────────────────

  Future<Map<String, String>> get _headers async {
    final token = await _auth.getAccessToken();
    return {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  // ── Sync completo al iniciar sesión ───────────────────────────────────────

  /// Llama esto justo después del login.
  /// Descarga carpetas y colección del servidor y las fusiona con el local.
  Future<void> syncOnLogin() async {
    await Future.wait([
      _downloadFolders(),
      _downloadCollection(),
    ]);
  }

  // ── Carpetas ──────────────────────────────────────────────────────────────

  /// Descarga carpetas del servidor y crea las que no existen localmente.
  Future<void> _downloadFolders() async {
    try {
      final res = await http
          .get(Uri.parse('$baseUrl/folders'), headers: await _headers)
          .timeout(const Duration(seconds: 10));

      if (res.statusCode != 200) return;

      final serverFolders =
          (jsonDecode(res.body) as List).cast<Map<String, dynamic>>();
      final localFolders = await CardDatabase.instance.getAllFolders();
      final localNames = localFolders.map((f) => f.name.toLowerCase()).toSet();

      for (final sf in serverFolders) {
        final name = sf['name'] as String;
        // No descarga la carpeta protegida Colección (ya existe local)
        if (name.toLowerCase() == 'colección' ||
            name.toLowerCase() == 'collection') continue;
        // Crea localmente si no existe
        if (!localNames.contains(name.toLowerCase())) {
          await CardDatabase.instance.createFolder(
            Folder(
              name: name,
              description: sf['is_public'] == true ? '__public__' : '',
              isPublic: sf['is_public'] as bool? ?? false,
            ),
          );
        }
      }
    } catch (_) {
      // Silencioso — si falla, el usuario sigue viendo sus datos locales
    }
  }

  /// Sube una carpeta nueva al servidor.
  Future<int?> uploadFolder(Folder folder) async {
    try {
      final res = await http
          .post(
            Uri.parse('$baseUrl/folders'),
            headers: await _headers,
            body: jsonEncode({'name': folder.name}),
          )
          .timeout(const Duration(seconds: 10));

      if (res.statusCode == 201) {
        final body = jsonDecode(res.body) as Map<String, dynamic>;
        return body['id'] as int?;
      }
    } catch (_) {}
    return null;
  }

  /// Actualiza visibilidad de una carpeta en el servidor.
  Future<void> updateFolderVisibility(
      int serverFolderId, bool isPublic) async {
    try {
      await http
          .patch(
            Uri.parse('$baseUrl/folders/$serverFolderId'),
            headers: await _headers,
            body: jsonEncode({'is_public': isPublic}),
          )
          .timeout(const Duration(seconds: 10));
    } catch (_) {}
  }

  /// Obtiene el share_token de una carpeta pública del servidor.
  Future<String?> getShareToken(int serverFolderId) async {
    try {
      final res = await http
          .get(Uri.parse('$baseUrl/folders'), headers: await _headers)
          .timeout(const Duration(seconds: 10));

      if (res.statusCode == 200) {
        final folders =
            (jsonDecode(res.body) as List).cast<Map<String, dynamic>>();
        final folder = folders.firstWhere(
          (f) => f['id'] == serverFolderId,
          orElse: () => {},
        );
        return folder['share_token'] as String?;
      }
    } catch (_) {}
    return null;
  }

  // ── Colección ─────────────────────────────────────────────────────────────

  /// Descarga la colección del servidor y la fusiona con el local.
  Future<void> _downloadCollection() async {
    try {
      final res = await http
          .get(Uri.parse('$baseUrl/collection'), headers: await _headers)
          .timeout(const Duration(seconds: 10));

      if (res.statusCode != 200) return;

      final serverCards =
          (jsonDecode(res.body) as List).cast<Map<String, dynamic>>();
      if (serverCards.isEmpty) return;

      // Para cada carta del servidor, verifica si existe localmente
      final localCards = await CardDatabase.instance.getAllCards();
      final localSetCodes = localCards.map((c) => c.setCode).toSet();
      final collectionId = CardDatabase.collectionFolderId;
      if (collectionId == null) return;

      for (final sc in serverCards) {
        final code = sc['card_set_code'] as String;
        final qty  = sc['quantity'] as int;

        if (!localSetCodes.contains(code)) {
          // Carta del servidor no existe local — créala sin imagen local
          final saved = await CardDatabase.instance.insertCard(ScannedCard(
            name:           code, // nombre se carga del servidor cuando se ve
            cardClass:      '',
            faction:        '',
            setCode:        code,
            ability:        '',
            trigger:        '',
            localImagePath: '',
          ));
          await CardDatabase.instance.addCardToFolder(
            folderId: collectionId,
            cardId:   saved.id!,
            quantity: qty,
          );
        }
      }
    } catch (_) {}
  }

  /// Sube la colección local al servidor (todas las cartas con sus cantidades).
  Future<void> uploadCollection() async {
    try {
      final localCards = await CardDatabase.instance.getAllCards();
      if (localCards.isEmpty) return;

      final items = <Map<String, dynamic>>[];
      for (final card in localCards) {
        if (card.id == null) continue;
        final qtys = await CardDatabase.instance
            .getFolderQuantitiesForCard(card.id!);
        final total = qtys.values.fold(0, (s, q) => s + q);
        if (total > 0) {
          items.add({'card_set_code': card.setCode, 'quantity': total});
        }
      }

      if (items.isEmpty) return;

      await http
          .put(
            Uri.parse('$baseUrl/collection/sync'),
            headers: await _headers,
            body: jsonEncode({'cards': items}),
          )
          .timeout(const Duration(seconds: 15));
    } catch (_) {}
  }

  /// Sube una sola carta al servidor (llamar después de escanear/agregar).
  Future<void> uploadCard(String cardSetCode, int quantity) async {
    try {
      // Obtiene la cantidad total actual del servidor para esta carta
      final res = await http
          .get(Uri.parse('$baseUrl/collection'), headers: await _headers)
          .timeout(const Duration(seconds: 10));

      int serverQty = 0;
      if (res.statusCode == 200) {
        final list =
            (jsonDecode(res.body) as List).cast<Map<String, dynamic>>();
        final existing = list.where((c) => c['card_set_code'] == cardSetCode);
        if (existing.isNotEmpty) {
          serverQty = existing.first['quantity'] as int;
        }
      }

      // Sube la cantidad acumulada
      await http
          .put(
            Uri.parse('$baseUrl/collection/sync'),
            headers: await _headers,
            body: jsonEncode({
              'cards': [
                {
                  'card_set_code': cardSetCode,
                  'quantity': serverQty + quantity,
                }
              ]
            }),
          )
          .timeout(const Duration(seconds: 10));
    } catch (_) {}
  }
}