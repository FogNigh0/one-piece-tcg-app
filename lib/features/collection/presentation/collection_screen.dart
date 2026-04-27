// lib/features/collection/presentation/collection_screen.dart
import 'dart:io';
import 'package:flutter/material.dart';

import '../../../app/app.dart';
import '../../../core/database/card_database.dart';
import '../../../core/widgets/card_image_widget.dart';
import '../../folders/presentation/folders_screen.dart';

class CollectionScreen extends StatefulWidget {
  const CollectionScreen({super.key});

  @override
  State<CollectionScreen> createState() => _CollectionScreenState();
}

class _CollectionScreenState extends State<CollectionScreen> {
  List<ScannedCard> _all = [];
  List<_GroupedCard> _grouped = [];
  List<_GroupedCard> _filtered = [];
  bool _loading     = true;
  bool _showFilters = false;

  final _searchCtrl = TextEditingController();

  String _filterType  = 'Todos';
  String _filterColor = 'Todos';
  String _filterSet   = 'Todos';

  static const _types  = ['Todos', 'CHARACTER', 'LEADER', 'EVENT', 'STAGE'];
  static const _colors = ['Todos', 'Red', 'Blue', 'Green', 'Purple', 'Black', 'Yellow'];

  @override
  void initState() {
    super.initState();
    _load();
    _searchCtrl.addListener(_applyFilter);
    AppEvents.collectionVersion.addListener(_onCollectionChanged);
  }

  void _onCollectionChanged() {
    if (mounted) _load();
  }

  @override
  void dispose() {
    AppEvents.collectionVersion.removeListener(_onCollectionChanged);
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final cards = await CardDatabase.instance.getAllCards();
    final grouped = _groupCards(cards);
    if (!mounted) return;
    setState(() {
      _all = cards;
      _grouped = grouped;
      _loading = false;
    });
    _applyFilter();
  }

  List<_GroupedCard> _groupCards(List<ScannedCard> cards) {
    final map = <String, List<ScannedCard>>{};
    for (final card in cards) {
      map.putIfAbsent(card.setCode, () => []).add(card);
    }
    final groups = map.entries.map((entry) {
      final items = entry.value
        ..sort((a, b) => b.scannedAt.compareTo(a.scannedAt));
      return _GroupedCard(setCode: entry.key, cards: items);
    }).toList();
    groups.sort((a, b) => b.latestScannedAt.compareTo(a.latestScannedAt));
    return groups;
  }

  void _applyFilter() {
    final query = _searchCtrl.text.toLowerCase().trim();
    setState(() {
      _filtered = _grouped.where((group) {
        final card = group.representative;

        if (query.isNotEmpty) {
          final matches =
              card.name.toLowerCase().contains(query) ||
              card.setCode.toLowerCase().contains(query) ||
              card.faction.toLowerCase().contains(query) ||
              card.cardClass.toLowerCase().contains(query);
          if (!matches) return false;
        }

        if (_filterType != 'Todos' &&
            card.cardClass.toUpperCase() != _filterType) return false;

        if (_filterSet != 'Todos') {
          final setPrefix = card.setCode.replaceAll(RegExp(r'[-_].*'), '');
          if (setPrefix != _filterSet) return false;
        }

        return true;
      }).toList();
    });
  }

  void _resetFilters() {
    _searchCtrl.clear();
    setState(() {
      _filterType  = 'Todos';
      _filterColor = 'Todos';
      _filterSet   = 'Todos';
    });
    _applyFilter();
  }

  bool get _hasActiveFilters =>
      _filterType != 'Todos' ||
      _filterColor != 'Todos' ||
      _filterSet   != 'Todos' ||
      _searchCtrl.text.isNotEmpty;

  List<String> get _availableSets {
    final sets = _all
        .map((c) => c.setCode.replaceAll(RegExp(r'[-_].*'), ''))
        .toSet()
        .toList()
      ..sort();
    return ['Todos', ...sets];
  }

