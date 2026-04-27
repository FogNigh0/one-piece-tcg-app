// lib/core/services/deck_service.dart
//
// Guarda y gestiona mazos localmente en SQLite.
// Formato de cartas: "3xOP05-082 1xOP11-097 4xOP14-079"

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

// ── Modelos ───────────────────────────────────────────────────────────────────

class DeckEntry {
  const DeckEntry({required this.quantity, required this.cardId});
  final int quantity;
  final String cardId;

  String toToken() => '${quantity}x$cardId';

  @override
  String toString() => toToken();
}

class Deck {
  Deck({
    this.id,
    required this.name,
    required this.entries,
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  final int? id;
  final String name;
  final List<DeckEntry> entries;
  final DateTime createdAt;
  final DateTime updatedAt;

  /// Total de cartas en el mazo (sumando cantidades)
  int get totalCards => entries.fold(0, (sum, e) => sum + e.quantity);

  /// Exporta al formato estándar TCG: "3xOP05-082 1xOP11-097"
  String toExportText() => entries.map((e) => e.toToken()).join(' ');

  /// Sets únicos presentes en el mazo
  Set<String> get sets =>
      entries.map((e) => e.cardId.split('-').first).toSet();

  Deck copyWith({String? name, List<DeckEntry>? entries}) => Deck(
        id: id,
        name: name ?? this.name,
        entries: entries ?? this.entries,
        createdAt: createdAt,
        updatedAt: DateTime.now(),
      );
}

// ── Parser ────────────────────────────────────────────────────────────────────

class DeckParser {
  /// Parsea texto tipo "3xOP05-082 1xOP11-097\n4xOP14-079"
  /// Acepta espacios, comas y saltos de línea como separadores.
  static List<DeckEntry> parse(String text) {
    final matches = RegExp(r'(\d+)x([A-Za-z0-9]+-\d+)', caseSensitive: false)
        .allMatches(text);
    return matches
        .map((m) => DeckEntry(
              quantity: int.parse(m.group(1)!),
              cardId: m.group(2)!.toUpperCase(),
            ))
        .toList();
  }

  /// Valida que el texto tenga al menos una entrada válida
  static bool isValid(String text) => parse(text).isNotEmpty;

  /// Agrupa entradas duplicadas sumando cantidades
  static List<DeckEntry> merge(List<DeckEntry> entries) {
    final map = <String, int>{};
    for (final e in entries) {
      map[e.cardId] = (map[e.cardId] ?? 0) + e.quantity;
    }
    return map.entries.map((e) => DeckEntry(quantity: e.value, cardId: e.key)).toList();
  }
}

// ── Base de datos ─────────────────────────────────────────────────────────────

class DeckService {
  DeckService._();
  static final DeckService instance = DeckService._();

  static Database? _db;

  Future<Database> get _database async {
    _db ??= await _open();
    return _db!;
  }

  Future<Database> _open() async {
    final path = p.join(await getDatabasesPath(), 'one_piece_cards.db');
    return openDatabase(
      path,
      version: 2,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS decks (
        id          INTEGER PRIMARY KEY AUTOINCREMENT,
        name        TEXT    NOT NULL,
        cards_text  TEXT    NOT NULL,
        created_at  TEXT    NOT NULL,
        updated_at  TEXT    NOT NULL
      )
    ''');
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS decks (
          id          INTEGER PRIMARY KEY AUTOINCREMENT,
          name        TEXT    NOT NULL,
          cards_text  TEXT    NOT NULL,
          created_at  TEXT    NOT NULL,
          updated_at  TEXT    NOT NULL
        )
      ''');
    }
  }

  // ── CRUD ──────────────────────────────────────────────────────────────────

  Future<Deck> saveDeck(Deck deck) async {
    final db = await _database;
    final now = DateTime.now().toIso8601String();
    final text = deck.toExportText();

    if (deck.id == null) {
      final id = await db.insert('decks', {
        'name': deck.name,
        'cards_text': text,
        'created_at': now,
        'updated_at': now,
      });
      return Deck(
        id: id,
        name: deck.name,
        entries: deck.entries,
        createdAt: deck.createdAt,
        updatedAt: deck.updatedAt,
      );
    } else {
      await db.update(
        'decks',
        {'name': deck.name, 'cards_text': text, 'updated_at': now},
        where: 'id = ?',
        whereArgs: [deck.id],
      );
      return deck;
    }
  }

  Future<List<Deck>> getAllDecks() async {
    final db = await _database;
    final rows = await db.query('decks', orderBy: 'updated_at DESC');
    return rows.map(_rowToDeck).toList();
  }

  Future<Deck?> getDeck(int id) async {
    final db = await _database;
    final rows = await db.query('decks', where: 'id = ?', whereArgs: [id]);
    if (rows.isEmpty) return null;
    return _rowToDeck(rows.first);
  }

  Future<void> deleteDeck(int id) async {
    final db = await _database;
    await db.delete('decks', where: 'id = ?', whereArgs: [id]);
  }

  Deck _rowToDeck(Map<String, dynamic> row) => Deck(
        id: row['id'] as int,
        name: row['name'] as String,
        entries: DeckParser.parse(row['cards_text'] as String),
        createdAt: DateTime.parse(row['created_at'] as String),
        updatedAt: DateTime.parse(row['updated_at'] as String),
      );
}
