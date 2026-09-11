import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/providers/auth_provider.dart';
import '../../core/providers/device_provider.dart';
import '../../core/utils/app_feedback.dart';
import 'onboarding_screen.dart';
import '../devices/home_screen.dart';

class LoginScreen extends StatefulWidget {
  final bool isRegistering;

  const LoginScreen({super.key, this.isRegistering = false});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailController = TextEditingController();
  final _otpController = TextEditingController();
  bool _otpSent = false;
  bool _isLoading = false;

  void _sendOtp() async {
    if (_emailController.text.isEmpty) {
      AppFeedback.showError(context, 'Please enter your email');
      return;
    }
    setState(() => _isLoading = true);
    try {
      await Provider.of<AuthProvider>(context, listen: false).loginWithEmail(_emailController.text.trim());
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _otpSent = true;
      });
      AppFeedback.showSuccess(context, 'OTP sent to your email.');
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      AppFeedback.showError(context, e);
    }
  }

  void _verifyOtp() async {
    if (_emailController.text.isEmpty) {
      AppFeedback.showError(context, 'Please enter your email');
      return;
    }
    if (_otpController.text.isEmpty) {
      AppFeedback.showError(context, 'Please enter the OTP');
      return;
    }
    setState(() => _isLoading = true);
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    try {
      final success = await authProvider.verifyOtp(_emailController.text.trim(), _otpController.text.trim());
      if (!mounted) return;
      setState(() => _isLoading = false);
      
      if (success) {
        // Fetch user devices upon successful login
        Provider.of<DeviceProvider>(context, listen: false).fetchDevices();

        if (authProvider.isFirstTimeUser) {
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(builder: (_) => const OnboardingScreen()),
            (route) => false,
          );
        } else {
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(builder: (_) => const HomeScreen()),
            (route) => false,
          );
        }
      } else {
        AppFeedback.showError(context, 'Invalid OTP. Please try again.');
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      AppFeedback.showError(context, e);
    }
  }

  @override
  void dispose() {
    _emailController.dispose();
    _otpController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Image.asset(
          'assets/ionet_logo.png',
          height: 32,
          fit: BoxFit.contain,
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              widget.isRegistering ? 'Create Account' : 'Login',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: 32),
            TextField(
              controller: _emailController,
              decoration: const InputDecoration(labelText: 'Email', prefixIcon: Icon(Icons.email_rounded)),
              keyboardType: TextInputType.emailAddress,
              enabled: !_otpSent,
            ),
            const SizedBox(height: 16),
            if (_otpSent) ...[
              TextField(
                controller: _otpController,
                decoration: const InputDecoration(labelText: 'OTP', prefixIcon: Icon(Icons.lock_rounded)),
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 24),
              _isLoading 
                ? const CircularProgressIndicator()
                : ElevatedButton(
                    onPressed: _verifyOtp,
                    style: ElevatedButton.styleFrom(minimumSize: const Size(double.infinity, 50)),
                    child: const Text('Verify OTP'),
                  ),
            ] else ...[
              const SizedBox(height: 8),
              _isLoading 
                ? const CircularProgressIndicator()
                : ElevatedButton(
                    onPressed: _sendOtp,
                    style: ElevatedButton.styleFrom(minimumSize: const Size(double.infinity, 50)),
                    child: const Text('Send OTP'),
                  ),
            ],
            const SizedBox(height: 16),
            TextButton(
              onPressed: () {
                if (widget.isRegistering) {
                  Navigator.of(context).pop();
                } else {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const LoginScreen(isRegistering: true)),
                  );
                }
              },
              child: Text(widget.isRegistering ? "Already have an account? Login" : "Don't have an account? Create one"),
            ),
          ],
        ),
      ),
    );
  }
}
