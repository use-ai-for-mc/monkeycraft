import 'package:flutter/material.dart';
import 'package:monkeycraft_client/auth/login_screen.dart';
import 'package:monkeycraft_client/shared/app_settings.dart';
import 'package:monkeycraft_client/audio/openaudiomc_service.dart';
import 'package:monkeycraft_client/shared/keyboard_prewarmer.dart';

final AppSettings appSettings = AppSettings();
final OpenAudioMcService openAudioMcService = OpenAudioMcService();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await appSettings.load();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: appSettings,
      builder: (context, child) {
        return MaterialApp(
          title: 'MonkeyCraft',
          theme: ThemeData(
            fontFamily: appSettings.font.familyName,
            colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
            useMaterial3: true,
          ),
          home: const KeyboardPrewarmerWidget(child: LoginScreen()),
        );
      },
    );
  }
}
