import 'package:flutter/material.dart';
import 'support_chat_screen.dart';

class HelpScreen extends StatelessWidget {
  const HelpScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Help'),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16.0),
          children: [
        const Text(
          'Frequently Asked Questions',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 16),
        _buildFaqItem('How do I add a device?', 'Go to the Devices tab and click the + floating button to add a new device by ID or QR scan.'),
        _buildFaqItem('What is a Quick Command?', 'Quick commands are pre-set messages you can send to your devices instantly. You can long-press to edit them.'),
        _buildFaqItem('How do I scan a QR code?', 'Click the scanner icon inside the Add Device dialog to scan a device QR code using your camera.'),
        _buildFaqItem('How do I earn credits?', 'Credits are provided automatically for demo purposes. They are shown on the top left of the home screen.'),
        const SizedBox(height: 32),
        const Text(
          'Still need help?',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 16),
        Card(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            leading: CircleAvatar(
              backgroundColor: Theme.of(context).colorScheme.primaryContainer,
              child: Icon(Icons.support_agent, color: Theme.of(context).colorScheme.onPrimaryContainer),
            ),
            title: const Text('Chat with Support Bot', style: TextStyle(fontWeight: FontWeight.bold)),
            subtitle: const Text('Get instant answers to minor queries.'),
            trailing: const Icon(Icons.arrow_forward_ios, size: 16),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const SupportChatScreen()),
              );
            },
          ),
        ),
      ],
    ),
      ),
    );
  }

  Widget _buildFaqItem(String question, String answer) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8.0),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ExpansionTile(
        title: Text(question, style: const TextStyle(fontWeight: FontWeight.w500)),
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Text(answer),
          ),
        ],
      ),
    );
  }
}
