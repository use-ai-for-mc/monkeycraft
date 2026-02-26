import 'package:flutter/material.dart';
import 'package:monkeycraft_client/screens/login_screen.dart';
import 'package:monkeycraft_client/services/app_settings.dart';

final AppSettings appSettings = AppSettings();

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
          home: const LoginScreen(),
        );
      },
    );
  }
}
