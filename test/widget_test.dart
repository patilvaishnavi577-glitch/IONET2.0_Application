// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.


import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:ionet/main.dart';
import 'package:ionet/core/providers/theme_provider.dart';
import 'package:ionet/core/providers/auth_provider.dart';
import 'package:ionet/core/providers/device_provider.dart';

void main() {
  testWidgets('App smoke test', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => ThemeProvider()),
          ChangeNotifierProvider(create: (_) => AuthProvider()),
          ChangeNotifierProvider(create: (_) => DeviceProvider()),
        ],
        child: const IONetApp(),
      ),
    );

    // Verify that the login screen is displayed initially (since authenticated is false).
    expect(find.text('Login'), findsWidgets);
  });
}
