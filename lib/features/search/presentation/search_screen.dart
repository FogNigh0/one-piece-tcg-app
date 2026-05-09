// lib/features/search/presentation/search_screen.dart
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import '../../../app/app.dart';
import '../../../core/database/card_database.dart';
import '../../../core/services/card_api_service.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});
  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _ctrl = TextEditingController();
  List<CardData> _results = [];
  bool _searching = false;
  String? _error;
  bool _showFilters = false;

  // Filtros
  String? _filterType;   // Leader, Character, Event, Stage
  String? _filterColor;  // Red, Blue, Green, Yellow, Purple, Black
  String? _filterSet;    // OP01, OP02 ...

  static const _baseUrl = 'http://192.168.1.114:8000';

  static const _types  = ['Leader', 'Character', 'Event', 'Stage'];
  static const _colors = ['Red', 'Blue', 'Green', 'Yellow', 'Purple', 'Black'];
  static const _sets   = [
    'OP01','OP02','OP03','OP04','OP05','OP06','OP07',
    'OP08','OP09','OP10','OP11','OP12','OP13','OP14',
    'ST01','ST02','ST03','ST04','ST05','ST06','ST07',
    'ST08','ST09','ST10','ST13','ST14','ST15','ST19','ST20','ST21',
    'EB01','EB02',
  ];

  int get _activeFilters =>
      (_filterType != null ? 1 : 0) +
      (_filterColor != null ? 1 : 0) +
      (_filterSet != null ? 1 : 0);

  Future<void> _search() async {
    final q = _ctrl.text.trim();
    FocusScope.of(context).unfocus();
    setState(() { _searching = true; _error = null; _results = []; });
    try {
      final params = <String, String>{};
      if (q.isNotEmpty) params['q'] = q;
      if (_filterType  != null) params['card_type'] = _filterType!;
      if (_filterColor != null) params['color']     = _filterColor!;
      if (_filterSet   != null) params['set_code']  = _filterSet!;

      final uri = Uri.parse('$_baseUrl/cards/').replace(queryParameters: params);
      final res = await http.get(uri).timeout(const Duration(seconds: 10));
      if (res.statusCode != 200) throw Exception('Error ${res.statusCode}');
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      final list = (body['results'] as List? ?? [])
          .cast<Map<String, dynamic>>()
          .map(CardData.fromJson)
          .toList();
      if (mounted) setState(() => _results = list);
      if (list.isEmpty && mounted) {
        setState(() => _error = 'No se encontraron resultados');
      }
    } catch (_) {
      if (mounted) setState(() => _error = 'No se pudo conectar al servidor.');
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  void _clearFilters() => setState(() {
    _filterType = null; _filterColor = null; _filterSet = null;
  });

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBlack,
      appBar: AppBar(
        title: const Text('Buscar cartas'),
        actions: [
          if (_activeFilters > 0)
            TextButton(
              onPressed: _clearFilters,
              child: const Text('Limpiar', style: TextStyle(color: kGold, fontSize: 12)),
            ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: kBorder),
        ),
      ),
      body: Column(children: [
        // ── Barra de búsqueda ──────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
          child: Row(children: [
            Expanded(
              child: TextField(
                controller: _ctrl,
                onSubmitted: (_) => _search(),
                textInputAction: TextInputAction.search,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  hintText: 'Nombre o ID (ej: Luffy, OP01-003)',
                  prefixIcon: Icon(Icons.search),
                ),
              ),
            ),
            const SizedBox(width: 8),
            // Botón filtros
            GestureDetector(
              onTap: () => setState(() => _showFilters = !_showFilters),
              child: Container(
                padding: const EdgeInsets.all(13),
                decoration: BoxDecoration(
                  color: _activeFilters > 0 ? kGold.withOpacity(0.15) : kSurface2,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: _activeFilters > 0 ? kGold.withOpacity(0.6) : kBorder),
                ),
                child: Stack(alignment: Alignment.topRight, children: [
                  Icon(Icons.tune, color: _activeFilters > 0 ? kGold : const Color(0xFF666666), size: 20),
                  if (_activeFilters > 0)
                    Container(
                      width: 8, height: 8,
                      decoration: const BoxDecoration(color: kGold, shape: BoxShape.circle),
                    ),
                ]),
              ),
            ),
            const SizedBox(width: 8),
            ElevatedButton(
              onPressed: _searching ? null : _search,
              child: _searching
                  ? const SizedBox(width: 18, height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: kBlack))
                  : const Text('Buscar'),
            ),
          ]),
        ),

        // ── Panel de filtros ───────────────────────────────────────────
        if (_showFilters)
          Container(
            margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: kSurface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: kBorder),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              // Tipo
              const Text('Tipo', style: TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              Wrap(spacing: 6, children: _types.map((t) => _FilterChip(
                label: t,
                selected: _filterType == t,
                onTap: () => setState(() => _filterType = _filterType == t ? null : t),
              )).toList()),
              const SizedBox(height: 10),
              // Color
              const Text('Color', style: TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              Wrap(spacing: 6, children: _colors.map((c) => _FilterChip(
                label: c,
                selected: _filterColor == c,
                color: _colorForLabel(c),
                onTap: () => setState(() => _filterColor = _filterColor == c ? null : c),
              )).toList()),
              const SizedBox(height: 10),
              // Set
              const Text('Set', style: TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              SizedBox(
                height: 32,
                child: ListView(scrollDirection: Axis.horizontal, children: _sets.map((s) => Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: _FilterChip(
                    label: s,
                    selected: _filterSet == s,
                    onTap: () => setState(() => _filterSet = _filterSet == s ? null : s),
                  ),
                )).toList()),
              ),
            ]),
          ),

        // ── Error ──────────────────────────────────────────────────────
        if (_error != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF2A1010),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFF5A1010)),
              ),
              child: Text(_error!, style: const TextStyle(color: Color(0xFFEF9A9A), fontSize: 13)),
            ),
          ),

        // ── Resultados ─────────────────────────────────────────────────
        Expanded(
          child: _results.isEmpty && !_searching
              ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: const [
                  Icon(Icons.style_outlined, size: 64, color: Color(0xFF2A2A2A)),
                  SizedBox(height: 16),
                  Text('Busca por nombre, ID o usa los filtros',
                      style: TextStyle(color: Color(0xFF555555), fontSize: 14)),
                ]))
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                  itemCount: _results.length,
                  itemBuilder: (_, i) => _CardResultTile(card: _results[i]),
                ),
        ),
      ]),
    );
  }

  Color? _colorForLabel(String c) {
    switch (c) {
      case 'Red':    return Colors.red;
      case 'Blue':   return Colors.blue;
      case 'Green':  return Colors.green;
      case 'Yellow': return Colors.yellow;
      case 'Purple': return Colors.purple;
      case 'Black':  return Colors.grey;
      default: return null;
    }
  }
}

