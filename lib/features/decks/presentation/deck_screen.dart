// lib/features/decks/presentation/deck_screen.dart
//
// Pantalla de gestión de mazos:
//   - Lista de mazos guardados
//   - Importar mazo desde texto (3xOP05-082 1xOP11-097...)
//   - Ver detalle de un mazo con cartas resueltas desde el servidor
//   - Exportar mazo al portapapeles
//   - Agregar carta escaneada al mazo actual

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/services/card_api_service.dart';
import '../../../core/services/deck_service.dart';
import '../../../core/widgets/card_image_widget.dart';

// ── Pantalla principal de mazos ───────────────────────────────────────────────

class DeckScreen extends StatefulWidget {
  const DeckScreen({super.key});

  @override
  State<DeckScreen> createState() => _DeckScreenState();
}

class _DeckScreenState extends State<DeckScreen> {
  late Future<List<Deck>> _decksFuture;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    setState(() => _decksFuture = DeckService.instance.getAllDecks());
  }

  Future<void> _showImportDialog() async {
    final result = await showDialog<Deck>(
      context: context,
      builder: (_) => const _ImportDeckDialog(),
    );
    if (result != null) {
      await DeckService.instance.saveDeck(result);
      _reload();
    }
  }

  Future<void> _deleteDeck(Deck deck) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar mazo'),
        content: Text('¿Eliminar "${deck.name}"?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Eliminar')),
        ],
      ),
    );
    if (ok == true && deck.id != null) {
      await DeckService.instance.deleteDeck(deck.id!);
      _reload();
    }
  }

  void _openDeck(Deck deck) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => DeckDetailScreen(deck: deck)),
    ).then((_) => _reload());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Mis Mazos'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _reload),
        ],
      ),
      body: FutureBuilder<List<Deck>>(
        future: _decksFuture,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final decks = snap.data ?? [];
          if (decks.isEmpty) {
            return Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.style_outlined, size: 64, color: Colors.grey),
                const SizedBox(height: 16),
                const Text('No tienes mazos guardados.',
                    style: TextStyle(color: Colors.grey)),
                const SizedBox(height: 20),
                FilledButton.icon(
                  onPressed: _showImportDialog,
                  icon: const Icon(Icons.add),
                  label: const Text('Importar mazo'),
                ),
              ]),
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: decks.length,
            itemBuilder: (_, i) => _DeckTile(
              deck: decks[i],
              onTap: () => _openDeck(decks[i]),
              onDelete: () => _deleteDeck(decks[i]),
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showImportDialog,
        icon: const Icon(Icons.add),
        label: const Text('Importar mazo'),
      ),
    );
  }
}

// ── Tile de mazo en la lista ──────────────────────────────────────────────────

class _DeckTile extends StatelessWidget {
  const _DeckTile({
    required this.deck,
    required this.onTap,
    required this.onDelete,
  });
  final Deck deck;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        leading: CircleAvatar(
          backgroundColor: Theme.of(context).colorScheme.primaryContainer,
          child: Text(
            '${deck.totalCards}',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onPrimaryContainer,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        title: Text(deck.name,
            style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${deck.entries.length} tipos · ${deck.totalCards} cartas'),
            Text(
              'Sets: ${deck.sets.join(', ')}',
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

// ── Diálogo importar mazo ─────────────────────────────────────────────────────

class _ImportDeckDialog extends StatefulWidget {
  const _ImportDeckDialog();

  @override
  State<_ImportDeckDialog> createState() => _ImportDeckDialogState();
}

class _ImportDeckDialogState extends State<_ImportDeckDialog> {
  final _nameCtrl = TextEditingController();
  final _textCtrl = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _textCtrl.dispose();
    super.dispose();
  }

  void _import() {
    final name = _nameCtrl.text.trim();
    final text = _textCtrl.text.trim();

    if (name.isEmpty) {
      setState(() => _error = 'Ponle un nombre al mazo');
      return;
    }
    if (!DeckParser.isValid(text)) {
      setState(() => _error = 'No se encontraron cartas válidas.\nEjemplo: 3xOP05-082 1xOP11-097');
      return;
    }

    final entries = DeckParser.merge(DeckParser.parse(text));
    final deck = Deck(name: name, entries: entries);
    Navigator.pop(context, deck);
  }

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (data?.text != null) {
      _textCtrl.text = data!.text!;
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Importar mazo'),
      content: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
            controller: _nameCtrl,
            decoration: const InputDecoration(
              labelText: 'Nombre del mazo',
              hintText: 'Ej: Mazo Luffy Gear 5',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _textCtrl,
            maxLines: 6,
            decoration: InputDecoration(
              labelText: 'Lista de cartas',
              hintText: '3xOP05-082\n1xOP11-097\n4xOP14-079',
              alignLabelWithHint: true,
              suffixIcon: IconButton(
                icon: const Icon(Icons.paste),
                tooltip: 'Pegar del portapapeles',
                onPressed: _paste,
              ),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!, style: const TextStyle(color: Colors.red, fontSize: 12)),
          ],
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(onPressed: _import, child: const Text('Importar')),
      ],
    );
  }
}

// ── Pantalla de detalle de un mazo ────────────────────────────────────────────

class DeckDetailScreen extends StatefulWidget {
  const DeckDetailScreen({super.key, required this.deck});
  final Deck deck;

  @override
  State<DeckDetailScreen> createState() => _DeckDetailScreenState();
}

class _DeckDetailScreenState extends State<DeckDetailScreen> {
  final _api = CardApiService();
  late Deck _deck;

  // Mapa cardId → datos del servidor
  final Map<String, CardData> _cardCache = {};
  bool _isResolving = false;
  int _resolved = 0;

  @override
  void initState() {
    super.initState();
    _deck = widget.deck;
    _resolveCards();
  }

  /// Consulta el servidor para obtener datos de cada carta
  Future<void> _resolveCards() async {
    setState(() { _isResolving = true; _resolved = 0; });

    for (final entry in _deck.entries) {
      if (_cardCache.containsKey(entry.cardId)) continue;
      try {
        final result = await _api.lookupCard(entry.cardId);
        if (result != null && mounted) {
          setState(() {
            _cardCache[entry.cardId] = result.card;
            _resolved++;
          });
        }
      } catch (_) {}
    }

    if (mounted) setState(() => _isResolving = false);
  }

  Future<void> _export() async {
    final text = _deck.toExportText();
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('¡Copiado al portapapeles!'), duration: Duration(seconds: 2)),
    );
  }

