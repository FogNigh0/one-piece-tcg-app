// lib/core/database/card_database.dart
//
// Base de datos local usando SQLite (sqflite).
// v1 → scanned_cards
// v2 → agrega folders y folder_cards (para colecciones virtuales)

import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

// ── Modelo ScannedCard ────────────────────────────────────────────────────────

class ScannedCard {
  ScannedCard({
    this.id,
    required this.name,
    required this.cardClass,
    required this.faction,
    required this.setCode,
    required this.ability,
    required this.trigger,
    required this.localImagePath,
    this.serverImageUrl,
    DateTime? scannedAt,
  }) : scannedAt = scannedAt ?? DateTime.now();

  final int? id;
  final String name;
  final String cardClass;
  final String faction;
  final String setCode;
  final String ability;
  final String trigger;
  final String localImagePath;
  final String? serverImageUrl;
  final DateTime scannedAt;

  Map<String, dynamic> toMap() => {
        if (id != null) 'id': id,
        'name': name,
        'card_class': cardClass,
        'faction': faction,
        'set_code': setCode,
        'ability': ability,
        'trigger': trigger,
        'local_image_path': localImagePath,
        'server_image_url': serverImageUrl,
        'scanned_at': scannedAt.toIso8601String(),
      };

  factory ScannedCard.fromMap(Map<String, dynamic> map) => ScannedCard(
        id: map['id'] as int?,
        name: map['name'] as String,
        cardClass: map['card_class'] as String,
        faction: map['faction'] as String,
        setCode: map['set_code'] as String,
        ability: map['ability'] as String,
        trigger: map['trigger'] as String,
        localImagePath: map['local_image_path'] as String,
        serverImageUrl: map['server_image_url'] as String?,
        scannedAt: DateTime.parse(map['scanned_at'] as String),
      );

  ScannedCard copyWith({String? serverImageUrl, int? id}) => ScannedCard(
        id: id ?? this.id,
        name: name,
        cardClass: cardClass,
        faction: faction,
        setCode: setCode,
        ability: ability,
        trigger: trigger,
        localImagePath: localImagePath,
        serverImageUrl: serverImageUrl ?? this.serverImageUrl,
        scannedAt: scannedAt,
      );
}

// ── Modelo Folder ─────────────────────────────────────────────────────────────

