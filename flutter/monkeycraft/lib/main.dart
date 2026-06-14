import 'package:flutter/material.dart';
import 'package:monkeycraft_client/auth/login_screen.dart';
import 'package:monkeycraft_client/shared/app_settings.dart';
import 'package:monkeycraft_client/audio/openaudiomc_service.dart';
import 'package:monkeycraft_client/audio/mcparks_v1_service.dart';
import 'package:monkeycraft_client/shared/keyboard_prewarmer.dart';
import 'package:monkeycraft_client/notifications/timed_notification_service.dart';
import 'package:monkeycraft_client/notifications/banner_style_nudge.dart';

final AppSettings appSettings = AppSettings();
final OpenAudioMcService openAudioMcService = OpenAudioMcService();
final McParksV1Service mcParksV1Service = McParksV1Service();
final TimedNotificationService notificationService = TimedNotificationService();
final BannerStyleNudge bannerStyleNudge = BannerStyleNudge(
  service: notificationService,
  settings: appSettings,
);

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
          debugShowCheckedModeBanner: false,
          theme: ThemeData(
            fontFamily: appSettings.font.familyName,
            colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
            useMaterial3: true,
          ),
          home: KeyboardPrewarmerWidget(
            child: BannerStyleNudgeGate(
              nudge: bannerStyleNudge,
              child: const LoginScreen(),
            ),
          ),
        );
      },
    );
  }
}
