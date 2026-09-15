import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/providers/device_provider.dart';
import '../../core/utils/app_feedback.dart';
import '../../data/models/device_model.dart';
import '../../data/models/message_model.dart';
import '../../data/models/quick_command_model.dart';
import 'device_profile_screen.dart';

class ChatScreen extends StatefulWidget {
  final DeviceModel device;
  const ChatScreen({super.key, required this.device});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> with WidgetsBindingObserver {
  final _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  void _sendMessage([String? text, String? displayText]) {
    final message = text ?? _messageController.text.trim();
    if (message.isEmpty) return;

    Provider.of<DeviceProvider>(context, listen: false)
        .sendMessage(widget.device.id, message, displayText: displayText);
    
    _messageController.clear();
    _scrollToBottom();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
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
    WidgetsBinding.instance.removeObserver(this);
    Provider.of<DeviceProvider>(context, listen: false).disconnectWebSocket(intentional: true);
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    final provider = Provider.of<DeviceProvider>(context, listen: false);
    if (state == AppLifecycleState.resumed) {
      final status = provider.getDeviceConnectionStatus(widget.device.id);
      if (status != 'online' && status != 'connecting') {
        debugPrint('[LIFECYCLE RESUMED] Reconnecting WebSocket for device ${widget.device.id}');
        provider.connectWebSocket(widget.device.id);
      }
    } else if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
      debugPrint('[LIFECYCLE BACKGROUNDED] Suspending WebSocket for device ${widget.device.id}');
      provider.disconnectWebSocket(intentional: false);
    }
  }

