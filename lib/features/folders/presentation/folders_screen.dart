// lib/features/folders/presentation/folders_screen.dart

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import 'package:one_piece_card_scanner/app/app.dart';
import '../../../core/services/sync_service.dart';
import '../../../core/database/card_database.dart';
import '../../../core/widgets/card_image_widget.dart';
import '../../collection/presentation/collection_screen.dart'
    show GroupedCard, GroupedCardDetailSheet, FolderCardSummary;

// ═══════════════════════════════════════════════════════════════════════════════
// Pantalla principal — lista de carpetas
// ═══════════════════════════════════════════════════════════════════════════════

class FoldersScreen extends StatefulWidget {
  const FoldersScreen({super.key});

  @override
  State<FoldersScreen> createState() => _FoldersScreenState();
}

class _FoldersScreenState extends State<FoldersScreen> {
  List<Folder> _folders = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final folders = await CardDatabase.instance.getAllFolders();
    if (mounted) {
      setState(() {
        _folders = folders;
        _loading = false;
      });
    }
  }

  Future<void> _showCreateDialog({Folder? existing}) async {
    final nameCtrl = TextEditingController(text: existing?.name ?? '');
    final descCtrl = TextEditingController(text: existing?.description ?? '');
    bool isPublic = existing?.isPublic ?? false;
    String? error;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text(existing == null ? 'Nueva carpeta' : 'Editar carpeta'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                autofocus: true,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  labelText: 'Nombre *',
                  hintText: 'Ej: Colección completa OP01',
                  errorText: error,
                ),
                onChanged: (_) => setDialogState(() => error = null),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: descCtrl,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Descripción (opcional)',
                  hintText: 'Ej: Cartas del set Romance Dawn',
                ),
              ),
              const SizedBox(height: 12),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Carpeta pública'),
                subtitle: Text(
                  isPublic
                      ? 'Visible para otros usuarios'
                      : 'Solo tú puedes verla',
                  style: const TextStyle(fontSize: 12),
                ),
                value: isPublic,
                onChanged: (v) => setDialogState(() => isPublic = v),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () async {
                final name = nameCtrl.text.trim();
                if (name.isEmpty) {
                  setDialogState(() => error = 'El nombre es obligatorio');
                  return;
                }
                Navigator.pop(ctx);
                if (existing == null) {
                  final newFolder = await CardDatabase.instance.createFolder(
                    Folder(
                      name: name,
                      description: descCtrl.text.trim(),
                      isPublic: isPublic,
                    ),
                  );
                  // Sube la carpeta nueva al servidor en background
                  SyncService().uploadFolder(newFolder);
                } else {
                  final updated = existing.copyWith(
                    name: name,
                    description: descCtrl.text.trim(),
                    isPublic: isPublic,
                  );
                  await CardDatabase.instance.updateFolder(updated);
                }
                AppEvents.notifyFoldersChanged();
                _load();
              },
              child: Text(existing == null ? 'Crear' : 'Guardar'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _deleteFolder(Folder folder) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar carpeta'),
        content: Text(
          '¿Eliminar "${folder.name}"?\n\nLas cartas no se eliminan de tu colección, solo de esta carpeta.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );

    if (ok == true && folder.id != null) {
      await CardDatabase.instance.deleteFolder(folder.id!);
      AppEvents.notifyFoldersChanged();
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Mis Carpetas'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _folders.isEmpty
          ? _EmptyFolders(onCreate: () => _showCreateDialog())
          : ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: _folders.length,
              itemBuilder: (_, i) => _FolderTile(
                folder: _folders[i],
                onTap: () async {
                  await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => FolderDetailScreen(folder: _folders[i]),
                    ),
                  );
                  _load();
                },
                onEdit: () => _showCreateDialog(existing: _folders[i]),
                onDelete: () => _deleteFolder(_folders[i]),
              ),
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showCreateDialog(),
        icon: const Icon(Icons.create_new_folder_outlined),
        label: const Text('Nueva carpeta'),
      ),
    );
  }
}

// ── Tile de carpeta ───────────────────────────────────────────────────────────

class _FolderTile extends StatelessWidget {
  const _FolderTile({
    required this.folder,
    required this.onTap,
    required this.onEdit,
    required this.onDelete,
  });

