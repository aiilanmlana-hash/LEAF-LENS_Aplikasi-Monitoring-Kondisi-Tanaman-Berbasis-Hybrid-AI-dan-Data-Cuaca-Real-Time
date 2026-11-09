import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../widgets/garden_artwork.dart';
import '../widgets/glass_surface.dart';
import '../widgets/plant_backdrop.dart';
import '../widgets/soft_motion.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  static Stream<User?> get authStateChanges =>
      FirebaseAuth.instance.authStateChanges();

  static Future<void> signOut() => FirebaseAuth.instance.signOut();

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _isRegistering = false;
  bool _isBusy = false;
  bool _obscurePassword = true;
  String? _errorMessage;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _isBusy = true;
      _errorMessage = null;
    });
    try {
      final auth = FirebaseAuth.instance;
      if (_isRegistering) {
        await auth.createUserWithEmailAndPassword(
          email: _email.text.trim(),
          password: _password.text,
        );
        await auth.currentUser?.sendEmailVerification();
        await auth.signOut();
        if (mounted) {
          setState(
            () => _errorMessage =
                'Tautan verifikasi telah dikirim. Verifikasi email sebelum masuk.',
          );
        }
      } else {
        await auth.signInWithEmailAndPassword(
          email: _email.text.trim(),
          password: _password.text,
        );
        if (auth.currentUser?.emailVerified != true) {
          await auth.currentUser?.sendEmailVerification();
          await auth.signOut();
          if (mounted) {
            setState(
              () => _errorMessage =
                  'Email belum terverifikasi. Tautan verifikasi baru telah dikirim.',
            );
          }
        }
      }
    } on FirebaseAuthException catch (error) {
      if (mounted) setState(() => _errorMessage = _messageFor(error.code));
    } catch (error) {
      if (mounted) setState(() => _errorMessage = 'Autentikasi gagal: $error');
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  String _messageFor(String code) => switch (code) {
        'email-already-in-use' => 'Email ini sudah terdaftar.',
        'invalid-email' => 'Format email tidak valid.',
        'invalid-credential' ||
        'wrong-password' ||
        'user-not-found' =>
          'Email atau password tidak sesuai.',
        'weak-password' => 'Gunakan password yang lebih kuat.',
        'network-request-failed' => 'Periksa koneksi internet lalu coba lagi.',
        'operation-not-allowed' =>
          'Aktifkan Email/Password di Firebase Authentication.',
        _ => 'Autentikasi gagal ($code).',
      };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        fit: StackFit.expand,
        children: [
          const PlantBackdrop(),
          SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final compact = constraints.maxWidth < 860;
                final welcome = _WelcomePanel(compact: compact);
                final login = _LoginPanel(
                  theme: theme,
                  formKey: _formKey,
                  email: _email,
                  password: _password,
                  isRegistering: _isRegistering,
                  isBusy: _isBusy,
                  obscurePassword: _obscurePassword,
                  errorMessage: _errorMessage,
                  onModeChanged: (value) => setState(() {
                    _isRegistering = value;
                    _errorMessage = null;
                  }),
                  onTogglePassword: () => setState(
                    () => _obscurePassword = !_obscurePassword,
                  ),
                  onSubmit: _submit,
                );
                return SingleChildScrollView(
                  padding: EdgeInsets.all(compact ? 16 : 28),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 1240),
                      child: compact
                          ? Column(
                              children: [
                                SoftEntrance(
                                  child: SizedBox(
                                    height: 250,
                                    child: welcome,
                                  ),
                                ),
                                const SizedBox(height: 16),
                                SoftEntrance(
                                  delay: const Duration(milliseconds: 100),
                                  child: ConstrainedBox(
                                    constraints:
                                        const BoxConstraints(maxWidth: 480),
                                    child: login,
                                  ),
                                ),
                                const SizedBox(height: 14),
                                Text(
                                  'Smart Plant Monitoring',
                                  textAlign: TextAlign.center,
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    color: PlantColors.forest,
                                  ),
                                ),
                              ],
                            )
                          : Row(
                              children: [
                                Expanded(
                                  child: SoftEntrance(
                                    child: SizedBox(
                                      height: (constraints.maxHeight - 56)
                                          .clamp(560.0, 850.0),
                                      child: welcome,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 28),
                                SizedBox(
                                  width: 440,
                                  child: SoftEntrance(
                                    delay: const Duration(milliseconds: 100),
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        login,
                                        const SizedBox(height: 12),
                                        Text(
                                          'Smart Plant Monitoring',
                                          textAlign: TextAlign.center,
                                          style: theme.textTheme.labelSmall
                                              ?.copyWith(
                                            color: PlantColors.forest,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _WelcomePanel extends StatelessWidget {
  const _WelcomePanel({required this.compact});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ClipRRect(
      borderRadius: BorderRadius.circular(28),
      child: Stack(
        fit: StackFit.expand,
        children: [
          const GlassSurface(
            opacity: 0.62,
            radius: 28,
            child: SizedBox.expand(),
          ),
          Positioned(
            right: compact ? -4 : 28,
            bottom: compact ? -45 : -70,
            width: compact ? 148 : 300,
            height: compact ? 230 : 570,
            child: const GardenArtwork(
              asset: 'assets/old-young-tree.webp',
              opacity: 0.88,
            ),
          ),
          if (!compact) ...[
            const Positioned(
              right: 24,
              top: 20,
              width: 84,
              height: 128,
              child: GardenArtwork(
                asset: 'assets/hanging-lanterns.webp',
                opacity: 0.6,
              ),
            ),
            const Positioned(
              right: 126,
              top: 120,
              width: 112,
              height: 116,
              child: GardenArtwork(
                asset: 'assets/bird-stump.webp',
                opacity: 0.7,
              ),
            ),
            const Positioned(
              right: 88,
              bottom: 8,
              width: 76,
              height: 102,
              child: GardenArtwork(
                asset: 'assets/young-deer.webp',
                opacity: 0.75,
              ),
            ),
            const Positioned(
              left: -38,
              top: -34,
              width: 190,
              height: 162,
              child: GardenArtwork(
                asset: 'assets/moss-branch.webp',
                opacity: 0.24,
              ),
            ),
          ],
          Padding(
            padding: EdgeInsets.all(compact ? 20 : 40),
            child: Align(
              alignment: Alignment.centerLeft,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: compact ? 280 : 440,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: compact
                      ? MainAxisAlignment.center
                      : MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: PlantColors.forest,
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: const Icon(
                            Icons.eco_rounded,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Flexible(
                          child: Text(
                            'Smart Plant',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleLarge?.copyWith(
                              color: PlantColors.forest,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (!compact) const Spacer(),
                    Text(
                      'SMART PLANT MONITORING',
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: PlantColors.olive,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.4,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Tumbuh lebih sehat,\ndengan data.',
                      style: (compact
                              ? theme.textTheme.titleLarge
                              : theme.textTheme.displaySmall)
                          ?.copyWith(
                        color: PlantColors.forest,
                        fontWeight: FontWeight.w700,
                        height: 1.08,
                      ),
                    ),
                    if (!compact) ...[
                      const SizedBox(height: 14),
                      Text(
                        'Kenali kondisi daun lewat kamera, segmentasi warna, dan klasifikasi visual dalam satu ruang monitoring.',
                        style: theme.textTheme.bodyLarge?.copyWith(
                          height: 1.5,
                          color: PlantColors.espresso.withValues(alpha: 0.82),
                        ),
                      ),
                      const SizedBox(height: 24),
                      Text(
                        'Computer vision · PlantVillage AI',
                        style: theme.textTheme.labelLarge?.copyWith(
                          color: PlantColors.forest,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LoginPanel extends StatelessWidget {
  const _LoginPanel({
    required this.theme,
    required this.formKey,
    required this.email,
    required this.password,
    required this.isRegistering,
    required this.isBusy,
    required this.obscurePassword,
    required this.errorMessage,
    required this.onModeChanged,
    required this.onTogglePassword,
    required this.onSubmit,
  });

  final ThemeData theme;
  final GlobalKey<FormState> formKey;
  final TextEditingController email;
  final TextEditingController password;
  final bool isRegistering;
  final bool isBusy;
  final bool obscurePassword;
  final String? errorMessage;
  final ValueChanged<bool> onModeChanged;
  final VoidCallback onTogglePassword;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    return GlassSurface(
      padding: const EdgeInsets.all(26),
      radius: 28,
      opacity: 0.84,
      child: Form(
        key: formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: 38,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  const Icon(
                    Icons.eco_rounded,
                    color: PlantColors.forest,
                    size: 30,
                  ),
                  const Positioned(
                    right: 8,
                    top: -18,
                    width: 44,
                    height: 54,
                    child: GardenArtwork(
                      asset: 'assets/swallow-bird.webp',
                      opacity: 0.62,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Text(
              isRegistering ? 'Mulai dari sini.' : 'Selamat datang kembali.',
              textAlign: TextAlign.center,
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              isRegistering
                  ? 'Buat ruang pribadi untuk monitoring tanaman.'
                  : 'Masuk ke ruang monitoring tanaman Anda.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: PlantColors.sage,
              ),
            ),
            const SizedBox(height: 20),
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: false, label: Text('Masuk')),
                ButtonSegment(value: true, label: Text('Buat akun')),
              ],
              selected: {isRegistering},
              onSelectionChanged:
                  isBusy ? null : (selection) => onModeChanged(selection.first),
            ),
            const SizedBox(height: 18),
            TextFormField(
              controller: email,
              keyboardType: TextInputType.emailAddress,
              autofillHints: const [AutofillHints.email],
              decoration: const InputDecoration(
                labelText: 'Email',
                prefixIcon: Icon(Icons.mail_outline_rounded),
              ),
              validator: (value) => (value ?? '').contains('@')
                  ? null
                  : 'Masukkan email yang valid.',
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: password,
              obscureText: obscurePassword,
              autofillHints: [
                isRegistering
                    ? AutofillHints.newPassword
                    : AutofillHints.password,
              ],
              decoration: InputDecoration(
                labelText: 'Password',
                prefixIcon: const Icon(Icons.lock_outline_rounded),
                suffixIcon: IconButton(
                  tooltip: obscurePassword
                      ? 'Tampilkan password'
                      : 'Sembunyikan password',
                  onPressed: onTogglePassword,
                  icon: Icon(
                    obscurePassword
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                  ),
                ),
              ),
              validator: (value) {
                final passwordValue = value ?? '';
                if (passwordValue.length < (isRegistering ? 10 : 6)) {
                  return isRegistering
                      ? 'Password baru minimal 10 karakter.'
                      : 'Password minimal 6 karakter.';
                }
                if (isRegistering &&
                    (!RegExp(r'[A-Z]').hasMatch(passwordValue) ||
                        !RegExp(r'[a-z]').hasMatch(passwordValue) ||
                        !RegExp(r'[0-9]').hasMatch(passwordValue))) {
                  return 'Gunakan huruf besar, kecil, dan angka.';
                }
                return null;
              },
            ),
            if (errorMessage != null) ...[
              const SizedBox(height: 12),
              Text(
                errorMessage!,
                style: TextStyle(color: theme.colorScheme.error),
              ),
            ],
            const SizedBox(height: 18),
            FilledButton(
              onPressed: isBusy ? null : onSubmit,
              child: isBusy
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(isRegistering ? 'Buat akun' : 'Masuk'),
            ),
            const SizedBox(height: 12),
            Text(
              'Riwayat monitoring Anda tersimpan pada akun pribadi.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: PlantColors.sage,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