class Folder {
  Folder({
    this.id,
    required this.name,
    this.description = '',
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  final int? id;
  final String name;
  final String description;
  final DateTime createdAt;

  // Total de cartas en la carpeta (suma de cantidades), cargado por join
  int totalCards = 0;

  Map<String, dynamic> toMap() => {
        if (id != null) 'id': id,
        'name': name,
        'description': description,
        'created_at': createdAt.toIso8601String(),
      };

  factory Folder.fromMap(Map<String, dynamic> map) {
    final f = Folder(
      id: map['id'] as int?,
      name: map['name'] as String,
      description: map['description'] as String? ?? '',
      createdAt: DateTime.parse(map['created_at'] as String),
    );
    f.totalCards = map['total_cards'] as int? ?? 0;
    return f;
  }

  Folder copyWith({String? name, String? description}) => Folder(
        id: id,
        name: name ?? this.name,
        description: description ?? this.description,
        createdAt: createdAt,
      );
}

// ── Modelo FolderCardEntry ────────────────────────────────────────────────────
// Carta dentro de una carpeta, con cantidad y datos de la carta

class FolderCardEntry {
  FolderCardEntry({
    required this.folderId,
    required this.card,
    required this.quantity,
  });

  final int folderId;
  final ScannedCard card;
  int quantity;
}

// ── CardDatabase ──────────────────────────────────────────────────────────────

class CardDatabase {
  CardDatabase._();
  static final CardDatabase instance = CardDatabase._();

  static Database? _db;

  Future<Database> get database async {
    _db ??= await _openDatabase();
    return _db!;
  }

  Future<Database> _openDatabase() async {
    final dbPath = await getDatabasesPath();
    final fullPath = p.join(dbPath, 'one_piece_cards.db');

    return openDatabase(
      fullPath,
      version: 2,
      onCreate: (db, version) async {
        await _createAllTables(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await _createFolderTables(db);
        }
      },
      onOpen: (db) async {
        await _ensureCollectionFolder(db);
      },
    );
  }

  // ID de la carpeta Colección — protegida por ID, sin importar el nombre
  static int? collectionFolderId;

  /// Crea la carpeta Colección si no existe.
  /// Usa description = '__collection__' como identificador interno inmutable.
  Future<void> _ensureCollectionFolder(Database db) async {
    final rows = await db.query(
      'folders',
      where: 'description = ?',
      whereArgs: ['__collection__'],
    );
    if (rows.isNotEmpty) {
      collectionFolderId = rows.first['id'] as int;
      return;
    }
    final id = await db.insert('folders', {
      'name': 'Colección',
      'description': '__collection__',
      'created_at': DateTime.now().toIso8601String(),
    });
    collectionFolderId = id;
  }

  Future<void> _createAllTables(Database db) async {
    await db.execute('''
      CREATE TABLE scanned_cards (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        card_class TEXT NOT NULL,
        faction TEXT NOT NULL,
        set_code TEXT NOT NULL,
        ability TEXT NOT NULL,
        trigger TEXT NOT NULL,
        local_image_path TEXT NOT NULL,
        server_image_url TEXT,
        scanned_at TEXT NOT NULL
      )
    ''');
    await _createFolderTables(db);
  }

  Future<void> _createFolderTables(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS folders (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        description TEXT NOT NULL DEFAULT '',
        created_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS folder_cards (
        folder_id INTEGER NOT NULL,
        card_id INTEGER NOT NULL,
        quantity INTEGER NOT NULL DEFAULT 1,
        added_at TEXT NOT NULL,
        PRIMARY KEY (folder_id, card_id),
        FOREIGN KEY (folder_id) REFERENCES folders(id) ON DELETE CASCADE,
        FOREIGN KEY (card_id) REFERENCES scanned_cards(id) ON DELETE CASCADE
      )
    ''');
  }

  // ── CRUD scanned_cards ────────────────────────────────────────────────────

  /// Inserta una carta y devuelve el objeto con su nuevo [id].
  Future<ScannedCard> insertCard(ScannedCard card) async {
    final db = await database;
    final id = await db.insert('scanned_cards', card.toMap());
    return card.copyWith(id: id);
  }

  /// Actualiza la URL del servidor para una carta ya guardada.
  Future<void> updateServerUrl(int id, String url) async {
    final db = await database;
    await db.update(
      'scanned_cards',
      {'server_image_url': url},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Devuelve todas las cartas ordenadas por fecha descendente.
  Future<List<ScannedCard>> getAllCards() async {
    final db = await database;
    final rows = await db.query('scanned_cards', orderBy: 'scanned_at DESC');
    return rows.map(ScannedCard.fromMap).toList();
  }

  /// Elimina una carta y su imagen local.
  Future<void> deleteCard(int id, String imagePath) async {
    final db = await database;
    await db.delete('scanned_cards', where: 'id = ?', whereArgs: [id]);
    final file = File(imagePath);
    if (await file.exists()) await file.delete();
  }

  // ── CRUD folders ──────────────────────────────────────────────────────────

  /// Crea una carpeta nueva y devuelve el objeto con su [id].
  Future<Folder> createFolder(Folder folder) async {
    final db = await database;
    final id = await db.insert('folders', folder.toMap());
    final created = Folder(
      id: id,
      name: folder.name,
      description: folder.description,
      createdAt: folder.createdAt,
    );
    return created;
  }

  /// Devuelve todas las carpetas con el total de cartas (suma de cantidades).
  Future<List<Folder>> getAllFolders() async {
    final db = await database;
    final rows = await db.rawQuery('''
      SELECT f.*, COALESCE(SUM(fc.quantity), 0) AS total_cards
      FROM folders f
      LEFT JOIN folder_cards fc ON fc.folder_id = f.id
      GROUP BY f.id
      ORDER BY f.created_at DESC
    ''');
    return rows.map(Folder.fromMap).toList();
  }

  /// Actualiza una carpeta. La carpeta Colección no permite editar nombre ni descripción.
  Future<void> updateFolder(Folder folder) async {
    if (folder.id == collectionFolderId) return;
    final db = await database;
    await db.update(
      'folders',
      {'name': folder.name, 'description': folder.description},
      where: 'id = ?',
      whereArgs: [folder.id],
    );
  }

  /// Elimina una carpeta. La carpeta Colección no puede eliminarse.
  Future<void> deleteFolder(int id) async {
    if (id == collectionFolderId) return;
    final db = await database;
    await db.delete('folders', where: 'id = ?', whereArgs: [id]);
  }

  // ── CRUD folder_cards ─────────────────────────────────────────────────────

  /// Agrega una carta a una carpeta con la cantidad indicada.
  /// Si la carta ya está en esa carpeta, suma la cantidad.
  Future<void> addCardToFolder({
    required int folderId,
    required int cardId,
    required int quantity,
  }) async {
    final db = await database;
    final existing = await db.query(
      'folder_cards',
      where: 'folder_id = ? AND card_id = ?',
      whereArgs: [folderId, cardId],
    );

    if (existing.isNotEmpty) {
      final currentQty = existing.first['quantity'] as int;
      await db.update(
        'folder_cards',
        {'quantity': currentQty + quantity},
        where: 'folder_id = ? AND card_id = ?',
        whereArgs: [folderId, cardId],
      );
    } else {
      await db.insert('folder_cards', {
        'folder_id': folderId,
        'card_id': cardId,
        'quantity': quantity,
        'added_at': DateTime.now().toIso8601String(),
      });
    }
  }

  /// Actualiza la cantidad de una carta en una carpeta.
  Future<void> updateCardQuantityInFolder({
    required int folderId,
    required int cardId,
    required int quantity,
  }) async {
    final db = await database;
    if (quantity <= 0) {
      await removeCardFromFolder(folderId: folderId, cardId: cardId);
      return;
    }
    await db.update(
      'folder_cards',
      {'quantity': quantity},
      where: 'folder_id = ? AND card_id = ?',
      whereArgs: [folderId, cardId],
    );
  }

/// Elimina una carta de una carpeta y, si no queda en ninguna otra carpeta,
/// la elimina también de la colección.
Future<void> removeCardFromFolderAndCleanup({
  required int folderId,
  required int cardId,
  required String imagePath,
}) async {
  await removeCardFromFolder(folderId: folderId, cardId: cardId);

  // Verificar si quedó en alguna otra carpeta
  final db = await database;
  final remaining = await db.query(
    'folder_cards',
    where: 'card_id = ?',
    whereArgs: [cardId],
  );

  if (remaining.isEmpty) {
    // No está en ninguna carpeta → eliminar de la colección
    await deleteCard(cardId, imagePath);
  }
}


  /// Elimina una carta de una carpeta.
/// Elimina UNA unidad de una carta en una carpeta.
/// Si la cantidad llega a 0, elimina la fila completa.
Future<void> removeCardFromFolder({
  required int folderId,
  required int cardId,
}) async {
  final db = await database;
  final existing = await db.query(
    'folder_cards',
    where: 'folder_id = ? AND card_id = ?',
    whereArgs: [folderId, cardId],
  );
  if (existing.isEmpty) return;
  final currentQty = existing.first['quantity'] as int;
  if (currentQty <= 1) {
    await db.delete(
      'folder_cards',
      where: 'folder_id = ? AND card_id = ?',
      whereArgs: [folderId, cardId],
    );
  } else {
    await db.update(
      'folder_cards',
      {'quantity': currentQty - 1},
      where: 'folder_id = ? AND card_id = ?',
      whereArgs: [folderId, cardId],
    );
  }
}

  /// Devuelve todas las cartas de una carpeta con sus cantidades.
  Future<List<FolderCardEntry>> getCardsInFolder(int folderId) async {
    final db = await database;
    final rows = await db.rawQuery('''
      SELECT sc.*, fc.quantity, fc.folder_id
      FROM folder_cards fc
      JOIN scanned_cards sc ON sc.id = fc.card_id
      WHERE fc.folder_id = ?
      ORDER BY fc.added_at DESC
    ''', [folderId]);

    return rows.map((row) {
      final qty = row['quantity'] as int;
      final fid = row['folder_id'] as int;
      // Construye ScannedCard ignorando columnas extra
      final card = ScannedCard.fromMap(row);
      return FolderCardEntry(folderId: fid, card: card, quantity: qty);
    }).toList();
  }

  /// Devuelve los IDs de carpetas que ya contienen una carta específica.
  Future<Map<int, int>> getFolderQuantitiesForCard(int cardId) async {
    final db = await database;
    final rows = await db.query(
      'folder_cards',
      where: 'card_id = ?',
      whereArgs: [cardId],
    );
    return {
      for (final r in rows) r['folder_id'] as int: r['quantity'] as int,
    };
  }

  // ── Helpers de imagen ─────────────────────────────────────────────────────

  static Future<String> persistImage(String tempPath) async {
    final appDir = await getApplicationDocumentsDirectory();
    final cardsDir = Directory(p.join(appDir.path, 'cards'));
    if (!await cardsDir.exists()) await cardsDir.create(recursive: true);

    final fileName = 'card_${DateTime.now().microsecondsSinceEpoch}.png';
    final dest = p.join(cardsDir.path, fileName);
    await File(tempPath).copy(dest);
    return dest;
  }
}