  Future<void> _saveName(String newName) async {
    if (newName.trim().isEmpty) return;
    final updated = _deck.copyWith(name: newName.trim());
    await DeckService.instance.saveDeck(updated);
    setState(() => _deck = updated);
  }

  Future<void> _editName() async {
    final ctrl = TextEditingController(text: _deck.name);
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Renombrar mazo'),
        content: TextField(controller: ctrl, autofocus: true),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, ctrl.text), child: const Text('Guardar')),
        ],
      ),
    );
    if (result != null) await _saveName(result);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: GestureDetector(
          onTap: _editName,
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Text(_deck.name),
            const SizedBox(width: 6),
            const Icon(Icons.edit, size: 14, color: Colors.grey),
          ]),
        ),
        actions: [
          if (_isResolving)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Center(
                child: Text(
                  '$_resolved/${_deck.entries.length}',
                  style: const TextStyle(fontSize: 12),
                ),
              ),
            ),
          IconButton(
            icon: const Icon(Icons.copy),
            tooltip: 'Exportar al portapapeles',
            onPressed: _export,
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _resolveCards,
          ),
        ],
      ),
      body: Column(
        children: [
          // Barra de resumen
          _SummaryBar(deck: _deck, cardCache: _cardCache),

          // Lista de cartas
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: _deck.entries.length,
              itemBuilder: (_, i) {
                final entry = _deck.entries[i];
                final card  = _cardCache[entry.cardId];
                return _DeckCardTile(entry: entry, card: card);
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ── Barra de resumen del mazo ─────────────────────────────────────────────────

class _SummaryBar extends StatelessWidget {
  const _SummaryBar({required this.deck, required this.cardCache});
  final Deck deck;
  final Map<String, CardData> cardCache;

  @override
  Widget build(BuildContext context) {
    // Conteo por tipo de carta
    final typeCounts = <String, int>{};
    for (final entry in deck.entries) {
      final card = cardCache[entry.cardId];
      final type = card?.cardType ?? '?';
      typeCounts[type] = (typeCounts[type] ?? 0) + entry.quantity;
    }

    return Container(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          _StatBadge(label: 'Total', value: '${deck.totalCards}'),
          const SizedBox(width: 8),
          ...typeCounts.entries.map((e) =>
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: _StatBadge(label: e.key, value: '${e.value}'),
            ),
          ),
          const Spacer(),
          Text(
            '${deck.entries.length} tipos',
            style: const TextStyle(fontSize: 12, color: Colors.grey),
          ),
        ],
      ),
    );
  }
}

class _StatBadge extends StatelessWidget {
  const _StatBadge({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.primaryContainer,
      borderRadius: BorderRadius.circular(20),
    ),
    child: Text(
      '$label: $value',
      style: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.bold,
        color: Theme.of(context).colorScheme.onPrimaryContainer,
      ),
    ),
  );
}

// ── Tile de carta dentro del mazo ─────────────────────────────────────────────

