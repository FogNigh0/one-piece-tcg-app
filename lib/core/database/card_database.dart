// lib/core/database/card_database.dart
// v3 — agrega campo `color` a ScannedCard, `isPublic` a Folder,
//       y deleteLocalImageSafely como método público

import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

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
    this.color = '',
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
  final String color;
  final DateTime scannedAt;

  bool get hasServerImage =>
      serverImageUrl != null && serverImageUrl!.isNotEmpty;

  String get displayImage => hasServerImage ? serverImageUrl! : localImagePath;

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
    'color': color,
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
    color: map['color'] as String? ?? '',
    scannedAt: DateTime.parse(map['scanned_at'] as String),
  );

  ScannedCard copyWith({
    String? serverImageUrl,
    int? id,
    String? localImagePath,
    String? color,
  }) => ScannedCard(
    id: id ?? this.id,
    name: name,
    cardClass: cardClass,
    faction: faction,
    setCode: setCode,
    ability: ability,
    trigger: trigger,
    localImagePath: localImagePath ?? this.localImagePath,
    serverImageUrl: serverImageUrl ?? this.serverImageUrl,
    color: color ?? this.color,
    scannedAt: scannedAt,
  );
}

class Folder {
  Folder({
    this.id,
    required this.name,
    this.description = '',
    this.isPublic = false,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  final int? id;
  final String name;
  final String description;
  final bool isPublic;
  final DateTime createdAt;
  int totalCards = 0;

  Map<String, dynamic> toMap() => {
    if (id != null) 'id': id,
    'name': name,
    'description': description,
    'is_public': isPublic ? 1 : 0,
    'created_at': createdAt.toIso8601String(),
  };

  factory Folder.fromMap(Map<String, dynamic> map) {
    final f = Folder(
      id: map['id'] as int?,
      name: map['name'] as String,
      description: map['description'] as String? ?? '',
      isPublic: (map['is_public'] as int? ?? 0) == 1,
      createdAt: DateTime.parse(map['created_at'] as String),
    );
    f.totalCards = map['total_cards'] as int? ?? 0;
    return f;
  }

  Folder copyWith({String? name, String? description, bool? isPublic}) =>
      Folder(
        id: id,
        name: name ?? this.name,
        description: description ?? this.description,
        isPublic: isPublic ?? this.isPublic,
        createdAt: createdAt,
      );
}

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

class CardDatabase {
  CardDatabase._();
  static final CardDatabase instance = CardDatabase._();

  static Database? _db;
  static int? _currentUserId;

  /// Llama esto después del login con el ID del usuario.
  /// Si el usuario cambia, cierra la BD anterior y abre la nueva.
  static Future<void> initForUser(int userId) async {
    if (_currentUserId == userId && _db != null) return;
    // Cierra la BD anterior si existe
    await _db?.close();
    _db = null;
    collectionFolderId = null;
    _currentUserId = userId;
  }

  /// Cierra la BD al hacer logout.
  static Future<void> closeForLogout() async {
    await _db?.close();
    _db = null;
    _currentUserId = null;
    collectionFolderId = null;
  }

  Future<Database> get database async {
    _db ??= await _openDatabase();
    return _db!;
  }

  Future<Database> _openDatabase() async {
    final dbPath = await getDatabasesPath();
    // BD separada por usuario: one_piece_cards_user_1.db
    final fileName = _currentUserId != null
        ? 'one_piece_cards_user_$_currentUserId.db'
        : 'one_piece_cards.db';
    final fullPath = p.join(dbPath, fileName);

    return openDatabase(
      fullPath,
      version: 3,
      onCreate: (db, version) async {
        await _createAllTables(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) await _createFolderTables(db);
        if (oldVersion < 3) {
          try {
            await db.execute(
              'ALTER TABLE scanned_cards ADD COLUMN color TEXT NOT NULL DEFAULT ""',
            );
          } catch (_) {}
          try {
            await db.execute(
              'ALTER TABLE folders ADD COLUMN is_public INTEGER NOT NULL DEFAULT 0',
            );
          } catch (_) {}
        }
      },
      onOpen: (db) async {
        await db.execute('PRAGMA foreign_keys = ON;');
        await _ensureCollectionFolder(db);
      },
    );
  }

  static int? collectionFolderId;

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
      'is_public': 0,
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
        color TEXT NOT NULL DEFAULT "",
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
        is_public INTEGER NOT NULL DEFAULT 0,
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

  Future<ScannedCard> insertCard(ScannedCard card) async {
    final db = await database;
    final id = await db.insert('scanned_cards', card.toMap());
    return card.copyWith(id: id);
  }

  Future<void> updateServerUrl(
    int id,
    String url, {
    bool deleteLocalImage = true,
  }) async {
    final db = await database;
    String? localPath;
    if (deleteLocalImage) {
      final rows = await db.query(
        'scanned_cards',
        columns: ['local_image_path'],
        where: 'id = ?',
        whereArgs: [id],
      );
      if (rows.isNotEmpty) {
        localPath = rows.first['local_image_path'] as String?;
      }
    }
    await db.update(
      'scanned_cards',
      {'server_image_url': url},
      where: 'id = ?',
      whereArgs: [id],
    );
    if (deleteLocalImage && localPath != null && localPath.isNotEmpty) {
      await deleteLocalImageSafely(localPath);
    }
  }

  /// Público para que scanner_screen pueda llamarlo directamente.
  Future<void> deleteLocalImageSafely(String path) async {
    try {
      final file = File(path);
      if (await file.exists()) await file.delete();
    } catch (_) {}
  }

  Future<List<ScannedCard>> getAllCards() async {
    final db = await database;
    final rows = await db.query('scanned_cards', orderBy: 'scanned_at DESC');
    return rows.map(ScannedCard.fromMap).toList();
  }

  Future<void> deleteCard(int id, String imagePath) async {
  final db = await database;
  // Limpiar folder_cards manualmente (no depender del CASCADE de SQLite)
  await db.delete('folder_cards', where: 'card_id = ?', whereArgs: [id]);
  await db.delete('scanned_cards', where: 'id = ?', whereArgs: [id]);
  final file = File(imagePath);
  if (await file.exists()) await file.delete();
  }

  Future<({int count, int savedKb})> cleanupLocalImages() async {
    final db = await database;
    final rows = await db.query(
      'scanned_cards',
      columns: ['local_image_path'],
      where: 'server_image_url IS NOT NULL AND server_image_url != ""',
    );
    int count = 0;
    int savedBytes = 0;
    for (final row in rows) {
      final path = row['local_image_path'] as String? ?? '';
      if (path.isEmpty) continue;
      final file = File(path);
      if (await file.exists()) {
        try {
          final size = await file.length();
          await file.delete();
          savedBytes += size;
          count++;
        } catch (_) {}
      }
    }
    return (count: count, savedKb: savedBytes ~/ 1024);
  }

  Future<double> localImagesSizeMb() async {
    final appDir = await getApplicationDocumentsDirectory();
    final cardsDir = Directory(p.join(appDir.path, 'cards'));
    if (!await cardsDir.exists()) return 0;
    int totalBytes = 0;
    await for (final entity in cardsDir.list()) {
      if (entity is File) totalBytes += await entity.length();
    }
    return totalBytes / (1024 * 1024);
  }

  Future<Folder> createFolder(Folder folder) async {
    final db = await database;
    final id = await db.insert('folders', folder.toMap());
    return Folder(
      id: id,
      name: folder.name,
      description: folder.description,
      isPublic: folder.isPublic,
      createdAt: folder.createdAt,
    );
  }

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

  Future<void> updateFolder(Folder folder) async {
    if (folder.id == collectionFolderId) return;
    final db = await database;
    await db.update(
      'folders',
      {
        'name': folder.name,
        'description': folder.description,
        'is_public': folder.isPublic ? 1 : 0,
      },
      where: 'id = ?',
      whereArgs: [folder.id],
    );
  }

  Future<void> deleteFolder(int id) async {
    if (id == collectionFolderId) return;
    final db = await database;
    await db.delete('folders', where: 'id = ?', whereArgs: [id]);
  }

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

  /// Elimina TODA la entrada de una carta en una carpeta (sin importar la cantidad)
  /// y si no queda en ninguna otra carpeta, borra también de scanned_cards.
  Future<void> removeCardFromFolderAndCleanup({
    required int folderId,
    required int cardId,
    required String imagePath,
  }) async {
    final db = await database;
    // Elimina la fila completa (no de 1 en 1)
    await db.delete(
      'folder_cards',
      where: 'folder_id = ? AND card_id = ?',
      whereArgs: [folderId, cardId],
    );
    // Si ya no está en ninguna carpeta, elimina el registro base
    final remaining = await db.query(
      'folder_cards',
      where: 'card_id = ?',
      whereArgs: [cardId],
    );
    if (remaining.isEmpty) await deleteCard(cardId, imagePath);
  }

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

  Future<List<FolderCardEntry>> getCardsInFolder(int folderId) async {
    final db = await database;
    final rows = await db.rawQuery(
      '''
      SELECT sc.*, fc.quantity, fc.folder_id
      FROM folder_cards fc
      JOIN scanned_cards sc ON sc.id = fc.card_id
      WHERE fc.folder_id = ?
      ORDER BY fc.added_at DESC
    ''',
      [folderId],
    );

    return rows.map((row) {
      final qty = row['quantity'] as int;
      final fid = row['folder_id'] as int;
      final card = ScannedCard.fromMap(row);
      return FolderCardEntry(folderId: fid, card: card, quantity: qty);
    }).toList();
  }

  Future<Map<int, int>> getFolderQuantitiesForCard(int cardId) async {
    final db = await database;
    final rows = await db.query(
      'folder_cards',
      where: 'card_id = ?',
      whereArgs: [cardId],
    );
    return {for (final r in rows) r['folder_id'] as int: r['quantity'] as int};
  }

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