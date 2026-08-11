import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/providers/auth_provider.dart';
import '../../core/providers/theme_provider.dart';
import 'profile_screen.dart';
import '../auth/login_screen.dart';
import '../../api_route_path.dart';

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
                  MaterialPageRoute(
                    builder: (context) => const ProfileScreen(),
                  ),
                );
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  vertical: 24.0,
                  horizontal: 16.0,
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    CircleAvatar(
                      radius: 45,
                      backgroundColor: Theme.of(
                        context,
                      ).colorScheme.primaryContainer,
                      backgroundImage:
                          auth.profilePicture != null &&
                              auth.profilePicture!.isNotEmpty
                          ? NetworkImage(auth.profilePicture!)
                          : null,
                      child:
                          auth.profilePicture == null ||
                              auth.profilePicture!.isEmpty
                          ? Icon(
                              Icons.person,
                              size: 54,
                              color: Theme.of(
                                context,
                              ).colorScheme.onPrimaryContainer,
                            )
                          : null,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      (auth.name == null || auth.name!.isEmpty)
                          ? 'Set up your profile'
                          : auth.name!,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primaryContainer,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.diamond_rounded,
                            size: 16,
                            color: Theme.of(
                              context,
                            ).colorScheme.onPrimaryContainer,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            '${auth.credits} Credits',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: Theme.of(
                                context,
                              ).colorScheme.onPrimaryContainer,
                            ),
                          ),
                        ],
                      ),
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
                  MaterialPageRoute(
                    builder: (context) => const ProfileScreen(),
                  ),
                );
              },
            ),
            Consumer<ThemeProvider>(
              builder: (context, themeProvider, _) {
                String themeName = 'System Default';
                if (themeProvider.themeMode == ThemeMode.light) {
                  themeName = 'Light';
                } else if (themeProvider.themeMode == ThemeMode.dark) {
                  themeName = 'Dark';
                }
                return ListTile(
                  leading: const Icon(Icons.brightness_6_outlined),
                  title: const Text('Theme'),
                  subtitle: Text(themeName),
                  onTap: () {
                    showDialog(
                      context: context,
                      builder: (dialogContext) {
                        return AlertDialog(
                          title: const Text('Choose Theme'),
                          content: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              RadioListTile<ThemeMode>(
                                title: const Text('System Default'),
                                value: ThemeMode.system,
                                groupValue: themeProvider.themeMode,
                                onChanged: (value) {
                                  if (value != null) {
                                    themeProvider.setThemeMode(value);
                                    Navigator.pop(dialogContext);
                                  }
                                },
                              ),
                              RadioListTile<ThemeMode>(
                                title: const Text('Light'),
                                value: ThemeMode.light,
                                groupValue: themeProvider.themeMode,
                                onChanged: (value) {
                                  if (value != null) {
                                    themeProvider.setThemeMode(value);
                                    Navigator.pop(dialogContext);
                                  }
                                },
                              ),
                              RadioListTile<ThemeMode>(
                                title: const Text('Dark'),
                                value: ThemeMode.dark,
                                groupValue: themeProvider.themeMode,
                                onChanged: (value) {
                                  if (value != null) {
                                    themeProvider.setThemeMode(value);
                                    Navigator.pop(dialogContext);
                                  }
                                },
                              ),
                            ],
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(dialogContext),
                              child: const Text('Cancel'),
                            ),
                          ],
                        );
                      },
                    );
                  },
                );
              },
            ),

            ListTile(
              leading: const Icon(Icons.logout, color: Colors.redAccent),
              title: const Text(
                'Logout',
                style: TextStyle(color: Colors.redAccent),
              ),
              onTap: () {
                showDialog(
                  context: context,
                  builder: (BuildContext context) {
                    return AlertDialog(
                      title: const Text('Logout'),
                      content: const Text('Are you sure you want to logout?'),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('Cancel'),
                        ),
                        ElevatedButton(
                          onPressed: () {
                            Navigator.pop(context);
                            Provider.of<AuthProvider>(
                              context,
                              listen: false,
                            ).logout();
                            Navigator.pushAndRemoveUntil(
                              context,
                              MaterialPageRoute(
                                builder: (context) => const LoginScreen(),
                              ),
                              (route) => false,
                            );
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.redAccent,
                            foregroundColor: Colors.white,
                          ),
                          child: const Text('Logout'),
                        ),
                      ],
                    );
                  },
                );
              },
            ),
            const SizedBox(height: 32),
            Center(
              child: Text(
                'Software Version: $appVersion',
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(
                    context,
                  ).colorScheme.onSurfaceVariant.withOpacity(0.5),
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],
        );
      },
    );
  }
}
