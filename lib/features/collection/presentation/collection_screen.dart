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
  List<GroupedCard> _grouped = [];
  List<GroupedCard> _filtered = [];

  static const int _pageSize = 20;
  int _currentPage = 0;
  List<GroupedCard> _pageItems = [];

  bool _loading = true;
  final _searchCtrl = TextEditingController();

  String _filterType = 'Todos';
  String _filterColor = 'Todos';
  String _filterSet = 'Todos';

  static const _types = ['Todos', 'CHARACTER', 'LEADER', 'EVENT', 'STAGE'];
  static const _colors = [
    'Todos', 'Red', 'Blue', 'Green', 'Purple', 'Black', 'Yellow', 'Multicolor',
  ];

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

  /// Agrupa por setCode EXACTO — OP14-091 y OP14-091_p1 quedan separados.
  List<GroupedCard> _groupCards(List<ScannedCard> cards) {
    final map = <String, List<ScannedCard>>{};
    for (final card in cards) {
      map.putIfAbsent(card.setCode, () => []).add(card);
    }
    final groups = map.entries.map((entry) {
      final items = entry.value
        ..sort((a, b) => b.scannedAt.compareTo(a.scannedAt));
      return GroupedCard(setCode: entry.key, cards: items);
    }).toList();
    groups.sort((a, b) => b.latestScannedAt.compareTo(a.latestScannedAt));
    return groups;
  }

  void _applyFilter() {
    final query = _searchCtrl.text.toLowerCase().trim();
    final result = _grouped.where((group) {
      final card = group.representative;
      if (query.isNotEmpty) {
        final matches =
            card.name.toLowerCase().contains(query) ||
            card.setCode.toLowerCase().contains(query) ||
            card.faction.toLowerCase().contains(query) ||
            card.cardClass.toLowerCase().contains(query);
        if (!matches) return false;
      }
      if (_filterType != 'Todos' && card.cardClass.toUpperCase() != _filterType)
        return false;
      if (_filterSet != 'Todos') {
        final setPrefix = card.setCode.replaceAll(RegExp(r'-.*'), '');
        if (setPrefix != _filterSet) return false;
      }
      if (_filterColor != 'Todos') {
        final cardColor = card.color.toLowerCase();
        final filterLower = _filterColor.toLowerCase();
        if (_filterColor == 'Multicolor') {
          if (!cardColor.contains('/') && !cardColor.contains(';'))
            return false;
        } else {
          if (!cardColor.contains(filterLower)) return false;
        }
      }
      return true;
    }).toList();

    setState(() {
      _filtered = result;
      _currentPage = 0;
      _updatePage();
    });
  }

  void _updatePage() {
    final start = _currentPage * _pageSize;
    final end = (start + _pageSize).clamp(0, _filtered.length);
    setState(() {
      _pageItems = _filtered.sublist(start, end);
    });
  }

  void _goToPage(int page) {
    setState(() => _currentPage = page);
    _updatePage();
  }

  void _resetFilters() {
    _searchCtrl.clear();
    setState(() {
      _filterType = 'Todos';
      _filterColor = 'Todos';
      _filterSet = 'Todos';
    });
    _applyFilter();
  }

  bool get _hasActiveFilters =>
      _filterType != 'Todos' ||
      _filterColor != 'Todos' ||
      _filterSet != 'Todos' ||
      _searchCtrl.text.isNotEmpty;

  List<String> get _availableSets {
    final sets = _all
        .map((c) => c.setCode.replaceAll(RegExp(r'-.*'), ''))
        .toSet()
        .toList()
      ..sort();
    return ['Todos', ...sets];
  }

  int get _totalPages => (_filtered.length / _pageSize).ceil().clamp(1, 99999);

  void _openFolders() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const FoldersScreen()),
    ).then((_) => _load());
  }

  Future<List<FolderCardSummary>> _buildFolderSummary(GroupedCard group) async {
    final folders = await CardDatabase.instance.getAllFolders();
    final result = <FolderCardSummary>[];
    for (final folder in folders) {
      final items = await CardDatabase.instance.getCardsInFolder(folder.id!);
      // Comparación exacta de setCode
      final matches = items
          .where((item) => item.card.setCode == group.setCode)
          .toList();
      if (matches.isNotEmpty) {
        final total = matches.fold(0, (sum, e) => sum + e.quantity);
        result.add(FolderCardSummary(folder: folder, quantity: total));
      }
    }
    return result;
  }

  Future<void> _showDeleteOptions(GroupedCard group) async {
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

  Future<void> _deleteOneCopy(GroupedCard group) async {
    final target = group.cards.first;
    if (target.id == null) return;
    await CardDatabase.instance.deleteCard(target.id!, target.localImagePath);
    AppEvents.notifyCollectionChanged();
  }

  Future<void> _deleteAllCopies(GroupedCard group) async {
    for (final card in group.cards) {
      if (card.id != null) {
        await CardDatabase.instance.deleteCard(card.id!, card.localImagePath);
      }
    }
    AppEvents.notifyCollectionChanged();
  }

  Future<void> _deleteFromSpecificFolder(
    GroupedCard group,
    List<FolderCardSummary> folderSummary,
  ) async {
    final selected = await showDialog<FolderCardSummary>(
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
                    Text('x${item.quantity}'),
                  ],
                ),
              ),
            )
            .toList(),
      ),
    );
    if (selected == null) return;
    final folderItems =
        await CardDatabase.instance.getCardsInFolder(selected.folder.id!);
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

  Future<void> _showDetail(GroupedCard group) async {
    final folderSummary = await _buildFolderSummary(group);
    final allFolders = await CardDatabase.instance.getAllFolders();
    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => GroupedCardDetailSheet(
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
    final totalPages = _totalPages;
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
                TextField(
                  controller: _searchCtrl,
                  decoration: InputDecoration(
                    hintText: 'Buscar por nombre, ID, set, tipo...',
                    prefixIcon: const Icon(Icons.search, size: 20),
                    suffixIcon: _searchCtrl.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear, size: 18),
                            onPressed: () {
                              _searchCtrl.clear();
                              _applyFilter();
                            },
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
                Row(
                  children: [
                    Expanded(
                      child: _FilterDropdown(
                        value: _filterSet,
                        items: _availableSets,
                        hint: 'Set',
                        onChanged: (v) {
                          setState(() => _filterSet = v!);
                          _applyFilter();
                        },
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: _FilterDropdown(
                        value: _filterType,
                        items: _types,
                        hint: 'Tipo',
                        onChanged: (v) {
                          setState(() => _filterType = v!);
                          _applyFilter();
                        },
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: _FilterDropdown(
                        value: _filterColor,
                        items: _colors,
                        hint: 'Color',
                        onChanged: (v) {
                          setState(() => _filterColor = v!);
                          _applyFilter();
                        },
                      ),
                    ),
                    if (_hasActiveFilters) ...[
                      const SizedBox(width: 4),
                      IconButton(
                        icon: const Icon(Icons.clear_all, size: 20),
                        tooltip: 'Limpiar filtros',
                        onPressed: _resetFilters,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(
                          minWidth: 32,
                          minHeight: 32,
                        ),
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
                      const Icon(Icons.search_off,
                          size: 48, color: Colors.grey),
                      const SizedBox(height: 12),
                      Text(
                        _grouped.isEmpty
                            ? 'Tu colección está vacía. ¡Escanea una carta para empezar!'
                            : 'No hay cartas que coincidan.',
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.grey),
                      ),
                    ],
                  ),
                )
              : Column(
                  children: [
                    Expanded(
                      child: ListView.builder(
                        padding: const EdgeInsets.all(12),
                        itemCount: _pageItems.length,
                        itemBuilder: (_, i) => GroupedCollectionTile(
                          group: _pageItems[i],
                          onDelete: () => _showDeleteOptions(_pageItems[i]),
                          onTap: () => _showDetail(_pageItems[i]),
                        ),
                      ),
                    ),
                    if (totalPages > 1)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            vertical: 8, horizontal: 16),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.surface,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.06),
                              blurRadius: 6,
                              offset: const Offset(0, -2),
                            ),
                          ],
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.first_page),
                              onPressed: _currentPage > 0
                                  ? () => _goToPage(0)
                                  : null,
                            ),
                            IconButton(
                              icon: const Icon(Icons.chevron_left),
                              onPressed: _currentPage > 0
                                  ? () => _goToPage(_currentPage - 1)
                                  : null,
                            ),
                            Text(
                              'Página ${_currentPage + 1} de $totalPages',
                              style: const TextStyle(
                                  fontWeight: FontWeight.w600, fontSize: 13),
                            ),
                            IconButton(
                              icon: const Icon(Icons.chevron_right),
                              onPressed: _currentPage < totalPages - 1
                                  ? () => _goToPage(_currentPage + 1)
                                  : null,
                            ),
                            IconButton(
                              icon: const Icon(Icons.last_page),
                              onPressed: _currentPage < totalPages - 1
                                  ? () => _goToPage(totalPages - 1)
                                  : null,
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
    );
  }
}

