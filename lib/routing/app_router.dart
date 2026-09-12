import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../features/auth/auth_state.dart';
import '../features/splash/splash_screen.dart';
import '../features/auth/login_screen.dart';
import '../features/auth/register_screen.dart';
import '../features/home/home_screen.dart';
import '../features/notifications/notifications_screen.dart';
import '../features/reporting/report_issue_screen.dart';
import '../features/issues/my_reports_screen.dart';
import '../features/issues/issue_details_screen.dart';
import '../models/issue.dart';
import '../features/map/map_screen.dart';
import '../features/profile/profile_screen.dart';

final GlobalKey<NavigatorState> _rootNavigatorKey =
    GlobalKey<NavigatorState>();

final goRouterProvider = Provider<GoRouter>((ref) {
  final authAsync = ref.watch(authProvider);

  return GoRouter(
    navigatorKey: _rootNavigatorKey,
    initialLocation: '/splash',
    redirect: (context, state) {
      final path = state.matchedLocation;

      // Session restore / auth request still in flight. Only force the splash
      // from non-auth routes: during login/register we let the screen show its
      // own spinner and error banner instead of tearing the form down mid-
      // submit and leaving the user stuck on the splash if the request fails.
      if (authAsync is AsyncLoading) {
        if (path == '/splash' || path == '/login' || path == '/register') {
          return null;
        }
        return '/splash';
      }

      // A failed auth operation (AsyncError) means "not signed in" for routing
      // purposes — never strand the user on the splash; /login and /register
      // remain reachable so the signup error is visible on the form.
      final authState = authAsync.valueOrNull;
      final isAuthed = authState?.status == AuthStatus.authenticated;

      // Once the session is known, leave the splash immediately: an
      // authenticated user goes home, everyone else to login. The splash no
      // longer navigates itself, so there is no fixed branding delay.
      if (path == '/splash') {
        return isAuthed ? '/' : '/login';
      }

      // Paths that are always reachable without authentication.
      const publicPaths = <String>{'/login', '/register', '/splash'};

      final isPublic = publicPaths.contains(path) || path.startsWith('/issue/');

      // Protected route, not signed in → login.
      if (!isAuthed && !isPublic) return '/login';

      // Signed in, but on an auth-only screen → home.
      if (isAuthed && publicPaths.contains(path)) return '/';

      return null;
    },
    routes: [
      GoRoute(
        path: '/splash',
        name: 'splash',
        builder: (context, state) => const SplashScreen(),
      ),
      GoRoute(
        path: '/login',
        name: 'login',
        builder: (context, state) => const LoginScreen(),
      ),
      GoRoute(
        path: '/register',
        name: 'register',
        builder: (context, state) => const RegisterScreen(),
      ),
      ShellRoute(
        builder: (context, state, child) => ScaffoldWithNavBar(child: child),
        routes: [
          GoRoute(
            path: '/',
            name: 'home',
            pageBuilder: (context, state) => const NoTransitionPage(
              child: HomeScreen(),
            ),
          ),
          GoRoute(
            path: '/report',
            name: 'report',
            pageBuilder: (context, state) => const NoTransitionPage(
              child: ReportIssueScreen(),
            ),
          ),
          GoRoute(
            path: '/my-reports',
            name: 'myReports',
            pageBuilder: (context, state) => const NoTransitionPage(
              child: MyReportsScreen(),
            ),
          ),
          GoRoute(
            path: '/map',
            name: 'map',
            pageBuilder: (context, state) => const NoTransitionPage(
              child: MapScreen(),
            ),
          ),
          GoRoute(
            path: '/profile',
            name: 'profile',
            pageBuilder: (context, state) => const NoTransitionPage(
              child: ProfileScreen(),
            ),
          ),
        ],
      ),
      GoRoute(
        path: '/issue/:id',
        name: 'issueDetails',
        builder: (context, state) {
          final issueId = state.pathParameters['id']!;
          return IssueDetailsScreen(issueId: issueId, issue: state.extra as Issue?);
        },
      ),
      GoRoute(
        path: '/notifications',
        name: 'notifications',
        builder: (context, state) => const NotificationsScreen(),
      ),
    ],
  );
});

class ScaffoldWithNavBar extends StatelessWidget {
  final Widget child;
  const ScaffoldWithNavBar({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: child,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _calculateSelectedIndex(context),
        onDestinationSelected: (index) => _onItemTapped(index, context),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: 'Home',
          ),
          NavigationDestination(
            icon: Icon(Icons.add_circle_outline),
            selectedIcon: Icon(Icons.add_circle),
            label: 'Report',
          ),
          NavigationDestination(
            icon: Icon(Icons.list_alt_outlined),
            selectedIcon: Icon(Icons.list_alt),
            label: 'Reports',
          ),
          NavigationDestination(
            icon: Icon(Icons.map_outlined),
            selectedIcon: Icon(Icons.map),
            label: 'Map',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outlined),
            selectedIcon: Icon(Icons.person),
            label: 'Profile',
          ),
        ],
      ),
    );
  }

  int _calculateSelectedIndex(BuildContext context) {
    final location = GoRouterState.of(context).uri.toString();
    if (location.startsWith('/report')) return 1;
    if (location.startsWith('/my-reports')) return 2;
    if (location.startsWith('/map')) return 3;
    if (location.startsWith('/profile')) return 4;
    return 0;
  }

  void _onItemTapped(int index, BuildContext context) {
    switch (index) {
      case 0:
        context.go('/');
        break;
      case 1:
        context.go('/report');
        break;
      case 2:
        context.go('/my-reports');
        break;
      case 3:
        context.go('/map');
        break;
      case 4:
        context.go('/profile');
        break;
    }
  }
}