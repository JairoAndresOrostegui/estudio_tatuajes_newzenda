import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'data/api.dart';
import 'ui/theme.dart';
import 'ui/login.dart';
import 'ui/shell.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('es_CO');
  Object? error;
  try {
    final appId = kIsWeb
        ? const String.fromEnvironment('appId')
        : defaultTargetPlatform == TargetPlatform.iOS
        ? const String.fromEnvironment('iosAppId')
        : const String.fromEnvironment('androidAppId');
    if (appId.isEmpty) {
      throw StateError(
        'Inicia con --dart-define-from-file=config/firebase.qa.json',
      );
    }
    await Firebase.initializeApp(
      options: FirebaseOptions(
        apiKey: kIsWeb
            ? const String.fromEnvironment('apiKey')
            : defaultTargetPlatform == TargetPlatform.iOS
            ? const String.fromEnvironment('iosApiKey')
            : const String.fromEnvironment('androidApiKey'),
        appId: appId,
        messagingSenderId: const String.fromEnvironment('messagingSenderId'),
        projectId: const String.fromEnvironment('projectId'),
        authDomain: const String.fromEnvironment('authDomain'),
        storageBucket: const String.fromEnvironment('storageBucket'),
        iosBundleId: const String.fromEnvironment('iosBundleId'),
      ),
    );
    if (const bool.fromEnvironment('EMULATORS')) {
      const host = String.fromEnvironment(
        'EMULATOR_HOST',
        defaultValue: '127.0.0.1',
      );
      await FirebaseAuth.instance.useAuthEmulator(host, 9099);
      FirebaseFunctions.instanceFor(
        region: 'us-central1',
      ).useFunctionsEmulator(host, 5001);
    }
  } catch (e) {
    error = e;
  }
  runApp(FindinkApp(startupError: error));
}

class FindinkApp extends StatelessWidget {
  final Object? startupError;
  const FindinkApp({super.key, this.startupError});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Findink House · QA',
    debugShowCheckedModeBanner: false,
    theme: appTheme(),
    locale: const Locale('es', 'CO'),
    supportedLocales: const [Locale('es', 'CO')],
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    home: startupError != null
        ? Scaffold(
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Text(
                  'No se pudo iniciar Findink House.\n${readableError(startupError!)}',
                ),
              ),
            ),
          )
        : const SessionGate(),
  );
}

class SessionGate extends StatefulWidget {
  const SessionGate({super.key});
  @override
  State<SessionGate> createState() => _SessionGateState();
}

class _SessionGateState extends State<SessionGate> {
  final api = Api();
  @override
  Widget build(BuildContext context) => StreamBuilder<User?>(
    stream: FirebaseAuth.instance.authStateChanges(),
    builder: (context, snapshot) {
      if (snapshot.connectionState == ConnectionState.waiting) {
        return const Scaffold(body: Center(child: CircularProgressIndicator()));
      }
      if (snapshot.data == null) return const LoginPage();
      return FutureBuilder<Json>(
        future: api.session(),
        builder: (context, session) {
          if (session.hasError) {
            return Scaffold(
              body: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 480),
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Brand(),
                        const SizedBox(height: 32),
                        const Text(
                          'Tu acceso al estudio',
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          readableError(session.error!),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 24),
                        FilledButton(
                          onPressed: () async {
                            await FirebaseAuth.instance.currentUser?.reload();
                            await FirebaseAuth.instance.currentUser?.getIdToken(
                              true,
                            );
                            if (mounted) setState(() {});
                          },
                          child: const Text('Volver a comprobar'),
                        ),
                        TextButton(
                          onPressed: () => FirebaseAuth.instance.signOut(),
                          child: const Text('Cerrar sesión'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          }
          if (!session.hasData) {
            return const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            );
          }
          return AppShell(api: api, member: session.data!);
        },
      );
    },
  );
}