// ─── Modelos de UI ────────────────────────────────────────────────────────────

class GroupedCard {
  GroupedCard({required this.setCode, required this.cards});
  final String setCode;
  final List<ScannedCard> cards;

  ScannedCard get representative => cards.first;

  /// Cantidad de filas en scanned_cards para este setCode exacto.
  int get totalCopies => cards.length;

  DateTime get latestScannedAt => cards.first.scannedAt;
}

class FolderCardSummary {
  FolderCardSummary({required this.folder, required this.quantity});
  final Folder folder;
  final int quantity;
}

// ─── Tile de carta agrupada ───────────────────────────────────────────────────

class GroupedCollectionTile extends StatelessWidget {
  const GroupedCollectionTile({
    super.key,
    required this.group,
    required this.onDelete,
    required this.onTap,
  });

  final GroupedCard group;
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
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
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
                        child: Icon(Icons.image_not_supported,
                            color: Colors.white, size: 20),
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
            // FIX #3: muestra totalCopies (cantidad real de filas escaneadas)
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
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
                      fontSize: 12, fontWeight: FontWeight.w500),
                ),
                if (card.cardClass.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  TypeBadge(type: card.cardClass),
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

// ─── Detalle de carta (bottom sheet) ─────────────────────────────────────────

class GroupedCardDetailSheet extends StatefulWidget {
  const GroupedCardDetailSheet({
    super.key,
    required this.group,
    required this.folderSummary,
    required this.onOpenFolder,
    required this.allFolders,
  });

  final GroupedCard group;
  final List<FolderCardSummary> folderSummary;
  final void Function(Folder folder) onOpenFolder;
  final List<Folder> allFolders;

  @override
  State<GroupedCardDetailSheet> createState() =>
      _GroupedCardDetailSheetState();
}

class _GroupedCardDetailSheetState extends State<GroupedCardDetailSheet> {
  Folder? _targetFolder;
  int _qty = 1;
  bool _saving = false;
  String? _feedback;

  @override
  void initState() {
    super.initState();
    if (widget.allFolders.isNotEmpty) {
      _targetFolder = widget.allFolders.first;
    }
  }

  Future<void> _addToFolder() async {
    final card = widget.group.representative;
    if (_targetFolder == null ||
        _targetFolder!.id == null ||
        card.id == null) {
      return;
    }
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
      _feedback = 'x$_qty agregada${_qty > 1 ? 's' : ''} a ${_targetFolder!.name}';
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
                      imageUrl: card.serverImageUrl!,
                      height: 220,
                      borderRadius: 12,
                      showShadow: true,
                    )
                  : localFile.existsSync()
                      ? ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: Image.file(localFile,
                              height: 220, fit: BoxFit.contain),
                        )
                      : const SizedBox.shrink(),
            ),
            const SizedBox(height: 16),
            Text(
              card.name,
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(card.setCode,
                style: const TextStyle(color: Colors.grey)),
            const SizedBox(height: 8),
            // FIX #1: solo muestra "En carpetas" (quitado "Copias escaneadas")
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                InfoChip(
                  label: 'En carpetas',
                  value: widget.folderSummary
                      .fold(0, (sum, e) => sum + e.quantity)
                      .toString(),
                ),
                InfoChip(label: 'Tipo', value: card.cardClass),
                if (card.faction.isNotEmpty)
                  InfoChip(label: 'Facción', value: card.faction),
              ],
            ),
            const Divider(height: 24),
            if (card.ability.isNotEmpty) ...[
              const Text('Efecto',
                  style: TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              Text(card.ability),
              const SizedBox(height: 14),
            ],
            if (card.trigger.isNotEmpty) ...[
              const Text('Trigger',
                  style: TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              Text(card.trigger),
              const SizedBox(height: 14),
            ],
            // FIX #2: sección "Mover entre carpetas" restaurada
            if (widget.folderSummary.isNotEmpty && widget.allFolders.length >= 1) ...[
              const Text(
                'Mover entre carpetas',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
              ),
              const SizedBox(height: 8),
              _MoveCardSection(
                group: widget.group,
                folderSummary: widget.folderSummary,
                allFolders: widget.allFolders,
              ),
              const Divider(height: 24),
            ],
            const Text(
              'Agregar a carpeta',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
            ),
            const SizedBox(height: 8),
            if (widget.allFolders.isEmpty)
              const Text('No tienes carpetas creadas todavía.',
                  style: TextStyle(color: Colors.grey))
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
                              child: Row(children: [
                                const Icon(Icons.folder_outlined),
                                const SizedBox(width: 10),
                                Expanded(child: Text(f.name)),
                              ]),
                            ),
                          )
                          .toList(),
                    ),
                  );
                  if (selected != null) {
                    setState(() => _targetFolder = selected);
                  }
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 14),
                  decoration: BoxDecoration(
                    color: Theme.of(context)
                        .colorScheme
                        .surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.folder_outlined),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          _targetFolder?.name ?? 'Sin carpeta',
                          style: const TextStyle(
                              fontWeight: FontWeight.w600),
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
                    horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: Theme.of(context)
                      .colorScheme
                      .surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  children: [
                    const Text('Cantidad',
                        style: TextStyle(fontWeight: FontWeight.w700)),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.remove_circle_outline),
                      onPressed:
                          _qty > 1 ? () => setState(() => _qty--) : null,
                    ),
                    SizedBox(
                      width: 40,
                      child: Center(
                        child: Text('$_qty',
                            style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold)),
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
                              strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.add_circle_outline),
                  label: Text(
                    _targetFolder == null
                        ? 'Agregar a carpeta (x$_qty)'
                        : 'Agregar a ${_targetFolder!.name} (x$_qty)',
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
                        fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ],
            const Divider(height: 24),
            const Text('En estas carpetas',
                style:
                    TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
            const SizedBox(height: 8),
            if (widget.folderSummary.isEmpty)
              const Text('Esta carta no está en ninguna carpeta.',
                  style: TextStyle(color: Colors.grey))
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
                          horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: Theme.of(context)
                            .colorScheme
                            .primaryContainer,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        'x${item.quantity}',
                        style: TextStyle(
                          color: Theme.of(context)
                              .colorScheme
                              .onPrimaryContainer,
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

// ─── Sección mover entre carpetas ────────────────────────────────────────────

class _MoveCardSection extends StatefulWidget {
  const _MoveCardSection({
    required this.group,
    required this.folderSummary,
    required this.allFolders,
  });

  final GroupedCard group;
  final List<FolderCardSummary> folderSummary;
  final List<Folder> allFolders;

  @override
  State<_MoveCardSection> createState() => _MoveCardSectionState();
}

class _MoveCardSectionState extends State<_MoveCardSection> {
  FolderCardSummary? _fromFolder;
  Folder? _toFolder;
  int _qty = 1;
  bool _moving = false;
  String? _feedback;

  @override
  void initState() {
    super.initState();
    _fromFolder = widget.folderSummary.first;
    // Destino por defecto: primera carpeta distinta al origen
    _toFolder = widget.allFolders.firstWhere(
      (f) => f.id != _fromFolder?.folder.id,
      orElse: () => widget.allFolders.first,
    );
  }

  int get _maxQty => _fromFolder?.quantity ?? 1;

  /// Recarga desde DB la cantidad real disponible en la carpeta origen.
  Future<int> _getRealQtyInOrigin() async {
    if (_fromFolder == null) return 0;
    final items = await CardDatabase.instance
        .getCardsInFolder(_fromFolder!.folder.id!);
    final matches = items
        .where((e) => e.card.setCode == widget.group.setCode)
        .toList();
    return matches.isEmpty ? 0 : matches.first.quantity;
  }

  Future<void> _move() async {
    if (_fromFolder == null || _toFolder == null) return;
    if (_fromFolder!.folder.id == _toFolder!.id) {
      setState(() => _feedback = 'Origen y destino son la misma carpeta');
      return;
    }
    setState(() {
      _moving = true;
      _feedback = null;
    });

    // Leer cantidad REAL desde DB (no la del widget que puede estar desactualizada)
    final folderItems = await CardDatabase.instance
        .getCardsInFolder(_fromFolder!.folder.id!);
    final matches = folderItems
        .where((e) => e.card.setCode == widget.group.setCode)
        .toList();

    if (matches.isEmpty) {
      if (mounted) setState(() {
        _moving = false;
        _feedback = 'No quedan cartas en esta carpeta';
        _qty = 1;
      });
      return;
    }

    final entry = matches.first;
    final cardId = entry.card.id;
    if (cardId == null) {
      if (mounted) setState(() { _moving = false; });
      return;
    }

    // Ajustar _qty por si el usuario pide mover más de lo que queda realmente
    final realAvailable = entry.quantity;
    final qtyToMove = _qty.clamp(1, realAvailable);
    final newQty = realAvailable - qtyToMove;

    if (newQty <= 0) {
      await CardDatabase.instance.removeCardFromFolderAndCleanup(
        folderId: _fromFolder!.folder.id!,
        cardId: cardId,
        imagePath: entry.card.localImagePath,
      );
    } else {
      await CardDatabase.instance.updateCardQuantityInFolder(
        folderId: _fromFolder!.folder.id!,
        cardId: cardId,
        quantity: newQty,
      );
    }
    await CardDatabase.instance.addCardToFolder(
      folderId: _toFolder!.id!,
      cardId: cardId,
      quantity: qtyToMove,
    );

    AppEvents.notifyCollectionChanged();
    if (!mounted) return;

    // Recargar cantidad real desde DB para actualizar _fromFolder y _maxQty
    final realQtyAfter = await _getRealQtyInOrigin();
    if (!mounted) return;

    setState(() {
      _moving = false;
      _feedback = 'x$qtyToMove movida${qtyToMove > 1 ? 's' : ''} a ${_toFolder!.name} [OK]';
      // Actualizar cantidad local para que _maxQty refleje el estado real
      _fromFolder = FolderCardSummary(
        folder: _fromFolder!.folder,
        quantity: realQtyAfter,
      );
      // Resetear _qty si supera lo que queda
      _qty = realQtyAfter > 0 ? 1 : 1;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: _folderPicker(
                label: 'Desde',
                selected: _fromFolder?.folder,
                options: widget.folderSummary.map((e) => e.folder).toList(),
                onPick: (f) {
                  final summary = widget.folderSummary
                      .firstWhere((s) => s.folder.id == f.id);
                  setState(() {
            _fromFolder = summary;
            if (_qty > summary.quantity) _qty = summary.quantity;
          });
                },
              ),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 8),
              child: Icon(Icons.arrow_forward, size: 20),
            ),
            Expanded(
              child: _folderPicker(
                label: 'Hacia',
                selected: _toFolder,
                options: widget.allFolders,
                onPick: (f) => setState(() => _toFolder = f),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            children: [
              const Text('Cantidad a mover',
                  style: TextStyle(fontWeight: FontWeight.w700)),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.remove_circle_outline),
                onPressed: _qty > 1 ? () => setState(() => _qty--) : null,
              ),
              SizedBox(
                width: 40,
                child: Center(
                  child: Text('$_qty',
                      style: const TextStyle(
                          fontSize: 18, fontWeight: FontWeight.bold)),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.add_circle_outline),
                onPressed: _qty < _maxQty ? () => setState(() => _qty++) : null,
              ),
              Text('/ $_maxQty',
                  style: const TextStyle(fontSize: 12, color: Colors.grey)),
            ],
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: _moving ? null : _move,
            icon: _moving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.swap_horiz),
            label: Text('Mover x$_qty'),
          ),
        ),
        if (_feedback != null) ...[
          const SizedBox(height: 8),
          Text(
            _feedback!,
            style: TextStyle(
              color: _feedback!.contains('[OK]')
                  ? Colors.green.shade700
                  : Colors.orange.shade700,
              fontWeight: FontWeight.w600,
              fontSize: 13,
            ),
          ),
        ],
      ],
    );
  }

  Widget _folderPicker({
    required String label,
    required Folder? selected,
    required List<Folder> options,
    required void Function(Folder) onPick,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () async {
        final pick = await showDialog<Folder>(
          context: context,
          builder: (ctx) => SimpleDialog(
            title: Text(label),
            children: options
                .map(
                  (f) => SimpleDialogOption(
                    onPressed: () => Navigator.pop(ctx, f),
                    child: Row(children: [
                      const Icon(Icons.folder_outlined, size: 18),
                      const SizedBox(width: 8),
                      Expanded(child: Text(f.name)),
                    ]),
                  ),
                )
                .toList(),
          ),
        );
        if (pick != null) onPick(pick);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: const TextStyle(
                    fontSize: 10, color: Colors.grey)),
            const SizedBox(height: 2),
            Row(
              children: [
                const Icon(Icons.folder_outlined, size: 14),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    selected?.name ?? '—',
                    style: const TextStyle(
                        fontSize: 12, fontWeight: FontWeight.w600),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const Icon(Icons.arrow_drop_down, size: 16),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Widgets auxiliares ───────────────────────────────────────────────────────

class InfoChip extends StatelessWidget {
  const InfoChip({super.key, required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text('$label: $value'),
    );
  }
}

class TypeBadge extends StatelessWidget {
  const TypeBadge({super.key, required this.type});
  final String type;

  Color get _color {
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
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: _color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        type,
        style: TextStyle(
            fontSize: 10, color: _color, fontWeight: FontWeight.w600),
      ),
    );
  }
}

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
          items: items
              .map(
                (item) => DropdownMenuItem(
                  value: item,
                  child: Text(item, style: const TextStyle(fontSize: 12)),
                ),
              )
              .toList(),
          onChanged: onChanged,
        ),
      ),
    );
  }
}