// lib/core/services/card_api_service.dart
//
// Servicio que consulta TU servidor para obtener datos de cartas.
// Cambia baseUrl según dónde estés probando.

import 'dart:convert';
import 'package:http/http.dart' as http;

// ── Modelo de carta ───────────────────────────────────────────────────────────

class CardData {
  const CardData({
    required this.id,
    required this.name,
    required this.setCode,
    required this.number,
    required this.cardType,
    required this.color,
    this.cost,
    this.power,
    this.counter,
    this.attribute,
    this.faction,
    this.effect,
    this.trigger,
    required this.rarity,
    this.imageUrl,
    this.hasAlternateArt = false,
    this.alternateVersions = const [],
  });

  final String id;
  final String name;
  final String setCode;
  final String number;
  final String cardType;
  final String color;
  final int? cost;
  final int? power;
  final int? counter;
  final String? attribute;
  final String? faction;
  final String? effect;
  final String? trigger;
  final String rarity;
  final String? imageUrl;
  final bool hasAlternateArt;
  final List<CardData> alternateVersions;

  factory CardData.fromJson(Map<String, dynamic> json) => CardData(
        id: json['id'] ?? '',
        name: json['name'] ?? '',
        setCode: json['set_code'] ?? '',
        number: json['number'] ?? '',
        cardType: json['card_type'] ?? '',
        color: json['color'] ?? '',
        cost: json['cost'] as int?,
        power: json['power'] as int?,
        counter: json['counter'] as int?,
        attribute: json['attribute'],
        faction: json['faction'],
        effect: json['effect'],
        trigger: json['trigger'],
        rarity: json['rarity'] ?? '',
        imageUrl: json['image_url'],
      );

  /// Devuelve true si es una versión con arte alternativo o parallel
  bool get isAlternate =>
      name.contains('Alternate Art') || name.contains('Parallel');

  /// Nombre limpio sin sufijos de variante
  String get cleanName => name
      .replaceAll(RegExp(r'\s*\(Alternate Art\)', caseSensitive: false), '')
      .replaceAll(RegExp(r'\s*\(Parallel\)', caseSensitive: false), '')
      .replaceAll(RegExp(r'\s*\(\d+\)', caseSensitive: false), '')
      .trim();

  String get rarityLabel {
    switch (rarity.toUpperCase()) {
      case 'C':   return 'Common';
      case 'UC':  return 'Uncommon';
      case 'R':   return 'Rare';
      case 'SR':  return 'Super Rare';
      case 'SEC': return 'Secret Rare';
      case 'L':   return 'Leader / Alt Art';
      default:    return rarity;
    }
  }
}

// ── Resultado del lookup ──────────────────────────────────────────────────────

class CardLookupResult {
  const CardLookupResult({
    required this.card,
    this.alternateVersions = const [],
  });

  final CardData card;
  /// Otras versiones del mismo código base (alternate art, parallel, etc.)
  final List<CardData> alternateVersions;

  bool get hasVariants => alternateVersions.isNotEmpty;
}

// ── Servicio ──────────────────────────────────────────────────────────────────

class CardApiService {
  CardApiService({String? baseUrl}) : baseUrl = baseUrl ?? _defaultUrl;

  // ── Cambia esta URL según dónde pruebes ────────────────────────────────────
  // Emulador Android:  http://10.0.2.2:8000
  // Celular físico:    http://TU-IP-LOCAL:8000   (ej: http://192.168.1.100:8000)
  // Producción:        https://tu-servidor.com
  static const String _defaultUrl = 'https://one-piece-tcg-server-production.up.railway.app';

  final String baseUrl;

  /// Busca una carta por su código exacto y también sus variantes (alt art, parallel).
  /// Devuelve null si no se encuentra.
  Future<CardLookupResult?> lookupCard(String cardId) async {
    cardId = cardId.trim().toUpperCase();

    try {
      // 1. Busca la carta exacta
      final response = await http
          .get(Uri.parse('$baseUrl/cards/$cardId'))
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 404) return null;
      if (response.statusCode != 200) {
        throw Exception('Error del servidor: ${response.statusCode}');
      }

      final card = CardData.fromJson(
          jsonDecode(response.body) as Map<String, dynamic>);

      // 2. Busca variantes del mismo número (mismo set+número, distinto nombre)
      //    Ej: OP04-019 y OP04-019 (Alternate Art) comparten el mismo slot
      final variantsResponse = await http
          .get(Uri.parse('$baseUrl/cards/?q=${card.cleanName}&set_code=${card.setCode}'))
          .timeout(const Duration(seconds: 10));

      List<CardData> alternates = [];
      if (variantsResponse.statusCode == 200) {
        final body =
            jsonDecode(variantsResponse.body) as Map<String, dynamic>;
        final results = (body['results'] as List<dynamic>? ?? [])
            .cast<Map<String, dynamic>>()
            .map(CardData.fromJson)
            .where((c) => c.id != cardId && c.isAlternate)
            .toList();
        alternates = results;
      }

      return CardLookupResult(card: card, alternateVersions: alternates);
    } on Exception {
      rethrow;
    }
  }

  /// Resuelve una lista de mazos tipo "3xOP05-082 1xOP11-097"
  Future<Map<String, dynamic>> resolveDeck(String deckText) async {
    final response = await http
        .post(
          Uri.parse('$baseUrl/decks/resolve'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'name': 'temp', 'cards_text': deckText}),
        )
        .timeout(const Duration(seconds: 15));

    if (response.statusCode != 200) {
      throw Exception('Error al resolver mazo: ${response.statusCode}');
    }

    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  /// Busca cartas por nombre o código
  Future<List<CardData>> searchCards(String query) async {
    final encoded = Uri.encodeComponent(query);
    final response = await http
        .get(Uri.parse('$baseUrl/cards/?q=$encoded&limit=30'))
        .timeout(const Duration(seconds: 10));

    if (response.statusCode != 200) {
      throw Exception('Error al buscar: ${response.statusCode}');
    }

    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final results = (body['results'] as List<dynamic>? ?? [])
        .cast<Map<String, dynamic>>()
        .map(CardData.fromJson)
        .toList();
    return results;
  }

  /// Obtiene una carpeta pública por su share_token (sin autenticación)
  Future<Map<String, dynamic>> getPublicFolder(String shareToken) async {
    final response = await http
        .get(Uri.parse('$baseUrl/folders/public/$shareToken'))
        .timeout(const Duration(seconds: 10));

    if (response.statusCode == 404) {
      throw Exception('Carpeta no encontrada o no es pública');
    }
    if (response.statusCode != 200) {
      throw Exception('Error al obtener carpeta: ${response.statusCode}');
    }

    return jsonDecode(response.body) as Map<String, dynamic>;
  }
}