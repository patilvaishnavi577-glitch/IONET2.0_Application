import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'core/theme.dart';
import 'core/api_config.dart';
import 'core/providers/theme_provider.dart';
import 'core/providers/auth_provider.dart';
import 'core/providers/device_provider.dart';
import 'core/providers/support_provider.dart';
import 'ui/auth/login_screen.dart';
import 'ui/devices/home_screen.dart';
import 'ui/auth/onboarding_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Force portrait orientation only
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);
  
  // Initialize API configuration
  ApiConfig.initialize();
  
  // Initialize theme and load saved theme
  final themeProvider = ThemeProvider();
  await themeProvider.loadSavedTheme();
  
  // Try to restore user session from local storage
  final authProvider = AuthProvider();
  final hasSession = await authProvider.tryRestoreSession();

  final deviceProvider = DeviceProvider();
  final supportProvider = SupportProvider();
  if (hasSession) {
    await deviceProvider.fetchDevices();
    await supportProvider.fetchChannels();
    await supportProvider.fetchSubscribedChannels();
  }

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: themeProvider),
        ChangeNotifierProvider.value(value: authProvider),
        ChangeNotifierProvider.value(value: deviceProvider),
        ChangeNotifierProvider.value(value: supportProvider),
      ],
      child: const IONetApp(),
    ),
  );
}

class IONetApp extends StatelessWidget {
  const IONetApp({super.key});

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final authProvider = Provider.of<AuthProvider>(context);

    return MaterialApp(
      title: 'IONet',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: themeProvider.themeMode,
      home: authProvider.isAuthenticated
          ? (authProvider.isFirstTimeUser
              ? const OnboardingScreen()
              : const HomeScreen())
          : const LoginScreen(),
    );
  }
}
