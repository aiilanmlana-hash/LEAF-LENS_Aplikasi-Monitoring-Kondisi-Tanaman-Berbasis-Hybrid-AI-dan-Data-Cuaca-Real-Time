import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import 'firebase_options.dart';
import 'screens/auth_screen.dart';
import 'screens/dashboard_screen.dart';
import 'screens/history_screen.dart';
import 'screens/scan_screen.dart';
import 'services/monitoring_repository.dart';
import 'services/plant_api_service.dart';
import 'theme/app_theme.dart';
import 'widgets/glass_surface.dart';
import 'widgets/plant_backdrop.dart';
import 'widgets/soft_motion.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  Object? startupError;
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    if (kIsWeb) {
      try {
        await FirebaseAuth.instance.setPersistence(Persistence.LOCAL);
      } catch (error, stackTrace) {
        FlutterError.reportError(
          FlutterErrorDetails(
            exception: error,
            stack: stackTrace,
            library: 'LEAF LENS auth persistence',
          ),
        );
      }
    }
  } catch (error, stackTrace) {
    startupError = error;
    FlutterError.reportError(
      FlutterErrorDetails(
        exception: error,
        stack: stackTrace,
        library: 'LEAF LENS Firebase startup',
      ),
    );
  }
  runApp(SmartPlantWebApp(startupError: startupError));
}

class SmartPlantWebApp extends StatelessWidget {
  const SmartPlantWebApp({this.startupError, this.home, super.key});

  final Object? startupError;
  final Widget? home;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'LEAF LENS | Erytheia',
      debugShowCheckedModeBanner: false,
      theme: PlantTheme.light,
      builder: (context, child) => Stack(
        fit: StackFit.expand,
        children: [const PlantBackdrop(), ?child],
      ),
      home:
          home ??
          (startupError == null
              ? const _AuthenticationGate()
              : _StartupFailure(error: startupError!)),
    );
  }
}

class _AuthenticationGate extends StatelessWidget {
  const _AuthenticationGate();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.userChanges(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return _StartupFailure(error: snapshot.error!);
        }
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            backgroundColor: Colors.transparent,
            body: Center(child: CircularProgressIndicator()),
          );
        }
        final user = snapshot.data;
        if (user == null || !user.emailVerified) return const AuthScreen();
        return _ApplicationShell(key: ValueKey(user.uid));
      },
    );
  }
}

class _ApplicationShell extends StatefulWidget {
  const _ApplicationShell({super.key});

  @override
  State<_ApplicationShell> createState() => _ApplicationShellState();
}

class _ApplicationShellState extends State<_ApplicationShell> {
  final _repository = MonitoringRepository();
  final _api = PlantApiService();
  int _selectedIndex = 0;

  static const _titles = ['Overview', 'Analisis tanaman', 'Riwayat monitoring'];

  @override
  void dispose() {
    _api.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Do not mount every tab in an IndexedStack. Previously the scan tab
    // requested a camera as soon as the user logged in, even while hidden on
    // the dashboard. It also kept all Firestore streams and the camera alive
    // during navigation. Building only the active page releases those costs.
    final activePage = switch (_selectedIndex) {
      0 => DashboardScreen(
        repository: _repository,
        onScan: () => setState(() => _selectedIndex = 1),
      ),
      1 => ScanScreen(repository: _repository, api: _api),
      _ => HistoryScreen(repository: _repository),
    };

    return LayoutBuilder(
      builder: (context, constraints) {
        final desktop = constraints.maxWidth >= 1040;
        Future<void> signOut() => FirebaseAuth.instance.signOut();
        final page = Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1480),
            child: KeyedSubtree(
              key: ValueKey(_selectedIndex),
              child: activePage,
            ),
          ),
        );

