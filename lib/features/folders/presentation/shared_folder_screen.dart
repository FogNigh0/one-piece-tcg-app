// lib/features/folders/presentation/shared_folder_screen.dart
//
// Pantalla que muestra una carpeta pública compartida.
// No requiere login — accesible via deep link.

import 'package:flutter/material.dart';
import '../../../app/app.dart';
import '../../../core/services/card_api_service.dart';

class SharedFolderScreen extends StatefulWidget {
  const SharedFolderScreen({super.key, required this.shareToken});
  final String shareToken;

  @override
  State<SharedFolderScreen> createState() => _SharedFolderScreenState();
}

class _SharedFolderScreenState extends State<SharedFolderScreen> {
  final _api = CardApiService();
  Map<String, dynamic>? _folder;
  List<Map<String, dynamic>> _cards = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final result = await _api.getPublicFolder(widget.shareToken);
      if (!mounted) return;
      setState(() {
        _folder = result;
        _cards  = List<Map<String, dynamic>>.from(result['cards'] ?? []);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error   = 'No se pudo cargar la carpeta. Puede que no exista o no sea pública.';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBlack,
      appBar: AppBar(
        backgroundColor: kBlack,
        title: Text(
          _folder?['name'] ?? 'Carpeta compartida',
          style: const TextStyle(color: kGold, fontWeight: FontWeight.w800),
        ),
        iconTheme: const IconThemeData(color: kGold),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: kGold))
          : _error != null
              ? _errorView()
              : _contentView(),
    );
  }

  Widget _errorView() => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.folder_off_outlined, color: Colors.white38, size: 56),
        const SizedBox(height: 16),
        Text(_error!, textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white54, fontSize: 14)),
      ]),
    ),
  );

  Widget _contentView() {
    final owner      = _folder?['owner_username'] ?? '';
    final totalCards = _folder?['total_cards'] ?? 0;

    return Column(children: [
      // Header info
      Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: const BoxDecoration(
          color: kSurface,
          border: Border(bottom: BorderSide(color: kBorder)),
        ),
        child: Row(children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: kGold.withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: kGold.withOpacity(0.3)),
            ),
            child: const Icon(Icons.folder, color: kGold, size: 24),
          ),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(
              'De: $owner',
              style: const TextStyle(color: Colors.white70, fontSize: 13),
            ),
            const SizedBox(height: 2),
            Text(
              '$totalCards cartas · ${_cards.length} tipos',
              style: const TextStyle(color: Colors.white38, fontSize: 12),
            ),
          ])),
          // Badge pública
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.green.withOpacity(0.15),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: Colors.green.withOpacity(0.4)),
            ),
            child: const Text('Pública',
                style: TextStyle(color: Colors.green, fontSize: 11, fontWeight: FontWeight.w600)),
          ),
        ]),
      ),

      // Lista de cartas
      Expanded(
        child: _cards.isEmpty
            ? const Center(
                child: Text('Esta carpeta está vacía.',
                    style: TextStyle(color: Colors.white38)))
            : ListView.builder(
                padding: const EdgeInsets.all(12),
                itemCount: _cards.length,
                itemBuilder: (_, i) {
                  final item = _cards[i];
                  final code = item['card_set_code'] as String;
                  final qty  = item['quantity'] as int;
                  return _CardRow(code: code, quantity: qty, api: _api);
                },
              ),
      ),
    ]);
  }
}

// ── Fila de carta con datos del servidor ──────────────────────────────────────

class _CardRow extends StatefulWidget {
  const _CardRow({required this.code, required this.quantity, required this.api});
  final String code;
  final int quantity;
  final CardApiService api;

  @override
  State<_CardRow> createState() => _CardRowState();
}

class _CardRowState extends State<_CardRow> {
  CardData? _card;

  @override
  void initState() {
    super.initState();
    _fetchCard();
  }

  Future<void> _fetchCard() async {
    try {
      final result = await widget.api.lookupCard(widget.code);
      if (!mounted) return;
      setState(() => _card = result?.card);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: kSurface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: kBorder),
      ),
      child: Row(children: [
        // Cantidad badge
        Container(
          width: 36, height: 36,
          decoration: BoxDecoration(
            color: kGold.withOpacity(0.12),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: kGold.withOpacity(0.3)),
          ),
          child: Center(
            child: Text('x${widget.quantity}',
                style: const TextStyle(
                    color: kGold, fontWeight: FontWeight.w800, fontSize: 12)),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(
            _card?.cleanName ?? widget.code,
            style: const TextStyle(
                color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14),
            maxLines: 1, overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 2),
          Row(children: [
            Text(widget.code,
                style: const TextStyle(color: kGold, fontSize: 11, fontWeight: FontWeight.w500)),
            if (_card != null) ...[
              const SizedBox(width: 8),
              Text(_card!.cardType,
                  style: const TextStyle(color: Colors.white38, fontSize: 11)),
            ],
          ]),
        ])),
        if (_card == null)
          const SizedBox(
            width: 14, height: 14,
            child: CircularProgressIndicator(strokeWidth: 1.5, color: kGold),
          ),
      ]),
    );
  }
}