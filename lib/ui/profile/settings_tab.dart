import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/providers/auth_provider.dart';
import '../../core/providers/theme_provider.dart';
import 'profile_screen.dart';
import '../support/help_screen.dart';
import '../auth/login_screen.dart';

class SettingsTab extends StatelessWidget {
  const SettingsTab({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<AuthProvider>(
      builder: (context, auth, _) {
        return ListView(
          padding: const EdgeInsets.symmetric(vertical: 16.0),
          children: [
            // Profile Header (similar to WhatsApp settings header)
            InkWell(
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const ProfileScreen()),
                );
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 24.0, horizontal: 16.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    CircleAvatar(
                      radius: 45,
                      backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                      backgroundImage: auth.profilePicture != null && auth.profilePicture!.isNotEmpty
                          ? NetworkImage(auth.profilePicture!)
                          : null,
                      child: auth.profilePicture == null || auth.profilePicture!.isEmpty
                          ? Icon(Icons.person, size: 54, color: Theme.of(context).colorScheme.onPrimaryContainer)
                          : null,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      (auth.name == null || auth.name!.isEmpty) ? 'Set up your profile' : auth.name!,
                      style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Available',
                      style: TextStyle(
                        fontSize: 14,
                        color: Theme.of(context).colorScheme.onSurfaceVariant.withOpacity(0.7),
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
            const Divider(height: 32),
            
            // Options
            ListTile(
              leading: const Icon(Icons.person_outline),
              title: const Text('Account Profile'),
              subtitle: const Text('Privacy, security, change number'),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const ProfileScreen()),
                );
              },
            ),
            Consumer<ThemeProvider>(
              builder: (context, themeProvider, _) {
                return ListTile(
                  leading: const Icon(Icons.brightness_6_outlined),
                  title: const Text('Toggle Theme'),
                  subtitle: Text(themeProvider.themeMode == ThemeMode.dark ? 'Dark Mode' : 'Light Mode'),
                  onTap: () {
                    themeProvider.toggleTheme(themeProvider.themeMode != ThemeMode.dark);
                  },
                );
              }
            ),
            ListTile(
              leading: const Icon(Icons.help_outline),
              title: const Text('Help'),
              subtitle: const Text('Help center, contact us, privacy policy'),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const HelpScreen()),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.logout, color: Colors.redAccent),
              title: const Text('Logout', style: TextStyle(color: Colors.redAccent)),
              onTap: () {
                Provider.of<AuthProvider>(context, listen: false).logout();
                Navigator.pushAndRemoveUntil(
                  context,
                  MaterialPageRoute(builder: (context) => const LoginScreen()),
                  (route) => false,
                );
              },
            ),
          ],
        );
      },
    );
  }
}
