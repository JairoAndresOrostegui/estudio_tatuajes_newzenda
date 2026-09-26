import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'theme.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});
  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final email = TextEditingController(), password = TextEditingController();
  final form = GlobalKey<FormState>();
  bool busy = false, hidden = true;
  String? error;
  @override
  void dispose() {
    email.dispose();
    password.dispose();
    super.dispose();
  }

  Future<void> run(Future<void> Function() fn) async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await fn();
    } on FirebaseAuthException catch (e) {
      if (mounted) {
        setState(
          () => error = switch (e.code) {
            'invalid-credential' ||
            'wrong-password' ||
            'user-not-found' => 'Revisa el correo y la contraseña.',
            'too-many-requests' => 'Demasiados intentos. Espera unos minutos.',
            'network-request-failed' => 'Revisa tu conexión a internet.',
            'popup-closed-by-user' =>
              'Se cerró la ventana de Google. Puedes intentarlo de nuevo.',
            _ => e.message ?? 'No fue posible iniciar sesión.',
          },
        );
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => error = 'No fue posible iniciar sesión. Inténtalo de nuevo.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  void signIn() {
    if (form.currentState!.validate()) {
      run(() async {
        await FirebaseAuth.instance.signInWithEmailAndPassword(
          email: email.text.trim(),
          password: password.text,
        );
      });
    }
  }

  Future<void> google() async {
    if (kIsWeb) {
      await FirebaseAuth.instance.signInWithPopup(GoogleAuthProvider());
    } else {
      await GoogleSignIn.instance.initialize(
        serverClientId: const String.fromEnvironment('googleWebClientId'),
        clientId: defaultTargetPlatform == TargetPlatform.iOS
            ? const String.fromEnvironment('iosClientId')
            : null,
      );
      final user = await GoogleSignIn.instance.authenticate();
      await FirebaseAuth.instance.signInWithCredential(
        GoogleAuthProvider.credential(idToken: user.authentication.idToken),
      );
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: LayoutBuilder(
      builder: (context, c) {
        final wide = c.maxWidth > 900;
        final login = Center(
          child: SingleChildScrollView(
            padding: EdgeInsets.all(wide ? 64 : 28),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Form(
                key: form,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Brand(),
                    const SizedBox(height: 52),
                    const Text(
                      'Tu estudio,\nen equilibrio.',
                      style: TextStyle(
                        fontSize: 38,
                        fontWeight: FontWeight.w700,
                        height: 1.12,
                        letterSpacing: -1.5,
                      ),
                    ),
                    const SizedBox(height: 18),
                    const Text(
                      'Inicia sesión para gestionar el día a día de Findink House.',
                      style: TextStyle(color: Color(0xff68756c), fontSize: 16),
                    ),
                    const SizedBox(height: 32),
                    TextFormField(
                      controller: email,
                      keyboardType: TextInputType.emailAddress,
                      autofillHints: const [AutofillHints.username],
                      decoration: const InputDecoration(
                        labelText: 'Correo electrónico',
                        prefixIcon: Icon(Icons.alternate_email),
                      ),
                      validator: (s) => s != null && s.contains('@')
                          ? null
                          : 'Escribe tu correo',
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: password,
                      obscureText: hidden,
                      autofillHints: const [AutofillHints.password],
                      onFieldSubmitted: (_) {
                        if (!busy) signIn();
                      },
                      decoration: InputDecoration(
                        labelText: 'Contraseña',
                        prefixIcon: const Icon(Icons.lock_outline),
                        suffixIcon: IconButton(
                          tooltip: hidden
                              ? 'Mostrar contraseña'
                              : 'Ocultar contraseña',
                          onPressed: () => setState(() => hidden = !hidden),
                          icon: Icon(
                            hidden
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined,
                          ),
                        ),
                      ),
                      validator: (s) => s != null && s.isNotEmpty
                          ? null
                          : 'Escribe tu contraseña',
                    ),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: busy
                            ? null
                            : () => run(() async {
                                if (!email.text.contains('@')) {
                                  setState(
                                    () => error = 'Escribe primero tu correo.',
                                  );
                                  return;
                                }
                                await FirebaseAuth.instance
                                    .sendPasswordResetEmail(
                                      email: email.text.trim(),
                                    );
                                if (mounted) {
                                  setState(
                                    () => error =
                                        'Si la cuenta existe, recibirás las instrucciones para restablecer tu contraseña.',
                                  );
                                }
                              }),
                        child: const Text('¿Olvidaste tu contraseña?'),
                      ),
                    ),
                    if (error != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 16),
                        child: Text(
                          error!,
                          style: const TextStyle(color: Color(0xff9e432e)),
                        ),
                      ),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: busy ? null : signIn,
                        child: busy
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Text('Entrar al estudio'),
                      ),
                    ),
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 20),
                      child: Row(
                        children: [
                          Expanded(child: Divider()),
                          Padding(
                            padding: EdgeInsets.symmetric(horizontal: 16),
                            child: Text('o continúa con'),
                          ),
                          Expanded(child: Divider()),
                        ],
                      ),
                    ),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: busy ? null : () => run(google),
                        icon: const Icon(Icons.g_mobiledata, size: 28),
                        label: const Text('Google'),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.all(16),
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    const Text(
                      'Acceso administrado · Solicita tu alta al dueño del estudio.',
                      style: TextStyle(fontSize: 12, color: Color(0xff68756c)),
                    ),
                    const SizedBox(height: 24),
                    const Chip(
                      label: Text('QA · Datos ficticios'),
                      avatar: Icon(Icons.science_outlined, size: 16),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
        return Row(
          children: [
            Expanded(child: login),
            if (wide)
              Expanded(
                child: Container(
                  margin: const EdgeInsets.all(20),
                  padding: const EdgeInsets.all(54),
                  decoration: BoxDecoration(
                    color: ink,
                    borderRadius: BorderRadius.circular(32),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'HECHO PARA CREAR',
                        style: TextStyle(
                          color: accent,
                          letterSpacing: 3,
                          fontSize: 12,
                        ),
                      ),
                      const Spacer(),
                      Center(
                        child: Container(
                          width: 230,
                          height: 230,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: accent.withValues(alpha: .3),
                            ),
                          ),
                          child: const Icon(
                            Icons.auto_awesome,
                            size: 130,
                            color: accent,
                          ),
                        ),
                      ),
                      const Spacer(),
                      const Text(
                        'Más espacio\npara tu arte.',
                        style: TextStyle(
                          fontSize: 48,
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                          height: 1.08,
                          letterSpacing: -2,
                        ),
                      ),
                      const SizedBox(height: 24),
                      const Text(
                        'Agenda, equipo y finanzas.\nTodo conectado en un mismo lugar.',
                        style: TextStyle(
                          color: Color(0xffb7c6bb),
                          fontSize: 17,
                          height: 1.6,
                        ),
                      ),
                      const SizedBox(height: 42),
                      const Divider(color: Color(0xff476052)),
                      const SizedBox(height: 18),
                      const Text(
                        'FINDINK HOUSE   /   GESTIÓN DEL ESTUDIO',
                        style: TextStyle(
                          color: accent,
                          fontSize: 11,
                          letterSpacing: 1.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        );
      },
    ),
  );
}