  Future<void> _handleRefresh(DeviceProvider provider, DeviceModel activeDevice) async {
    final status = provider.getDeviceConnectionStatus(activeDevice.id);
    if (status != 'online') {
      provider.connectWebSocket(activeDevice.id);
      await Future.delayed(const Duration(milliseconds: 600));
    }
    provider.sendMessage(activeDevice.id, '/status', displayText: 'Get device status');
    await provider.fetchDeviceById(activeDevice.id);
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



  void _showEditCommandDialog(DeviceProvider provider, QuickCommandModel command) {
    showDialog(
      context: context,
      builder: (context) => EditCustomCommandDialog(
        provider: provider,
        deviceId: widget.device.id,
        command: command,
      ),
    );
  }

  List<TextSpan> buildColoredSpans(String text, bool isDark, TextStyle defaultStyle) {
    final List<TextSpan> spans = [];
    final RegExp regExp = RegExp(r'\b(on|off)\b', caseSensitive: false);
    
    int start = 0;
    final matches = regExp.allMatches(text);
    
    for (final match in matches) {
      if (match.start > start) {
        spans.add(TextSpan(
          text: text.substring(start, match.start),
          style: defaultStyle,
        ));
      }
      
      final word = match.group(0)!;
      final isOn = word.toLowerCase() == 'on';
      final color = isOn
          ? (isDark ? const Color(0xFF4ADE80) : const Color(0xFF16A34A))
          : (isDark ? const Color(0xFFF87171) : const Color(0xFFDC2626));
          
      spans.add(TextSpan(
        text: word,
        style: defaultStyle.copyWith(
          color: color,
          fontWeight: FontWeight.bold,
        ),
      ));
      
      start = match.end;
    }
    
    if (start < text.length) {
      spans.add(TextSpan(
        text: text.substring(start),
        style: defaultStyle,
      ));
    }
    
    return spans;
  }

  Widget _buildFormattedMessage(BuildContext context, String text, bool isUser) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    
    if (isUser) {
      return Text.rich(
        TextSpan(
          style: TextStyle(
            color: theme.colorScheme.onPrimary,
            fontSize: 13,
          ),
          children: buildColoredSpans(text, isDark, TextStyle(color: theme.colorScheme.onPrimary, fontSize: 13)),
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
      
      // Skip available commands from displaying in message bubble
      if (line.startsWith('/')) {
        continue;
      }

      // Skip Device ID from displaying at message start
      if (line.toLowerCase().startsWith('device id')) {
        continue;
      }

      final List<TextSpan> spans = [];
      if (line.startsWith('Firmware:')) {
        final parts = line.split('Firmware:');
        spans.add(TextSpan(
          text: 'Firmware: ',
          style: TextStyle(color: isDark ? Colors.grey[400] : Colors.grey[600]),
        ));
        spans.addAll(buildColoredSpans(parts.length > 1 ? parts[1] : '', isDark, TextStyle(color: isDark ? Colors.white : Colors.black)));
      } else if (line.contains('Status:')) {
        final index = line.indexOf(':');
        if (index != -1) {
          final prefix = line.substring(0, index + 1);
          final suffix = line.substring(index + 1);
          spans.add(TextSpan(
            text: prefix,
            style: TextStyle(color: isDark ? Colors.grey[400] : Colors.grey[600]),
          ));
          
          spans.addAll(buildColoredSpans(suffix, isDark, const TextStyle(
            fontWeight: FontWeight.bold,
          )));
        } else {
          spans.addAll(buildColoredSpans(line, isDark, TextStyle(color: isDark ? Colors.white : Colors.black)));
        }
      } else {
        spans.addAll(buildColoredSpans(line, isDark, TextStyle(color: isDark ? Colors.white : Colors.black87)));
      }

      widgets.add(
        Text.rich(
          TextSpan(
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

    if (widgets.isEmpty && text.trim().isNotEmpty) {
      return Text(
        text,
        style: TextStyle(
          fontFamily: 'monospace',
          fontSize: 13,
          color: isDark ? Colors.white : Colors.black87,
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: widgets,
    );
  }

  bool _isReadOnlyKey(String key) {
    final lower = key.toLowerCase();
    return lower.contains('version') ||
        lower.contains('firmware') ||
        lower == 'id' ||
        lower == 'deviceid' ||
        lower == 'timestamp' ||
        lower.contains('command');
  }

  String _formatKeyLabel(String key) {
    final withSpaces = key
        .replaceAllMapped(RegExp(r'([a-z])([A-Z])'), (m) => '${m.group(1)} ${m.group(2)}')
        .replaceAll('_', ' ');
    return withSpaces
        .split(' ')
        .map((word) => word.isNotEmpty ? '${word[0].toUpperCase()}${word.substring(1)}' : '')
        .join(' ');
  }

  Widget _buildResponseMessageBubble(BuildContext context, MessageModel msg) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final isSuccess = msg.isSuccess == true;
    final color = isSuccess
        ? (isDark ? const Color(0xFF4ADE80) : const Color(0xFF16A34A))
        : (isDark ? const Color(0xFFF87171) : const Color(0xFFDC2626));
    final bgColor = isSuccess
        ? (isDark ? const Color(0xFF064E3B).withValues(alpha: 0.3) : const Color(0xFFDCFCE7))
        : (isDark ? const Color(0xFF7F1D1D).withValues(alpha: 0.3) : const Color(0xFFFEE2E2));

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isSuccess ? Icons.check_circle_rounded : Icons.error_outline_rounded,
            size: 18,
            color: color,
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              msg.text,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDataTableCard(
    BuildContext context,
    DeviceProvider provider,
    DeviceModel activeDevice,
    MessageModel msg,
  ) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final data = msg.rawData ?? {};
    final isLive = provider.getDeviceConnectionStatus(activeDevice.id) == 'online';

    IconData headerIcon = Icons.show_chart_rounded;
    String headerTitle = 'Device Status';
    Widget? headerBadge;

    if (msg.isEditable) {
      headerIcon = Icons.tune_rounded;
      headerTitle = 'Device Holding Registers';
      if (activeDevice.isOwner) {
        headerBadge = Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: const Color(0xFF00A884).withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(6),
          ),
          child: const Text(
            'Single-Reg Write',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: Color(0xFF00A884),
            ),
          ),
        );
      }
    } else if (msg.command == '/about' ||
        msg.text.toLowerCase().contains('hardwareversion') ||
        msg.text.toLowerCase().contains('firmware')) {
      headerIcon = Icons.info_outline_rounded;
      headerTitle = 'Device Information';
      headerBadge = Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: Colors.blue.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(6),
        ),
        child: const Text(
          'About',
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w600,
            color: Colors.blue,
          ),
        ),
      );
    } else {
      headerIcon = Icons.analytics_outlined;
      headerTitle = 'Device Status';
      headerBadge = Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: const Color(0xFF00A884).withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 5,
              height: 5,
              decoration: const BoxDecoration(
                color: Color(0xFF00A884),
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 4),
            const Text(
              'Telemetry',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: Color(0xFF00A884),
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      constraints: const BoxConstraints(maxWidth: 360),
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E2630) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? Colors.white.withValues(alpha: 0.08) : Colors.black.withValues(alpha: 0.08),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.06),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: isDark
                  ? const Color(0xFF00A884).withValues(alpha: 0.12)
                  : const Color(0xFF00A884).withValues(alpha: 0.08),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(15)),
            ),
            child: Row(
              children: [
                Icon(
                  headerIcon,
                  color: const Color(0xFF00A884),
                  size: 18,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    headerTitle,
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.white : Colors.black87,
                    ),
                  ),
                ),
                ?headerBadge,
              ],
            ),
          ),
          ListView.separated(
            padding: const EdgeInsets.symmetric(vertical: 4),
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: data.length,
            separatorBuilder: (context, idx) => Divider(
              height: 1,
              thickness: 0.5,
              color: isDark ? Colors.white10 : Colors.black12,
            ),
            itemBuilder: (context, index) {
              final key = data.keys.elementAt(index);
              final val = data[key];
              final isReadOnly = _isReadOnlyKey(key);
              final formattedLabel = _formatKeyLabel(key);
              final valStr = val?.toString() ?? '';
              final isOn = valStr.toLowerCase() == 'on';
              final isOff = valStr.toLowerCase() == 'off';

              Color? valColor;
              if (isOn) {
                valColor = isDark ? const Color(0xFF4ADE80) : const Color(0xFF16A34A);
              } else if (isOff) {
                valColor = isDark ? const Color(0xFFF87171) : const Color(0xFFDC2626);
              }

              final canEditThisRow = msg.isEditable && activeDevice.isOwner && !isReadOnly && isLive;

              return Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: canEditThisRow
                      ? () => _showEditRegisterDialog(context, provider, activeDevice.id, key, val)
                      : null,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                formattedLabel,
                                style: TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w500,
                                  color: isDark ? Colors.grey[300] : Colors.grey[800],
                                ),
                              ),
                              if (msg.isEditable)
                                Text(
                                  key,
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontFamily: 'monospace',
                                    color: isDark ? Colors.grey[500] : Colors.grey[500],
                                  ),
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: isDark
                                ? theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5)
                                : Colors.grey[100],
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: valColor?.withValues(alpha: 0.4) ??
                                  (isDark ? Colors.white10 : Colors.black12),
                            ),
                          ),
                          child: Text(
                            valStr,
                            style: TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: valColor ?? (isDark ? Colors.white : Colors.black87),
                            ),
                          ),
                        ),
                        if (canEditThisRow) ...[
                          const SizedBox(width: 6),
                          Icon(
                            Icons.edit_outlined,
                            size: 15,
                            color: isLive
                                ? const Color(0xFF00A884)
                                : (isDark ? Colors.grey[600] : Colors.grey[400]),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  void _showEditRegisterDialog(
    BuildContext context,
    DeviceProvider provider,
    String deviceId,
    String key,
    dynamic rawValue,
  ) {
    final strVal = rawValue?.toString() ?? '';
    final isAlarmOrBool = strVal.toLowerCase() == 'on' || strVal.toLowerCase() == 'off';
    
    // Extract number and unit
    String initialNumber = strVal;
    String unit = '';
    final match = RegExp(r'^(-?\d+(?:\.\d+)?)\s*(.*)$').firstMatch(strVal.trim());
    if (match != null && match.group(1) != null) {
      initialNumber = match.group(1)!;
      unit = match.group(2) ?? '';
    }

    final controller = TextEditingController(text: initialNumber);
    String selectedAlarm = strVal.toLowerCase() == 'off' ? 'Off' : 'On';

    showDialog(
      context: context,
      builder: (dialogContext) {
        final theme = Theme.of(dialogContext);
        final isDark = theme.brightness == Brightness.dark;
        final formattedLabel = _formatKeyLabel(key);

        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
              titlePadding: const EdgeInsets.fromLTRB(20, 18, 20, 10),
              contentPadding: const EdgeInsets.fromLTRB(20, 10, 20, 16),
              title: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: const Color(0xFF00A884).withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.edit_rounded, color: Color(0xFF00A884), size: 18),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Edit $formattedLabel',
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          'Register: $key',
                          style: TextStyle(
                            fontSize: 11,
                            fontFamily: 'monospace',
                            color: isDark ? Colors.grey[400] : Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    margin: const EdgeInsets.only(bottom: 14),
                    decoration: BoxDecoration(
                      color: isDark
                          ? theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4)
                          : Colors.grey[100],
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Current Value:',
                          style: TextStyle(
                            fontSize: 12,
                            color: isDark ? Colors.grey[400] : Colors.grey[600],
                          ),
                        ),
                        Text(
                          strVal,
                          style: const TextStyle(
                            fontSize: 12,
                            fontFamily: 'monospace',
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (isAlarmOrBool) ...[
                    const Text(
                      'Select State:',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: InkWell(
                            borderRadius: BorderRadius.circular(10),
                            onTap: () {
                              setDialogState(() => selectedAlarm = 'On');
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 10),
                              decoration: BoxDecoration(
                                color: selectedAlarm == 'On'
                                    ? const Color(0xFF00A884).withValues(alpha: 0.18)
                                    : Colors.transparent,
                                border: Border.all(
                                  color: selectedAlarm == 'On'
                                      ? const Color(0xFF00A884)
                                      : (isDark ? Colors.white12 : Colors.black12),
                                  width: selectedAlarm == 'On' ? 1.6 : 1,
                                ),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              alignment: Alignment.center,
                              child: Text(
                                'On',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: selectedAlarm == 'On'
                                      ? (isDark ? const Color(0xFF4ADE80) : const Color(0xFF16A34A))
                                      : (isDark ? Colors.grey[400] : Colors.grey[600]),
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: InkWell(
                            borderRadius: BorderRadius.circular(10),
                            onTap: () {
                              setDialogState(() => selectedAlarm = 'Off');
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 10),
                              decoration: BoxDecoration(
                                color: selectedAlarm == 'Off'
                                    ? Colors.redAccent.withValues(alpha: 0.18)
                                    : Colors.transparent,
                                border: Border.all(
                                  color: selectedAlarm == 'Off'
                                      ? Colors.redAccent
                                      : (isDark ? Colors.white12 : Colors.black12),
                                  width: selectedAlarm == 'Off' ? 1.6 : 1,
                                ),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              alignment: Alignment.center,
                              child: Text(
                                'Off',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: selectedAlarm == 'Off'
                                      ? (isDark ? const Color(0xFFF87171) : const Color(0xFFDC2626))
                                      : (isDark ? Colors.grey[400] : Colors.grey[600]),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ] else ...[
                    TextField(
                      controller: controller,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                      autofocus: true,
                      decoration: InputDecoration(
                        labelText: 'New Value',
                        suffixText: unit.isNotEmpty ? unit : null,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      ),
                    ),
                  ],
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    FocusManager.instance.primaryFocus?.unfocus();
                    Navigator.pop(dialogContext);
                  },
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () {
                    dynamic valToSend;
                    if (isAlarmOrBool) {
                      valToSend = selectedAlarm;
                    } else {
                      final input = controller.text.trim();
                      if (input.isEmpty) return;
                      final asInt = int.tryParse(input);
                      final asDouble = double.tryParse(input);
                      if (asInt != null) {
                        valToSend = asInt;
                      } else if (asDouble != null) {
                        valToSend = asDouble;
                      } else {
                        valToSend = input;
                      }
                    }

                    provider.writeSingleRegister(deviceId, key, valToSend);
                    FocusManager.instance.primaryFocus?.unfocus();
                    Navigator.pop(dialogContext);
                    AppFeedback.showSuccess(context, 'Write command sent for $formattedLabel');
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF00A884),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  child: const Text('Write'),
                ),
              ],
            );
          },
        );
      },
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

    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: IntrinsicHeight(
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
                          : theme.colorScheme.surfaceContainerHighest,
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
                      onPressed: isLive ? () => _sendMessage('/status', 'Get device status') : null,
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
                            : theme.colorScheme.surfaceContainerHighest,
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
          ),
        );
      },
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

    final allCommands = deviceProvider.getQuickCommands(activeDevice.id);
    QuickCommandModel? settingsCommand;
    for (final cmd in allCommands) {
      final msg = cmd.message.trim().toLowerCase();
      if (msg == '/holding' ||
          msg == '/setting' ||
          msg == '/settings' ||
          msg.startsWith('/holding ') ||
          msg.startsWith('/setting ') ||
          msg.startsWith('/settings ')) {
        settingsCommand = cmd;
        break;
      }
    }
    final bool hasSettingsCommand = settingsCommand != null;

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
                        } else {
                          statusLabel = 'Offline • Tap to retry';
                        }
                        
                        return InkWell(
                          borderRadius: BorderRadius.circular(4),
                          onTap: (connStatus == 'online' || connStatus == 'connecting')
                              ? null
                              : () {
                                  deviceProvider.connectWebSocket(activeDevice.id);
                                },
                          child: Row(
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
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
          if (activeDevice.isOwner)
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert),
              onSelected: (value) {
                if (value == 'settings') {
                  final status = deviceProvider.getDeviceConnectionStatus(activeDevice.id);
                  if (status != 'online') {
                    deviceProvider.connectWebSocket(activeDevice.id);
                  }
                  final cmdToSend = settingsCommand?.message ?? '/holding';
                  final labelToSend = (settingsCommand != null && settingsCommand.label.trim().isNotEmpty)
                      ? settingsCommand.label.trim()
                      : 'Get device settings';
                  _sendMessage(cmdToSend, labelToSend);
                } else if (value == 'config') {
                  _showConfigurationDialog(context, deviceProvider, activeDevice);
                } else if (value == 'wifi_setup') {
                  _showWifiSetupDialog(context, deviceProvider, activeDevice);
                }
              },
              itemBuilder: (context) => [
                if (hasSettingsCommand)
                  const PopupMenuItem<String>(
                    value: 'settings',
                    child: Row(
                      children: [
                        Icon(Icons.tune_rounded, size: 20, color: Color(0xFF00A884)),
                        SizedBox(width: 8),
                        Text('Settings'),
                      ],
                    ),
                  ),
                const PopupMenuItem<String>(
                  value: 'config',
                  child: Row(
                    children: [
                      Icon(Icons.settings_outlined, size: 20),
                      SizedBox(width: 8),
                      Text('Configuration'),
                    ],
                  ),
                ),
                const PopupMenuItem<String>(
                  value: 'wifi_setup',
                  child: Row(
                    children: [
                      Icon(Icons.wifi, size: 20),
                      SizedBox(width: 8),
                      Text('Wi-Fi Setup'),
                    ],
                  ),
                ),
              ],
            ),
        ],
      ),
      body: Consumer<DeviceProvider>(
        builder: (context, provider, child) {
          final messages = provider.getMessagesForDevice(widget.device.id);
          final connStatus = provider.getDeviceConnectionStatus(activeDevice.id);
          final isLive = connStatus == 'online';
          
          return Column(
            children: [
              Expanded(
                child: RefreshIndicator(
                  color: const Color(0xFF00A884),
                  onRefresh: () => _handleRefresh(provider, activeDevice),
                  child: messages.isEmpty
                      ? _buildWelcomeView(context, activeDevice, provider)
                      : ListView.builder(
                          physics: const AlwaysScrollableScrollPhysics(),
                          controller: _scrollController,
                          reverse: true,
                          padding: const EdgeInsets.all(16),
                          itemCount: messages.length,
                          itemBuilder: (context, index) {
                            final msg = messages[messages.length - 1 - index];
                            final isResendable = msg.isUser &&
                                msg.command != '/write_single_reg' &&
                                !msg.text.startsWith('Sent Configuration:') &&
                                !msg.text.startsWith('Sent Wi-Fi Setup:') &&
                                !msg.text.startsWith('Set ');

                            if (!msg.isUser && msg.rawData != null && msg.rawData!.isNotEmpty) {
                              return Align(
                                alignment: Alignment.centerLeft,
                                child: _buildDataTableCard(context, provider, activeDevice, msg),
                              );
                            }

                            if (!msg.isUser && msg.isSuccess != null) {
                              return Align(
                                alignment: Alignment.centerLeft,
                                child: _buildResponseMessageBubble(context, msg),
                              );
                            }

                            return Align(
                              alignment: msg.isUser ? Alignment.centerRight : Alignment.centerLeft,
                              child: Container(
                                margin: const EdgeInsets.only(bottom: 8),
                                child: Material(
                                  color: msg.isUser 
                                      ? Theme.of(context).colorScheme.primary 
                                      : Theme.of(context).colorScheme.surfaceContainerHighest,
                                  borderRadius: BorderRadius.circular(20),
                                  clipBehavior: Clip.antiAlias,
                                  child: InkWell(
                                    onTap: isResendable
                                        ? () {
                                            final cmd = msg.command ?? msg.text;
                                            final display = msg.text;
                                            _sendMessage(cmd, display);
                                            ScaffoldMessenger.of(context).hideCurrentSnackBar();
                                          }
                                        : null,
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        crossAxisAlignment: CrossAxisAlignment.center,
                                        children: [
                                          Flexible(
                                            child: _buildFormattedMessage(context, msg.text, msg.isUser),
                                          ),
                                          if (isResendable) ...[
                                            const SizedBox(width: 6),
                                            Icon(
                                              Icons.replay_rounded,
                                              size: 13,
                                              color: theme.colorScheme.onPrimary.withValues(alpha: 0.7),
                                            ),
                                          ],
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
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
                              onPressed: isLive ? () => _sendMessage('/status', 'Get device status') : null,
                              tooltip: 'Get device status',
                            ),
                            suffixIcon: IconButton(
                              icon: const Icon(Icons.bolt_rounded, color: Color(0xFF00A884)),
                              tooltip: 'Quick Commands',
                              onPressed: () => _showCommandPaletteBottomSheet(context, provider),
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
                            : (isDark ? theme.colorScheme.surfaceContainerHighest : theme.colorScheme.surfaceContainerHighest),
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

  void _showConfigurationDialog(BuildContext context, DeviceProvider provider, DeviceModel activeDevice) {
    showDialog(
      context: context,
      builder: (context) {
        return DeviceConfigDialog(
          provider: provider,
          device: activeDevice,
        );
      },
    );
  }

  void _showWifiSetupDialog(BuildContext context, DeviceProvider provider, DeviceModel activeDevice) {
    showDialog(
      context: context,
      builder: (context) {
        return WifiSetupDialog(
          provider: provider,
          device: activeDevice,
        );
      },
    );
  }

  void _showCommandPaletteBottomSheet(BuildContext context, DeviceProvider provider) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: false,
      backgroundColor: Colors.transparent,
      builder: (bottomSheetContext) {
        final theme = Theme.of(bottomSheetContext);
        final isDark = theme.brightness == Brightness.dark;
        final deviceCommands = provider.getDeviceCommands(widget.device.id);
        final customCommands = provider.getCustomCommands(widget.device.id);

        return Container(
          margin: const EdgeInsets.only(left: 12, right: 12, bottom: 16),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1E2630) : Colors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.4 : 0.12),
                blurRadius: 18,
                offset: const Offset(0, -2),
              ),
            ],
          ),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Minimal Header
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 14, 18, 10),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.bolt_rounded,
                        color: Color(0xFF00A884),
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      const Text(
                        'Quick Commands',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1, thickness: 0.6),
                // Compact list area
                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // 1. Device Commands (labels only, no command strings)
                        ...deviceCommands.map((command) {
                          return _buildMinimalCommandTile(
                            context: bottomSheetContext,
                            command: command,
                            isCustom: false,
                            isDark: isDark,
                            onTap: () {
                              Navigator.pop(bottomSheetContext);
                              _sendMessage(command.message, command.label);
                            },
                          );
                        }),
                        // 2. Custom Buttons (at the end)
                        ...customCommands.map((command) {
                          return _buildMinimalCommandTile(
                            context: bottomSheetContext,
                            command: command,
                            isCustom: true,
                            isDark: isDark,
                            onTap: () {
                              Navigator.pop(bottomSheetContext);
                              _sendMessage(command.message, command.label);
                            },
                            onEdit: () {
                              Navigator.pop(bottomSheetContext);
                              _showEditCommandDialog(provider, command);
                            },
                          );
                        }),
                        if (deviceCommands.isEmpty && customCommands.isEmpty)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 18),
                            child: Text(
                              'No commands available',
                              style: TextStyle(
                                fontSize: 13,
                                color: isDark ? Colors.grey[500] : Colors.grey[400],
                                fontStyle: FontStyle.italic,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildMinimalCommandTile({
    required BuildContext context,
    required QuickCommandModel command,
    required bool isCustom,
    required bool isDark,
    required VoidCallback onTap,
    VoidCallback? onEdit,
  }) {
    IconData icon = Icons.chevron_right_rounded;
    final lowerLabel = command.label.toLowerCase();
    final lowerMsg = command.message.toLowerCase();
    
    if (lowerLabel.contains('status') || lowerMsg.contains('status')) {
      icon = Icons.show_chart_rounded;
    } else if (lowerLabel.contains('reboot') || lowerMsg.contains('reboot')) {
      icon = Icons.restart_alt_rounded;
    } else if (lowerLabel.contains('diagnose') || lowerMsg.contains('diagnose')) {
      icon = Icons.healing_rounded;
    } else if (isCustom) {
      icon = Icons.touch_app_rounded;
    }

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 2, horizontal: 4),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          onLongPress: onEdit,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                Icon(
                  icon,
                  size: 18,
                  color: const Color(0xFF00A884),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    command.label,
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w500,
                      color: isDark ? Colors.white : Colors.black87,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (isCustom && onEdit != null)
                  InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: onEdit,
                    child: Padding(
                      padding: const EdgeInsets.all(4.0),
                      child: Icon(
                        Icons.edit_outlined,
                        size: 16,
                        color: isDark ? Colors.grey[400] : Colors.grey[500],
                      ),
                    ),
                  )
                else
                  Icon(
                    Icons.arrow_forward_ios_rounded,
                    size: 11,
                    color: isDark ? Colors.grey[600] : Colors.grey[400],
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class DeviceConfigDialog extends StatefulWidget {
  final DeviceProvider provider;
  final DeviceModel device;

  const DeviceConfigDialog({
    super.key,
    required this.provider,
    required this.device,
  });

  @override
  State<DeviceConfigDialog> createState() => _DeviceConfigDialogState();
}

class _DeviceConfigDialogState extends State<DeviceConfigDialog> {
  final List<ConfigItem> configItems = [];

  @override
  void initState() {
    super.initState();
    refillData();
  }

  void refillData() {
    for (final item in configItems) {
      item.dispose();
    }
    configItems.clear();

    final latestData = widget.provider.getLatestDeviceStatusData(widget.device.id);
    if (latestData != null && latestData.isNotEmpty) {
      latestData.forEach((key, val) {
        final isNA = key.toUpperCase().startsWith('NA');
        configItems.add(ConfigItem(key: key, value: isNA ? '' : key));
      });
    }
  }

  @override
  void dispose() {
    for (final item in configItems) {
      item.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return AlertDialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: const Color(0xFF00A884).withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.tune_rounded, color: Color(0xFF00A884), size: 20),
          ),
          const SizedBox(width: 10),
          const Text('Device Configuration', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        ],
      ),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'TELEMETRY ITEMS',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.8,
                      color: isDark ? Colors.grey[400] : Colors.grey[600],
                    ),
                  ),
                  TextButton.icon(
                    onPressed: () {
                      setState(() {
                        refillData();
                      });
                    },
                    icon: const Icon(Icons.refresh, size: 16),
                    label: const Text('Reset', style: TextStyle(fontSize: 12)),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if (configItems.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 20.0),
                  child: Center(
                    child: Text(
                      'No status configuration data available.\nPlease query device status in the chat first.',
                      style: TextStyle(color: Colors.grey, fontSize: 13),
                      textAlign: TextAlign.center,
                    ),
                  ),
                )
              else
                ...configItems.map((item) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 14.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.key,
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 13.5,
                          ),
                        ),
                        const SizedBox(height: 6),
                        TextField(
                          controller: item.valueController,
                          decoration: InputDecoration(
                            hintText: 'Enter custom name for ${item.key}',
                            hintStyle: TextStyle(
                              fontSize: 12.5,
                              color: isDark ? Colors.grey[500] : Colors.grey[400],
                            ),
                            suffixIcon: item.valueController.text.isNotEmpty
                                ? IconButton(
                                    icon: const Icon(Icons.clear_rounded, size: 16),
                                    onPressed: () {
                                      setState(() {
                                        item.valueController.clear();
                                      });
                                    },
                                  )
                                : null,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                            isDense: true,
                          ),
                          style: const TextStyle(fontSize: 13.5),
                          onChanged: (_) {
                            setState(() {});
                          },
                        ),
                      ],
                    ),
                  );
                }),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () {
            FocusManager.instance.primaryFocus?.unfocus();
            Navigator.pop(context);
          },
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: configItems.isEmpty
              ? null
              : () {
                  final Map<String, dynamic> configData = {};
                  for (int i = 0; i < configItems.length; i++) {
                    final item = configItems[i];
                    final val = item.valueController.text.trim();
                    configData[item.key] = val.isNotEmpty ? val : item.key;
                  }

                  widget.provider.sendConfig(widget.device.id, configData);
                  
                  FocusManager.instance.primaryFocus?.unfocus();
                  Navigator.pop(context);
                  
                  AppFeedback.showSuccess(context, 'Configuration command sent successfully');
                },
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF00A884),
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
          child: const Text('Send'),
        ),
      ],
    );
  }
}