  void _openFolders() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const FoldersScreen()),
    ).then((_) => _load());
  }

  Future<List<_FolderCardSummary>> _buildFolderSummary(
    _GroupedCard group,
  ) async {
    final folders = await CardDatabase.instance.getAllFolders();
    final result = <_FolderCardSummary>[];
    for (final folder in folders) {
      final items = await CardDatabase.instance.getCardsInFolder(folder.id!);
      final matches = items
          .where((item) => item.card.setCode == group.setCode)
          .toList();
      if (matches.isNotEmpty) {
        final total = matches.fold<int>(0, (sum, e) => sum + e.quantity);
        result.add(_FolderCardSummary(folder: folder, quantity: total));
      }
    }
    return result;
  }

  Future<void> _showDeleteOptions(_GroupedCard group) async {
    final folderSummary = await _buildFolderSummary(group);
    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text(
                'Eliminar ${group.representative.name}',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.remove_circle_outline),
              title: const Text('Borrar 1 copia'),
              onTap: () async {
                Navigator.pop(ctx);
                await _deleteOneCopy(group);
              },
            ),
            ListTile(
              leading: const Icon(Icons.folder_delete_outlined),
              title: const Text('Borrar de una carpeta específica'),
              subtitle: folderSummary.isEmpty
                  ? const Text('No está en ninguna carpeta')
                  : null,
              enabled: folderSummary.isNotEmpty,
              onTap: folderSummary.isEmpty
                  ? null
                  : () async {
                      Navigator.pop(ctx);
                      await _deleteFromSpecificFolder(group, folderSummary);
                    },
            ),
            ListTile(
              leading: const Icon(
                Icons.delete_forever_outlined,
                color: Colors.red,
              ),
              title: const Text(
                'Borrar todas las copias',
                style: TextStyle(color: Colors.red),
              ),
              onTap: () async {
                Navigator.pop(ctx);
                await _deleteAllCopies(group);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Future<void> _deleteOneCopy(_GroupedCard group) async {
    final target = group.cards.first;
    if (target.id == null) return;
    await CardDatabase.instance.deleteCard(target.id!, target.localImagePath);
    AppEvents.notifyCollectionChanged();
  }

  Future<void> _deleteAllCopies(_GroupedCard group) async {
    for (final card in group.cards) {
      if (card.id != null) {
        await CardDatabase.instance.deleteCard(card.id!, card.localImagePath);
      }
    }
    AppEvents.notifyCollectionChanged();
  }

  Future<void> _deleteFromSpecificFolder(
    _GroupedCard group,
    List<_FolderCardSummary> folderSummary,
  ) async {
    final selected = await showDialog<_FolderCardSummary>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('¿De qué carpeta?'),
        children: folderSummary
            .map(
              (item) => SimpleDialogOption(
                onPressed: () => Navigator.pop(ctx, item),
                child: Row(
                  children: [
                    const Icon(Icons.folder_outlined),
                    const SizedBox(width: 10),
                    Expanded(child: Text(item.folder.name)),
                    Text('x\${item.quantity}'),
                  ],
                ),
              ),
            )
            .toList(),
      ),
    );
    if (selected == null) return;
    final folderItems = await CardDatabase.instance.getCardsInFolder(
      selected.folder.id!,
    );
    final matches = folderItems
        .where((e) => e.card.setCode == group.setCode)
        .toList();
    if (matches.isEmpty) return;
    final target = matches.first;
    if (target.card.id == null) return;
    await CardDatabase.instance.removeCardFromFolderAndCleanup(
      folderId: selected.folder.id!,
      cardId: target.card.id!,
      imagePath: target.card.localImagePath,
    );
    AppEvents.notifyCollectionChanged();
  }

  Future<void> _showDetail(_GroupedCard group) async {
    final folderSummary = await _buildFolderSummary(group);
    final allFolders = await CardDatabase.instance.getAllFolders();
    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => _GroupedCardDetailSheet(
        group: group,
        folderSummary: folderSummary,
        allFolders: allFolders,
        onOpenFolder: (folder) {
          Navigator.pop(context);
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const FoldersScreen()),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Colección (${_filtered.length})'),
        actions: [
          if (_hasActiveFilters)
            IconButton(
              icon: const Icon(Icons.clear_all),
              tooltip: 'Limpiar filtros',
              onPressed: _resetFilters,
            ),
          IconButton(
            icon: const Icon(Icons.folder_outlined),
            tooltip: 'Mis Carpetas',
            onPressed: _openFolders,
          ),
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(108),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: Column(
              children: [
                // ── Fila 1: búsqueda ───────────────────────────────────────
                TextField(
                  controller: _searchCtrl,
                  decoration: InputDecoration(
                    hintText: 'Buscar por nombre, ID, set, tipo...',
                    prefixIcon: const Icon(Icons.search, size: 20),
                    suffixIcon: _searchCtrl.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear, size: 18),
                            onPressed: () { _searchCtrl.clear(); _applyFilter(); },
                          )
                        : null,
                    isDense: true,
                    filled: true,
                    fillColor: Theme.of(context).colorScheme.surface,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                // ── Fila 2: dropdowns de filtro ────────────────────────────
                Row(
                  children: [
                    // Set
                    Expanded(
                      child: _FilterDropdown(
                        value: _filterSet,
                        items: _availableSets,
                        hint: 'Set',
                        onChanged: (v) { setState(() => _filterSet = v!); _applyFilter(); },
                      ),
                    ),
                    const SizedBox(width: 6),
                    // Tipo
                    Expanded(
                      child: _FilterDropdown(
                        value: _filterType,
                        items: _types,
                        hint: 'Tipo',
                        onChanged: (v) { setState(() => _filterType = v!); _applyFilter(); },
                      ),
                    ),
                    const SizedBox(width: 6),
                    // Color
                    Expanded(
                      child: _FilterDropdown(
                        value: _filterColor,
                        items: _colors,
                        hint: 'Color',
                        onChanged: (v) { setState(() => _filterColor = v!); _applyFilter(); },
                      ),
                    ),
                    // Limpiar (solo si hay filtros activos)
                    if (_hasActiveFilters) ...[
                      const SizedBox(width: 4),
                      IconButton(
                        icon: const Icon(Icons.clear_all, size: 20),
                        tooltip: 'Limpiar filtros',
                        onPressed: _resetFilters,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _filtered.isEmpty
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.search_off, size: 48, color: Colors.grey),
                  const SizedBox(height: 12),
                  Text(
                    _grouped.isEmpty
                        ? 'Tu colección está vacía.\nEscanea una carta para empezar.'
                        : 'No hay cartas que coincidan.',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.grey),
                  ),
                ],
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: _filtered.length,
              itemBuilder: (_, i) => _GroupedCollectionTile(
                group: _filtered[i],
                onDelete: () => _showDeleteOptions(_filtered[i]),
                onTap: () => _showDetail(_filtered[i]),
              ),
            ),
    );
  }
}

class _GroupedCard {
  _GroupedCard({required this.setCode, required this.cards});
  final String setCode;
  final List<ScannedCard> cards;
  ScannedCard get representative => cards.first;
  int get totalCopies => cards.length;
  DateTime get latestScannedAt => cards.first.scannedAt;
}

class _FolderCardSummary {
  _FolderCardSummary({required this.folder, required this.quantity});
  final Folder folder;
  final int quantity;
}

class _GroupedCollectionTile extends StatelessWidget {
  const _GroupedCollectionTile({
    required this.group,
    required this.onDelete,
    required this.onTap,
  });
  final _GroupedCard group;
  final VoidCallback onDelete;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final card = group.representative;
    final localFile = File(card.localImagePath);
    final imageUrl = card.serverImageUrl;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        leading: ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: SizedBox(
            width: 50,
            height: 72,
            child: imageUrl != null
                ? CardThumbnail(imageUrl: imageUrl)
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
        title: Row(
          children: [
            Expanded(
              child: Text(
                card.name,
                style: const TextStyle(fontWeight: FontWeight.bold),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                'x${group.totalCopies}',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onPrimaryContainer,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  card.setCode,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                if (card.cardClass.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  _TypeBadge(type: card.cardClass),
                ],
              ],
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
        trailing: IconButton(
          icon: const Icon(Icons.delete_outline, color: Colors.red),
          onPressed: onDelete,
        ),
        onTap: onTap,
      ),
    );
  }
}

class _GroupedCardDetailSheet extends StatefulWidget {
  const _GroupedCardDetailSheet({
    required this.group,
    required this.folderSummary,
    required this.onOpenFolder,
    required this.allFolders,
  });
  final _GroupedCard group;
  final List<_FolderCardSummary> folderSummary;
  final void Function(Folder folder) onOpenFolder;
  final List<Folder> allFolders;

  @override
  State<_GroupedCardDetailSheet> createState() =>
      _GroupedCardDetailSheetState();
}

class _GroupedCardDetailSheetState extends State<_GroupedCardDetailSheet> {
  Folder? _targetFolder;
  int _qty = 1;
  bool _saving = false;
  String? _feedback;

  @override
  void initState() {
    super.initState();
    if (widget.allFolders.isNotEmpty) _targetFolder = widget.allFolders.first;
  }

  Future<void> _addToFolder() async {
    final card = widget.group.representative;
    if (_targetFolder == null || _targetFolder!.id == null || card.id == null)
      return;
    setState(() {
      _saving = true;
      _feedback = null;
    });
    await CardDatabase.instance.addCardToFolder(
      folderId: _targetFolder!.id!,
      cardId: card.id!,
      quantity: _qty,
    );
    AppEvents.notifyCollectionChanged();
    if (!mounted) return;
    setState(() {
      _saving = false;
      _feedback = 'x$_qty agregadas a "${_targetFolder!.name}"';
      _qty = 1;
    });
  }

  @override
  Widget build(BuildContext context) {
    final card = widget.group.representative;
    final localFile = File(card.localImagePath);
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.85,
      builder: (_, ctrl) => SingleChildScrollView(
        controller: ctrl,
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Center(
              child: card.serverImageUrl != null
                  ? CardImageWidget(
                      imageUrl: card.serverImageUrl,
                      height: 220,
                      borderRadius: 12,
                      showShadow: true,
                    )
                  : localFile.existsSync()
                  ? ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.file(
                        localFile,
                        height: 220,
                        fit: BoxFit.contain,
                      ),
                    )
                  : const SizedBox.shrink(),
            ),
            const SizedBox(height: 16),
            Text(
              card.name,
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(card.setCode, style: const TextStyle(color: Colors.grey)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _InfoChip(
                  label: 'Copias totales',
                  value: '${widget.group.totalCopies}',
                ),
                _InfoChip(label: 'Tipo', value: card.cardClass),
                if (card.faction.isNotEmpty)
                  _InfoChip(label: 'Facción', value: card.faction),
              ],
            ),
            const Divider(height: 24),
            if (card.ability.isNotEmpty) ...[
              const Text(
                'Efecto',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 6),
              Text(card.ability),
              const SizedBox(height: 14),
            ],
            if (card.trigger.isNotEmpty) ...[
              const Text(
                'Trigger',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 6),
              Text(card.trigger),
              const SizedBox(height: 14),
            ],

            // ── Agregar a carpeta ─────────────────────────────────────────
            const Text(
              'Agregar a carpeta',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
            ),
            const SizedBox(height: 8),
            if (widget.allFolders.isEmpty)
              const Text(
                'No tienes carpetas creadas todavía.',
                style: TextStyle(color: Colors.grey),
              )
            else ...[
              InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: () async {
                  final selected = await showDialog<Folder>(
                    context: context,
                    builder: (ctx) => SimpleDialog(
                      title: const Text('Elegir carpeta'),
                      children: widget.allFolders
                          .map(
                            (f) => SimpleDialogOption(
                              onPressed: () => Navigator.pop(ctx, f),
                              child: Row(
                                children: [
                                  const Icon(Icons.folder_outlined),
                                  const SizedBox(width: 10),
                                  Expanded(child: Text(f.name)),
                                ],
                              ),
                            ),
                          )
                          .toList(),
                    ),
                  );
                  if (selected != null)
                    setState(() => _targetFolder = selected);
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 14,
                  ),
                  decoration: BoxDecoration(
                    color: Theme.of(
                      context,
                    ).colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.folder_outlined),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          _targetFolder?.name ?? 'Sin carpeta',
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                      const Icon(Icons.keyboard_arrow_down_rounded),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  children: [
                    const Text(
                      'Cantidad',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.remove_circle_outline),
                      onPressed: _qty > 1 ? () => setState(() => _qty--) : null,
                    ),
                    SizedBox(
                      width: 40,
                      child: Center(
                        child: Text(
                          '$_qty',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.add_circle_outline),
                      onPressed: () => setState(() => _qty++),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _saving ? null : _addToFolder,
                  icon: _saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.add_circle_outline),
                  label: Text(
                    _targetFolder == null
                        ? 'Agregar a carpeta (x$_qty)'
                        : 'Agregar a "${_targetFolder!.name}" (x$_qty)',
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
              if (_feedback != null) ...[
                const SizedBox(height: 10),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.green.shade50,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    _feedback!,
                    style: TextStyle(
                      color: Colors.green.shade800,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ],

            const Divider(height: 24),
            const Text(
              'En estas carpetas',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
            ),
            const SizedBox(height: 8),
            if (widget.folderSummary.isEmpty)
              const Text(
                'Esta carta no está en ninguna carpeta.',
                style: TextStyle(color: Colors.grey),
              )
            else
              ...widget.folderSummary.map(
                (item) => Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    leading: const Icon(Icons.folder_outlined),
                    title: Text(item.folder.name),
                    subtitle: const Text('Tocar para abrir'),
                    trailing: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primaryContainer,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        'x${item.quantity}',
                        style: TextStyle(
                          color: Theme.of(
                            context,
                          ).colorScheme.onPrimaryContainer,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    onTap: () => widget.onOpenFolder(item.folder),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  const _InfoChip({required this.label, required this.value});
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(12),
    ),
    child: Text('$label: $value'),
  );
}

class _TypeBadge extends StatelessWidget {
  const _TypeBadge({required this.type});
  final String type;
  Color _color() {
    switch (type.toUpperCase()) {
      case 'LEADER':
        return Colors.amber.shade700;
      case 'CHARACTER':
        return Colors.blue;
      case 'EVENT':
        return Colors.purple;
      case 'STAGE':
        return Colors.green;
      default:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    decoration: BoxDecoration(
      color: _color().withOpacity(0.12),
      borderRadius: BorderRadius.circular(4),
    ),
    child: Text(
      type,
      style: TextStyle(
        fontSize: 10,
        color: _color(),
        fontWeight: FontWeight.w600,
      ),
    ),
  );
}

// ── Widget dropdown de filtro compacto ───────────────────────────────────────

class _FilterDropdown extends StatelessWidget {
  const _FilterDropdown({
    required this.value,
    required this.items,
    required this.hint,
    required this.onChanged,
  });

  final String value;
  final List<String> items;
  final String hint;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    final isActive = value != 'Todos';
    return Container(
      height: 34,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: isActive
            ? Theme.of(context).colorScheme.primaryContainer
            : Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isActive
              ? Theme.of(context).colorScheme.primary.withOpacity(0.5)
              : Colors.transparent,
        ),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value,
          isExpanded: true,
          isDense: true,
          style: TextStyle(
            fontSize: 12,
            color: isActive
                ? Theme.of(context).colorScheme.onPrimaryContainer
                : Theme.of(context).colorScheme.onSurface,
          ),
          icon: Icon(
            Icons.arrow_drop_down,
            size: 18,
            color: isActive
                ? Theme.of(context).colorScheme.primary
                : Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          items: items.map((item) => DropdownMenuItem(
            value: item,
            child: Text(item, style: const TextStyle(fontSize: 12)),
          )).toList(),
          onChanged: onChanged,
        ),
      ),
    );
  }
}
