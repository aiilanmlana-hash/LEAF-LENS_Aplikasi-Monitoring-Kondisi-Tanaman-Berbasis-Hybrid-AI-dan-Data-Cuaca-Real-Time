import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'firebase_options.dart';
import 'providers/monitoring_provider.dart';
import 'screens/auth_screen.dart';
import 'screens/dashboard_screen.dart';
import 'screens/history_screen.dart';
import 'screens/scan_screen.dart';
import 'theme/app_theme.dart';
import 'widgets/glass_surface.dart';
import 'widgets/plant_backdrop.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    runApp(const SmartPlantApp());
  } catch (error, stackTrace) {
    FlutterError.reportError(
      FlutterErrorDetails(
        exception: error,
        stack: stackTrace,
        library: 'Smart Plant AI startup',
      ),
    );
    runApp(_StartupFailureApp(error: error));
  }
}

class SmartPlantApp extends StatelessWidget {
  const SmartPlantApp({this.home, super.key});

  final Widget? home;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Smart Plant Monitoring & AI Detection',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: ThemeMode.light,
      home: home ?? const _AuthenticationGate(),
    );
  }
}

class _AuthenticationGate extends StatelessWidget {
  const _AuthenticationGate();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: AuthScreen.authStateChanges,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return _StartupFailurePage(error: snapshot.error!);
        }
        if (!snapshot.hasData) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        if (snapshot.data == null) return const AuthScreen();
        return ChangeNotifierProvider(
          key: ValueKey(snapshot.data!.uid),
          create: (_) => MonitoringProvider()..initialize(),
          child: const _ApplicationShell(),
        );
      },
    );
  }
}

class _ApplicationShell extends StatefulWidget {
  const _ApplicationShell();

  @override
  State<_ApplicationShell> createState() => _ApplicationShellState();
}

class _ApplicationShellState extends State<_ApplicationShell> {
  int _selectedIndex = 0;
  final _navigationLabels = const [
    'Ringkasan',
    'Analisis tanaman',
    'Riwayat monitoring',
  ];

  @override
  Widget build(BuildContext context) {
    final screens = [
      DashboardScreen(onScan: () => setState(() => _selectedIndex = 1)),
      ScanScreen(isActive: _selectedIndex == 1),
      const HistoryScreen(),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final desktop = constraints.maxWidth >= 900;
        final content = Column(
          children: [
            _TopBar(
              title: _navigationLabels[_selectedIndex],
              onSignOut: AuthScreen.signOut,
            ),
            Expanded(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1240),
                  child: IndexedStack(
                    index: _selectedIndex,
                    children: screens,
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
              child: GlassSurface(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                radius: 24,
                opacity: 0.62,
                shadow: false,
                child: Text(
                  'Smart Plant Monitoring',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: PlantColors.forest.withValues(alpha: 0.78),
                      ),
                ),
              ),
            ),
          ],
        );

        if (!desktop) {
          return Scaffold(
            backgroundColor: Colors.transparent,
            body: Stack(
              fit: StackFit.expand,
              children: [
                const PlantBackdrop(),
                content,
              ],
            ),
            bottomNavigationBar: NavigationBar(
              selectedIndex: _selectedIndex,
              onDestinationSelected: (index) =>
                  setState(() => _selectedIndex = index),
              destinations: const [
                NavigationDestination(
                  icon: Icon(Icons.space_dashboard_outlined),
                  selectedIcon: Icon(Icons.space_dashboard),
                  label: 'Ringkasan',
                ),
                NavigationDestination(
                  icon: Icon(Icons.center_focus_strong),
                  label: 'Analisis',
                ),
                NavigationDestination(
                  icon: Icon(Icons.history),
                  label: 'Riwayat',
                ),
              ],
            ),
          );
        }

        return Scaffold(
          backgroundColor: Colors.transparent,
          body: Stack(
            fit: StackFit.expand,
            children: [
              const PlantBackdrop(),
              Row(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 14, 0, 14),
                    child: GlassSurface(
                      radius: 24,
                      opacity: 0.76,
                      child: NavigationRail(
                        selectedIndex: _selectedIndex,
                        onDestinationSelected: (index) =>
                            setState(() => _selectedIndex = index),
                        labelType: NavigationRailLabelType.all,
                        leading: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 22),
                          child: Icon(
                            Icons.eco_outlined,
                            size: 30,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                        ),
                        destinations: const [
                          NavigationRailDestination(
                            icon: Icon(Icons.space_dashboard_outlined),
                            selectedIcon: Icon(Icons.space_dashboard),
                            label: Text('Ringkasan'),
                          ),
                          NavigationRailDestination(
                            icon: Icon(Icons.center_focus_strong),
                            label: Text('Analisis'),
                          ),
                          NavigationRailDestination(
                            icon: Icon(Icons.history),
                            label: Text('Riwayat'),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(child: content),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({required this.title, required this.onSignOut});

  final String title;
  final Future<void> Function() onSignOut;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
        child: GlassSurface(
          padding: const EdgeInsets.fromLTRB(14, 7, 8, 7),
          radius: 24,
          opacity: 0.78,
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: PlantColors.forest,
                  borderRadius: BorderRadius.circular(13),
                ),
                child: const Icon(
                  Icons.eco_rounded,
                  color: Colors.white,
                  size: 21,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                    Text(
                      'SMART PLANT MONITORING & AI',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: PlantColors.sage,
                            letterSpacing: 0.6,
                          ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Keluar',
                onPressed: onSignOut,
                icon: const Icon(Icons.logout_outlined),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StartupFailureApp extends StatelessWidget {
  const _StartupFailureApp({required this.error});

  final Object error;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      theme: AppTheme.light,
      home: _StartupFailurePage(error: error),
    );
  }
}

class _StartupFailurePage extends StatelessWidget {
  const _StartupFailurePage({required this.error});

  final Object error;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.cloud_off_outlined, size: 40),
                const SizedBox(height: 16),
                Text(
                  'Aplikasi gagal terhubung ke Firebase',
                  style: Theme.of(context).textTheme.titleLarge,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                SelectableText('$error', textAlign: TextAlign.center),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