class _DeckCardTile extends StatelessWidget {
  const _DeckCardTile({required this.entry, required this.card});
  final DeckEntry entry;
  final CardData? card;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        leading: card?.imageUrl != null
            ? CardThumbnail(imageUrl: card!.imageUrl)
            : _QuantityBadge(quantity: entry.quantity),
        title: Row(children: [
          if (card?.imageUrl != null) ...[
            _QuantityBadge(quantity: entry.quantity),
            const SizedBox(width: 8),
          ],
          Expanded(
            child: Text(
              card?.cleanName ?? entry.cardId,
              style: const TextStyle(fontWeight: FontWeight.bold),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ]),
        subtitle: card != null
            ? Row(children: [
                Text(entry.cardId,
                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500)),
                const SizedBox(width: 8),
                _TypeChip(type: card!.cardType),
                const SizedBox(width: 4),
                if (card!.color.isNotEmpty) _ColorDot(color: card!.color),
              ])
            : Text(entry.cardId,
                style: const TextStyle(fontSize: 12, color: Colors.grey)),
        onTap: card != null ? () => _showCardDetail(context, card!) : null,
      ),
    );
  }

  void _showCardDetail(BuildContext context, CardData card) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.7,
        builder: (_, ctrl) => SingleChildScrollView(
          controller: ctrl,
          padding: const EdgeInsets.all(20),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Center(child: Container(
              width: 36, height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            )),
            const SizedBox(height: 16),
            if (card.imageUrl != null)
              Center(child: CardImageWidget(
                imageUrl: card.imageUrl,
                height: 240,
                borderRadius: 12,
                showShadow: true,
              )),
            const SizedBox(height: 16),
            Text(card.cleanName,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text(card.id, style: const TextStyle(color: Colors.grey)),
            const Divider(height: 20),
            Wrap(spacing: 8, runSpacing: 8, children: [
              _DetailChip('Tipo', card.cardType),
              _DetailChip('Color', card.color),
              _DetailChip('Rareza', card.rarityLabel),
              if (card.cost    != null) _DetailChip('Costo',   '${card.cost}'),
              if (card.power   != null) _DetailChip('Poder',   '${card.power}'),
              if (card.counter != null) _DetailChip('Counter', '+${card.counter}'),
              if (card.attribute?.isNotEmpty == true) _DetailChip('Atributo', card.attribute!),
              if (card.faction?.isNotEmpty   == true) _DetailChip('Tipo 2', card.faction!),
            ]),
            if (card.effect?.isNotEmpty == true) ...[
              const SizedBox(height: 12),
              const Text('Efecto', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Text(card.effect!),
            ],
            if (card.trigger?.isNotEmpty == true) ...[
              const SizedBox(height: 8),
              const Text('Trigger', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Text(card.trigger!),
            ],
          ]),
        ),
      ),
    );
  }
}

Widget _DetailChip(String label, String value) => Builder(
  builder: (context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.secondaryContainer,
      borderRadius: BorderRadius.circular(8),
    ),
    child: RichText(text: TextSpan(
      style: DefaultTextStyle.of(context).style.copyWith(fontSize: 12),
      children: [
        TextSpan(text: '$label: ', style: const TextStyle(fontWeight: FontWeight.w600)),
        TextSpan(text: value),
      ],
    )),
  ),
);

class _QuantityBadge extends StatelessWidget {
  const _QuantityBadge({required this.quantity});
  final int quantity;

  @override
  Widget build(BuildContext context) => Container(
    width: 32, height: 32,
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.primary,
      borderRadius: BorderRadius.circular(8),
    ),
    child: Center(
      child: Text(
        'x$quantity',
        style: TextStyle(
          color: Theme.of(context).colorScheme.onPrimary,
          fontWeight: FontWeight.bold,
          fontSize: 13,
        ),
      ),
    ),
  );
}

class _TypeChip extends StatelessWidget {
  const _TypeChip({required this.type});
  final String type;

  Color _color(BuildContext context) {
    switch (type.toUpperCase()) {
      case 'LEADER':    return Colors.amber.shade700;
      case 'CHARACTER': return Colors.blue;
      case 'EVENT':     return Colors.purple;
      case 'STAGE':     return Colors.green;
      default:          return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    decoration: BoxDecoration(
      color: _color(context).withOpacity(0.15),
      borderRadius: BorderRadius.circular(4),
      border: Border.all(color: _color(context).withOpacity(0.4)),
    ),
    child: Text(type, style: TextStyle(fontSize: 10, color: _color(context), fontWeight: FontWeight.w600)),
  );
}

class _ColorDot extends StatelessWidget {
  const _ColorDot({required this.color});
  final String color;

  Color _dotColor() {
    final c = color.toLowerCase();
    if (c.contains('red'))    return Colors.red;
    if (c.contains('blue'))   return Colors.blue;
    if (c.contains('green'))  return Colors.green;
    if (c.contains('purple')) return Colors.purple;
    if (c.contains('black'))  return Colors.black87;
    if (c.contains('yellow')) return Colors.amber;
    return Colors.grey;
  }

  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
    Container(
      width: 10, height: 10,
      decoration: BoxDecoration(color: _dotColor(), shape: BoxShape.circle),
    ),
    const SizedBox(width: 3),
    Text(color, style: const TextStyle(fontSize: 11, color: Colors.grey)),
  ]);
}
