import 'api_client.dart';

class ServerSyncService {
  ServerSyncService({ApiClient? client})
      : _client = client ?? ApiClient();

  final ApiClient _client;

  // ── Colección global ──────────────────────────────────────────────────────

  /// Sube toda la colección local al servidor (reemplaza la anterior).
  Future<int> syncCollection(List<Map<String, dynamic>> cards) async {
    final res = await _client.put('/collection/sync', {
      'cards': cards, // [{'card_set_code': 'OP01-001', 'quantity': 2}, ...]
    });
    final body = _client.parseOrThrow(res);
    return body['synced'] as int;
  }

  /// Descarga la colección del servidor.
  Future<List<Map<String, dynamic>>> fetchCollection() async {
    final res = await _client.get('/collection');
    final list = _client.parseListOrThrow(res);
    return list.cast<Map<String, dynamic>>();
  }

  // ── Carpetas ──────────────────────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> fetchFolders() async {
    final res = await _client.get('/folders');
    return _client.parseListOrThrow(res).cast<Map<String, dynamic>>();
  }

  Future<Map<String, dynamic>> createFolder(String name) async {
    final res = await _client.post('/folders', {'name': name});
    return _client.parseOrThrow(res);
  }

  Future<void> deleteFolder(int folderId) async {
    await _client.delete('/folders/$folderId');
  }

  Future<Map<String, dynamic>> toggleFolderPublic(
      int folderId, bool isPublic) async {
    final res = await _client.patch(
      '/folders/$folderId',
      {'is_public': isPublic},
    );
    return _client.parseOrThrow(res);
  }

  Future<int> syncFolderCards(
      int folderId, List<Map<String, dynamic>> cards) async {
    final res = await _client.put('/folders/$folderId/cards', {'cards': cards});
    final body = _client.parseOrThrow(res);
    return body['synced'] as int;
  }

  Future<List<Map<String, dynamic>>> fetchFolderCards(int folderId) async {
    final res = await _client.get('/folders/$folderId/cards');
    return _client.parseListOrThrow(res).cast<Map<String, dynamic>>();
  }
}