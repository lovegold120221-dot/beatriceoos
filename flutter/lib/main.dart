import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:provider/provider.dart';
import 'app.dart';
import 'core/theme.dart';
import 'data/repositories/auth_repository.dart';
import 'data/repositories/settings_repository.dart';
import 'data/services/audio_service.dart';
import 'data/services/firebase_service.dart';
import 'data/services/gemini_service.dart';
import 'data/services/device_control_service.dart';
import 'data/services/mobile_use_ai_service.dart';
import 'data/services/mobile_use_action_handler.dart';
import 'domain/use_cases/auth_use_case.dart';
import 'domain/use_cases/settings_use_case.dart';
import 'ui/viewmodels/auth_viewmodel.dart';
import 'ui/viewmodels/settings_viewmodel.dart';
import 'ui/viewmodels/chat_viewmodel.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  await MobileUseAiService.instance.init();
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
          update: (context, authRepo, _) => AuthUseCase(authRepo),
        ),
        ProxyProvider<AuthUseCase, AuthViewModel>(
          update: (context, authUseCase, _) => AuthViewModel(authUseCase),
        ),
        Provider<SettingsRepository>(
          create: (_) => SettingsRepository(),
        ),
        ProxyProvider<SettingsRepository, SettingsUseCase>(
          update: (context, settingsRepo, _) => SettingsUseCase(settingsRepo),
        ),
        ProxyProvider<SettingsUseCase, SettingsViewModel>(
          update: (context, settingsUseCase, _) => SettingsViewModel(settingsUseCase),
        ),
        Provider<DeviceControlService>(
          create: (_) => DeviceControlService(),
        ),
        Provider<MobileUseAiService>(
          create: (_) => MobileUseAiService.instance,
        ),
        ProxyProvider<DeviceControlService, MobileUseActionHandler>(
          update: (context, deviceControl, _) =>
              MobileUseActionHandler(deviceControl),
        ),
        Provider<GeminiService>(
          create: (_) => GeminiService(),
        ),
        Provider<AudioService>(
          create: (_) => AudioService(),
        ),
        ProxyProvider3<AuthViewModel, SettingsViewModel, GeminiService, ChatViewModel>(
          update: (context, auth, settings, gemini, _) => ChatViewModel(auth, settings, gemini),
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
        onGenerateRoute: AppRouter.onGenerateRoute,
      ),
    );
  }
}