        if (desktop) {
          return Scaffold(
            backgroundColor: Colors.transparent,
            body: SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Row(
                  children: [
                    SizedBox(
                      width: 252,
                      child: _GlassSidebar(
                        selectedIndex: _selectedIndex,
                        userEmail:
                            FirebaseAuth.instance.currentUser?.email ?? '',
                        onSelect: (index) =>
                            setState(() => _selectedIndex = index),
                        onSignOut: signOut,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        children: [
                          _Header(
                            title: _titles[_selectedIndex],
                            onSignOut: signOut,
                          ),
                          const SizedBox(height: 8),
                          Expanded(
                            child: _PageTransition(
                              index: _selectedIndex,
                              child: page,
                            ),
                          ),
                          const _ProjectFooter(),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }

        return Scaffold(
          backgroundColor: Colors.transparent,
          body: SafeArea(
            child: Column(
              children: [
                _Header(
                  title: _titles[_selectedIndex],
                  onSignOut: signOut,
                  compact: true,
                ),
                Expanded(
                  child: _PageTransition(index: _selectedIndex, child: page),
                ),
                const Padding(
                  padding: EdgeInsets.fromLTRB(14, 0, 14, 8),
                  child: _ProjectFooter(compact: true),
                ),
              ],
            ),
          ),
          bottomNavigationBar: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
              child: GlassSurface(
                radius: 22,
                opacity: 0.76,
                blur: 20,
                padding: const EdgeInsets.all(6),
                child: Row(
                  children: [
                    _BottomNavItem(
                      icon: Icons.space_dashboard_outlined,
                      selectedIcon: Icons.space_dashboard_rounded,
                      label: 'Ringkasan',
                      selected: _selectedIndex == 0,
                      onTap: () => setState(() => _selectedIndex = 0),
                    ),
                    _BottomNavItem(
                      icon: Icons.center_focus_strong,
                      selectedIcon: Icons.center_focus_strong,
                      label: 'Analisis',
                      selected: _selectedIndex == 1,
                      onTap: () => setState(() => _selectedIndex = 1),
                    ),
                    _BottomNavItem(
                      icon: Icons.history_outlined,
                      selectedIcon: Icons.history_rounded,
                      label: 'Riwayat',
                      selected: _selectedIndex == 2,
                      onTap: () => setState(() => _selectedIndex = 2),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _GlassSidebar extends StatelessWidget {
  const _GlassSidebar({
    required this.selectedIndex,
    required this.userEmail,
    required this.onSelect,
    required this.onSignOut,
  });

  final int selectedIndex;
  final String userEmail;
  final ValueChanged<int> onSelect;
  final Future<void> Function() onSignOut;

  static const _items = [
    (
      Icons.space_dashboard_outlined,
      Icons.space_dashboard_rounded,
      'Ringkasan',
    ),
    (Icons.center_focus_strong, Icons.center_focus_strong, 'Analisis daun'),
    (Icons.history_outlined, Icons.history_rounded, 'Riwayat'),
  ];

  @override
  Widget build(BuildContext context) {
    return GlassSurface(
      radius: 26,
      opacity: 0.72,
      blur: 24,
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: PlantPalette.forest,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(Icons.eco_rounded, color: Colors.white),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'LEAF LENS',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        color: PlantPalette.forest,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      'HYBRID AI · CUACA REAL-TIME',
                      maxLines: 1,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: PlantPalette.sage,
                        letterSpacing: 0,
                        fontSize: 9,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 30),
          Text(
            'WORKSPACE',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: PlantPalette.sage,
              fontWeight: FontWeight.w800,
              letterSpacing: 0,
            ),
          ),
          const SizedBox(height: 10),
          for (var index = 0; index < _items.length; index++)
            _SidebarItem(
              icon: _items[index].$1,
              selectedIcon: _items[index].$2,
              label: _items[index].$3,
              selected: selectedIndex == index,
              onTap: () => onSelect(index),
            ),
          const Spacer(),
          GlassSurface(
            radius: 17,
            padding: const EdgeInsets.all(11),
            opacity: 0.54,
            blur: 12,
            child: Row(
              children: [
                CircleAvatar(
                  radius: 17,
                  backgroundColor: PlantPalette.sage.withValues(alpha: 0.18),
                  child: const Icon(
                    Icons.person_outline_rounded,
                    color: PlantPalette.forest,
                    size: 19,
                  ),
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                    userEmail.isEmpty ? 'Akun aktif' : userEmail,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: PlantPalette.ink,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Keluar',
                  onPressed: onSignOut,
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(
                    Icons.logout_rounded,
                    size: 18,
                    color: PlantPalette.sage,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'LEAF LENS · Erytheia',
            textAlign: TextAlign.center,
            style: TextStyle(color: PlantPalette.sage, fontSize: 9),
          ),
        ],
      ),
    );
  }
}

class _SidebarItem extends StatelessWidget {
  const _SidebarItem({
    required this.icon,
    required this.selectedIcon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final IconData selectedIcon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(15),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOut,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            decoration: BoxDecoration(
              color: selected
                  ? Colors.white.withValues(alpha: 0.76)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(15),
              border: selected
                  ? Border.all(color: Colors.white.withValues(alpha: 0.9))
                  : null,
              boxShadow: selected
                  ? [
                      BoxShadow(
                        color: PlantPalette.forest.withValues(alpha: 0.06),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ]
                  : const [],
            ),
            child: Row(
              children: [
                Icon(
                  selected ? selectedIcon : icon,
                  size: 20,
                  color: selected ? PlantPalette.forest : PlantPalette.sage,
                ),
                const SizedBox(width: 11),
                Text(
                  label,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: selected ? PlantPalette.forest : PlantPalette.ink,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
                const Spacer(),
                if (selected)
                  Container(
                    width: 5,
                    height: 5,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: PlantPalette.olive,
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

class _BottomNavItem extends StatelessWidget {
  const _BottomNavItem({
    required this.icon,
    required this.selectedIcon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final IconData selectedIcon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOut,
            padding: const EdgeInsets.symmetric(vertical: 7),
            decoration: BoxDecoration(
              color: selected
                  ? Colors.white.withValues(alpha: 0.88)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(16),
              boxShadow: selected
                  ? [
                      BoxShadow(
                        color: PlantPalette.forest.withValues(alpha: 0.08),
                        blurRadius: 12,
                        offset: const Offset(0, 3),
                      ),
                    ]
                  : const [],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  selected ? selectedIcon : icon,
                  size: 20,
                  color: selected ? PlantPalette.forest : PlantPalette.sage,
                ),
                const SizedBox(height: 3),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: selected ? PlantPalette.forest : PlantPalette.sage,
                    fontSize: 10,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
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

class _Header extends StatelessWidget {
  const _Header({
    required this.title,
    required this.onSignOut,
    this.compact = false,
  });

  final String title;
  final Future<void> Function() onSignOut;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        compact ? 14 : 0,
        compact ? 10 : 0,
        compact ? 14 : 0,
        0,
      ),
      child: GlassSurface(
        radius: 21,
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 14 : 20,
          vertical: compact ? 6 : 9,
        ),
        opacity: 0.72,
        blur: 20,
        child: Row(
          children: [
            if (compact) ...[
              const Icon(
                Icons.eco_rounded,
                color: PlantPalette.forest,
                size: 20,
              ),
              const SizedBox(width: 8),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: PlantPalette.forest,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (!compact)
                    Text(
                      'Ruang kerja pemantauan tanaman',
                      style: Theme.of(context).textTheme.labelSmall
                          ?.copyWith(color: PlantPalette.sage),
                    ),
                ],
              ),
            ),
            const _LiveStatus(),
            const SizedBox(width: 10),
            if (compact)
              IconButton(
                tooltip: 'Keluar',
                onPressed: onSignOut,
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.logout_rounded, size: 19),
              ),
          ],
        ),
      ),
    );
  }
}

class _LiveStatus extends StatelessWidget {
  const _LiveStatus();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: PlantPalette.forest.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(22),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const BreathingDot(),
          const SizedBox(width: 7),
          Text(
            'SESI AKTIF',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: PlantPalette.forest,
              fontSize: 9,
              letterSpacing: 0,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _PageTransition extends StatefulWidget {
  const _PageTransition({required this.index, required this.child});

  final int index;
  final Widget child;

  @override
  State<_PageTransition> createState() => _PageTransitionState();
}

class _PageTransitionState extends State<_PageTransition>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 260),
      value: 1,
    );
  }

  @override
  void didUpdateWidget(covariant _PageTransition oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.index != widget.index &&
        !(MediaQuery.maybeOf(context)?.disableAnimations ?? false)) {
      _controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (reduceMotion) return widget.child;
    return AnimatedBuilder(
      animation: _controller,
      child: widget.child,
      builder: (context, child) {
        final value = Curves.easeOutCubic.transform(_controller.value);
        return Opacity(
          opacity: value,
          child: Transform.translate(
            offset: Offset(0, 8 * (1 - value)),
            child: Transform.scale(
              scale: 0.97 + (0.03 * value),
              alignment: Alignment.topCenter,
              child: child,
            ),
          ),
        );
      },
    );
  }
}

class _ProjectFooter extends StatelessWidget {
  const _ProjectFooter({this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(compact ? 14 : 0, 6, compact ? 14 : 0, 8),
      child: GlassSurface(
        radius: 15,
        opacity: 0.48,
        blur: 12,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Text(
          compact
              ? 'LEAF LENS · Erytheia'
              : 'LEAF LENS · HYBRID AI & CUACA REAL-TIME',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: PlantPalette.forest.withValues(alpha: 0.78),
            fontSize: compact ? 9 : 9.5,
            height: 1.35,
            letterSpacing: 0,
          ),
        ),
      ),
    );
  }
}

class _StartupFailure extends StatelessWidget {
  const _StartupFailure({required this.error});

  final Object error;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 600),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.cloud_off_outlined,
                  size: 42,
                  color: PlantPalette.red,
                ),
                const SizedBox(height: 12),
                Text(
                  'Firebase tidak dapat diinisialisasi',
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
