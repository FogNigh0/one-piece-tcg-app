// lib/core/services/server_sync_service.dart
//
// Sube imágenes y metadatos a tu servidor propio y los descarga de vuelta.
// Cambia [baseUrl] a la URL de tu servidor.

import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import '../database/card_database.dart';

class ServerSyncService {
  ServerSyncService({String? baseUrl})
      : baseUrl = baseUrl ?? 'https://TU-SERVIDOR.com/api';

  final String baseUrl;

  // ── Subir carta ────────────────────────────────────────────────────────────

  /// Sube la imagen y los metadatos de una carta al servidor.
  /// Devuelve la URL pública de la imagen o lanza una excepción si falla.
  ///
  /// El servidor debe aceptar un POST multipart/form-data con:
  ///   - campo "image":     el archivo PNG de la carta
  ///   - campo "metadata":  JSON con los datos de la carta
  ///
  /// Y responder con JSON: { "image_url": "https://..." }
  Future<String> uploadCard(ScannedCard card) async {
    final request = http.MultipartRequest(
      'POST',
      Uri.parse('$baseUrl/cards'),
    );

    // Adjunta imagen
    request.files.add(
      await http.MultipartFile.fromPath(
        'image',
        card.localImagePath,
        filename: '${card.setCode}_${card.name}.png'
            .replaceAll(RegExp(r'[^\w.-]'), '_'),
      ),
    );

    // Adjunta metadatos como JSON
    request.fields['metadata'] = jsonEncode({
      'name': card.name,
      'card_class': card.cardClass,
      'faction': card.faction,
      'set_code': card.setCode,
      'ability': card.ability,
      'trigger': card.trigger,
      'scanned_at': card.scannedAt.toIso8601String(),
    });

    final streamed = await request.send().timeout(const Duration(seconds: 30));
    final response = await http.Response.fromStream(streamed);

    if (response.statusCode == 200 || response.statusCode == 201) {
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final url = body['image_url'] as String?;
      if (url != null && url.isNotEmpty) return url;
    }

    throw ServerException(
      'Error al subir carta: ${response.statusCode} ${response.body}',
    );
  }

  // ── Obtener cartas del servidor ────────────────────────────────────────────

  /// Descarga la lista de cartas guardadas en el servidor.
  ///
  /// El servidor debe responder a GET /cards con JSON:
  /// [
  ///   {
  ///     "id": 1,
  ///     "name": "Monkey D. Luffy",
  ///     "set_code": "OP01-001",
  ///     "image_url": "https://...",
  ///     ...
  ///   }
  /// ]
  Future<List<ServerCard>> fetchCards() async {
    final response = await http
        .get(Uri.parse('$baseUrl/cards'))
        .timeout(const Duration(seconds: 15));

    if (response.statusCode == 200) {
      final list = jsonDecode(response.body) as List<dynamic>;
      return list
          .cast<Map<String, dynamic>>()
          .map(ServerCard.fromJson)
          .toList();
    }

    throw ServerException(
      'Error al obtener cartas: ${response.statusCode}',
    );
  }

  /// Descarga el contenido binario de una imagen desde su URL.
  Future<File> downloadImage(String url, String destPath) async {
    final response = await http
        .get(Uri.parse(url))
        .timeout(const Duration(seconds: 30));

    if (response.statusCode == 200) {
      final file = File(destPath);
      await file.writeAsBytes(response.bodyBytes);
      return file;
    }

    throw ServerException('Error al descargar imagen: ${response.statusCode}');
  }
}

// ── Modelos de respuesta del servidor ─────────────────────────────────────────

class ServerCard {
  const ServerCard({
    required this.serverId,
    required this.name,
    required this.setCode,
    required this.imageUrl,
    required this.cardClass,
    required this.faction,
  });

  final int serverId;
  final String name;
  final String setCode;
  final String imageUrl;
  final String cardClass;
  final String faction;

  factory ServerCard.fromJson(Map<String, dynamic> json) => ServerCard(
        serverId: json['id'] as int,
        name: json['name'] as String,
        setCode: json['set_code'] as String,
        imageUrl: json['image_url'] as String,
        cardClass: json['card_class'] as String? ?? '',
        faction: json['faction'] as String? ?? '',
      );
}

class ServerException implements Exception {
  const ServerException(this.message);
  final String message;

  @override
  String toString() => 'ServerException: $message';
}