// ── Chip de filtro ─────────────────────────────────────────────────────────
class _FilterChip extends StatelessWidget {
  const _FilterChip({required this.label, required this.selected,
      required this.onTap, this.color});
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          margin: const EdgeInsets.only(bottom: 4),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: selected ? kGold.withOpacity(0.15) : kSurface2,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: selected ? kGold : kBorder,
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            if (color != null) ...[
              Container(width: 8, height: 8,
                  decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
              const SizedBox(width: 5),
            ],
            Text(label, style: TextStyle(
              color: selected ? kGold : Colors.white70,
              fontSize: 12,
              fontWeight: selected ? FontWeight.w700 : FontWeight.normal,
            )),
          ]),
        ),
      );
}

// ── Tile de resultado ──────────────────────────────────────────────────────
class _CardResultTile extends StatefulWidget {
  const _CardResultTile({required this.card});
  final CardData card;
  @override
  State<_CardResultTile> createState() => _CardResultTileState();
}

class _CardResultTileState extends State<_CardResultTile> {
  bool _saving = false;
  bool _saved  = false;
  int  _qty    = 1;
  Folder? _selectedFolder;
  List<Folder> _folders = [];
  bool _foldersLoaded = false;

  @override
  void initState() {
    super.initState();
    _loadFolders();
  }

  Future<void> _loadFolders() async {
    final folders = await CardDatabase.instance.getAllFolders();
    if (mounted) setState(() { _folders = folders; _foldersLoaded = true; });
  }

