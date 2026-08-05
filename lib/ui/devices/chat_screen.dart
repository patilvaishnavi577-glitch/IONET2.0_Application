import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/providers/device_provider.dart';
import '../../data/models/device_model.dart';
import '../../data/models/quick_command_model.dart';
import 'device_profile_screen.dart';

class ChatScreen extends StatefulWidget {
  final DeviceModel device;
  const ChatScreen({super.key, required this.device});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  void _sendMessage([String? text]) {
    final message = text ?? _messageController.text.trim();
    if (message.isEmpty) return;

    Provider.of<DeviceProvider>(context, listen: false)
        .sendMessage(widget.device.id, message);
    
    _messageController.clear();
    _scrollToBottom();
  }

  @override
  void initState() {
    super.initState();
    _scrollToBottom();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final provider = Provider.of<DeviceProvider>(context, listen: false);
      provider.clearMessages(widget.device.id);
      provider.loadCustomCommands(widget.device.id);
      provider.connectWebSocket(widget.device.id);
    });
  }

  @override
  void dispose() {
    Provider.of<DeviceProvider>(context, listen: false).disconnectWebSocket();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }



  void _showAddCommandDialog(DeviceProvider provider) {
    final labelController = TextEditingController();
    final messageController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Add Custom Button'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: labelController,
                decoration: const InputDecoration(
                  labelText: 'Button Label (e.g. Relay 3 ON)',
                  hintText: 'Enter text displayed on button',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: messageController,
                decoration: const InputDecoration(
                  labelText: 'Command / Message (e.g. /relay3_on)',
                  hintText: 'Enter text sent to device',
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                final label = labelController.text.trim();
                final message = messageController.text.trim();
                if (label.isNotEmpty && message.isNotEmpty) {
                  provider.addDeviceQuickCommand(
                    widget.device.id,
                    QuickCommandModel(label: label, message: message),
                  );
                  Navigator.pop(context);
                }
              },
              child: const Text('Add'),
            ),
          ],
        );
      },
    );
  }

  void _showDeleteCommandDialog(DeviceProvider provider, QuickCommandModel command) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Delete Button'),
          content: Text('Are you sure you want to delete the custom button "${command.label}"?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              onPressed: () {
                provider.deleteDeviceQuickCommand(widget.device.id, command);
                Navigator.pop(context);
              },
              child: const Text('Delete', style: TextStyle(color: Colors.white)),
            ),
          ],
        );
      },
    );
  }

  Widget _buildFormattedMessage(BuildContext context, String text, bool isUser) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    
    if (isUser) {
      return Text(
        text,
        style: TextStyle(
          color: theme.colorScheme.onPrimary,
          fontSize: 13,
        ),
      );
    }

    final List<TextSpan> spans = [];
    final List<String> lines = text.split('\n');
    
    for (int i = 0; i < lines.length; i++) {
      final line = lines[i];
      
      if (line.trim().isEmpty) {
        spans.add(const TextSpan(text: '\n'));
        continue;
      }
      
      if (line.startsWith('Device Id :')) {
        final parts = line.split('Device Id :');
        spans.add(TextSpan(
          text: 'Device Id : ',
          style: TextStyle(color: isDark ? Colors.grey[400] : Colors.grey[600]),
        ));
        spans.add(TextSpan(
          text: parts.length > 1 ? parts[1] : '',
          style: TextStyle(
            color: isDark ? Colors.white : Colors.black,
            fontWeight: FontWeight.bold,
          ),
        ));
      } else if (line.startsWith('Firmware:')) {
        final parts = line.split('Firmware:');
        spans.add(TextSpan(
          text: 'Firmware: ',
          style: TextStyle(color: isDark ? Colors.grey[400] : Colors.grey[600]),
        ));
        spans.add(TextSpan(
          text: parts.length > 1 ? parts[1] : '',
          style: TextStyle(color: isDark ? Colors.white : Colors.black),
        ));
      } else if (line.contains('Status:')) {
        final index = line.indexOf(':');
        if (index != -1) {
          final prefix = line.substring(0, index + 1);
          final suffix = line.substring(index + 1);
          spans.add(TextSpan(
            text: prefix,
            style: TextStyle(color: isDark ? Colors.grey[400] : Colors.grey[600]),
          ));
          
          final isValOn = suffix.toLowerCase().contains('on');
          final isValOff = suffix.toLowerCase().contains('off');
          final statusColor = isValOn 
              ? (isDark ? const Color(0xFF4ADE80) : const Color(0xFF16A34A)) 
              : (isValOff 
                  ? (isDark ? const Color(0xFFF87171) : const Color(0xFFDC2626)) 
                  : (isDark ? Colors.white : Colors.black87));
          
          spans.add(TextSpan(
            text: suffix,
            style: TextStyle(
              color: statusColor,
              fontWeight: FontWeight.bold,
            ),
          ));
        } else {
          spans.add(TextSpan(text: line, style: TextStyle(color: isDark ? Colors.white : Colors.black)));
        }
      } else if (line.startsWith('/')) {
        final index = line.indexOf(' : ');
        if (index != -1) {
          final cmd = line.substring(0, index);
          final desc = line.substring(index);
          spans.add(TextSpan(
            text: cmd,
            style: TextStyle(
              color: isDark ? const Color(0xFF4ADE80) : const Color(0xFF00A884), 
              fontWeight: FontWeight.bold
            ),
          ));
          spans.add(TextSpan(
            text: desc,
            style: TextStyle(color: isDark ? Colors.grey[400] : Colors.grey[600]),
          ));
        } else {
          spans.add(TextSpan(
            text: line,
            style: TextStyle(
              color: isDark ? const Color(0xFF4ADE80) : const Color(0xFF00A884), 
              fontWeight: FontWeight.bold
            ),
          ));
        }
      } else {
        spans.add(TextSpan(
          text: line,
          style: TextStyle(color: isDark ? Colors.white : Colors.black87),
        ));
      }
      
      if (i < lines.length - 1) {
        spans.add(const TextSpan(text: '\n'));
      }
    }
    
    return RichText(
      text: TextSpan(
        style: TextStyle(
          fontFamily: 'monospace',
          fontSize: 13,
          height: 1.3,
          color: isDark ? Colors.white : Colors.black87,
        ),
        children: spans,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final deviceProvider = Provider.of<DeviceProvider>(context);
    final activeDevice = deviceProvider.devices.firstWhere(
      (d) => d.id == widget.device.id,
      orElse: () => widget.device,
    );

    return Scaffold(
      appBar: AppBar(
        title: GestureDetector(
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => DeviceProfileScreen(deviceId: activeDevice.id),
              ),
            );
          },
          child: Row(
            children: [
              CircleAvatar(
                backgroundImage: activeDevice.profilePhotoUrl.isNotEmpty
                    ? NetworkImage(activeDevice.profilePhotoUrl)
                    : null,
                radius: 16,
                child: activeDevice.profilePhotoUrl.isEmpty
                    ? const Icon(Icons.device_hub, size: 16)
                    : null,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      activeDevice.name,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    Builder(
                      builder: (context) {
                        final connStatus = deviceProvider.getDeviceConnectionStatus(activeDevice.id);
                        final lastSeen = deviceProvider.getDeviceLastSeenIST(activeDevice.id);
                        
                        Color dotColor = Colors.red;
                        String statusLabel = 'Offline';
                        
                        if (connStatus == 'online') {
                          dotColor = Colors.green;
                          statusLabel = 'Online';
                        } else if (connStatus == 'connecting') {
                          dotColor = Colors.orange;
                          statusLabel = 'Connecting...';
                        } else if (lastSeen != null) {
                          statusLabel = 'Offline • $lastSeen';
                        }
                        
                        return Row(
                          children: [
                            Container(
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: dotColor,
                              ),
                            ),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                statusLabel,
                                style: const TextStyle(fontSize: 10, color: Colors.grey),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

      ),
      body: Column(
        children: [
          Expanded(
            child: Consumer<DeviceProvider>(
              builder: (context, provider, child) {
                final messages = provider.getMessagesForDevice(widget.device.id);
                return ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.all(16),
                  itemCount: messages.length,
                  itemBuilder: (context, index) {
                    final msg = messages[index];
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
                        child: _buildFormattedMessage(context, msg.text, msg.isUser),
                      ),
                    );
                  },
                );
              },
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            height: 50,
            child: Consumer<DeviceProvider>(
              builder: (context, provider, child) {
                final commands = provider.getQuickCommands(widget.device.id);
                return ListView(
                  scrollDirection: Axis.horizontal,
                  children: [
                    // circular add button to create custom commands
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Material(
                        color: Theme.of(context).colorScheme.primaryContainer,
                        shape: const CircleBorder(),
                        child: IconButton(
                          icon: Icon(Icons.add, size: 18, color: Theme.of(context).colorScheme.onPrimaryContainer),
                          onPressed: () => _showAddCommandDialog(provider),
                          constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
                          padding: EdgeInsets.zero,
                        ),
                      ),
                    ),
                    ...commands.asMap().entries.map((entry) {
                      final command = entry.value;
                      return Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: Material(
                          color: Theme.of(context).colorScheme.secondaryContainer,
                          shape: const StadiumBorder(),
                          child: InkWell(
                            onTap: () => _sendMessage(command.message),
                            onLongPress: () {
                              if (provider.isCustomCommand(widget.device.id, command)) {
                                _showDeleteCommandDialog(provider, command);
                              } else {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('Only custom buttons can be deleted.'),
                                    duration: Duration(seconds: 2),
                                  ),
                                );
                              }
                            },
                            customBorder: const StadiumBorder(),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                              child: Center(
                                child: Text(
                                  command.label,
                                  style: TextStyle(color: Theme.of(context).colorScheme.onSecondaryContainer),
                                ),
                              ),
                            ),
                          ),
                        ),
                      );
                    }),
                  ],
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
                      controller: _messageController,
                      decoration: InputDecoration(
                        hintText: 'Type a message...',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                        ),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      ),
                      onSubmitted: (_) => _sendMessage(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  CircleAvatar(
                    radius: 24,
                    backgroundColor: Theme.of(context).colorScheme.primary,
                    child: IconButton(
                      icon: const Icon(Icons.send, color: Colors.white),
                      onPressed: () => _sendMessage(),
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