class ConfigItem {
  final String key;
  final TextEditingController valueController;

  ConfigItem({required this.key, required String value})
      : valueController = TextEditingController(text: value);

  void dispose() {
    valueController.dispose();
  }
}

class WifiSetupDialog extends StatefulWidget {
  final DeviceProvider provider;
  final DeviceModel device;

  const WifiSetupDialog({
    super.key,
    required this.provider,
    required this.device,
  });

  @override
  State<WifiSetupDialog> createState() => _WifiSetupDialogState();
}

class _WifiSetupDialogState extends State<WifiSetupDialog> {
  final _ssidController = TextEditingController();
  final _passController = TextEditingController();
  bool _obscurePassword = true;
  String? _ssidError;

  @override
  void dispose() {
    _ssidController.dispose();
    _passController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.wifi, color: Color(0xFF00A884)),
          SizedBox(width: 8),
          Text('Wi-Fi Setup'),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Enter the Wi-Fi credentials to configure on your device.',
              style: TextStyle(
                fontSize: 13,
                color: isDark ? Colors.grey[400] : Colors.grey[600],
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _ssidController,
              decoration: InputDecoration(
                labelText: 'Wi-Fi SSID',
                hintText: 'e.g. Home Network',
                prefixIcon: const Icon(Icons.wifi_rounded, size: 20),
                errorText: _ssidError,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              ),
              onChanged: (val) {
                if (_ssidError != null && val.trim().isNotEmpty) {
                  setState(() {
                    _ssidError = null;
                  });
                }
              },
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _passController,
              obscureText: _obscurePassword,
              decoration: InputDecoration(
                labelText: 'Wi-Fi Password',
                hintText: 'Enter network password',
                prefixIcon: const Icon(Icons.lock_outline_rounded, size: 20),
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscurePassword ? Icons.visibility_off : Icons.visibility,
                    size: 20,
                  ),
                  onPressed: () {
                    setState(() {
                      _obscurePassword = !_obscurePassword;
                    });
                  },
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () {
            FocusManager.instance.primaryFocus?.unfocus();
            Navigator.pop(context);
          },
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: () {
            final ssid = _ssidController.text.trim();
            final pass = _passController.text;

            if (ssid.isEmpty) {
              setState(() {
                _ssidError = 'SSID is required';
              });
              return;
            }

            widget.provider.sendWifiSetup(widget.device.id, ssid, pass);

            FocusManager.instance.primaryFocus?.unfocus();
            Navigator.pop(context);

            AppFeedback.showSuccess(context, 'Wi-Fi setup command sent successfully');
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF00A884),
            foregroundColor: Colors.white,
          ),
          child: const Text('Send'),
        ),
      ],
    );
  }
}

