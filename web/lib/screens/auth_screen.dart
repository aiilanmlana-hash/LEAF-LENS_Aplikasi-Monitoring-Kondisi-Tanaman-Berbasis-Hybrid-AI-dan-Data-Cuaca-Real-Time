import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:model_viewer_plus/model_viewer_plus.dart';

import '../theme/app_theme.dart';
import '../widgets/glass_surface.dart';
import '../widgets/garden_artwork.dart';
import '../widgets/soft_motion.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  static const _requestTimeout = Duration(seconds: 20);
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _register = false;
  bool _busy = false;
  bool _showPassword = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final auth = FirebaseAuth.instance;
      if (_register) {
        await auth
            .createUserWithEmailAndPassword(
              email: _email.text.trim(),
              password: _password.text,
            )
            .timeout(_requestTimeout);
        final user = auth.currentUser;
        if (user != null) {
          await user.sendEmailVerification().timeout(_requestTimeout);
        }
        await auth.signOut().timeout(_requestTimeout);
        if (mounted) {
          _showError(
            'Tautan verifikasi telah dikirim. Verifikasi email sebelum masuk.',
          );
        }
      } else {
        await auth
            .signInWithEmailAndPassword(
              email: _email.text.trim(),
              password: _password.text,
            )
            .timeout(_requestTimeout);
        await auth.currentUser?.reload().timeout(_requestTimeout);
        if (auth.currentUser?.emailVerified != true) {
          final user = auth.currentUser;
          if (user != null) {
            await user.sendEmailVerification().timeout(_requestTimeout);
          }
          await auth.signOut().timeout(_requestTimeout);
          if (mounted) {
            _showError(
              'Email belum terverifikasi. Tautan verifikasi baru telah dikirim.',
            );
          }
        }
      }
    } on TimeoutException {
      if (mounted) {
        _showError(
          'Koneksi ke layanan login terlalu lama. Periksa internet lalu coba lagi.',
        );
      }
    } on FirebaseAuthException catch (error) {
      if (mounted) _showError(_friendlyError(error.code));
    } catch (error) {
      if (mounted) _showError('Autentikasi gagal: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _signInWithGoogle() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final provider = GoogleAuthProvider()
        ..setCustomParameters({'prompt': 'select_account'});
      await FirebaseAuth.instance
          .signInWithPopup(provider)
          .timeout(_requestTimeout);
    } on TimeoutException {
      if (mounted) {
        _showError(
          'Login Google terlalu lama. Periksa koneksi lalu coba lagi.',
        );
      }
    } on FirebaseAuthException catch (error) {
      if (mounted) _showError(_googleError(error.code));
    } catch (error) {
      if (mounted) _showError('Login Google gagal: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _showError(String message) => setState(() => _error = message);

  String _friendlyError(String code) => switch (code) {
    'email-already-in-use' => 'Email ini sudah terdaftar.',
    'invalid-email' => 'Format email tidak valid.',
    'invalid-credential' ||
    'wrong-password' ||
    'user-not-found' => 'Email atau password tidak sesuai.',
    'weak-password' => 'Gunakan password yang lebih kuat.',
    'operation-not-allowed' =>
      'Aktifkan metode Email/Password di Firebase Authentication.',
    'network-request-failed' => 'Koneksi internet gagal. Coba lagi.',
    _ => 'Autentikasi gagal ($code).',
  };

  String _googleError(String code) => switch (code) {
    'popup-closed-by-user' => 'Login Google dibatalkan.',
    'cancelled-popup-request' => 'Permintaan login Google dibatalkan.',
    'popup-blocked' => 'Popup diblokir browser. Izinkan popup lalu coba lagi.',
    'unauthorized-domain' =>
      'Domain ini belum diizinkan di Firebase Authentication.',
    'operation-not-allowed' =>
      'Aktifkan Google di Firebase Authentication → Sign-in method.',
    'account-exists-with-different-credential' => 'Email ini sudah memakai metode login lain. Masuk dengan metode tersebut.',
    'network-request-failed' => 'Koneksi internet gagal. Coba lagi.',
    _ => 'Login Google gagal ($code).',
  };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxWidth < 960;
            final welcome = _WelcomePanel(compact: compact);
            final login = _LoginPanel(
              formKey: _formKey,
              email: _email,
              password: _password,
              isRegister: _register,
              busy: _busy,
              showPassword: _showPassword,
              error: _error,
              onModeChanged: (register) => setState(() {
                _register = register;
                _error = null;
              }),
              onTogglePassword: () =>
                  setState(() => _showPassword = !_showPassword),
              onSubmit: _submit,
              onGoogleSignIn: _signInWithGoogle,
            );

            return SingleChildScrollView(
              padding: EdgeInsets.all(compact ? 18 : 30),
              child: Center(
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: 1320,
                    minHeight: compact ? 0 : constraints.maxHeight - 60,
                  ),
                  child: compact
                      ? Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            if (kIsWeb)
                              SizedBox(
                                height: 270,
                                child: Center(
                                  child: ConstrainedBox(
                                    constraints: const BoxConstraints(
                                      maxWidth: 380,
                                    ),
                                    child: _CornModelViewer(),
                                  ),
                                ),
                              ),
                            SoftEntrance(
                              child: HoverLift(
                                child: SizedBox(height: 260, child: welcome),
                              ),
                            ),
                            const SizedBox(height: 18),
                            SoftEntrance(
                              delay: const Duration(milliseconds: 110),
                              child: HoverLift(
                                child: ConstrainedBox(
                                  constraints: const BoxConstraints(
                                    maxWidth: 460,
                                  ),
                                  child: login,
                                ),
                              ),
                            ),
                            const SizedBox(height: 14),
                            const _AuthFooter(),
                          ],
                        )
                      : SizedBox(
                          height: (constraints.maxHeight - 60).clamp(
                            600.0,
                            900.0,
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Expanded(
                                child: SoftEntrance(
                                  child: HoverLift(child: welcome),
                                ),
                              ),
                              const SizedBox(width: 34),
                              SizedBox(
                                width: 440,
                                child: SoftEntrance(
                                  delay: const Duration(milliseconds: 110),
                                  child: HoverLift(
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        login,
                                        const SizedBox(height: 12),
                                        const _AuthFooter(),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _WelcomePanel extends StatelessWidget {
  const _WelcomePanel({required this.compact});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final treeWidth = compact
            ? constraints.maxWidth < 520
                  ? 174.0
                  : 220.0
            : (constraints.maxWidth * 0.47).clamp(260.0, 390.0);
        final showCornModel = kIsWeb && !compact && constraints.maxWidth >= 320;
        final cornWidth = (constraints.maxWidth * 0.55).clamp(220.0, 420.0);
        final cornHeight = (constraints.maxHeight * 0.48).clamp(300.0, 420.0);
        final textMaxWidth = compact
            ? constraints.maxWidth * 0.68
            : (constraints.maxWidth - 84).clamp(220.0, 430.0);
        final headlineFontSize = compact
            ? constraints.maxWidth < 520
                  ? 22.0
                  : 30.0
            : textMaxWidth < 350
            ? 32.0
            : 42.0;
        return ClipRRect(
          borderRadius: BorderRadius.circular(34),
          child: Stack(
            fit: StackFit.expand,
            children: [
              const GlassSurface(
                tint: Color(0xFFF9F8F1),
                opacity: 0.48,
                radius: 34,
                blur: 24,
                borderOpacity: 0.82,
                child: SizedBox.expand(),
              ),
              Positioned(
                right: compact ? -8 : 10,
                bottom: compact ? -32 : -76,
                width: treeWidth,
                height: compact ? 252 : 650,
                child: IgnorePointer(
                  child: Opacity(
                    opacity: compact ? 0.7 : 0.8,
                    child: Image.asset(
                      'assets/old-young-tree.webp',
                      fit: BoxFit.contain,
                      alignment: Alignment.bottomCenter,
                    ),
                  ),
                ),
              ),
              if (!compact) ...[
                Positioned(
                  left: -34,
                  top: -40,
                  width: 250,
                  height: 210,
                  child: const GardenArtwork(
                    asset: 'assets/hanging-branch.webp',
                    opacity: 0.14,
                  ),
                ),
                Positioned(
                  left: 294,
                  top: -16,
                  width: 72,
                  height: 112,
                  child: const GardenArtwork(
                    asset: 'assets/hanging-lanterns.webp',
                    opacity: 0.42,
                  ),
                ),
                Positioned(
                  right: 30,
                  top: 122,
                  width: 124,
                  height: 126,
                  child: const GardenArtwork(
                    asset: 'assets/bird-stump.webp',
                    opacity: 0.58,
                  ),
                ),
                Positioned(
                  right: 164,
                  top: 114,
                  width: 64,
                  height: 102,
                  child: const GardenArtwork(
                    asset: 'assets/forest-fairy.webp',
                    opacity: 0.3,
                  ),
                ),
                Positioned(
                  right: 76,
                  bottom: -14,
                  width: 92,
                  height: 142,
                  child: const GardenArtwork(
                    asset: 'assets/young-deer.webp',
                    opacity: 0.78,
                  ),
                ),
                Positioned(
                  right: 14,
                  bottom: -16,
                  width: 132,
                  height: 70,
                  child: const GardenArtwork(
                    asset: 'assets/river-stones.webp',
                    opacity: 0.8,
                  ),
                ),
              ],
              if (showCornModel)
                Positioned(
                  left:
                      ((constraints.maxWidth - cornWidth) / 2 -
                              constraints.maxWidth * 0.045)
                          .clamp(0.0, constraints.maxWidth - cornWidth),
                  top: (constraints.maxHeight * 0.1).clamp(65.0, 100.0),
                  width: cornWidth,
                  height: cornHeight,
                  child: const _CornModelViewer(),
                ),
              Padding(
                padding: EdgeInsets.all(compact ? 22 : 42),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: textMaxWidth),
                    child: Column(
                      mainAxisAlignment: compact
                          ? MainAxisAlignment.center
                          : MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _BrandMark(compact: compact),
                        if (!compact) const Spacer(),
                        Text(
                          'ANALISIS DAUN',
                          style: Theme.of(context).textTheme.labelMedium
                              ?.copyWith(
                                color: PlantPalette.olive,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0,
                              ),
                        ),
                        SizedBox(height: compact ? 8 : 14),
                        Text(
                          'Kenali daun,\nrawat lebih tepat.',
                          style: Theme.of(context).textTheme.displaySmall
                              ?.copyWith(
                                color: PlantPalette.forest,
                                height: 1.08,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0,
                                fontSize: headlineFontSize,
                              ),
                        ),
                        if (!compact) ...[
                          const SizedBox(height: 16),
                          Text(
                            'Pindai daun untuk melihat kondisi tanaman dan memperoleh arahan perawatan.',
                            style: Theme.of(context).textTheme.bodyLarge
                                ?.copyWith(
                                  color: PlantPalette.ink.withValues(
                                    alpha: 0.8,
                                  ),
                                  height: 1.55,
                                ),
                          ),
                          const SizedBox(height: 30),
                          const _CapabilityPill(
                            text: 'Computer vision · PlantVillage AI',
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
      },
    );
  }
}

class _CornModelViewer extends StatelessWidget {
  const _CornModelViewer();

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: ModelViewer(
        src: 'assets/assets/models/mr_potato_head.glb',
        alt: 'Model 3D Mr. Potato Head',
        backgroundColor: Colors.transparent,
        loading: Loading.eager,
        reveal: Reveal.auto,
        cameraControls: true,
        autoRotate: true,
        disableZoom: true,
        touchAction: TouchAction.panY,
        interactionPrompt: InteractionPrompt.whenFocused,
        shadowIntensity: 0.28,
        relatedCss: '''
          model-viewer::part(default-progress-bar) {
            height: 3px;
            background-color: rgba(55, 75, 43, 0.16);
          }
        ''',
      ),
    );
  }
}

class _BrandMark extends StatelessWidget {
  const _BrandMark({required this.compact});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: compact ? 36 : 44,
          height: compact ? 36 : 44,
          decoration: BoxDecoration(
            color: PlantPalette.forest,
            borderRadius: BorderRadius.circular(15),
            boxShadow: [
              BoxShadow(
                color: PlantPalette.forest.withValues(alpha: 0.18),
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: const Icon(Icons.eco_rounded, color: Colors.white, size: 23),
        ),
        const SizedBox(width: 11),
        Flexible(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'LEAF LENS',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: PlantPalette.forest,
                  fontWeight: FontWeight.w800,
                  height: 1.05,
                ),
              ),
              Text(
                'HYBRID AI · CUACA REAL-TIME',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: PlantPalette.sage,
                  letterSpacing: 0,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _CapabilityPill extends StatelessWidget {
  const _CapabilityPill({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return GlassSurface(
      radius: 30,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      opacity: 0.65,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.auto_awesome_outlined,
            color: PlantPalette.forest,
            size: 17,
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: PlantPalette.forest,
                fontWeight: FontWeight.w600,
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
    required this.formKey,
    required this.email,
    required this.password,
    required this.isRegister,
    required this.busy,
    required this.showPassword,
    required this.error,
    required this.onModeChanged,
    required this.onTogglePassword,
    required this.onSubmit,
    required this.onGoogleSignIn,
  });

  final GlobalKey<FormState> formKey;
  final TextEditingController email;
  final TextEditingController password;
  final bool isRegister;
  final bool busy;
  final bool showPassword;
  final String? error;
  final ValueChanged<bool> onModeChanged;
  final VoidCallback onTogglePassword;
  final VoidCallback onSubmit;
  final VoidCallback onGoogleSignIn;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GlassSurface(
      radius: 30,
      padding: const EdgeInsets.all(30),
      opacity: 0.76,
      blur: 24,
      child: Form(
        key: formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: 34,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  const Align(
                    alignment: Alignment.center,
                    child: Icon(
                      Icons.eco_rounded,
                      color: PlantPalette.forest,
                      size: 30,
                    ),
                  ),
                  Positioned(
                    right: 0,
                    top: -18,
                    width: 46,
                    height: 58,
                    child: const GardenArtwork(
                      asset: 'assets/swallow-bird.webp',
                      opacity: 0.58,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Text(
              isRegister ? 'Mulai dari sini.' : 'Selamat datang kembali.',
              textAlign: TextAlign.center,
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w700,
                letterSpacing: 0,
              ),
            ),
            const SizedBox(height: 7),
            Text(
              isRegister
                  ? 'Buat akun untuk mulai memantau tanaman.'
                  : 'Masuk untuk memantau tanaman Anda.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: PlantPalette.sage,
              ),
            ),
            const SizedBox(height: 24),
            _AuthModeToggle(isRegister: isRegister, onChanged: onModeChanged),
            const SizedBox(height: 20),
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
              obscureText: !showPassword,
              autofillHints: [
                isRegister ? AutofillHints.newPassword : AutofillHints.password,
              ],
              decoration: InputDecoration(
                labelText: 'Password',
                prefixIcon: const Icon(Icons.lock_outline_rounded),
                suffixIcon: IconButton(
                  tooltip: showPassword
                      ? 'Sembunyikan password'
                      : 'Lihat password',
                  onPressed: onTogglePassword,
                  icon: Icon(
                    showPassword
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined,
                  ),
                ),
              ),
              validator: (value) {
                final passwordValue = value ?? '';
                if (passwordValue.length < (isRegister ? 10 : 6)) {
                  return isRegister
                      ? 'Password baru minimal 10 karakter.'
                      : 'Password minimal 6 karakter.';
                }
                if (isRegister &&
                    (!RegExp(r'[A-Z]').hasMatch(passwordValue) ||
                        !RegExp(r'[a-z]').hasMatch(passwordValue) ||
                        !RegExp(r'[0-9]').hasMatch(passwordValue))) {
                  return 'Gunakan huruf besar, kecil, dan angka.';
                }
                return null;
              },
            ),
            if (error != null) ...[
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: PlantPalette.red.withValues(alpha: 0.09),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: PlantPalette.red.withValues(alpha: 0.14),
                  ),
                ),
                child: Text(
                  error!,
                  style: TextStyle(color: theme.colorScheme.error),
                ),
              ),
            ],
            const SizedBox(height: 20),
            PressScale(
              enabled: !busy,
              child: FilledButton(
                onPressed: busy ? null : onSubmit,
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(54),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                child: busy
                    ? const SizedBox.square(
                        dimension: 19,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(
                        isRegister ? 'Buat akun' : 'Masuk',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
              ),
            ),
            const SizedBox(height: 12),
            PressScale(
              enabled: !busy,
              child: OutlinedButton.icon(
                onPressed: busy ? null : onGoogleSignIn,
                icon: const SizedBox.square(
                  dimension: 20,
                  child: Center(
                    child: Text(
                      'G',
                      style: TextStyle(
                        color: Color(0xFF4285F4),
                        fontSize: 19,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
                label: Text(
                  isRegister ? 'Daftar dengan Google' : 'Masuk dengan Google',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(54),
                  backgroundColor: Colors.white.withValues(alpha: 0.78),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Text(
              isRegister
                  ? 'Verifikasi email diperlukan sebelum masuk.'
                  : 'Masuk untuk membuka riwayat pribadi.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: PlantPalette.sage,
                height: 1.45,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AuthModeToggle extends StatelessWidget {
  const _AuthModeToggle({required this.isRegister, required this.onChanged});

  final bool isRegister;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return GlassSurface(
      radius: 16,
      padding: const EdgeInsets.all(4),
      opacity: 0.52,
      blur: 12,
      child: Row(
        children: [
          _AuthModeButton(
            label: 'Masuk',
            selected: !isRegister,
            onPressed: () => onChanged(false),
          ),
          _AuthModeButton(
            label: 'Buat akun',
            selected: isRegister,
            onPressed: () => onChanged(true),
          ),
        ],
      ),
    );
  }
}

class _AuthModeButton extends StatelessWidget {
  const _AuthModeButton({
    required this.label,
    required this.selected,
    required this.onPressed,
  });

  final String label;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        decoration: BoxDecoration(
          color: selected
              ? Colors.white.withValues(alpha: 0.9)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
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
        child: TextButton(
          onPressed: onPressed,
          style: TextButton.styleFrom(
            foregroundColor: selected ? PlantPalette.forest : PlantPalette.sage,
            minimumSize: const Size.fromHeight(42),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }
}

class _AuthFooter extends StatelessWidget {
  const _AuthFooter();

  @override
  Widget build(BuildContext context) {
    return Text(
      'LEAF LENS · Erytheia',
      textAlign: TextAlign.center,
      style: Theme.of(context).textTheme.labelSmall
          ?.copyWith(color: PlantPalette.forest.withValues(alpha: 0.72)),
    );
  }
}
