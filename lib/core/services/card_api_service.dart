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
  static const String _defaultUrl = 'http://192.168.1.114:8000';

  final String baseUrl;

  /// Busca una carta por su código exacto y también sus variantes (alt art, parallel).
  /// Devuelve null si no se encuentra.
  Future<CardLookupResult?> lookupCard(String cardId) async {
    cardId = cardId.trim().toUpperCase();

    try {
      // 1. Busca la carta exacta por código
      final response = await http
          .get(Uri.parse('$baseUrl/cards/$cardId'))
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 404) return null;
      if (response.statusCode != 200) {
        throw Exception('Error del servidor: ${response.statusCode}');
      }

      final card = CardData.fromJson(
          jsonDecode(response.body) as Map<String, dynamic>);

      // 2. Busca todas las versiones del mismo set con el mismo nombre limpio.
      final searchName = card.cleanName;
      if (searchName.isEmpty) {
        return CardLookupResult(card: card, alternateVersions: []);
      }

      final variantsResponse = await http
          .get(Uri.parse(
              '$baseUrl/cards/?q=${Uri.encodeComponent(searchName)}&set_code=${card.setCode}'))
          .timeout(const Duration(seconds: 10));

      List<CardData> otherVersions = [];
      if (variantsResponse.statusCode == 200) {
        final body = jsonDecode(variantsResponse.body) as Map<String, dynamic>;
        final all = (body['results'] as List<dynamic>? ?? [])
            .cast<Map<String, dynamic>>()
            .map(CardData.fromJson)
            .where((c) => c.id != cardId)
            .toList();
        otherVersions = all;
      }

      // 3. Si la carta encontrada es Alternate Art y existe una versión base,
      //    ponemos la base como carta principal para mostrar primero.
      if (card.isAlternate && otherVersions.isNotEmpty) {
        final base = otherVersions.firstWhere(
          (c) => !c.isAlternate,
          orElse: () => card,
        );
        if (base.id != card.id) {
          final variants = [card, ...otherVersions.where((c) => c.id != base.id)];
          return CardLookupResult(card: base, alternateVersions: variants);
        }
      }

      return CardLookupResult(card: card, alternateVersions: otherVersions);

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
}