  final Folder folder;
  final VoidCallback onTap;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 10,
        ),
        leading: CircleAvatar(
          backgroundColor: cs.primaryContainer,
          child: Icon(Icons.folder_outlined, color: cs.onPrimaryContainer),
        ),
        title: Text(
          folder.name,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  folder.totalCards == 1
                      ? '1 carta'
                      : '${folder.totalCards} cartas',
                  style: TextStyle(
                    color: cs.primary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                if (folder.isPublic) ...[
                  const SizedBox(width: 8),
                  Icon(Icons.public, size: 13, color: Colors.green.shade600),
                  const SizedBox(width: 2),
                  Text(
                    'Pública',
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.green.shade600,
                    ),
                  ),
                ],
              ],
            ),
            if (folder.description.isNotEmpty)
              Text(
                folder.description,
                style: const TextStyle(fontSize: 11, color: Colors.grey),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
          ],
        ),
        trailing: PopupMenuButton<String>(
          onSelected: (v) {
            if (v == 'edit') onEdit();
            if (v == 'delete') onDelete();
            if (v == 'share') _shareFolder(context);
          },
          itemBuilder: (_) {
            final isProtected = folder.id == CardDatabase.collectionFolderId;
            return [
              if (!isProtected)
                const PopupMenuItem(
                  value: 'edit',
                  child: ListTile(
                    leading: Icon(Icons.edit_outlined),
                    title: Text('Editar'),
                    dense: true,
                  ),
                ),
              // Compartir solo si es pública y tiene share_token
              if (folder.isPublic)
                const PopupMenuItem(
                  value: 'share',
                  child: ListTile(
                    leading: Icon(Icons.share_outlined, color: Colors.green),
                    title: Text('Compartir link',
                        style: TextStyle(color: Colors.green)),
                    dense: true,
                  ),
                ),
              if (!folder.isPublic && !isProtected)
                const PopupMenuItem(
                  enabled: false,
                  child: ListTile(
                    leading: Icon(Icons.share_outlined, color: Colors.grey),
                    title: Text('Hacer pública para compartir',
                        style: TextStyle(color: Colors.grey, fontSize: 12)),
                    dense: true,
                  ),
                ),
              if (!isProtected)
                const PopupMenuItem(
                  value: 'delete',
                  child: ListTile(
                    leading: Icon(Icons.delete_outline, color: Colors.red),
                    title: Text(
                      'Eliminar',
                      style: TextStyle(color: Colors.red),
                    ),
                    dense: true,
                  ),
                ),
              if (isProtected)
                const PopupMenuItem(
                  enabled: false,
                  child: ListTile(
                    leading: Icon(Icons.lock_outline, color: Colors.grey),
                    title: Text(
                      'Carpeta protegida',
                      style: TextStyle(color: Colors.grey),
                    ),
                    dense: true,
                  ),
                ),
            ];
          },
        ),
        onTap: onTap,
      ),
    );
  }

  Future<void> _shareFolder(BuildContext context) async {
    if (!folder.isPublic) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('La carpeta debe ser pública para compartir')),
      );
      return;
    }
    // Obtiene el share_token del servidor
    final token = await SyncService().getShareToken(folder.id!);
    if (token == null || token.isEmpty) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No se pudo obtener el link. Intenta de nuevo.')),
        );
      }
      return;
    }
    final link = 'opcardscanner://folder/$token';
    Share.share(
      'Mira mi colección One Piece TCG 🏴‍☠️\n$link',
      subject: 'Carpeta: ${folder.name}',
    );
  }
}

// ── Estado vacío ──────────────────────────────────────────────────────────────

