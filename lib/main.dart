import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'src/app_controller.dart';
import 'src/l10n/app_strings.dart';
import 'src/models.dart';
import 'src/pages/gameplay_page.dart';
import 'src/pages/library_page.dart';
import 'src/pages/settings_page.dart';
import 'src/pages/start_page.dart';
import 'src/services/backend_api.dart';
import 'src/services/backend_runtime.dart';
import 'src/services/config_store.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  final store = await ConfigStore.open(legacyPrefs: prefs);
  final controller = AppController(
    store: store,
    api: await createBackendApi(store: store),
    runtime: createBackendRuntime(),
  );

  runApp(WhatIfApp(controller: controller));
  controller.initialize();
}

class WhatIfApp extends StatefulWidget {
  const WhatIfApp({super.key, required this.controller});

  final AppController controller;

  @override
  State<WhatIfApp> createState() => _WhatIfAppState();
}

class _WhatIfAppState extends State<WhatIfApp> {
  @override
  void dispose() {
    widget.controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        final strings = AppStrings(widget.controller.locale);

        return MaterialApp(
          title: strings.text('app.name'),
          debugShowCheckedModeBanner: false,
          theme: _buildTheme(),
          home: _RootShell(controller: widget.controller, strings: strings),
        );
      },
    );
  }

  ThemeData _buildTheme() {
    final base = ThemeData.dark(useMaterial3: true);
    final colorScheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFFD6922F),
      brightness: Brightness.dark,
    ).copyWith(surface: const Color(0xFF10182A));

    return base.copyWith(
      colorScheme: colorScheme,
      scaffoldBackgroundColor: Colors.transparent,
      textTheme: GoogleFonts.ibmPlexSansTextTheme(base.textTheme),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xFF111A2D),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Color(0xFF2A354C)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Color(0xFF2A354C)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Color(0xFFD6922F)),
        ),
      ),
    );
  }
}

class _RootShell extends StatelessWidget {
  const _RootShell({required this.controller, required this.strings});

  final AppController controller;
  final AppStrings strings;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF09111F), Color(0xFF07101B), Color(0xFF02050B)],
          ),
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            const _BackgroundAtmosphere(),
            SafeArea(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 280),
                switchInCurve: Curves.easeOutCubic,
                switchOutCurve: Curves.easeInCubic,
                child: controller.initializing
                    ? _LoadingScreen(strings: strings)
                    : _buildPage(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPage() {
    switch (controller.page) {
      case AppPage.start:
        return StartPage(
          key: const ValueKey('start'),
          controller: controller,
          strings: strings,
        );
      case AppPage.library:
        return LibraryPage(
          key: const ValueKey('library'),
          controller: controller,
          strings: strings,
        );
      case AppPage.settings:
        return SettingsPage(
          key: const ValueKey('settings'),
          controller: controller,
          strings: strings,
        );
      case AppPage.gameplay:
        return GameplayPage(
          key: ValueKey(
            'gameplay-${controller.resumeState?.turn ?? 0}-${controller.resumeState?.eventId ?? 'new'}',
          ),
          controller: controller,
          strings: strings,
        );
    }
  }
}

class _LoadingScreen extends StatelessWidget {
  const _LoadingScreen({required this.strings});

  final AppStrings strings;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Card(
          color: const Color(0xCC0E1727),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(28),
            side: const BorderSide(color: Color(0x22D6922F)),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  strings.text('app.name'),
                  style: GoogleFonts.cinzel(
                    fontSize: 30,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 3,
                  ),
                ),
                const SizedBox(height: 20),
                const CircularProgressIndicator(),
                const SizedBox(height: 18),
                Text(
                  strings.text('app.loading'),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                Text(
                  strings.text('app.loadingHint'),
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: const Color(0xFF9AACC9),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _BackgroundAtmosphere extends StatelessWidget {
  const _BackgroundAtmosphere();

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned(
          top: -120,
          left: -40,
          child: _glow(280, const Color(0x3359A4FF)),
        ),
        Positioned(
          top: 120,
          right: -60,
          child: _glow(240, const Color(0x33D6922F)),
        ),
        Positioned(
          bottom: -80,
          left: 80,
          child: _glow(220, const Color(0x2237B28C)),
        ),
      ],
    );
  }

  Widget _glow(double size, Color color) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [color, color.withValues(alpha: 0.2), Colors.transparent],
          ),
        ),
      ),
    );
  }
}
