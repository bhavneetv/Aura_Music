import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:audio_service/audio_service.dart';
import 'providers/settings_provider.dart';
import 'providers/customization_provider.dart';
import 'routes/app_routes.dart';
import 'themes/app_theme.dart';
import 'services/storage/storage_service.dart';
import 'services/audio/audio_handler.dart';

final audioHandlerProvider = Provider<AudioHandler>((ref) => throw UnimplementedError());

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await StorageService.init();
  final audioHandler = await initAudioHandler();
  
  runApp(
    ProviderScope(
      overrides: [
        audioHandlerProvider.overrideWithValue(audioHandler),
      ],
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

    return MaterialApp.router(
      title: customBranding.appName,
      debugShowCheckedModeBanner: false,
      themeMode: themeMode,
      theme: AppTheme.buildLightTheme(customBranding.accentColor),
      darkTheme: AppTheme.buildDarkTheme(customBranding.accentColor),
      routerConfig: appRouter,
    );
  }
}
