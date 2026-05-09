import 'package:flutter/material.dart';
import '../../../core/services/auth_service.dart';
import 'dart:async';
import '../../../app/app.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, required this.onLoginSuccess});
  final VoidCallback onLoginSuccess;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _auth = AuthService();

  bool _isLogin = true; // alterna entre Login y Registro
  bool _loading = false;
  bool _obscure = true;
  String? _error;

  // username solo para registro
  final _usernameCtrl = TextEditingController();

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    _usernameCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      if (_isLogin) {
        await _auth.login(
          emailOrUsername: _emailCtrl.text.trim(),
          password: _passwordCtrl.text,
        );
      } else {
        await _auth.register(
          username: _usernameCtrl.text.trim(),
          email: _emailCtrl.text.trim(),
          password: _passwordCtrl.text,
        );
      }
      // Llamamos el callback después del frame actual
      final cb = widget.onLoginSuccess;
      Future.delayed(Duration.zero, cb);
      return;
    } on AuthException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } on TimeoutException {
      if (mounted) setState(() => _error = 'Tiempo de espera agotado. Intenta de nuevo.');
    } catch (e) {
      if (mounted) setState(() => _error = 'Error de conexión. ¿El servidor está activo?');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1A1A2E),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 40),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Logo
                  const Icon(Icons.style, size: 72, color: Color(0xFFE94560)),
                  const SizedBox(height: 12),
                  const Text(
                    'One Piece TCG',
                    style: TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _isLogin ? 'Inicia sesión' : 'Crear cuenta',
                    style: const TextStyle(color: Colors.white54, fontSize: 15),
                  ),
                  const SizedBox(height: 36),

                  // Campo username (solo registro)
                  if (!_isLogin) ...[
                    _buildField(
                      controller: _usernameCtrl,
                      label: 'Usuario',
                      icon: Icons.person_outline,
                      validator: (v) => (v == null || v.trim().isEmpty)
                          ? 'Ingresa un usuario'
                          : null,
                    ),
                    const SizedBox(height: 16),
                  ],

                  // Email
                  _buildField(
                    controller: _emailCtrl,
                    label: 'Email o usuario',
                    icon: Icons.email_outlined,
                    keyboard: TextInputType.emailAddress,
                    validator: (v) => (v == null || v.trim().isEmpty)
                        ? 'Ingresa tu email'
                        : null,
                  ),
                  const SizedBox(height: 16),

                  // Contraseña
                  _buildField(
                    controller: _passwordCtrl,
                    label: 'Contraseña',
                    icon: Icons.lock_outline,
                    obscure: _obscure,
                    suffix: IconButton(
                      icon: Icon(
                        _obscure ? Icons.visibility_off : Icons.visibility,
                        color: Colors.white38,
                      ),
                      onPressed: () => setState(() => _obscure = !_obscure),
                    ),
                    validator: (v) => (v == null || v.length < 6)
                        ? 'Mínimo 6 caracteres'
                        : null,
                  ),
                  const SizedBox(height: 24),

                  // Error
                  if (_error != null) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFE94560).withOpacity(0.15),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: const Color(0xFFE94560).withOpacity(0.4),
                        ),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.error_outline,
                            color: Color(0xFFE94560),
                            size: 18,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _error!,
                              style: const TextStyle(
                                color: Color(0xFFE94560),
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],

                  // Botón principal
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton(
                      onPressed: _loading ? null : _submit,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFE94560),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: _loading
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : Text(
                              _isLogin ? 'Iniciar sesión' : 'Crear cuenta',
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Alternar login / registro
                  GestureDetector(
                    onTap: () => setState(() {
                      _isLogin = !_isLogin;
                      _error = null;
                    }),
                    child: RichText(
                      text: TextSpan(
                        style: const TextStyle(
                          color: Colors.white54,
                          fontSize: 14,
                        ),
                        children: [
                          TextSpan(
                            text: _isLogin
                                ? '¿No tienes cuenta? '
                                : '¿Ya tienes cuenta? ',
                          ),
                          TextSpan(
                            text: _isLogin ? 'Regístrate' : 'Inicia sesión',
                            style: const TextStyle(
                              color: Color(0xFFE94560),
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    TextInputType keyboard = TextInputType.text,
    bool obscure = false,
    Widget? suffix,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      obscureText: obscure,
      keyboardType: keyboard,
      style: const TextStyle(color: Colors.white),
      validator: validator,
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Colors.white54),
        prefixIcon: Icon(icon, color: Colors.white38),
        suffixIcon: suffix,
        filled: true,
        fillColor: const Color(0xFF16213E),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFE94560), width: 1.5),
        ),
        errorStyle: const TextStyle(color: Color(0xFFE94560)),
      ),
    );
  }
}