class _EmptyFolders extends StatelessWidget {
  const _EmptyFolders({required this.onCreate});
  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.folder_open_outlined,
            size: 72,
            color: Theme.of(context).colorScheme.primary.withOpacity(0.4),
          ),
          const SizedBox(height: 16),
          const Text(
            'No tienes carpetas todavía',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
          const SizedBox(height: 6),
          const Text(
            'Crea carpetas para organizar tus cartas\nen colecciones virtuales.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey),
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: onCreate,
            icon: const Icon(Icons.create_new_folder_outlined),
            label: const Text('Crear primera carpeta'),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// Pantalla de detalle de carpeta
// ═══════════════════════════════════════════════════════════════════════════════

class FolderDetailScreen extends StatefulWidget {
  const FolderDetailScreen({super.key, required this.folder});
  final Folder folder;

  @override
  State<FolderDetailScreen> createState() => _FolderDetailScreenState();
}

class _FolderDetailScreenState extends State<FolderDetailScreen> {
  List<FolderCardEntry> _entries = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    if (widget.folder.id == null) return;
    final entries = await CardDatabase.instance.getCardsInFolder(
      widget.folder.id!,
    );
    if (mounted) {
      setState(() {
        _entries = entries;
        _loading = false;
      });
    }
  }

  int get _totalCards => _entries.fold(0, (sum, e) => sum + e.quantity);

  /// Abre el bottom sheet de detalle igual al de CollectionScreen
  Future<void> _showCardDetail(FolderCardEntry entry) async {
    // Construye el GroupedCard con las copias de esta carta
    final allCards = await CardDatabase.instance.getAllCards();
    final sameCopies = allCards.where((c) {
      final norm = RegExp(r'_p\d+\$');
      return c.setCode.replaceAll(norm, '') ==
          entry.card.setCode.replaceAll(norm, '');
    }).toList();
    final group = GroupedCard(
      setCode: entry.card.setCode,
      cards: sameCopies.isEmpty ? [entry.card] : sameCopies,
    );

    // Construye el resumen de carpetas para esta carta
    final allFolders = await CardDatabase.instance.getAllFolders();
    final List<FolderCardSummary> folderSummary = [];
    for (final folder in allFolders) {
      final items = await CardDatabase.instance.getCardsInFolder(folder.id!);
      final matches = items.where((e) {
        final norm = RegExp(r'_p\d+\$');
        return e.card.setCode.replaceAll(norm, '') ==
            entry.card.setCode.replaceAll(norm, '');
      }).toList();
      if (matches.isNotEmpty) {
        final total = matches.fold(0, (s, e) => s + e.quantity);
        folderSummary.add(FolderCardSummary(folder: folder, quantity: total));
      }
    }

    if (!mounted) return;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => GroupedCardDetailSheet(
        group: group,
        folderSummary: folderSummary,
        allFolders: allFolders,
        onOpenFolder: (folder) {
          Navigator.pop(context);
          // Si la carpeta destino es diferente a la actual, navega a ella
          if (folder.id != widget.folder.id) {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(
                builder: (_) => FolderDetailScreen(folder: folder),
              ),
            );
          }
        },
      ),
    );

    // Recarga por si agregó/movió cartas desde el sheet
    _load();
  }

  Future<void> _editQuantity(FolderCardEntry entry) async {
    final ctrl = TextEditingController(text: '${entry.quantity}');

    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Cantidad de "${entry.card.name}"'),
        content: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            IconButton(
              icon: const Icon(Icons.remove_circle_outline),
              iconSize: 32,
              onPressed: () {
                final val = int.tryParse(ctrl.text) ?? 1;
                if (val > 1) ctrl.text = '${val - 1}';
              },
            ),
            SizedBox(
              width: 64,
              child: TextField(
                controller: ctrl,
                keyboardType: TextInputType.number,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
                decoration: const InputDecoration(border: OutlineInputBorder()),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.add_circle_outline),
              iconSize: 32,
              onPressed: () {
                final val = int.tryParse(ctrl.text) ?? 1;
                ctrl.text = '${val + 1}';
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () async {
              final qty = int.tryParse(ctrl.text) ?? 1;
              Navigator.pop(ctx);
              await CardDatabase.instance.updateCardQuantityInFolder(
                folderId: entry.folderId,
                cardId: entry.card.id!,
                quantity: qty,
              );
              _load();
            },
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
  }

  Future<void> _removeCard(FolderCardEntry entry) async {
    final action = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Quitar "${entry.card.name}"'),
        content: Text(
          'Tienes x${entry.quantity} en esta carpeta.\n¿Cuántas quieres quitar?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar'),
          ),
          OutlinedButton(
            onPressed: () => Navigator.pop(ctx, 'one'),
            child: const Text('Quitar 1'),
          ),
          OutlinedButton(
            onPressed: () => Navigator.pop(ctx, 'custom'),
            child: const Text('Elegir cantidad'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, 'all'),
            child: const Text('Quitar todas'),
          ),
        ],
      ),
    );

    if (action == null || entry.card.id == null || widget.folder.id == null) {
      return;
    }

    if (action == 'one') {
      final newQty = entry.quantity - 1;
      if (newQty <= 0) {
        final db = await CardDatabase.instance.database;
        await db.delete(
          'folder_cards',
          where: 'folder_id = ? AND card_id = ?',
          whereArgs: [widget.folder.id!, entry.card.id!],
        );
        final remaining = await CardDatabase.instance
            .getFolderQuantitiesForCard(entry.card.id!);
        if (remaining.isEmpty) {
          await CardDatabase.instance.deleteCard(
            entry.card.id!,
            entry.card.localImagePath,
          );
        }
      } else {
        await CardDatabase.instance.updateCardQuantityInFolder(
          folderId: widget.folder.id!,
          cardId: entry.card.id!,
          quantity: newQty,
        );
      }
      AppEvents.notifyCollectionChanged();
      SyncService().uploadCollection();
      _load();
    } else if (action == 'custom') {
      await _removeCustomQuantity(entry);
    } else if (action == 'all') {
      final db = await CardDatabase.instance.database;
      await db.delete(
        'folder_cards',
        where: 'folder_id = ? AND card_id = ?',
        whereArgs: [widget.folder.id!, entry.card.id!],
      );
      final remaining = await CardDatabase.instance.getFolderQuantitiesForCard(
        entry.card.id!,
      );
      if (remaining.isEmpty) {
        await CardDatabase.instance.deleteCard(
          entry.card.id!,
          entry.card.localImagePath,
        );
      }
      AppEvents.notifyCollectionChanged();
      SyncService().uploadCollection();
      _load();
    }
  }

  Future<void> _removeCustomQuantity(FolderCardEntry entry) async {
    int qty = 1;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text('Quitar de "${widget.folder.name}"'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Tienes x${entry.quantity}. ¿Cuántas quieres quitar?'),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(
                    icon: const Icon(Icons.remove_circle_outline),
                    iconSize: 32,
                    onPressed: qty > 1
                        ? () => setDialogState(() => qty--)
                        : null,
                  ),
                  SizedBox(
                    width: 56,
                    child: Center(
                      child: Text(
                        '$qty',
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.add_circle_outline),
                    iconSize: 32,
                    onPressed: qty < entry.quantity
                        ? () => setDialogState(() => qty++)
                        : null,
                  ),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Colors.red),
              onPressed: () => Navigator.pop(ctx, true),
              child: Text('Quitar $qty'),
            ),
          ],
        ),
      ),
    );

    if (confirmed != true ||
        entry.card.id == null ||
        widget.folder.id == null) {
      return;
    }

    final newQty = entry.quantity - qty;
    if (newQty <= 0) {
      final db = await CardDatabase.instance.database;
      await db.delete(
        'folder_cards',
        where: 'folder_id = ? AND card_id = ?',
        whereArgs: [widget.folder.id!, entry.card.id!],
      );
      final remaining = await CardDatabase.instance.getFolderQuantitiesForCard(
        entry.card.id!,
      );
      if (remaining.isEmpty) {
        await CardDatabase.instance.deleteCard(
          entry.card.id!,
          entry.card.localImagePath,
        );
      }
    } else {
      await CardDatabase.instance.updateCardQuantityInFolder(
        folderId: widget.folder.id!,
        cardId: entry.card.id!,
        quantity: newQty,
      );
    }

    AppEvents.notifyCollectionChanged();
      SyncService().uploadCollection();
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.folder.name),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
        ],
        bottom: _entries.isNotEmpty
            ? PreferredSize(
                preferredSize: const Size.fromHeight(28),
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text(
                    '$_totalCards carta${_totalCards == 1 ? '' : 's'} en total · ${_entries.length} tipo${_entries.length == 1 ? '' : 's'}',
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              )
            : null,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _entries.isEmpty
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.inbox_outlined,
                    size: 64,
                    color: Colors.grey.shade400,
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Esta carpeta está vacía.\nEscanea cartas y agrégalas desde el Scanner.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey),
                  ),
                ],
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: _entries.length,
              itemBuilder: (_, i) => _FolderCardTile(
                entry: _entries[i],
                onTap: () => _showCardDetail(_entries[i]),
                onEditQuantity: () => _editQuantity(_entries[i]),
                onRemove: () => _removeCard(_entries[i]),
              ),
            ),
    );
  }
}

