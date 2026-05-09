// lib/features/home/presentation/home_screen.dart
import 'dart:io';
import 'package:flutter/material.dart';
import '../../../app/app.dart';
import '../../../core/database/card_database.dart';
import '../../folders/presentation/folders_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _totalCards = 0, _totalUnique = 0, _totalFolders = 0;
  List<ScannedCard> _recentCards = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
    AppEvents.collectionVersion.addListener(_load);
  }

  @override
  void dispose() {
    AppEvents.collectionVersion.removeListener(_load);
    super.dispose();
  }

  Future<void> _load() async {
    final cards   = await CardDatabase.instance.getAllCards();
    final folders = await CardDatabase.instance.getAllFolders();
    if (!mounted) return;
    setState(() {
      _totalCards   = cards.fold(0, (sum, _) => sum + 1); // cuenta total de registros
      _totalUnique  = cards.map((c) => c.setCode).toSet().length;
      _totalFolders = folders.length;
      _recentCards  = cards.take(15).toList();
      _loading      = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBlack,
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: kGold))
          : CustomScrollView(
              slivers: [
                SliverAppBar(
                  backgroundColor: kBlack,
                  pinned: true,
                  elevation: 0,
                  title: Row(children: const [
                    Icon(Icons.album, color: kGold, size: 24),
                    SizedBox(width: 8),
                    Text('OP Card Scanner', style: TextStyle(
                      color: kGold, fontSize: 20, fontWeight: FontWeight.w800)),
                  ]),
                  bottom: PreferredSize(
                    preferredSize: const Size.fromHeight(1),
                    child: Container(height: 1, color: kBorder),
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
                  sliver: SliverList(
                    delegate: SliverChildListDelegate([
                      const _SectionTitle('Mi Colección'),
                      const SizedBox(height: 12),
                      Row(children: [
                        Expanded(child: _StatCard(
                          label: 'Cartas totales',
                          value: '$_totalCards',
                          icon: Icons.style_outlined,
                          onTap: () => AppEvents.navigateTo(3),
                        )),
                        const SizedBox(width: 10),
                        Expanded(child: _StatCard(
                          label: 'Únicas',
                          value: '$_totalUnique',
                          icon: Icons.filter_none_outlined,
                          onTap: () => AppEvents.navigateTo(3),
                        )),
                        const SizedBox(width: 10),
                        Expanded(child: _StatCard(
                          label: 'Carpetas',
                          value: '$_totalFolders',
                          icon: Icons.folder_outlined,
                          onTap: () => Navigator.push(context,
                            MaterialPageRoute(builder: (_) => const FoldersScreen())),
                        )),
                      ]),
                      const SizedBox(height: 28),
                      const _SectionTitle('Accesos rápidos'),
                      const SizedBox(height: 12),
                      GridView.count(
                        crossAxisCount: 2,
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        mainAxisSpacing: 10,
                        crossAxisSpacing: 10,
                        childAspectRatio: 2.3,
                        children: [
                          _ActionCard(Icons.document_scanner, 'Escanear carta',
                              () => AppEvents.navigateTo(2)),
                          _ActionCard(Icons.search, 'Buscar carta',
                              () => AppEvents.navigateTo(1)),
                          _ActionCard(Icons.collections_bookmark_outlined, 'Mi Colección',
                              () => AppEvents.navigateTo(3)),
                          _ActionCard(Icons.folder_outlined, 'Mis Carpetas', () =>
                              Navigator.push(context,
                                MaterialPageRoute(builder: (_) => const FoldersScreen()))),
                        ],
                      ),
                      if (_recentCards.isNotEmpty) ...[
                        const SizedBox(height: 28),
                        const _SectionTitle('Escaneadas recientemente'),
                        const SizedBox(height: 12),
                        SizedBox(
                          height: 175,
                          child: ListView.separated(
                            scrollDirection: Axis.horizontal,
                            itemCount: _recentCards.length,
                            separatorBuilder: (_, __) => const SizedBox(width: 10),
                            itemBuilder: (_, i) => _RecentCardItem(_recentCards[i]),
                          ),
                        ),
                      ],
                    ]),
                  ),
                ),
              ],
            ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Text(text,
      style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700));
}

class _StatCard extends StatelessWidget {
  const _StatCard({required this.label, required this.value,
      required this.icon, required this.onTap});
  final String label, value;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
          decoration: BoxDecoration(
            color: kSurface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: kBorder),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Icon(icon, color: kGold, size: 18),
              const Icon(Icons.chevron_right, color: Color(0xFF444444), size: 14),
            ]),
            const SizedBox(height: 8),
            Text(value, style: const TextStyle(
                color: kGold, fontSize: 20, fontWeight: FontWeight.w800)),
            const SizedBox(height: 2),
            Text(label, style: const TextStyle(
                color: Color(0xFF888888), fontSize: 10),
                maxLines: 1, overflow: TextOverflow.ellipsis),
          ]),
        ),
      );
}

class _ActionCard extends StatelessWidget {
  const _ActionCard(this.icon, this.label, this.onTap);
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: kSurface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: kBorder),
          ),
          child: Row(children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: kGold.withOpacity(0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, color: kGold, size: 18),
            ),
            const SizedBox(width: 10),
            Expanded(child: Text(label, style: const TextStyle(
                color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600))),
            const Icon(Icons.chevron_right, color: Color(0xFF444444), size: 16),
          ]),
        ),
      );
}

class _RecentCardItem extends StatelessWidget {
  const _RecentCardItem(this.card);
  final ScannedCard card;

  Widget _buildImage() {
    // Primero intenta imagen local, luego imagen del servidor
    final hasLocal = card.localImagePath.isNotEmpty;
    final hasServer = card.serverImageUrl != null && card.serverImageUrl!.isNotEmpty;

    if (hasLocal) {
      final file = File(card.localImagePath);
      return Image.file(file,
          height: 112, width: 110, fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => hasServer
              ? Image.network(card.serverImageUrl!,
                  height: 112, width: 110, fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => const _CardImgPlaceholder())
              : const _CardImgPlaceholder());
    }
    if (hasServer) {
      return Image.network(card.serverImageUrl!,
          height: 112, width: 110, fit: BoxFit.cover,
          loadingBuilder: (_, child, prog) =>
              prog == null ? child : const _CardImgPlaceholder(),
          errorBuilder: (_, __, ___) => const _CardImgPlaceholder());
    }
    return const _CardImgPlaceholder();
  }

  @override
  Widget build(BuildContext context) => Container(
        width: 110,
        decoration: BoxDecoration(
          color: kSurface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: kBorder),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(11)),
            child: _buildImage(),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(6, 5, 6, 2),
            child: Text(card.setCode, style: const TextStyle(
                color: kGold, fontSize: 9, fontWeight: FontWeight.w700),
                maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Text(card.name, style: const TextStyle(
                color: Colors.white70, fontSize: 10),
                maxLines: 2, overflow: TextOverflow.ellipsis),
          ),
        ]),
      );
}

class _CardImgPlaceholder extends StatelessWidget {
  const _CardImgPlaceholder();
  @override
  Widget build(BuildContext context) => Container(
      height: 112, width: 110, color: kSurface2,
      child: const Center(child: Icon(Icons.image_not_supported_outlined,
          color: Color(0xFF333333), size: 28)));
}