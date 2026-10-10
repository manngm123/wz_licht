// main.dart – Wohnzimmer Licht (Govee LAN, ohne Server)

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'home_page.dart';
import 'theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);

  runApp(const WohnzimmerApp());
}

class WohnzimmerApp extends StatelessWidget {
  const WohnzimmerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Wohnzimmer',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      home: const HomePage(),
    );
  }
}