// ── Tile de carta en la carpeta ───────────────────────────────────────────────

class _FolderCardTile extends StatelessWidget {
  const _FolderCardTile({
    required this.entry,
    required this.onTap,
    required this.onEditQuantity,
    required this.onRemove,
  });

  final FolderCardEntry entry;
  final VoidCallback onTap;
  final VoidCallback onEditQuantity;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final card = entry.card;
    final localFile = File(card.localImagePath);
    final cs = Theme.of(context).colorScheme;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        onTap: onTap, // ← abre el detalle
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        leading: ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: SizedBox(
            width: 50,
            height: 72,
            child: card.serverImageUrl != null
                ? CardThumbnail(imageUrl: card.serverImageUrl)
                : localFile.existsSync()
                ? Image.file(localFile, fit: BoxFit.cover)
                : const ColoredBox(
                    color: Colors.grey,
                    child: Icon(
                      Icons.image_not_supported,
                      color: Colors.white,
                      size: 20,
                    ),
                  ),
          ),
        ),
        title: Text(
          card.name,
          style: const TextStyle(fontWeight: FontWeight.bold),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              card.setCode,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
            ),
            if (card.faction.isNotEmpty)
              Text(
                card.faction,
                style: const TextStyle(fontSize: 11, color: Colors.grey),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            GestureDetector(
              onTap: onEditQuantity,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: cs.primaryContainer,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'x${entry.quantity}',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: cs.onPrimaryContainer,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(width: 3),
                    Icon(Icons.edit, size: 12, color: cs.onPrimaryContainer),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 6),
            IconButton(
              icon: const Icon(Icons.remove_circle_outline, color: Colors.red),
              tooltip: 'Quitar de carpeta',
              onPressed: onRemove,
            ),
          ],
        ),
      ),
    );
  }

}