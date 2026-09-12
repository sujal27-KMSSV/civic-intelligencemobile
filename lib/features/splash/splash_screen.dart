import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/constants/app_constants.dart';
import '../../core/utils/perf.dart';
import '../../core/widgets/app_logo.dart';
import '../auth/auth_state.dart';
import '../feed/issue_feed_repository.dart';

class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _fadeIn;
  ProviderSubscription<AsyncValue<AuthState>>? _sub;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _fadeIn = CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic);
    _controller.forward();

    // Kick off session restoration immediately; navigate the moment it
    // completes instead of waiting out a fixed branding delay.
    _warmWithPerf(ref.read(authProvider.future), 'auth restore').ignore();
    _sub = ref.listenManual(authProvider, _onAuthRestored);
  }

  /// Fires once restoration resolves (success or failure). Navigation is left
  /// to the router's redirect (it moves off `/splash` once the session is
  /// known); here we only pre-warm the shared feed so Home/Map render
  /// instantly for an authenticated user.
  void _onAuthRestored(AsyncValue<AuthState>? previous, AsyncValue<AuthState> next) {
    if (!(next.hasValue || next.hasError) || !mounted) return;
    final authState = next.valueOrNull;
    if (authState?.status == AuthStatus.authenticated) {
      _warmWithPerf(ref.read(issueFeedProvider.future), 'feed warm').ignore();
    }
  }

  @override
  void dispose() {
    _sub?.close();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF1A73E8), Color(0xFF0D47A1)],
          ),
        ),
        child: Center(
          child: FadeTransition(
            opacity: _fadeIn,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const AppLogo(size: 88),
                const SizedBox(height: 24),
                Text(
                  AppConstants.appName,
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.5,
                      ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Report. Track. Build a better city.',
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: Colors.white.withValues(alpha: 0.85),
                      ),
                ),
                const SizedBox(height: 48),
                const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    color: Colors.white,
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

/// Returns the future unchanged, but logs how long it took when
/// `--dart-define=PERF_TIMING=true` is set.
Future<T> _warmWithPerf<T>(Future<T> future, String tag) {
  if (!perfTimingEnabled) return future;
  final stopwatch = Stopwatch()..start();
  return future.whenComplete(() {
    perfLog('startup', tag, stopwatch.elapsedMilliseconds);
  });
}