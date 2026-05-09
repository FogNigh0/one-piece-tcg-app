import 'package:flutter/material.dart';
import '../../../app/app.dart';
import '../../../core/services/auth_service.dart';
import '../../../core/database/card_database.dart';
import '../../auth/presentation/login_screen.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});
  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _auth = AuthService();
  Map<String, dynamic>? _user;
  int _totalCards = 0, _totalFolders = 0;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final user    = await _auth.getCachedUser();
    final cards   = await CardDatabase.instance.getAllCards();
    final folders = await CardDatabase.instance.getAllFolders();
    if (!mounted) return;
    setState(() {
      _user         = user;
      _totalCards   = cards.length;
      _totalFolders = folders.length;
      _loading      = false;
    });
  }

  Future<void> _logout() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: kSurface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Cerrar sesión',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
        content: const Text('¿Estás seguro que quieres cerrar sesión?',
            style: TextStyle(color: Colors.white70)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red.shade700,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
            ),
            child: const Text('Cerrar sesión'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    await _auth.logout();
    // Cierra la BD del usuario actual
    await CardDatabase.closeForLogout();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const AuthGate()),
      (_) => false,
    );
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
                    Icon(Icons.person, color: kGold, size: 24),
                    SizedBox(width: 8),
                    Text('Mi Perfil', style: TextStyle(
                        color: kGold, fontSize: 20, fontWeight: FontWeight.w800)),
                  ]),
                  bottom: PreferredSize(
                    preferredSize: const Size.fromHeight(1),
                    child: Container(height: 1, color: kBorder),
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 24, 16, 32),
                  sliver: SliverList(
                    delegate: SliverChildListDelegate([

                      // Avatar + nombre
                      Center(
                        child: Column(children: [
                          Container(
                            width: 80, height: 80,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: kSurface,
                              border: Border.all(color: kGold, width: 2),
                            ),
                            child: Center(
                              child: Text(
                                (_user?['username'] ?? '?')[0].toUpperCase(),
                                style: const TextStyle(
                                    color: kGold, fontSize: 32,
                                    fontWeight: FontWeight.w800),
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          Text(_user?['username'] ?? '',
                              style: const TextStyle(
                                  color: Colors.white, fontSize: 20,
                                  fontWeight: FontWeight.w700)),
                          const SizedBox(height: 4),
                          Text(_user?['email'] ?? '',
                              style: const TextStyle(
                                  color: Colors.white54, fontSize: 13)),
                        ]),
                      ),
                      const SizedBox(height: 28),

                      // Stats
                      const _SectionLabel('Estadísticas'),
                      const SizedBox(height: 12),
                      Row(children: [
                        Expanded(child: _StatTile(
                          icon: Icons.style_outlined,
                          label: 'Cartas escaneadas',
                          value: '$_totalCards',
                        )),
                        const SizedBox(width: 10),
                        Expanded(child: _StatTile(
                          icon: Icons.folder_outlined,
                          label: 'Carpetas',
                          value: '$_totalFolders',
                        )),
                      ]),
                      const SizedBox(height: 28),

                      // Cuenta
                      const _SectionLabel('Cuenta'),
                      const SizedBox(height: 12),
                      _MenuItem(
                        icon: Icons.info_outline,
                        label: 'Miembro desde',
                        trailing: Text(
                          _formatDate(_user?['created_at']),
                          style: const TextStyle(
                              color: Colors.white54, fontSize: 13),
                        ),
                      ),
                      const SizedBox(height: 28),

                      // Cerrar sesión
                      SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: OutlinedButton.icon(
                          onPressed: _logout,
                          icon: const Icon(Icons.logout, color: Colors.red),
                          label: const Text('Cerrar sesión',
                              style: TextStyle(
                                  color: Colors.red,
                                  fontWeight: FontWeight.w600)),
                          style: OutlinedButton.styleFrom(
                            side: BorderSide(
                                color: Colors.red.shade700, width: 1.5),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12)),
                          ),
                        ),
                      ),
                    ]),
                  ),
                ),
              ],
            ),
    );
  }

  String _formatDate(dynamic raw) {
    if (raw == null) return '—';
    try {
      final dt = DateTime.parse(raw.toString());
      return '${dt.day}/${dt.month}/${dt.year}';
    } catch (_) {
      return '—';
    }
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Text(text,
      style: const TextStyle(
          color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700));
}

class _StatTile extends StatelessWidget {
  const _StatTile(
      {required this.icon, required this.label, required this.value});
  final IconData icon;
  final String label, value;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: kSurface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: kBorder),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, color: kGold, size: 20),
          const SizedBox(height: 8),
          Text(value,
              style: const TextStyle(
                  color: kGold, fontSize: 22, fontWeight: FontWeight.w800)),
          const SizedBox(height: 2),
          Text(label,
              style: const TextStyle(color: Colors.white54, fontSize: 11),
              maxLines: 1, overflow: TextOverflow.ellipsis),
        ]),
      );
}

class _MenuItem extends StatelessWidget {
  const _MenuItem({required this.icon, required this.label, this.trailing});
  final IconData icon;
  final String label;
  final Widget? trailing;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: kSurface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: kBorder),
        ),
        child: Row(children: [
          Icon(icon, color: Colors.white38, size: 20),
          const SizedBox(width: 12),
          Expanded(child: Text(label,
              style: const TextStyle(color: Colors.white70, fontSize: 14))),
          if (trailing != null) trailing!,
        ]),
      );
}

// Reinicia la app shell después del login
class _AppRestart extends StatelessWidget {
  const _AppRestart();
  @override
  Widget build(BuildContext context) => const AppShell();
}