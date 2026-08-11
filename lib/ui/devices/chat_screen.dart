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
          0.0,
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
                  labelText: 'Button Label',
                  labelStyle: TextStyle(fontSize: 12, fontStyle: FontStyle.italic),
                  hintText: 'Enter text displayed on button',
                  hintStyle: TextStyle(fontSize: 12, fontStyle: FontStyle.italic),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: messageController,
                decoration: const InputDecoration(
                  labelText: 'Command',
                  labelStyle: TextStyle(fontSize: 12, fontStyle: FontStyle.italic),
                  hintText: 'Enter text sent to device',
                  hintStyle: TextStyle(fontSize: 12, fontStyle: FontStyle.italic),
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

  void _showEditCommandDialog(DeviceProvider provider, QuickCommandModel command) {
    final labelController = TextEditingController(text: command.label);
    final messageController = TextEditingController(text: command.message);

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Edit Custom Button'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: labelController,
                decoration: const InputDecoration(
                  labelText: 'Button Label',
                  labelStyle: TextStyle(fontSize: 12, fontStyle: FontStyle.italic),
                  hintText: 'Enter text displayed on button',
                  hintStyle: TextStyle(fontSize: 12, fontStyle: FontStyle.italic),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: messageController,
                decoration: const InputDecoration(
                  labelText: 'Command',
                  labelStyle: TextStyle(fontSize: 12, fontStyle: FontStyle.italic),
                  hintText: 'Enter text sent to device',
                  hintStyle: TextStyle(fontSize: 12, fontStyle: FontStyle.italic),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                provider.deleteDeviceQuickCommand(widget.device.id, command);
                Navigator.pop(context);
              },
              child: const Text('Delete', style: TextStyle(color: Colors.red)),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                final label = labelController.text.trim();
                final message = messageController.text.trim();
                if (label.isNotEmpty && message.isNotEmpty) {
                  provider.editDeviceQuickCommand(
                    widget.device.id,
                    command,
                    QuickCommandModel(label: label, message: message),
                  );
                  Navigator.pop(context);
                }
              },
              child: const Text('Save'),
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

    final List<String> lines = text.split('\n');
    final List<Widget> widgets = [];
    
    for (int i = 0; i < lines.length; i++) {
      final line = lines[i];
      
      if (line.trim().isEmpty) {
        widgets.add(const SizedBox(height: 6));
        continue;
      }
      
      if (line.startsWith('/')) {
        final index = line.indexOf(' : ');
        final String cmd = index != -1 ? line.substring(0, index) : line;
        final String desc = index != -1 ? line.substring(index) : '';
        
        widgets.add(
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: InkWell(
              onTap: () => _sendMessage(cmd),
              borderRadius: BorderRadius.circular(4),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 4),
                child: RichText(
                  text: TextSpan(
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 13,
                      height: 1.3,
                    ),
                    children: [
                      TextSpan(
                        text: cmd,
                        style: TextStyle(
                          color: isDark ? const Color(0xFF4ADE80) : const Color(0xFF00A884), 
                          fontWeight: FontWeight.bold,
                          decoration: TextDecoration.underline,
                        ),
                      ),
                      TextSpan(
                        text: desc,
                        style: TextStyle(color: isDark ? Colors.grey[400] : Colors.grey[600]),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
        continue;
      }

      final List<TextSpan> spans = [];
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
      } else {
        spans.add(TextSpan(
          text: line,
          style: TextStyle(color: isDark ? Colors.white : Colors.black87),
        ));
      }

      widgets.add(
        RichText(
          text: TextSpan(
            style: TextStyle(
              fontFamily: 'monospace',
              fontSize: 13,
              height: 1.3,
              color: isDark ? Colors.white : Colors.black87,
            ),
            children: spans,
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: widgets,
    );
  }

  Widget _buildWelcomeView(BuildContext context, DeviceModel activeDevice, DeviceProvider provider) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final connStatus = provider.getDeviceConnectionStatus(activeDevice.id);
    final isLive = connStatus == 'online';
    
    final initials = activeDevice.name.trim().isNotEmpty
        ? activeDevice.name.trim().split(' ').map((e) => e[0]).take(2).join().toUpperCase()
        : 'DV';

    return Center(
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              CircleAvatar(
                radius: 54,
                backgroundColor: isDark 
                    ? theme.colorScheme.surfaceContainerHighest 
                    : theme.colorScheme.surfaceVariant,
                child: Text(
                  initials,
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Text(
                'Start chat with ${activeDevice.name}',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white : Colors.black87,
                ),
              ),
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                child: Text(
                  'Request a live status report to see device data\nand available commands.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13,
                    color: isDark ? Colors.grey[400] : Colors.grey[600],
                    height: 1.4,
                  ),
                ),
              ),
              const SizedBox(height: 32),
              ElevatedButton.icon(
                onPressed: isLive ? () => _sendMessage('/status') : null,
                icon: const Icon(Icons.show_chart_rounded, size: 20),
                label: const Text(
                  'Get device status',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                ),
                style: ElevatedButton.styleFrom(
                  foregroundColor: Colors.white,
                  backgroundColor: const Color(0xFF00A884),
                  disabledForegroundColor: isDark ? Colors.grey[600] : Colors.grey[400],
                  disabledBackgroundColor: isDark 
                      ? theme.colorScheme.surfaceContainerHighest 
                      : theme.colorScheme.surfaceVariant,
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(24),
                  ),
                ),
              ),
              if (!isLive) ...[
                const SizedBox(height: 16),
                Text(
                  connStatus == 'connecting' ? 'Connecting...' : 'Waiting for connection...',
                  style: TextStyle(
                    fontSize: 12,
                    fontStyle: FontStyle.italic,
                    color: isDark ? Colors.grey[500] : Colors.grey[500],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
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
                radius: 16,
                backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                backgroundImage: activeDevice.profilePhotoUrl.isNotEmpty
                    ? NetworkImage(activeDevice.profilePhotoUrl) as ImageProvider
                    : const AssetImage('assets/ionet_logo.png'),
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
      body: Consumer<DeviceProvider>(
        builder: (context, provider, child) {
          final messages = provider.getMessagesForDevice(widget.device.id);
          final connStatus = provider.getDeviceConnectionStatus(activeDevice.id);
          final isLive = connStatus == 'online';
          
          return Column(
            children: [
              Expanded(
                child: messages.isEmpty
                    ? _buildWelcomeView(context, activeDevice, provider)
                    : ListView.builder(
                        controller: _scrollController,
                        reverse: true,
                        padding: const EdgeInsets.all(16),
                        itemCount: messages.length,
                        itemBuilder: (context, index) {
                          final reversed = messages.reversed.toList();
                          final msg = reversed[index];
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
                      ),
              ),
              if (messages.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  height: 42,
                  child: Builder(
                    builder: (context) {
                      final commands = provider.getQuickCommands(widget.device.id);
                      return ListView(
                        scrollDirection: Axis.horizontal,
                        children: [
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            child: Material(
                              color: Theme.of(context).colorScheme.primaryContainer,
                              shape: const CircleBorder(),
                              child: IconButton(
                                icon: Icon(Icons.add, size: 16, color: Theme.of(context).colorScheme.onPrimaryContainer),
                                onPressed: () => _showAddCommandDialog(provider),
                                constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
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
                                      _showEditCommandDialog(provider, command);
                                    } else {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(
                                          content: Text('Only custom buttons can be edited.'),
                                          duration: Duration(seconds: 2),
                                        ),
                                      );
                                    }
                                  },
                                  customBorder: const StadiumBorder(),
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                    child: Center(
                                      child: Text(
                                        command.label,
                                        style: TextStyle(
                                          color: Theme.of(context).colorScheme.onSecondaryContainer,
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            );
                          }),
                        ],
                      );
                    }
                  ),
                ),
              SafeArea(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _messageController,
                          decoration: InputDecoration(
                            hintText: 'Send command...',
                            prefixIcon: IconButton(
                              icon: Icon(
                                Icons.show_chart_rounded,
                                color: isLive 
                                    ? const Color(0xFF00A884) 
                                    : (isDark ? Colors.grey[600] : Colors.grey[400]),
                                size: 22,
                              ),
                              onPressed: isLive ? () => _sendMessage('/status') : null,
                              tooltip: 'Get device status',
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(24),
                            ),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                          ),
                          onSubmitted: (_) => _sendMessage(),
                        ),
                      ),
                      const SizedBox(width: 8),
                      CircleAvatar(
                        radius: 22,
                        backgroundColor: isLive 
                            ? const Color(0xFF00A884)
                            : (isDark ? theme.colorScheme.surfaceContainerHighest : theme.colorScheme.surfaceVariant),
                        child: IconButton(
                          icon: Icon(
                            Icons.send, 
                            color: isLive ? Colors.white : (isDark ? Colors.grey[600] : Colors.grey[400]), 
                            size: 18,
                          ),
                          onPressed: isLive ? () => _sendMessage() : null,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }


}
