import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:provider/provider.dart';
import 'app.dart';
import 'core/theme.dart';
import 'data/repositories/auth_repository.dart';
import 'data/repositories/settings_repository.dart';
import 'data/services/audio_service.dart';
import 'data/services/firebase_service.dart';
import 'data/services/gemini_service.dart';
import 'domain/use_cases/auth_use_case.dart';
import 'domain/use_cases/settings_use_case.dart';
import 'ui/viewmodels/auth_viewmodel.dart';
import 'ui/viewmodels/settings_viewmodel.dart';
import 'ui/viewmodels/chat_viewmodel.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);
  runApp(const BeatriceApp());
}

class BeatriceApp extends StatelessWidget {
  const BeatriceApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        Provider<FirebaseService>(
          create: (_) => FirebaseService(),
        ),
        Provider<AuthRepository>(
          create: (_) => AuthRepository(),
        ),
        ProxyProvider<AuthRepository, AuthUseCase>(
          create: (context) => AuthUseCase(context.read<AuthRepository>()),
        ),
        ProxyProvider<AuthUseCase, AuthViewModel>(
          create: (context) => AuthViewModel(context.read<AuthUseCase>()),
        ),
        Provider<SettingsRepository>(
          create: (_) => SettingsRepository(),
        ),
        ProxyProvider<SettingsRepository, SettingsUseCase>(
          create: (context) => SettingsUseCase(context.read<SettingsRepository>()),
        ),
        ProxyProvider<SettingsUseCase, SettingsViewModel>(
          create: (context) => SettingsViewModel(context.read<SettingsUseCase>()),
        ),
        Provider<GeminiService>(
          create: (_) => GeminiService(),
        ),
        Provider<AudioService>(
          create: (_) => AudioService(),
        ),
        ProxyProvider3<AuthViewModel, SettingsViewModel, GeminiService, ChatViewModel>(
          create: (context) => ChatViewModel(
            context.read<AuthViewModel>(),
            context.read<SettingsViewModel>(),
            context.read<GeminiService>(),
          ),
        ),
      ],
      child: MaterialApp(
        title: 'Beatrice',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        darkTheme: AppTheme.dark,
        themeMode: ThemeMode.dark,
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: const [Locale('en', 'US')],
        routerConfig: AppRouter.router,
      ),
    );
  }
}