import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:audio_service/audio_service.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'providers/settings_provider.dart';
import 'providers/customization_provider.dart';
import 'routes/app_routes.dart';
import 'themes/app_theme.dart';
import 'services/storage/storage_service.dart';
import 'services/audio/audio_handler.dart';
import 'services/version/version_service.dart';

import 'services/voice/voice_assistant_service.dart';
import 'services/quick_actions/quick_actions_service.dart';

final audioHandlerProvider = Provider<AudioHandler>((ref) => throw UnimplementedError());

AudioHandler? _audioHandlerInstance;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      statusBarBrightness: Brightness.dark,
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarDividerColor: Colors.transparent,
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );

  try {
    await dotenv.load(fileName: ".env");
  } catch (e) {
    debugPrint('Could not load .env file: $e');
  }
  await StorageService.init();
  await AppVersionService.init();
  
  _audioHandlerInstance ??= await initAudioHandler();

  final container = ProviderContainer(
    overrides: [
      audioHandlerProvider.overrideWithValue(_audioHandlerInstance!),
    ],
  );

  await VoiceAssistantService.instance.init(container);
  await QuickActionsService.instance.init(container);
  
  runApp(
    UncontrolledProviderScope(
      container: container,
      child: const MyApp(),
    ),
  );
}

class MyApp extends ConsumerWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeProvider);
    final customBranding = ref.watch(customizationProvider);

    final isDark = themeMode == ThemeMode.dark ||
        (themeMode == ThemeMode.system &&
            WidgetsBinding.instance.platformDispatcher.platformBrightness == Brightness.dark);

    final overlayStyle = SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
      statusBarBrightness: isDark ? Brightness.dark : Brightness.light,
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarDividerColor: Colors.transparent,
      systemNavigationBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
    );

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: overlayStyle,
      child: MaterialApp.router(
        title: customBranding.appName,
        debugShowCheckedModeBanner: false,
        themeMode: themeMode,
        theme: AppTheme.buildLightTheme(customBranding.accentColor),
        darkTheme: AppTheme.buildDarkTheme(customBranding.accentColor),
        routerConfig: appRouter,
      ),
    );
  }
}