class EditCustomCommandDialog extends StatefulWidget {
  final DeviceProvider provider;
  final String deviceId;
  final QuickCommandModel command;

  const EditCustomCommandDialog({
    super.key,
    required this.provider,
    required this.deviceId,
    required this.command,
  });

  @override
  State<EditCustomCommandDialog> createState() => _EditCustomCommandDialogState();
}

class _EditCustomCommandDialogState extends State<EditCustomCommandDialog> {
  late final TextEditingController _labelController;
  late final TextEditingController _messageController;

  @override
  void initState() {
    super.initState();
    _labelController = TextEditingController(text: widget.command.label);
    _messageController = TextEditingController(text: widget.command.message);
  }

  @override
  void dispose() {
    _labelController.dispose();
    _messageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Edit Custom Button'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _labelController,
            decoration: const InputDecoration(
              labelText: 'Button Label',
              labelStyle: TextStyle(fontSize: 12, fontStyle: FontStyle.italic),
              hintText: 'Enter text displayed on button',
              hintStyle: TextStyle(fontSize: 12, fontStyle: FontStyle.italic),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _messageController,
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
            widget.provider.deleteDeviceQuickCommand(widget.deviceId, widget.command);
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
            final label = _labelController.text.trim();
            final message = _messageController.text.trim();
            if (label.isNotEmpty && message.isNotEmpty) {
              widget.provider.editDeviceQuickCommand(
                widget.deviceId,
                widget.command,
                QuickCommandModel(label: label, message: message),
              );
              Navigator.pop(context);
            }
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}

