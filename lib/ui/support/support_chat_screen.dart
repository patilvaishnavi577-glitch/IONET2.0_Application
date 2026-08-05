import 'package:flutter/material.dart';
import '../../data/models/message_model.dart';

class SupportChatScreen extends StatefulWidget {
  const SupportChatScreen({super.key});

  @override
  State<SupportChatScreen> createState() => _SupportChatScreenState();
}

class _SupportChatScreenState extends State<SupportChatScreen> {
  final List<MessageModel> _messages = [
    MessageModel(
      id: 'bot_1',
      text: 'Hi there! I am the IONet support bot. How can I help you today?',
      timestamp: DateTime.now(),
      isUser: false,
    ),
  ];
  final TextEditingController _controller = TextEditingController();

  void _sendMessage() {
    if (_controller.text.trim().isEmpty) return;
    
    final userText = _controller.text;
    setState(() {
      _messages.add(
        MessageModel(
          id: 'user_${DateTime.now().millisecondsSinceEpoch}',
          text: userText,
          timestamp: DateTime.now(),
          isUser: true,
        ),
      );
    });
    _controller.clear();

    Future.delayed(const Duration(seconds: 1), () {
      if (!mounted) return;
      setState(() {
        _messages.add(
          MessageModel(
            id: 'bot_${DateTime.now().millisecondsSinceEpoch}',
            text: 'I understand you are asking about "$userText". As a mock bot, I recommend checking our FAQs!',
            timestamp: DateTime.now(),
            isUser: false,
          ),
        );
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Support Bot')),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(16.0),
              itemCount: _messages.length,
              itemBuilder: (context, index) {
                final msg = _messages[index];
                return Align(
                  alignment: msg.isUser ? Alignment.centerRight : Alignment.centerLeft,
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    decoration: BoxDecoration(
                      color: msg.isUser 
                          ? Theme.of(context).colorScheme.primary 
                          : Theme.of(context).colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      msg.text,
                      style: TextStyle(
                        color: msg.isUser 
                            ? Theme.of(context).colorScheme.onPrimary 
                            : Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(8.0),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      decoration: const InputDecoration(
                        hintText: 'Type your query...',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.all(Radius.circular(24)),
                        ),
                        contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  CircleAvatar(
                    backgroundColor: Theme.of(context).colorScheme.primary,
                    child: IconButton(
                      icon: Icon(Icons.send, color: Theme.of(context).colorScheme.onPrimary),
                      onPressed: _sendMessage,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
