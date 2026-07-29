import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:provider/provider.dart';

import 'core/logger.dart';
import 'core/router.dart';
import 'core/theme.dart';
import 'core/network/api_client.dart';
import 'core/network/connectivity_controller.dart';
import 'data/repositories/auth_repository.dart';
import 'data/repositories/settings_repository.dart';
import 'data/services/audio_player_service.dart';
import 'data/services/audio_recorder_service.dart';
import 'data/services/audio_service.dart';
import 'data/services/firebase_service.dart';
import 'data/services/genai_live_client.dart';
import 'data/services/gemini_service.dart';
import 'data/services/device_control_service.dart';
import 'data/services/memory_service.dart';
import 'data/services/mobile_use_ai_service.dart';
import 'data/services/mobile_use_action_handler.dart';
import 'data/services/screen_automation_service.dart';
import 'domain/private_agent/orchestrator.dart';
import 'domain/use_cases/auth_use_case.dart';
import 'domain/use_cases/settings_use_case.dart';
import 'ui/viewmodels/auth_viewmodel.dart';
import 'ui/viewmodels/settings_viewmodel.dart';
import 'ui/viewmodels/chat_viewmodel.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  ErrorWidget.builder = (FlutterErrorDetails details) {
    const mode = kReleaseMode;
    return Material(
      color: const Color(0xFF121212),
      child: Center(
        child: Text(
          mode ? 'Something went wrong. Please restart the app.' : 'Error: ${details.exception}',
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.white70, fontSize: 14),
        ),
      ),
    );
  };

  try {
    await Firebase.initializeApp();
  } catch (e, s) {
    appLogger.w('Firebase init skipped', error: e, stackTrace: s);
  }
  try {
    await MobileUseAiService.instance.init();
  } catch (e, s) {
    appLogger.w('MobileUseAiService init skipped', error: e, stackTrace: s);
  }

  await SystemChrome.setPreferredOrientations([
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
        // ── Core infrastructure ───────────────────────────────────────
        ChangeNotifierProvider<ConnectivityController>(
          create: (_) => ConnectivityController(),
        ),
        ProxyProvider<ConnectivityController, ApiClient>(
          update: (context, connectivity, prev) {
            final api = prev ?? ApiClient();
            api.connectivity = connectivity;
            return api;
          },
        ),

        // ── Data services ─────────────────────────────────────────────
        Provider<FirebaseService>(create: (_) => FirebaseService()),
        Provider<AuthRepository>(create: (_) => AuthRepository()),
        ProxyProvider<AuthRepository, AuthUseCase>(
          update: (context, repo, _) => AuthUseCase(repo),
        ),
        Provider<SettingsRepository>(create: (_) => SettingsRepository()),
        ProxyProvider<SettingsRepository, SettingsUseCase>(
          update: (context, repo, _) => SettingsUseCase(repo),
        ),

        // DeviceControlService
        ProxyProvider<ApiClient, DeviceControlService>(
          update: (context, api, prev) => prev ?? DeviceControlService(api),
        ),
        ProxyProvider<ApiClient, MobileUseAiService>(
          update: (context, api, prev) {
            final svc = prev ?? MobileUseAiService.instance;
            svc.apiClient = api;
            return svc;
          },
        ),
        ProxyProvider<DeviceControlService, MobileUseActionHandler>(
          update: (context, deviceControl, _) =>
              MobileUseActionHandler(deviceControl),
        ),
        Provider<ScreenAutomationService>(
          create: (_) => ScreenAutomationService(),
        ),
        ProxyProvider3<DeviceControlService, MobileUseAiService,
            MobileUseActionHandler, MobileUseAgent>(
          update: (context, deviceControl, aiService, actionHandler, prev) =>
              prev ??
              MobileUseAgent(deviceControl, aiService, actionHandler),
        ),
        Provider<GeminiService>(create: (_) => GeminiService()),

        // ── New Live API and audio services ───────────────────────────
        Provider<GenAILiveClient>(create: (_) => GenAILiveClient()),
        ChangeNotifierProvider<AudioRecorderService>(
          create: (_) => AudioRecorderService(),
        ),
        ChangeNotifierProvider<AudioPlayerService>(
          create: (_) => AudioPlayerService(),
        ),
        Provider<MemoryService>(create: (_) => MemoryService()),
        Provider<AudioService>(create: (_) => AudioService()),

        // ── View models ───────────────────────────────────────────────
        ChangeNotifierProxyProvider<AuthUseCase, AuthViewModel>(
          create: (context) => AuthViewModel(context.read<AuthUseCase>()),
          update: (context, authUseCase, prev) => prev ?? AuthViewModel(authUseCase),
        ),
        ChangeNotifierProxyProvider<SettingsUseCase, SettingsViewModel>(
          create: (context) => SettingsViewModel(context.read<SettingsUseCase>()),
          update: (context, settingsUseCase, prev) =>
              prev ?? SettingsViewModel(settingsUseCase),
        ),
        // ChatViewModel uses Provider with create, reading deps from context
        ChangeNotifierProvider<ChatViewModel>(
          create: (context) => ChatViewModel(
            context.read<AuthViewModel>(),
            context.read<SettingsViewModel>(),
            context.read<MobileUseAgent>(),
            context.read<GenAILiveClient>(),
            context.read<AudioRecorderService>(),
            context.read<AudioPlayerService>(),
            context.read<MemoryService>(),
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
        onGenerateRoute: AppRouter.onGenerateRoute,
      ),
    );
  }
}