  Future<void> _pickFolder() async {
    final result = await showDialog<Object>(
      context: context,
      builder: (ctx) => SimpleDialog(
        backgroundColor: kSurface,
        title: const Text('Agregar a carpeta', style: TextStyle(color: Colors.white)),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, 'col'),
            child: Row(children: const [
              Icon(Icons.collections_bookmark_outlined, color: kGold),
              SizedBox(width: 10),
              Text('Colección (por defecto)', style: TextStyle(color: Colors.white70)),
            ]),
          ),
          if (_folders.isNotEmpty) const Divider(color: kBorder, height: 1),
          ..._folders.map((f) => SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, f),
            child: Row(children: [
              const Icon(Icons.folder_outlined, color: Color(0xFF888888)),
              const SizedBox(width: 10),
              Expanded(child: Text(f.name, style: const TextStyle(color: Colors.white))),
            ]),
          )),
        ],
      ),
    );
    if (result == 'col') setState(() => _selectedFolder = null);
    else if (result is Folder) setState(() => _selectedFolder = result);
  }

  Future<void> _addToCollection() async {
    setState(() => _saving = true);
    try {
      String imagePath = '';
      if (widget.card.imageUrl != null && widget.card.imageUrl!.isNotEmpty) {
        try {
          final imgRes = await http.get(Uri.parse(widget.card.imageUrl!))
              .timeout(const Duration(seconds: 15));
          if (imgRes.statusCode == 200) {
            final dir      = await getApplicationDocumentsDirectory();
            final cardsDir = Directory(p.join(dir.path, 'cards'));
            if (!await cardsDir.exists()) await cardsDir.create(recursive: true);
            final file = File(p.join(cardsDir.path,
                'card_${DateTime.now().microsecondsSinceEpoch}.png'));
            await file.writeAsBytes(imgRes.bodyBytes);
            imagePath = file.path;
          }
        } catch (_) {}
      }

      final scanned = ScannedCard(
        name:           widget.card.cleanName,
        cardClass:      widget.card.cardType,
        faction:        widget.card.faction ?? '',
        setCode:        widget.card.id,
        ability:        widget.card.effect ?? '',
        trigger:        widget.card.trigger ?? '',
        localImagePath: imagePath,
        serverImageUrl: widget.card.imageUrl,
      );

      final allCards = await CardDatabase.instance.getAllCards();
      ScannedCard? existing;
      for (final c in allCards) {
        if (c.setCode == widget.card.id) { existing = c; break; }
      }
      final int cardDbId = existing != null
          ? existing.id!
          : (await CardDatabase.instance.insertCard(scanned)).id!;

      final targetId = _selectedFolder?.id ?? CardDatabase.collectionFolderId;
      if (targetId != null) {
        await CardDatabase.instance.addCardToFolder(
            folderId: targetId, cardId: cardDbId, quantity: _qty);
      }

      AppEvents.notifyCollectionChanged();
      if (mounted) setState(() { _saving = false; _saved = true; });
    } catch (_) {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final card = widget.card;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: kSurface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: kBorder),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          // Imagen
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: card.imageUrl != null && card.imageUrl!.isNotEmpty
                ? Image.network(card.imageUrl!, width: 56, height: 72, fit: BoxFit.cover,
                    loadingBuilder: (_, child, prog) => prog == null ? child : _ImgPlaceholder(),
                    errorBuilder: (_, __, ___) => _ImgPlaceholder())
                : _ImgPlaceholder(),
          ),
          const SizedBox(width: 12),
          // Info
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(card.cleanName, style: const TextStyle(
                color: Colors.white, fontWeight: FontWeight.w700, fontSize: 14),
                maxLines: 2, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 4),
            Text(card.id, style: const TextStyle(
                color: kGold, fontSize: 11, fontWeight: FontWeight.w600)),
            const SizedBox(height: 2),
            Text('${card.cardType}  •  ${card.rarityLabel}',
                style: const TextStyle(color: Color(0xFF888888), fontSize: 11)),
            if (card.color.isNotEmpty)
              Text(card.color, style: const TextStyle(
                  color: Color(0xFF666666), fontSize: 10)),
          ])),
          // Controles
          if (!_saved)
            Column(mainAxisSize: MainAxisSize.min, children: [
              Row(mainAxisSize: MainAxisSize.min, children: [
                GestureDetector(
                  onTap: _qty > 1 ? () => setState(() => _qty--) : null,
                  child: Icon(Icons.remove_circle_outline,
                      color: _qty > 1 ? kGold : const Color(0xFF333333), size: 22)),
                Padding(padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: Text('$_qty', style: const TextStyle(
                      color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16))),
                GestureDetector(
                  onTap: () => setState(() => _qty++),
                  child: const Icon(Icons.add_circle_outline, color: kGold, size: 22)),
              ]),
            ])
          else
            const Icon(Icons.check_circle, color: Colors.green, size: 28),
        ]),

        // Carpeta + botón
        if (!_saved) ...[
          const SizedBox(height: 10),
          Row(children: [
            // Selector de carpeta
            Expanded(
              child: GestureDetector(
                onTap: _foldersLoaded ? _pickFolder : null,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: kSurface2,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: kBorder),
                  ),
                  child: Row(children: [
                    Icon(_selectedFolder == null
                        ? Icons.collections_bookmark_outlined
                        : Icons.folder_outlined,
                        color: kGold, size: 16),
                    const SizedBox(width: 6),
                    Expanded(child: Text(
                      _selectedFolder?.name ?? 'Colección',
                      style: const TextStyle(color: Colors.white70, fontSize: 12),
                      maxLines: 1, overflow: TextOverflow.ellipsis)),
                    const Icon(Icons.arrow_drop_down, color: Color(0xFF666666), size: 18),
                  ]),
                ),
              ),
            ),
            const SizedBox(width: 8),
            // Botón agregar
            _saving
                ? const SizedBox(width: 24, height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2, color: kGold))
                : GestureDetector(
                    onTap: _addToCollection,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        color: kGold,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Text('+ Agregar',
                          style: TextStyle(color: kBlack, fontSize: 12,
                              fontWeight: FontWeight.w800)),
                    ),
                  ),
          ]),
        ],
      ]),
    );
  }
}

class _ImgPlaceholder extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(
      width: 56, height: 72, color: kSurface2,
      child: const Center(child: Icon(Icons.image_not_supported_outlined,
          color: Color(0xFF333333), size: 20)));
}