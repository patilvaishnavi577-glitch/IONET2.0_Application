import 'dart:math' as math;
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
      provider.loadDeviceCommands(widget.device.id);
      provider.loadCustomCommands(widget.device.id);
      provider.loadRelayNamesFromPrefs(widget.device.id);
      provider.fetchDeviceDetails(widget.device.id);
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
      margin: const EdgeInsets.only(bottom: 6),
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

    final isNumeric = (msg.type != null && msg.type!.toUpperCase() == 'NUMERIC') ||
        msg.command == '/numeric' ||
        msg.command == '/write_register' ||
        msg.command == 'write_register';
    final isText = (msg.type != null && msg.type!.toUpperCase() == 'TEXT') ||
        msg.command == '/text';
    final isRadio = (msg.type != null && msg.type!.toUpperCase() == 'RADIO') ||
        msg.command == '/radio';
    final isClickable = (msg.type != null && msg.type!.toUpperCase() == 'CLICKABLE') ||
        msg.command == '/clickable';
    final titleLower = (msg.title ?? '').toLowerCase();
    final textLower = msg.text.toLowerCase();
    final cmdLower = (msg.command ?? '').toLowerCase();
    final isCheckMode = titleLower.contains('check mode') ||
        cmdLower.contains('check mode') ||
        cmdLower.contains('check_mode') ||
        (msg.type != null && msg.type!.toUpperCase() == 'CHECK_MODE') ||
        textLower.contains('check mode') ||
        (data.isNotEmpty && data.values.every((v) {
          final s = (v is Map ? v['value'] : v)?.toString().toLowerCase().trim() ?? '';
          return s.contains('on/off') || s.contains('rtc') || s.contains('cyclic') || s.contains('cdt') || s.contains('pulse');
        }));
    final isTimingOrRtc = !isCheckMode && ((msg.type != null && msg.type!.toUpperCase() == 'TIME') ||
        msg.command == '/time' ||
        titleLower.contains('on-off') ||
        titleLower.contains('on/off') ||
        titleLower.contains('timing') ||
        titleLower.contains('rtc') ||
        textLower.contains('on-off') ||
        textLower.contains('timing') ||
        textLower.contains('rtc'));
    final isCDT = !isCheckMode && !isTimingOrRtc &&
        ((msg.command == '/cdt') ||
        (msg.type != null && msg.type!.toUpperCase() == 'CDT') ||
        titleLower.contains('cdt') ||
        (titleLower.contains('off time') && !titleLower.contains('on-off') && !titleLower.contains('on/off')) ||
        textLower.contains('cdt') ||
        (textLower.contains('off time') && !textLower.contains('on-off') && !textLower.contains('on/off')));
    final isTime = !isCheckMode && (isTimingOrRtc ||
        (!isCDT &&
        ((msg.type != null && msg.type!.toUpperCase() == 'TIME') ||
        msg.command == '/time' ||
        titleLower.contains('time'))));
    final isCyclic = !isCheckMode && ((msg.type != null && msg.type!.toUpperCase() == 'CYCLIC') ||
        msg.command == '/cyclic');

    String? customTitle = (msg.title != null && msg.title!.trim().isNotEmpty && !msg.title!.trim().startsWith('Device '))
        ? msg.title!.trim()
        : null;

    if (customTitle == null &&
        msg.text.trim().isNotEmpty &&
        !msg.text.contains('\n') &&
        msg.text.trim().length < 100 &&
        !msg.text.trim().startsWith('Device ')) {
      customTitle = msg.text.trim();
    }

    customTitle ??= (msg.title != null && msg.title!.trim().isNotEmpty) ? msg.title!.trim() : null;

    if (isCheckMode) {
      headerTitle = 'Check Mode';
      headerIcon = Icons.rule_rounded;
      headerBadge = null;
    } else if (msg.isEditable) {
      final isSetting = msg.command == '/setting' || msg.command == '/settings';
      final String typeDisplay = (msg.type != null && msg.type!.isNotEmpty)
          ? '${msg.type![0].toUpperCase()}${msg.type!.substring(1).toLowerCase()}'
          : '';
      headerTitle = customTitle ??
          (typeDisplay.isNotEmpty
              ? 'Device $typeDisplay'
              : (isSetting
                  ? 'Device Setting'
                  : (isNumeric
                      ? 'Device Numeric Settings'
                      : (isText
                          ? 'Device Channels'
                          : (isRadio
                              ? 'Device Radio Options'
                              : (isClickable
                                  ? 'Device Clickable Actions'
                                  : (isTime
                                      ? 'Device Timings'
                                      : (isCyclic ? 'Set on-off minutes, e.g. 5-5' : 'Device Holding'))))))));

      final lowerTitle = headerTitle.toLowerCase();
      if (lowerTitle.contains('choose a relay') || (isClickable && lowerTitle.contains('relay'))) {
        headerIcon = Icons.grid_view_rounded;
      } else if (!isCDT && (isCyclic || lowerTitle.contains('cyclic') || lowerTitle.contains('minute') || lowerTitle.contains('on-off'))) {
        headerIcon = Icons.sync_rounded;
      } else if (isRadio) {
        headerIcon = Icons.radio_button_checked_rounded;
      } else if (!isCDT && (isTime || lowerTitle.contains('time'))) {
        headerIcon = Icons.schedule_rounded;
      } else {
        headerIcon = Icons.tune_rounded;
      }

      // Match Web UI (Image 2): "● Timings" badge for Timing card
      if (isTime) {
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
                'Timings',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF00A884),
                ),
              ),
            ],
          ),
        );
      } else {
        headerBadge = null;
      }
    } else if (msg.command == '/about' ||
        msg.text.toLowerCase().contains('hardwareversion') ||
        msg.text.toLowerCase().contains('firmware')) {
      headerIcon = Icons.info_outline_rounded;
      headerTitle = 'Device Information';
      headerBadge = null;
    } else {
      headerIcon = Icons.analytics_outlined;
      headerTitle = 'Device Status';
      headerBadge = null;
    }

    return Container(
      constraints: const BoxConstraints(maxWidth: 360),
      margin: const EdgeInsets.only(bottom: 8),
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
              final rawItem = data[key];
              dynamic val = rawItem;
              String? rangeStr;
              if (rawItem is Map) {
                val = rawItem['value'];
                rangeStr = rawItem['range']?.toString();
              }

              final isReadOnly = (rawItem is Map && rawItem.containsKey('readonly'))
                  ? (rawItem['readonly'] == true)
                  : ((rawItem is Map && rawItem.containsKey('editable'))
                      ? (rawItem['editable'] != true)
                      : _isReadOnlyKey(key));
              final formattedLabel = _formatKeyLabel(key);
              final isSetting = msg.command == '/setting' || msg.command == '/settings';
              final isText = (msg.type != null && msg.type!.toUpperCase() == 'TEXT') || msg.command == '/text';
              final isRadio = (msg.type != null && msg.type!.toUpperCase() == 'RADIO') || msg.command == '/radio';
              final isClickable = (msg.type != null && msg.type!.toUpperCase() == 'CLICKABLE') || msg.command == '/clickable';
              final keyLower = key.toLowerCase();
              final isRowTiming = !isCheckMode && (isTimingOrRtc ||
                  keyLower.contains('timing') ||
                  keyLower.contains('on-off') ||
                  keyLower.contains('on_off') ||
                  formattedLabel.toLowerCase().contains('timing'));
              final isCDT = !isCheckMode && !isRowTiming &&
                  ((msg.command == '/cdt') ||
                  (msg.type != null && msg.type!.toUpperCase() == 'CDT') ||
                  keyLower.contains('cdt') ||
                  (keyLower.contains('off_time') && !keyLower.contains('on_off')) ||
                  (keyLower.contains('off time') && !keyLower.contains('on-off')) ||
                  titleLower.contains('cdt') ||
                  (titleLower.contains('off time') && !titleLower.contains('on-off') && !titleLower.contains('on/off')));
              final isTime = !isCheckMode && (isRowTiming ||
                  (!isCDT &&
                  ((msg.type != null && msg.type!.toUpperCase() == 'TIME') ||
                  msg.command == '/time' ||
                  keyLower.contains('time'))));
              final isCyclic = !isCheckMode && ((msg.type != null && msg.type!.toUpperCase() == 'CYCLIC') || msg.command == '/cyclic');

              final relayNames = provider.getDeviceRelayNames(activeDevice.id);
              String valStr = val?.toString() ?? '';

              // Mode mapping for status / check mode (e.g. 0 -> '0 - On/Off', 2 -> '2 - Cyclic', 4 -> '4 - Pulse')
              final isStatusOrMode = isCheckMode ||
                  (msg.title != null && msg.title!.toLowerCase().contains('status')) ||
                  msg.command == '/status' ||
                  (msg.title != null && msg.title!.toLowerCase().contains('mode'));
              if (isStatusOrMode) {
                const modeMapping = {
                  '0': '0 - On/Off',
                  '1': '1 - RTC',
                  '2': '2 - Cyclic',
                  '3': '3 - CDT',
                  '4': '4 - Pulse',
                };
                if (modeMapping.containsKey(valStr.trim())) {
                  valStr = modeMapping[valStr.trim()]!;
                }
              }

              // Determine displayLabel: prioritize actual relay name instead of '1', '2', '3', '4'
              String displayLabel;
              if (isTime && int.tryParse(key.trim()) != null) {
                displayLabel = 'Set Timing ${key.trim()}';
              } else if (isTime && key.toLowerCase().startsWith('set_timing')) {
                displayLabel = 'Set Timing ${key.toLowerCase().replaceAll('set_timing', '').replaceAll('_', ' ').trim()}';
              } else if (isTime && key.toLowerCase().startsWith('timing')) {
                displayLabel = 'Set Timing ${key.toLowerCase().replaceAll('timing', '').replaceAll('_', ' ').trim()}';
              } else if (isTime && !formattedLabel.toLowerCase().startsWith('set ') && formattedLabel.toLowerCase().contains('timing')) {
                displayLabel = 'Set $formattedLabel';
              } else if (isText && valStr.trim().isNotEmpty && int.tryParse(valStr.trim()) == null) {
                displayLabel = valStr.trim();
                if (int.tryParse(key.trim()) != null) {
                  provider.setRelayName(activeDevice.id, key.trim(), valStr.trim());
                }
              } else if (relayNames.containsKey(key.trim())) {
                displayLabel = relayNames[key.trim()]!;
              } else if (relayNames.containsKey(key.toLowerCase().replaceAll('relay', '').replaceAll('_', '').trim())) {
                displayLabel = relayNames[key.toLowerCase().replaceAll('relay', '').replaceAll('_', '').trim()]!;
              } else if (rawItem is Map && (rawItem['label'] != null || rawItem['title'] != null || rawItem['name'] != null)) {
                displayLabel = (rawItem['label'] ?? rawItem['title'] ?? rawItem['name']).toString();
              } else {
                displayLabel = formattedLabel;
              }

              final isOn = valStr.toLowerCase() == 'on';
              final isOff = valStr.toLowerCase() == 'off';

              Color? valColor;
              if (isOn) {
                valColor = isDark ? const Color(0xFF4ADE80) : const Color(0xFF16A34A);
              } else if (isOff) {
                valColor = isDark ? const Color(0xFFF87171) : const Color(0xFFDC2626);
              }

              final canEditThisRow = !isCheckMode && msg.isEditable && activeDevice.isOwner && !isReadOnly && isLive;
              final isMode = isCheckMode || (!isClickable &&
                  (key.toLowerCase() == 'mode' ||
                   key.toLowerCase() == 'relay_mode' ||
                   (msg.command == '/mode') ||
                   (msg.type != null && msg.type!.toUpperCase() == 'MODE') ||
                   (rangeStr != null && (rangeStr.toLowerCase().contains('rtc') || rangeStr.toLowerCase().contains('cyclic')))));

              final modeNames = ['On/Off', 'RTC', 'Cyclic', 'CDT', 'Pulse'];
              String modeDisplayStr = valStr;
              if (isMode) {
                int mIdx = 0;
                final trimmedVal = valStr.trim();
                if (int.tryParse(trimmedVal) != null) {
                  mIdx = (int.tryParse(trimmedVal)!).clamp(0, modeNames.length - 1);
                  modeDisplayStr = '${modeNames[mIdx]} ($mIdx)';
                } else {
                  for (int i = 0; i < modeNames.length; i++) {
                    if (trimmedVal.toLowerCase().contains(modeNames[i].toLowerCase())) {
                      mIdx = i;
                      if (!trimmedVal.contains('(')) {
                        modeDisplayStr = '${modeNames[i]} ($i)';
                      }
                      break;
                    }
                  }
                }
              }

              return Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: canEditThisRow
                      ? () {
                          if (isClickable) {
                            final actionCmd = (rawItem is Map && (rawItem['command'] != null || rawItem['message'] != null || rawItem['action'] != null))
                                ? (rawItem['command'] ?? rawItem['message'] ?? rawItem['action']).toString()
                                : ((valStr.trim().isNotEmpty && valStr.trim() != displayLabel && int.tryParse(valStr.trim()) == null)
                                    ? valStr.trim()
                                    : (key.trim().isNotEmpty && int.tryParse(key.trim()) == null
                                        ? key.trim()
                                        : displayLabel));
                            _sendMessage(actionCmd, displayLabel);
                          } else if (isMode) {
                            _showModeSelectionDialog(
                              context,
                              provider,
                              activeDevice.id,
                              key,
                              rawItem,
                              msg: msg,
                              currentValStr: valStr,
                            );
                          } else if (isCyclic) {
                            _showCyclicWheelPickerDialog(
                              context,
                              provider,
                              activeDevice.id,
                              key,
                              rawItem,
                              msg: msg,
                            );
                          } else if (isTime) {
                            _showTimeWheelPickerDialog(
                              context,
                              provider,
                              activeDevice.id,
                              key,
                              rawItem,
                              msg: msg,
                            );
                          } else {
                            _showEditRegisterDialog(
                              context,
                              provider,
                              activeDevice.id,
                              key,
                              rawItem,
                              msg: msg,
                              range: rangeStr,
                              isSetting: isSetting,
                              isNumeric: isNumeric || isCDT,
                              isText: isText,
                              isRadio: isRadio,
                              isClickable: isClickable,
                            );
                          }
                        }
                      : null,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  if (isClickable) ...[
                                    const Icon(
                                      Icons.link_rounded,
                                      size: 16,
                                      color: Color(0xFF38BDF8),
                                    ),
                                    const SizedBox(width: 6),
                                  ] else if (isCheckMode) ...[
                                    const Icon(
                                      Icons.tune_rounded,
                                      size: 14,
                                      color: Color(0xFF00A884),
                                    ),
                                    const SizedBox(width: 5),
                                  ] else if (isTime) ...[
                                    Icon(
                                      isCyclic
                                          ? Icons.sync_alt_rounded
                                          : Icons.schedule_rounded,
                                      size: 14,
                                      color: isCyclic
                                          ? const Color(0xFFF59E0B)
                                          : (isLive
                                              ? const Color(0xFF00A884)
                                              : (isDark ? Colors.grey[500] : Colors.grey[400])),
                                    ),
                                    const SizedBox(width: 5),
                                  ],
                                  Expanded(
                                    child: Text(
                                      displayLabel,
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: isClickable ? FontWeight.w500 : FontWeight.w500,
                                        color: isClickable
                                            ? const Color(0xFF38BDF8)
                                            : (isDark ? Colors.grey[200] : Colors.grey[800]),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              if (msg.isEditable && rangeStr != null && rangeStr.isNotEmpty && !isMode && !isSetting && !isClickable && !isCyclic && !isRadio)
                                Padding(
                                  padding: const EdgeInsets.only(top: 3),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                                    decoration: BoxDecoration(
                                      color: (isDark ? Colors.white : Colors.black).withValues(alpha: 0.06),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      'Range: $rangeStr',
                                      style: TextStyle(
                                        fontSize: 9.5,
                                        fontFamily: 'monospace',
                                        color: isDark ? const Color(0xFF4ADE80) : const Color(0xFF00897B),
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        if (isClickable)
                          const Padding(
                            padding: EdgeInsets.only(right: 2),
                            child: Icon(
                              Icons.chevron_right_rounded,
                              size: 18,
                              color: Color(0xFF38BDF8),
                            ),
                          )
                        else if (isMode) ...[
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: isDark
                                  ? theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5)
                                  : Colors.grey[100],
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                color: const Color(0xFF00A884).withValues(alpha: 0.35),
                              ),
                            ),
                            child: Text(
                              modeDisplayStr,
                              style: const TextStyle(
                                fontFamily: 'monospace',
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF00A884),
                              ),
                            ),
                          ),
                          if (canEditThisRow) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.all(5),
                              decoration: BoxDecoration(
                                color: (isDark ? Colors.white : Colors.black).withValues(alpha: 0.04),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(
                                  color: const Color(0xFF00A884).withValues(alpha: 0.35),
                                ),
                              ),
                              child: const Icon(
                                Icons.edit_outlined,
                                size: 14,
                                color: Color(0xFF00A884),
                              ),
                            ),
                          ],
                        ]
                        else if (isText)
                          Container(
                            padding: const EdgeInsets.all(5),
                            decoration: BoxDecoration(
                              color: (isDark ? Colors.white : Colors.black).withValues(alpha: 0.04),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                color: const Color(0xFF00A884).withValues(alpha: 0.35),
                              ),
                            ),
                            child: const Icon(
                              Icons.edit_outlined,
                              size: 14,
                              color: Color(0xFF00A884),
                            ),
                          )
                        else if (isTime) ...[
                          Container(
                            height: 32,
                            constraints: const BoxConstraints(minWidth: 70),
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: isDark ? const Color(0xFF141D26) : Colors.grey[100],
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                color: isDark ? Colors.white12 : Colors.black12,
                              ),
                            ),
                            alignment: Alignment.center,
                            child: Text(
                              valStr.trim(),
                              style: TextStyle(
                                fontFamily: 'monospace',
                                fontSize: 11.5,
                                fontWeight: FontWeight.bold,
                                color: isDark ? Colors.white : Colors.black87,
                              ),
                            ),
                          ),
                          if (canEditThisRow) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.all(5),
                              decoration: BoxDecoration(
                                color: (isDark ? Colors.white : Colors.black).withValues(alpha: 0.04),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(
                                  color: const Color(0xFF00A884).withValues(alpha: 0.35),
                                ),
                              ),
                              child: const Icon(
                                Icons.edit_outlined,
                                size: 14,
                                color: Color(0xFF00A884),
                              ),
                            ),
                          ],
                        ]
                        else if (isCDT) ...[
                          Container(
                            height: 32,
                            constraints: const BoxConstraints(minWidth: 70),
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: isDark ? const Color(0xFF141D26) : Colors.grey[100],
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                color: isDark ? Colors.white12 : Colors.black12,
                              ),
                            ),
                            alignment: Alignment.center,
                            child: Text(
                              (valStr.trim().isNotEmpty && !valStr.toLowerCase().contains('min') && double.tryParse(valStr.trim()) != null)
                                  ? '${valStr.trim()} min'
                                  : (valStr.trim().isEmpty ? '1 min' : valStr.trim()),
                              style: TextStyle(
                                fontFamily: 'monospace',
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: isDark ? const Color(0xFF00A884) : const Color(0xFF00897B),
                              ),
                            ),
                          ),
                          if (canEditThisRow) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.all(5),
                              decoration: BoxDecoration(
                                color: (isDark ? Colors.white : Colors.black).withValues(alpha: 0.04),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(
                                  color: const Color(0xFF00A884).withValues(alpha: 0.35),
                                ),
                              ),
                              child: const Icon(
                                Icons.edit_outlined,
                                size: 14,
                                color: Color(0xFF00A884),
                              ),
                            ),
                          ],
                        ]
                        else if (isCyclic) ...[
                          Builder(
                            builder: (context) {
                              final cyclicParts = valStr.trim().split(RegExp(r'[\s\-]+')).where((e) => e.isNotEmpty).toList();
                              final displayStr = cyclicParts.length >= 2
                                  ? '${cyclicParts[0]}-${cyclicParts[1]}'
                                  : (cyclicParts.isNotEmpty ? cyclicParts[0] : 'Set Time');
                              return Container(
                                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF59E0B).withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(
                                    color: const Color(0xFFF59E0B).withValues(alpha: 0.45),
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      displayStr,
                                      style: const TextStyle(
                                        fontFamily: 'monospace',
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                        color: Color(0xFFF59E0B),
                                      ),
                                    ),
                                    const SizedBox(width: 5),
                                    const Icon(
                                      Icons.sync_alt_rounded,
                                      size: 13,
                                      color: Color(0xFFF59E0B),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                        ]
                        else
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
                                color: isRadio
                                    ? (valStr.trim() == '1'
                                        ? const Color(0xFF00A884)
                                        : (isDark ? Colors.grey[400] : Colors.grey[600]))
                                    : (valColor ?? (isDark ? Colors.white : Colors.black87)),
                              ),
                            ),
                          ),
                        if (canEditThisRow && !isCyclic && !isClickable && !isText && !isMode && !isTime && !isCDT) ...[
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

  void _showModeSelectionDialog(
    BuildContext context,
    DeviceProvider provider,
    String deviceId,
    String key,
    dynamic rawValue, {
    MessageModel? msg,
    String? currentValStr,
  }) {
    List<Map<String, dynamic>> modeOptions = [];
    if (rawValue is Map && rawValue['options'] is List) {
      final opts = rawValue['options'] as List;
      for (int i = 0; i < opts.length; i++) {
        final optStr = opts[i].toString().trim();
        IconData icon = Icons.tune_rounded;
        final lower = optStr.toLowerCase();
        if (lower.contains('on') || lower.contains('off')) {
          icon = Icons.power_settings_new_rounded;
        } else if (lower.contains('rtc') || lower.contains('time')) {
          icon = Icons.access_time_rounded;
        } else if (lower.contains('cyclic')) {
          icon = Icons.sync_alt_rounded;
        } else if (lower.contains('cdt')) {
          icon = Icons.layers_rounded;
        } else if (lower.contains('pulse')) {
          icon = Icons.bolt_rounded;
        }
        modeOptions.add({
          'title': optStr,
          'subtitle': 'Mode $i',
          'icon': icon,
        });
      }
    } else if (rawValue is Map && rawValue['options'] is String) {
      final opts = (rawValue['options'] as String).split(RegExp(r'[,|/]')).map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
      for (int i = 0; i < opts.length; i++) {
        final optStr = opts[i];
        IconData icon = Icons.tune_rounded;
        final lower = optStr.toLowerCase();
        if (lower.contains('on') || lower.contains('off')) {
          icon = Icons.power_settings_new_rounded;
        } else if (lower.contains('rtc') || lower.contains('time')) {
          icon = Icons.access_time_rounded;
        } else if (lower.contains('cyclic')) {
          icon = Icons.sync_alt_rounded;
        } else if (lower.contains('cdt')) {
          icon = Icons.layers_rounded;
        } else if (lower.contains('pulse')) {
          icon = Icons.bolt_rounded;
        }
        modeOptions.add({
          'title': optStr,
          'subtitle': 'Mode $i',
          'icon': icon,
        });
      }
    }

    if (modeOptions.isEmpty) {
      modeOptions = [
        {
          'title': 'On/Off',
          'subtitle': 'Mode 0',
          'icon': Icons.power_settings_new_rounded,
        },
        {
          'title': 'RTC',
          'subtitle': 'Mode 1',
          'icon': Icons.access_time_rounded,
        },
        {
          'title': 'Cyclic',
          'subtitle': 'Mode 2',
          'icon': Icons.sync_alt_rounded,
        },
        {
          'title': 'CDT',
          'subtitle': 'Mode 3',
          'icon': Icons.layers_rounded,
        },
        {
          'title': 'Pulse',
          'subtitle': 'Mode 4',
          'icon': Icons.bolt_rounded,
        },
      ];
    }

    int selectedIndex = 0;
    final valText = (currentValStr ?? '').trim();
    if (int.tryParse(valText) != null) {
      selectedIndex = (int.tryParse(valText)!).clamp(0, modeOptions.length - 1);
    } else {
      for (int i = 0; i < modeOptions.length; i++) {
        if (valText.toLowerCase().contains((modeOptions[i]['title'] as String).toLowerCase())) {
          selectedIndex = i;
          break;
        
        }
      }
    }

    final formattedLabel = _formatKeyLabel(key);
    final displayItemLabel = (rawValue is Map &&
            (rawValue['label'] != null ||
                rawValue['title'] != null ||
                rawValue['name'] != null))
        ? (rawValue['label'] ?? rawValue['title'] ?? rawValue['name']).toString()
        : formattedLabel;

    showDialog(
      context: context,
      builder: (dialogContext) {
        final theme = Theme.of(dialogContext);
        final isDark = theme.brightness == Brightness.dark;
        const brandGreen = Color(0xFF00A884);

        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: isDark ? const Color(0xFF16202A) : Colors.white,
              insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(
                  color: isDark ? const Color(0xFF233240) : Colors.black12,
                ),
              ),
              titlePadding: const EdgeInsets.fromLTRB(16, 14, 10, 8),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              actionsPadding: const EdgeInsets.fromLTRB(16, 8, 16, 14),
              title: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(7),
                    decoration: BoxDecoration(
                      color: brandGreen.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.toggle_on_rounded,
                      size: 20,
                      color: brandGreen,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          displayItemLabel,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: isDark ? Colors.white : Colors.black87,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Select mode option',
                          style: TextStyle(
                            fontSize: 11,
                            color: isDark ? Colors.grey[400] : Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, size: 20),
                    color: isDark ? Colors.grey[400] : Colors.grey[600],
                    splashRadius: 18,
                    onPressed: () => Navigator.pop(dialogContext),
                  ),
                ],
              ),
              content: SizedBox(
                width: math.min(360.0, MediaQuery.of(dialogContext).size.width - 32),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: List.generate(modeOptions.length, (index) {
                      final isSelected = selectedIndex == index;
                      final item = modeOptions[index];
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(10),
                          onTap: () {
                            setDialogState(() {
                              selectedIndex = index;
                            });
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? brandGreen.withValues(alpha: 0.12)
                                  : (isDark
                                      ? const Color(0xFF1E293B).withValues(alpha: 0.4)
                                      : Colors.grey[50]),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: isSelected
                                    ? brandGreen
                                    : (isDark ? Colors.white10 : Colors.black12),
                                width: isSelected ? 1.6 : 1,
                              ),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: isSelected
                                        ? brandGreen.withValues(alpha: 0.2)
                                        : (isDark
                                            ? Colors.white.withValues(alpha: 0.05)
                                            : Colors.grey[200]),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Icon(
                                    item['icon'] as IconData,
                                    size: 18,
                                    color: isSelected
                                        ? brandGreen
                                        : (isDark ? Colors.grey[400] : Colors.grey[600]),
                                  ),
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        item['title'] as String,
                                        style: TextStyle(
                                          fontSize: 14,
                                          fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                                          color: isDark ? Colors.white : Colors.black87,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        item['subtitle'] as String,
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: isDark ? Colors.grey[400] : Colors.grey[600],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                if (isSelected)
                                  Container(
                                    width: 20,
                                    height: 20,
                                    decoration: const BoxDecoration(
                                      color: brandGreen,
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(
                                      Icons.check,
                                      size: 13,
                                      color: Colors.white,
                                    ),
                                  )
                                else
                                  Container(
                                    width: 20,
                                    height: 20,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                        color: isDark ? Colors.white24 : Colors.black26,
                                        width: 1.5,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      );
                    }),
                  ),
                ),
              ),
              actions: [
                Row(
                  children: [
                    Expanded(
                      child: SizedBox(
                        height: 48,
                        child: OutlinedButton(
                          onPressed: () => Navigator.pop(dialogContext),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            side: BorderSide(
                              color: isDark ? Colors.grey[700]! : Colors.grey[300]!,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          child: Text(
                            'Cancel',
                            style: TextStyle(
                              color: isDark ? Colors.grey[300] : Colors.grey[700],
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: SizedBox(
                        height: 48,
                        child: ElevatedButton(
                          onPressed: () {
                            final rawCmd = (rawValue is Map &&
                                    rawValue['command'] != null &&
                                    rawValue['command'].toString().isNotEmpty)
                                ? rawValue['command'].toString()
                                : (msg?.command ?? '/write_register');
                            final writeCmd = rawCmd.startsWith('/write') ? rawCmd : '/write_register';
                            provider.writeSingleRegister(
                              deviceId,
                              key,
                              selectedIndex,
                              writeCommand: writeCmd,
                            );
                            FocusManager.instance.primaryFocus?.unfocus();
                            Navigator.pop(dialogContext);
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: brandGreen,
                            foregroundColor: Colors.white,
                            elevation: 0,
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Transform.rotate(
                                angle: -0.2,
                                child: const Icon(Icons.send_rounded, size: 15, color: Colors.white),
                              ),
                              const SizedBox(width: 8),
                              const Text(
                                'Apply',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 15,
                                  color: Colors.white,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showCyclicWheelPickerDialog(
    BuildContext context,
    DeviceProvider provider,
    String deviceId,
    String key,
    dynamic rawValue, {
    MessageModel? msg,
  }) {
    dynamic effectiveValue = rawValue;
    if (rawValue is Map) {
      effectiveValue = rawValue['value'];
    }
    final strVal = effectiveValue?.toString() ?? '';
    final parts = strVal.trim().split(RegExp(r'[\s\-]+')).where((e) => e.isNotEmpty).toList();

    int startMin = (parts.isNotEmpty ? int.tryParse(parts[0]) : null) ?? 10;
    int endMin = (parts.length > 1 ? int.tryParse(parts[1]) : null) ?? 20;

    startMin = startMin.clamp(0, 999);
    endMin = endMin.clamp(0, 999);

    final formattedLabel = _formatKeyLabel(key);
    final displayItemLabel = (rawValue is Map && (rawValue['label'] != null || rawValue['title'] != null || rawValue['name'] != null))
        ? (rawValue['label'] ?? rawValue['title'] ?? rawValue['name']).toString()
        : (key == 'set_cyclic_time' ? 'Set Cyclic Time' : formattedLabel);

    int activeColumn = 0; // 0 for Start Min, 1 for End Min

    final startMinController = FixedExtentScrollController(initialItem: startMin);
    final endMinController = FixedExtentScrollController(initialItem: endMin);
    final startTextController = TextEditingController(text: startMin.toString());
    final endTextController = TextEditingController(text: endMin.toString());
    final startFocusNode = FocusNode();
    final endFocusNode = FocusNode();

    showDialog(
      context: context,
      builder: (dialogContext) {
        final theme = Theme.of(dialogContext);
        final isDark = theme.brightness == Brightness.dark;
        const amberColor = Color(0xFFF59E0B);

        return StatefulBuilder(
          builder: (context, setDialogState) {
            Widget buildWheelColumn({
              required String title,
              required int itemCount,
              required FixedExtentScrollController controller,
              required int selectedValue,
              required bool isActive,
              required ValueChanged<int> onSelectedItemChanged,
            }) {
              return Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.5,
                        color: isActive
                            ? amberColor
                            : (isDark ? Colors.grey[400] : Colors.grey[600]),
                      ),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      height: 140,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          if (isActive)
                            Container(
                              height: 38,
                              margin: const EdgeInsets.symmetric(horizontal: 4),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: amberColor,
                                  width: 1.6,
                                ),
                              ),
                            ),
                          ListWheelScrollView.useDelegate(
                            controller: controller,
                            itemExtent: 38,
                            perspective: 0.003,
                            diameterRatio: 1.4,
                            physics: const FixedExtentScrollPhysics(),
                            onSelectedItemChanged: onSelectedItemChanged,
                            childDelegate: ListWheelChildBuilderDelegate(
                              childCount: itemCount,
                              builder: (context, index) {
                                final isSelected = selectedValue == index;
                                return Center(
                                  child: Text(
                                    index.toString(),
                                    style: TextStyle(
                                      fontFamily: 'monospace',
                                      fontSize: isSelected ? 20 : 15,
                                      fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                                      color: isSelected
                                          ? (isDark ? Colors.white : Colors.black87)
                                          : (isDark ? Colors.grey[500] : Colors.grey[400]),
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            }

            return AlertDialog(
              backgroundColor: isDark ? const Color(0xFF16202A) : Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
              titlePadding: const EdgeInsets.fromLTRB(20, 18, 16, 12),
              contentPadding: const EdgeInsets.fromLTRB(14, 0, 14, 18),
              title: Row(
                children: [
                  const Icon(
                    Icons.sync_alt_rounded,
                    color: amberColor,
                    size: 22,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      displayItemLabel,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: isDark ? Colors.white : Colors.black87,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  InkWell(
                    borderRadius: BorderRadius.circular(20),
                    onTap: () {
                      FocusManager.instance.primaryFocus?.unfocus();
                      Navigator.pop(dialogContext);
                    },
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: Icon(
                        Icons.close_rounded,
                        size: 20,
                        color: isDark ? Colors.grey[400] : Colors.grey[600],
                      ),
                    ),
                  ),
                ],
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Top Cards (START MIN & END MIN with direct typing)
                    Row(
                      children: [
                        // Start Min Card
                        Expanded(
                          child: InkWell(
                            borderRadius: BorderRadius.circular(8),
                            onTap: () {
                              setDialogState(() => activeColumn = 0);
                              startFocusNode.requestFocus();
                              startTextController.selection = TextSelection(
                                baseOffset: 0,
                                extentOffset: startTextController.text.length,
                              );
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
                              decoration: BoxDecoration(
                                color: activeColumn == 0
                                    ? (isDark
                                        ? amberColor.withValues(alpha: 0.12)
                                        : Colors.amber.shade50)
                                    : (isDark
                                        ? Colors.white.withValues(alpha: 0.04)
                                        : Colors.grey[100]),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: activeColumn == 0
                                      ? amberColor
                                      : (isDark ? Colors.white12 : Colors.black12),
                                  width: activeColumn == 0 ? 1.6 : 1,
                                ),
                              ),
                              child: Column(
                                children: [
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(
                                        Icons.access_time_rounded,
                                        size: 13,
                                        color: activeColumn == 0
                                            ? amberColor
                                            : (isDark ? Colors.grey[400] : Colors.grey[600]),
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        'START MIN',
                                        style: TextStyle(
                                          fontSize: 10.5,
                                          fontWeight: FontWeight.bold,
                                          letterSpacing: 0.4,
                                          color: activeColumn == 0
                                              ? amberColor
                                              : (isDark ? Colors.grey[400] : Colors.grey[600]),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  FittedBox(
                                    fit: BoxFit.scaleDown,
                                    child: Row(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        // Dedicated square input box for manual typing
                                        Container(
                                          height: 44,
                                          constraints: const BoxConstraints(minWidth: 54),
                                          padding: const EdgeInsets.symmetric(horizontal: 8),
                                          decoration: BoxDecoration(
                                            color: isDark
                                                ? const Color(0xFF1E293B)
                                                : Colors.white,
                                            borderRadius: BorderRadius.circular(6),
                                            border: Border.all(
                                              color: activeColumn == 0
                                                  ? amberColor
                                                  : (isDark ? Colors.white24 : Colors.black26),
                                              width: activeColumn == 0 ? 1.8 : 1.2,
                                            ),
                                          ),
                                          alignment: Alignment.center,
                                          child: IntrinsicWidth(
                                            child: TextField(
                                              controller: startTextController,
                                              focusNode: startFocusNode,
                                              keyboardType: TextInputType.number,
                                              textAlign: TextAlign.center,
                                              style: TextStyle(
                                                fontFamily: 'monospace',
                                                fontSize: 20,
                                                fontWeight: FontWeight.bold,
                                                color: activeColumn == 0
                                                    ? (isDark ? Colors.white : Colors.black87)
                                                    : (isDark ? Colors.grey[300] : Colors.grey[700]),
                                              ),
                                              decoration: const InputDecoration(
                                                isDense: true,
                                                border: InputBorder.none,
                                                contentPadding: EdgeInsets.zero,
                                              ),
                                              onTap: () {
                                                setDialogState(() => activeColumn = 0);
                                                startTextController.selection = TextSelection(
                                                  baseOffset: 0,
                                                  extentOffset: startTextController.text.length,
                                                );
                                              },
                                              onChanged: (val) {
                                                final n = int.tryParse(val.trim());
                                                if (n != null) {
                                                  final clamped = n.clamp(0, 999);
                                                  setDialogState(() {
                                                    startMin = clamped;
                                                    activeColumn = 0;
                                                  });
                                                  if (startMinController.hasClients &&
                                                      startMinController.selectedItem != clamped) {
                                                    startMinController.jumpToItem(clamped);
                                                  }
                                                }
                                              },
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 4),
                                        Text(
                                          'min',
                                          style: TextStyle(
                                            fontSize: 12.5,
                                            fontWeight: FontWeight.w600,
                                            color: activeColumn == 0
                                                ? amberColor
                                                : (isDark ? Colors.grey[400] : Colors.grey[600]),
                                          ),
                                        ),
                                        const SizedBox(width: 3),
                                        Icon(
                                          Icons.edit_outlined,
                                          size: 13,
                                          color: activeColumn == 0
                                              ? amberColor.withValues(alpha: 0.9)
                                              : (isDark ? Colors.white38 : Colors.black38),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        // End Min Card
                        Expanded(
                          child: InkWell(
                            borderRadius: BorderRadius.circular(8),
                            onTap: () {
                              setDialogState(() => activeColumn = 1);
                              endFocusNode.requestFocus();
                              endTextController.selection = TextSelection(
                                baseOffset: 0,
                                extentOffset: endTextController.text.length,
                              );
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
                              decoration: BoxDecoration(
                                color: activeColumn == 1
                                    ? (isDark
                                        ? amberColor.withValues(alpha: 0.12)
                                        : Colors.amber.shade50)
                                    : (isDark
                                        ? Colors.white.withValues(alpha: 0.04)
                                        : Colors.grey[100]),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: activeColumn == 1
                                      ? amberColor
                                      : (isDark ? Colors.white12 : Colors.black12),
                                  width: activeColumn == 1 ? 1.6 : 1,
                                ),
                              ),
                              child: Column(
                                children: [
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(
                                        Icons.access_time_rounded,
                                        size: 13,
                                        color: activeColumn == 1
                                            ? amberColor
                                            : (isDark ? Colors.grey[400] : Colors.grey[600]),
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        'END MIN',
                                        style: TextStyle(
                                          fontSize: 10.5,
                                          fontWeight: FontWeight.bold,
                                          letterSpacing: 0.4,
                                          color: activeColumn == 1
                                              ? amberColor
                                              : (isDark ? Colors.grey[400] : Colors.grey[600]),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  FittedBox(
                                    fit: BoxFit.scaleDown,
                                    child: Row(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        // Dedicated square input box for manual typing
                                        Container(
                                          height: 44,
                                          constraints: const BoxConstraints(minWidth: 54),
                                          padding: const EdgeInsets.symmetric(horizontal: 8),
                                          decoration: BoxDecoration(
                                            color: isDark
                                                ? const Color(0xFF1E293B)
                                                : Colors.white,
                                            borderRadius: BorderRadius.circular(6),
                                            border: Border.all(
                                              color: activeColumn == 1
                                                  ? amberColor
                                                  : (isDark ? Colors.white24 : Colors.black26),
                                              width: activeColumn == 1 ? 1.8 : 1.2,
                                            ),
                                          ),
                                          alignment: Alignment.center,
                                          child: IntrinsicWidth(
                                            child: TextField(
                                              controller: endTextController,
                                              focusNode: endFocusNode,
                                              keyboardType: TextInputType.number,
                                              textAlign: TextAlign.center,
                                              style: TextStyle(
                                                fontFamily: 'monospace',
                                                fontSize: 20,
                                                fontWeight: FontWeight.bold,
                                                color: activeColumn == 1
                                                  ? (isDark ? Colors.white : Colors.black87)
                                                  : (isDark ? Colors.grey[300] : Colors.grey[700]),
                                              ),
                                              decoration: const InputDecoration(
                                                isDense: true,
                                                border: InputBorder.none,
                                                contentPadding: EdgeInsets.zero,
                                              ),
                                              onTap: () {
                                                setDialogState(() => activeColumn = 1);
                                                endTextController.selection = TextSelection(
                                                  baseOffset: 0,
                                                  extentOffset: endTextController.text.length,
                                                );
                                              },
                                              onChanged: (val) {
                                                final n = int.tryParse(val.trim());
                                                if (n != null) {
                                                  final clamped = n.clamp(0, 999);
                                                  setDialogState(() {
                                                    endMin = clamped;
                                                    activeColumn = 1;
                                                  });
                                                  if (endMinController.hasClients &&
                                                      endMinController.selectedItem != clamped) {
                                                    endMinController.jumpToItem(clamped);
                                                  }
                                                }
                                              },
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 4),
                                        Text(
                                          'min',
                                          style: TextStyle(
                                            fontSize: 12.5,
                                            fontWeight: FontWeight.w600,
                                            color: activeColumn == 1
                                                ? amberColor
                                                : (isDark ? Colors.grey[400] : Colors.grey[600]),
                                          ),
                                        ),
                                        const SizedBox(width: 3),
                                        Icon(
                                          Icons.edit_outlined,
                                          size: 13,
                                          color: activeColumn == 1
                                              ? amberColor.withValues(alpha: 0.9)
                                              : (isDark ? Colors.white38 : Colors.black38),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    // Scroll Wheels Container
                    Container(
                      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                      decoration: BoxDecoration(
                        color: isDark
                            ? const Color(0xFF101720)
                            : Colors.grey[50],
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: isDark ? Colors.white10 : Colors.black12,
                        ),
                      ),
                      child: Row(
                        children: [
                          buildWheelColumn(
                            title: 'START (MIN)',
                            itemCount: 1000,
                            controller: startMinController,
                            selectedValue: startMin,
                            isActive: activeColumn == 0,
                            onSelectedItemChanged: (index) {
                              setDialogState(() {
                                startMin = index;
                                activeColumn = 0;
                                if (startTextController.text != index.toString()) {
                                  startTextController.text = index.toString();
                                }
                              });
                            },
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 6),
                            child: Text(
                              '-',
                              style: TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                                color: isDark ? Colors.grey[500] : Colors.grey[400],
                              ),
                            ),
                          ),
                          buildWheelColumn(
                            title: 'END (MIN)',
                            itemCount: 1000,
                            controller: endMinController,
                            selectedValue: endMin,
                            isActive: activeColumn == 1,
                            onSelectedItemChanged: (index) {
                              setDialogState(() {
                                endMin = index;
                                activeColumn = 1;
                                if (endTextController.text != index.toString()) {
                                  endTextController.text = index.toString();
                                }
                              });
                            },
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    // Submit Button
                    SizedBox(
                      width: double.infinity,
                      height: 46,
                      child: ElevatedButton(
                        onPressed: () {
                          final finalStart = int.tryParse(startTextController.text.trim())?.clamp(0, 999) ?? startMin;
                          final finalEnd = int.tryParse(endTextController.text.trim())?.clamp(0, 999) ?? endMin;
                          final cyclicPayload = '$finalStart-$finalEnd';
                          final rawCmd = (rawValue is Map && rawValue['command'] != null && rawValue['command'].toString().isNotEmpty)
                              ? rawValue['command'].toString()
                              : '/write_register';
                          final writeCmd = rawCmd.startsWith('/write') ? rawCmd : '/write_register';
                          provider.writeSingleRegister(deviceId, key, cyclicPayload, writeCommand: writeCmd);
                          FocusManager.instance.primaryFocus?.unfocus();
                          Navigator.pop(dialogContext);
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: amberColor,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        child: const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.check_circle_rounded, color: Colors.white, size: 18),
                            SizedBox(width: 6),
                            Text(
                              'Submit',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 15,
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
      },
    );
  }

  void _showTimeWheelPickerDialog(
    BuildContext context,
    DeviceProvider provider,
    String deviceId,
    String key,
    dynamic rawValue, {
    MessageModel? msg,
  }) {
    dynamic effectiveValue = rawValue;
    if (rawValue is Map) {
      effectiveValue = rawValue['value'];
    }
    final strVal = effectiveValue?.toString() ?? '';
    final parts = strVal.trim().split(RegExp(r'[\s\-]+')).where((e) => e.isNotEmpty).toList();

    String rawStart = parts.isNotEmpty && parts[0].contains(':') ? parts[0] : '01:00';
    String rawStop = parts.length > 1 && parts[1].contains(':') ? parts[1] : '17:30';

    final startSplit = rawStart.split(':');
    int startHour = (int.tryParse(startSplit[0]) ?? 1).clamp(0, 23);
    int startMin = (startSplit.length > 1 ? (int.tryParse(startSplit[1]) ?? 0) : 0).clamp(0, 59);

    final stopSplit = rawStop.split(':');
    int stopHour = (int.tryParse(stopSplit[0]) ?? 17).clamp(0, 23);
    int stopMin = (stopSplit.length > 1 ? (int.tryParse(stopSplit[1]) ?? 30) : 30).clamp(0, 59);

    final formattedLabel = _formatKeyLabel(key);
    String displayItemLabel = (rawValue is Map && (rawValue['label'] != null || rawValue['title'] != null || rawValue['name'] != null))
        ? (rawValue['label'] ?? rawValue['title'] ?? rawValue['name']).toString()
        : formattedLabel;

    if (int.tryParse(key.trim()) != null) {
      displayItemLabel = 'Set Timing ${key.trim()}';
    } else if (key.toLowerCase().startsWith('set_timing')) {
      displayItemLabel = 'Set Timing ${key.toLowerCase().replaceAll('set_timing', '').replaceAll('_', ' ').trim()}';
    } else if (key.toLowerCase().startsWith('timing')) {
      displayItemLabel = 'Set Timing ${key.toLowerCase().replaceAll('timing', '').replaceAll('_', ' ').trim()}';
    } else if (!displayItemLabel.toLowerCase().startsWith('set ') && displayItemLabel.toLowerCase().contains('timing')) {
      displayItemLabel = 'Set $displayItemLabel';
    }

    int activeTab = 0; // 0 for Start Time (ON), 1 for Stop Time (OFF)

    final startHourController = FixedExtentScrollController(initialItem: startHour);
    final startMinController = FixedExtentScrollController(initialItem: startMin);
    final stopHourController = FixedExtentScrollController(initialItem: stopHour);
    final stopMinController = FixedExtentScrollController(initialItem: stopMin);

    showDialog(
      context: context,
      builder: (dialogContext) {
        final theme = Theme.of(dialogContext);
        final isDark = theme.brightness == Brightness.dark;

        return StatefulBuilder(
          builder: (context, setDialogState) {
            String format2(int n) => n.toString().padLeft(2, '0');

            Widget buildWheelPicker({
              required int selectedHour,
              required int selectedMin,
              required FixedExtentScrollController hourCtrl,
              required FixedExtentScrollController minCtrl,
              required ValueChanged<int> onHourChanged,
              required ValueChanged<int> onMinChanged,
            }) {
              return Stack(
                alignment: Alignment.center,
                children: [
                  Container(
                    height: 38,
                    decoration: BoxDecoration(
                      color: const Color(0xFF00A884).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: const Color(0xFF00A884),
                        width: 1.5,
                      ),
                    ),
                  ),
                  Row(
                    children: [
                      Expanded(
                        child: ListWheelScrollView.useDelegate(
                          controller: hourCtrl,
                          itemExtent: 38,
                          perspective: 0.003,
                          diameterRatio: 1.4,
                          physics: const FixedExtentScrollPhysics(),
                          onSelectedItemChanged: onHourChanged,
                          childDelegate: ListWheelChildBuilderDelegate(
                            childCount: 24,
                            builder: (context, index) {
                              final isSelected = selectedHour == index;
                              return Center(
                                child: Text(
                                  format2(index),
                                  style: TextStyle(
                                    fontSize: isSelected ? 20 : 15,
                                    fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                                    color: isSelected
                                        ? (isDark ? Colors.white : Colors.black87)
                                        : (isDark ? Colors.grey[500] : Colors.grey[400]),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 4),
                        child: Text(
                          ':',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF00A884),
                          ),
                        ),
                      ),
                      Expanded(
                        child: ListWheelScrollView.useDelegate(
                          controller: minCtrl,
                          itemExtent: 38,
                          perspective: 0.003,
                          diameterRatio: 1.4,
                          physics: const FixedExtentScrollPhysics(),
                          onSelectedItemChanged: onMinChanged,
                          childDelegate: ListWheelChildBuilderDelegate(
                            childCount: 60,
                            builder: (context, index) {
                              final isSelected = selectedMin == index;
                              return Center(
                                child: Text(
                                  format2(index),
                                  style: TextStyle(
                                    fontSize: isSelected ? 20 : 15,
                                    fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                                    color: isSelected
                                        ? (isDark ? Colors.white : Colors.black87)
                                        : (isDark ? Colors.grey[500] : Colors.grey[400]),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              );
            }

            return AlertDialog(
              backgroundColor: isDark ? const Color(0xFF16202A) : Colors.white,
              insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(
                  color: isDark ? const Color(0xFF233240) : Colors.black12,
                ),
              ),
              titlePadding: const EdgeInsets.fromLTRB(16, 14, 10, 8),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              actionsPadding: const EdgeInsets.fromLTRB(16, 8, 16, 14),
              title: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: const Color(0xFF00A884).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.access_time_filled_rounded,
                      color: Color(0xFF00A884),
                      size: 18,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      displayItemLabel,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: isDark ? Colors.white : Colors.black87,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, size: 20),
                    color: isDark ? Colors.grey[400] : Colors.grey[600],
                    splashRadius: 18,
                    onPressed: () {
                      FocusManager.instance.primaryFocus?.unfocus();
                      Navigator.pop(dialogContext);
                    },
                  ),
                ],
              ),
              content: SizedBox(
                width: math.min(340.0, MediaQuery.of(dialogContext).size.width - 32),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Start & End Time Selector Tabs matching Web UI
                      Row(
                        children: [
                          // START TIME Tab
                          Expanded(
                            child: InkWell(
                              borderRadius: BorderRadius.circular(10),
                              onTap: () => setDialogState(() => activeTab = 0),
                              child: Container(
                                padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
                                decoration: BoxDecoration(
                                  color: activeTab == 0
                                      ? (isDark ? const Color(0xFF162E2E) : const Color(0xFFE6F7F2))
                                      : (isDark ? const Color(0xFF1E2836) : Colors.grey[100]),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                    color: activeTab == 0
                                        ? const Color(0xFF00A884)
                                        : (isDark ? const Color(0xFF283848) : Colors.black12),
                                    width: activeTab == 0 ? 1.5 : 1,
                                  ),
                                ),
                                child: Column(
                                  children: [
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Icon(
                                          Icons.adjust_rounded,
                                          size: 13,
                                          color: activeTab == 0 ? const Color(0xFF00A884) : Colors.grey[500],
                                        ),
                                        const SizedBox(width: 5),
                                        Text(
                                          'START TIME',
                                          style: TextStyle(
                                            fontSize: 10.5,
                                            fontWeight: FontWeight.bold,
                                            letterSpacing: 0.5,
                                            color: activeTab == 0
                                                ? const Color(0xFF00A884)
                                                : (isDark ? Colors.grey[400] : Colors.grey[600]),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 5),
                                    Text(
                                      '${format2(startHour)}:${format2(startMin)}',
                                      style: TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold,
                                        color: activeTab == 0
                                            ? (isDark ? Colors.white : Colors.black87)
                                            : (isDark ? Colors.grey[400] : Colors.grey[600]),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          // END TIME Tab
                          Expanded(
                            child: InkWell(
                              borderRadius: BorderRadius.circular(10),
                              onTap: () => setDialogState(() => activeTab = 1),
                              child: Container(
                                padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
                                decoration: BoxDecoration(
                                  color: activeTab == 1
                                      ? (isDark ? const Color(0xFF162E2E) : const Color(0xFFE6F7F2))
                                      : (isDark ? const Color(0xFF1E2836) : Colors.grey[100]),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                    color: activeTab == 1
                                        ? const Color(0xFF00A884)
                                        : (isDark ? const Color(0xFF283848) : Colors.black12),
                                    width: activeTab == 1 ? 1.5 : 1,
                                  ),
                                ),
                                child: Column(
                                  children: [
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Icon(
                                          Icons.adjust_rounded,
                                          size: 13,
                                          color: activeTab == 1 ? const Color(0xFF00A884) : Colors.grey[500],
                                        ),
                                        const SizedBox(width: 5),
                                        Text(
                                          'END TIME',
                                          style: TextStyle(
                                            fontSize: 10.5,
                                            fontWeight: FontWeight.bold,
                                            letterSpacing: 0.5,
                                            color: activeTab == 1
                                                ? const Color(0xFF00A884)
                                                : (isDark ? Colors.grey[400] : Colors.grey[600]),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 5),
                                    Text(
                                      '${format2(stopHour)}:${format2(stopMin)}',
                                      style: TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold,
                                        color: activeTab == 1
                                            ? (isDark ? Colors.white : Colors.black87)
                                            : (isDark ? Colors.grey[400] : Colors.grey[600]),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      // Wheel Picker Container
                      Container(
                        padding: const EdgeInsets.fromLTRB(10, 10, 10, 6),
                        decoration: BoxDecoration(
                          color: isDark ? const Color(0xFF121B24) : Colors.grey[50],
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: isDark ? const Color(0xFF233240) : Colors.black12,
                          ),
                        ),
                        child: Column(
                          children: [
                            // Column Headers: HOURS | MINUTES
                            Row(
                              children: [
                                Expanded(
                                  child: Center(
                                    child: Text(
                                      'HOURS',
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                        letterSpacing: 0.6,
                                        color: isDark ? Colors.grey[400] : Colors.grey[600],
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: Center(
                                    child: Text(
                                      'MINUTES',
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                        letterSpacing: 0.6,
                                        color: isDark ? Colors.grey[400] : Colors.grey[600],
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            SizedBox(
                              height: 135,
                              child: IndexedStack(
                                index: activeTab,
                                children: [
                                  buildWheelPicker(
                                    selectedHour: startHour,
                                    selectedMin: startMin,
                                    hourCtrl: startHourController,
                                    minCtrl: startMinController,
                                    onHourChanged: (val) => setDialogState(() => startHour = val),
                                    onMinChanged: (val) => setDialogState(() => startMin = val),
                                  ),
                                  buildWheelPicker(
                                    selectedHour: stopHour,
                                    selectedMin: stopMin,
                                    hourCtrl: stopHourController,
                                    minCtrl: stopMinController,
                                    onHourChanged: (val) => setDialogState(() => stopHour = val),
                                    onMinChanged: (val) => setDialogState(() => stopMin = val),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton(
                    onPressed: () {
                      final timePayload = '${format2(startHour)}:${format2(startMin)} ${format2(stopHour)}:${format2(stopMin)}';
                      final rawCmd = (rawValue is Map &&
                              rawValue['command'] != null &&
                              rawValue['command'].toString().isNotEmpty)
                          ? rawValue['command'].toString()
                          : ((msg?.command != null && msg!.command!.isNotEmpty)
                              ? (msg.command!.startsWith('/write')
                                  ? msg.command!
                                  : (msg.command == '/time' ? '/write_time' : msg.command!))
                              : null);
                      final writeCmd = rawCmd ?? '/write_register';
                      provider.writeSingleRegister(deviceId, key, timePayload, writeCommand: writeCmd);
                      FocusManager.instance.primaryFocus?.unfocus();
                      Navigator.pop(dialogContext);
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF00A884),
                      foregroundColor: Colors.white,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      alignment: Alignment.center,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.check_circle_rounded, size: 18, color: Colors.white),
                        SizedBox(width: 8),
                        Text(
                          'Submit',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showEditRegisterDialog(
    BuildContext context,
    DeviceProvider provider,
    String deviceId,
    String key,
    dynamic rawValue, {
    MessageModel? msg,
    String? range,
    bool isSetting = false,
    bool isNumeric = false,
    bool isText = false,
    bool isRadio = false,
    bool isClickable = false,
  }) {
    dynamic effectiveValue = rawValue;
    String? effectiveRange = range;
    if (rawValue is Map) {
      effectiveValue = rawValue['value'];
      effectiveRange ??= rawValue['range']?.toString();
    }

    final strVal = effectiveValue?.toString() ?? '';

    // Dynamic radio options from backend (list, comma-separated string, or range)
    List<String> radioOptions = [];
    if (rawValue is Map && rawValue['options'] is List) {
      radioOptions = (rawValue['options'] as List)
          .map((e) => e.toString().trim())
          .where((e) => e.isNotEmpty)
          .toList();
    } else if (rawValue is Map && rawValue['options'] is String) {
      radioOptions = (rawValue['options'] as String)
          .split(RegExp(r'[,|/]'))
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList();
    } else if (effectiveRange != null && effectiveRange.contains('-')) {
      final parts = effectiveRange.split('-').map((e) => e.trim()).toList();
      if (parts.length == 2 && int.tryParse(parts[0]) != null && int.tryParse(parts[1]) != null) {
        final start = int.parse(parts[0]);
        final end = int.parse(parts[1]);
        if (end - start >= 1 && end - start <= 5) {
          radioOptions = [for (int i = start; i <= end; i++) i.toString()];
        }
      }
    }
    if (radioOptions.isEmpty) {
      radioOptions = ['0', '1'];
    }
    
    // Parse range bounds if present (e.g. "10-20", "0-1", "0-60 min", "0-180")
    String unit = '';
    double? minRange;
    double? maxRange;
    if (rawValue is Map) {
      if (rawValue['min'] != null) minRange ??= double.tryParse(rawValue['min'].toString());
      if (rawValue['max'] != null) maxRange ??= double.tryParse(rawValue['max'].toString());
    }
    if (!isText && !isRadio && !isClickable && effectiveRange != null && effectiveRange.trim().isNotEmpty) {
      final rangeMatch = RegExp(r'^(-?\d+(?:\.\d+)?)\s*-\s*(-?\d+(?:\.\d+)?)(?:\s*(.*))?$').firstMatch(effectiveRange.trim());
      if (rangeMatch != null) {
        minRange ??= double.tryParse(rangeMatch.group(1)!);
        maxRange ??= double.tryParse(rangeMatch.group(2)!);
        if (rangeMatch.group(3) != null && rangeMatch.group(3)!.trim().isNotEmpty) {
          final rangeUnit = rangeMatch.group(3)!.trim();
          if (unit.isEmpty) unit = rangeUnit;
        }
      }
    }

    final isZeroOne = !isText && !isClickable && ((effectiveRange?.trim() == '0-1') || (minRange == 0 && maxRange == 1));
    final isAlarmOrBool = !isText && !isClickable && (strVal.toLowerCase() == 'on' || strVal.toLowerCase() == 'off' || isZeroOne);
    final isBinaryChoice = isRadio || isZeroOne || isAlarmOrBool;

    final List<String> binaryOptions = isRadio
        ? radioOptions
        : (isZeroOne
            ? ['0', '1']
            : (isAlarmOrBool
                ? ((strVal.trim() == '0' || strVal.trim() == '1') ? ['0', '1'] : ['Off', 'On'])
                : ['0', '1']));

    String selectedState;
    if (isRadio) {
      selectedState = radioOptions.contains(strVal.trim()) ? strVal.trim() : radioOptions.first;
    } else if (isZeroOne) {
      selectedState = (strVal.trim() == '0' || strVal.toLowerCase() == 'off') ? '0' : '1';
    } else if (isAlarmOrBool) {
      selectedState = (strVal.toLowerCase() == 'off' || strVal.trim() == '0')
          ? (binaryOptions.contains('Off') ? 'Off' : '0')
          : (binaryOptions.contains('On') ? 'On' : '1');
    } else {
      selectedState = strVal.trim();
    }

    // Extract number and unit
    String initialNumber = strVal;
    if (rawValue is Map && rawValue['unit'] != null) {
      unit = rawValue['unit'].toString().trim();
    }
    if (!isText && !isRadio && !isClickable) {
      final match = RegExp(r'^(-?\d+(?:\.\d+)?)\s*(.*)$').firstMatch(strVal.trim());
      if (match != null && match.group(1) != null) {
        initialNumber = match.group(1)!;
        if (unit.isEmpty) {
          unit = match.group(2) ?? '';
        }
      }
      final msgTitleLower = msg?.title?.toLowerCase() ?? '';
      if (unit.isEmpty && (key.toLowerCase().contains('time') || key.toLowerCase().contains('min') || (effectiveRange != null && effectiveRange.toLowerCase().contains('min')) || msgTitleLower.contains('off time') || msgTitleLower.contains('min'))) {
        unit = 'min';
      }
      if (!isBinaryChoice && (initialNumber.trim().isEmpty || double.tryParse(initialNumber.trim()) == null)) {
        initialNumber = '1';
      }
      if (minRange == null) {
        if (key.toLowerCase().contains('time') || unit == 'min' || isSetting || isNumeric || double.tryParse(initialNumber) != null) {
          minRange = 0.0;
          maxRange ??= ((double.tryParse(initialNumber) ?? 0) > 90) ? ((double.tryParse(initialNumber) ?? 0) * 2) : 180.0;
        }
      } else {
        maxRange ??= minRange + 100.0;
      }
      if (minRange != null && maxRange != null && minRange >= maxRange) {
        maxRange = minRange + 100.0;
      }
    }

    final relayNames = provider.getDeviceRelayNames(deviceId);
    final controller = TextEditingController(
      text: isText
          ? (strVal.isNotEmpty && int.tryParse(strVal.trim()) == null ? strVal : (relayNames[key.trim()] ?? initialNumber))
          : initialNumber,
    );
    final bool hasSlider = !isText && !isRadio && !isClickable && !isAlarmOrBool && minRange != null && maxRange != null && minRange < maxRange;
    final bool isIntegerRange = hasSlider && (minRange % 1 == 0) && (maxRange % 1 == 0);
    double currentSliderVal = (double.tryParse(initialNumber) ?? (minRange ?? 0.0)).clamp(
      minRange ?? 0.0,
      maxRange ?? ((minRange ?? 0.0) + 1.0),
    );

    String? getRangeError(String text) {
      if (isRadio || isBinaryChoice) return null;
      final trimmed = text.trim();
      if (trimmed.isEmpty) return isText ? 'Name cannot be empty' : 'Value cannot be empty';
      if (isText || isClickable) return null;
      final numVal = double.tryParse(trimmed);
      if (numVal == null) return 'Enter a valid number';
      if (minRange != null && maxRange != null) {
        if (numVal < minRange || numVal > maxRange) {
          final minStr = minRange % 1 == 0 ? minRange.toInt().toString() : minRange.toString();
          final maxStr = maxRange % 1 == 0 ? maxRange.toInt().toString() : maxRange.toString();
          return 'Must be between $minStr and $maxStr';
        }
      }
      return null;
    }

    String? rangeError = (isBinaryChoice || isText || isClickable) ? null : getRangeError(initialNumber);

    showDialog(
      context: context,
      builder: (dialogContext) {
        final theme = Theme.of(dialogContext);
        final isDark = theme.brightness == Brightness.dark;
        final formattedLabel = _formatKeyLabel(key);
        final relayNames = provider.getDeviceRelayNames(deviceId);
        String displayItemLabel;
        if (msg != null && msg.title != null && msg.title!.trim().isNotEmpty && !msg.title!.trim().startsWith('Device ') && !isText) {
          displayItemLabel = msg.title!.trim();
        } else if (isText && strVal.trim().isNotEmpty && int.tryParse(strVal.trim()) == null) {
          displayItemLabel = strVal.trim();
        } else if (relayNames.containsKey(key.trim())) {
          displayItemLabel = relayNames[key.trim()]!;
        } else if (rawValue is Map && (rawValue['label'] != null || rawValue['title'] != null || rawValue['name'] != null)) {
          displayItemLabel = (rawValue['label'] ?? rawValue['title'] ?? rawValue['name']).toString();
        } else {
          displayItemLabel = formattedLabel;
        }

        return StatefulBuilder(
          builder: (context, setDialogState) {
            final bool canSubmit = isBinaryChoice || isClickable || rangeError == null;
            final double sliderMin = minRange ?? 0.0;
            final double sliderMax = maxRange ?? 1.0;

            return AlertDialog(
              backgroundColor: isDark ? const Color(0xFF16202A) : Colors.white,
              insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(
                  color: isDark ? const Color(0xFF233240) : Colors.black12,
                ),
              ),
              titlePadding: const EdgeInsets.fromLTRB(16, 14, 10, 8),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              actionsPadding: const EdgeInsets.fromLTRB(16, 8, 16, 14),
              title: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: const Color(0xFF00A884).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      isClickable
                          ? Icons.touch_app_rounded
                          : (isText ? Icons.edit_rounded : Icons.tune_rounded),
                      color: const Color(0xFF00A884),
                      size: 18,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      displayItemLabel,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: isDark ? Colors.white : Colors.black87,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, size: 20),
                    color: isDark ? Colors.grey[400] : Colors.grey[600],
                    splashRadius: 18,
                    onPressed: () {
                      FocusManager.instance.primaryFocus?.unfocus();
                      Navigator.pop(dialogContext);
                    },
                  ),
                ],
              ),
              content: SizedBox(
                width: math.min(300.0, MediaQuery.of(dialogContext).size.width - 48),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (isBinaryChoice) ...[
                        if (binaryOptions.length <= 2)
                          Row(
                            children: binaryOptions.map((opt) {
                              final isSelected = selectedState.toLowerCase() == opt.toLowerCase();
                              final isOffOpt = opt == '0' || opt.toLowerCase() == 'off';
                              final optIcon = isOffOpt ? Icons.power_off_rounded : Icons.power_settings_new_rounded;

                              return Expanded(
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 4),
                                  child: InkWell(
                                    borderRadius: BorderRadius.circular(10),
                                    onTap: () {
                                      setDialogState(() {
                                        selectedState = opt;
                                      });
                                    },
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(vertical: 14),
                                      decoration: BoxDecoration(
                                        color: isSelected
                                            ? const Color(0xFF00A884).withValues(alpha: 0.12)
                                            : (isDark
                                                ? const Color(0xFF1E293B).withValues(alpha: 0.45)
                                                : Colors.grey[100]),
                                        border: Border.all(
                                          color: isSelected
                                              ? const Color(0xFF00A884)
                                              : (isDark ? Colors.white10 : Colors.black12),
                                          width: isSelected ? 1.6 : 1,
                                        ),
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      alignment: Alignment.center,
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            optIcon,
                                            size: 20,
                                            color: isSelected
                                                ? const Color(0xFF00A884)
                                                : (isDark ? Colors.grey[400] : Colors.grey[600]),
                                          ),
                                          const SizedBox(height: 6),
                                          Text(
                                            opt,
                                            style: TextStyle(
                                              fontFamily: 'monospace',
                                              fontSize: 14,
                                              fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                                              color: isSelected
                                                  ? const Color(0xFF00A884)
                                                  : (isDark ? Colors.white70 : Colors.black87),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              );
                            }).toList(),
                          )
                        else
                          Column(
                            mainAxisSize: MainAxisSize.min,
                            children: binaryOptions.map((opt) {
                              final isSelected = selectedState.toLowerCase() == opt.toLowerCase();
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(10),
                                  onTap: () {
                                    setDialogState(() {
                                      selectedState = opt;
                                    });
                                  },
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                                    decoration: BoxDecoration(
                                      color: isSelected
                                          ? const Color(0xFF00A884).withValues(alpha: 0.12)
                                          : (isDark
                                              ? const Color(0xFF1E293B).withValues(alpha: 0.45)
                                              : Colors.grey[100]),
                                      border: Border.all(
                                        color: isSelected
                                            ? const Color(0xFF00A884)
                                            : (isDark ? Colors.white10 : Colors.black12),
                                        width: isSelected ? 1.6 : 1,
                                      ),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: Row(
                                      children: [
                                        Icon(
                                          isSelected
                                              ? Icons.radio_button_checked_rounded
                                              : Icons.radio_button_off_rounded,
                                          size: 20,
                                          color: isSelected
                                              ? const Color(0xFF00A884)
                                              : (isDark ? Colors.grey[400] : Colors.grey[600]),
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Text(
                                            opt,
                                            style: TextStyle(
                                              fontSize: 14,
                                              fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                                              color: isSelected
                                                  ? const Color(0xFF00A884)
                                                  : (isDark ? Colors.white70 : Colors.black87),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              );
                            }).toList(),
                          ),
                      ] else if (isText || isClickable) ...[
                        TextField(
                          controller: controller,
                          keyboardType: TextInputType.text,
                          decoration: InputDecoration(
                            hintText: isText ? 'Enter name' : 'Enter value',
                            errorText: rangeError,
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                            focusedBorder: const OutlineInputBorder(
                              borderRadius: BorderRadius.all(Radius.circular(10)),
                              borderSide: BorderSide(color: Color(0xFF00A884), width: 1.5),
                            ),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                          ),
                          onChanged: (val) {
                            setDialogState(() {
                              rangeError = getRangeError(val);
                            });
                          },
                        ),
                      ] else ...[
                        // Stepper row matching Web UI ([-] [ 0 min ] [+])
                        Row(
                          children: [
                            InkWell(
                              borderRadius: BorderRadius.circular(22),
                              onTap: () {
                                double curr = double.tryParse(controller.text.trim()) ?? currentSliderVal;
                                double next = curr - 1.0;
                                if (minRange != null && next < minRange) next = minRange;
                                setDialogState(() {
                                  currentSliderVal = next.clamp(sliderMin, sliderMax);
                                  controller.text = (next % 1 == 0) ? next.toInt().toString() : next.toString();
                                  rangeError = getRangeError(controller.text);
                                });
                              },
                              child: Container(
                                width: 44,
                                height: 44,
                                decoration: BoxDecoration(
                                  color: isDark ? const Color(0xFF243447) : Colors.grey[200],
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: isDark ? Colors.white12 : Colors.black12,
                                  ),
                                ),
                                child: Icon(
                                  Icons.remove_rounded,
                                  size: 20,
                                  color: isDark ? Colors.white70 : Colors.black87,
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Container(
                                height: 48,
                                decoration: BoxDecoration(
                                  color: isDark ? const Color(0xFF1E2836) : Colors.grey[100],
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                    color: rangeError != null
                                        ? Colors.redAccent
                                        : (isDark ? const Color(0xFF2E3E50) : Colors.black12),
                                  ),
                                ),
                                child: Stack(
                                  alignment: Alignment.center,
                                  children: [
                                    TextField(
                                      controller: controller,
                                      textAlign: TextAlign.center,
                                      keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                                      style: TextStyle(
                                        fontSize: 22,
                                        fontWeight: FontWeight.bold,
                                        color: isDark ? Colors.white : Colors.black87,
                                      ),
                                      decoration: const InputDecoration(
                                        isDense: true,
                                        border: InputBorder.none,
                                        contentPadding: EdgeInsets.symmetric(horizontal: 40),
                                      ),
                                      onChanged: (val) {
                                        setDialogState(() {
                                          rangeError = getRangeError(val);
                                          final typed = double.tryParse(val.trim());
                                          if (typed != null) {
                                            currentSliderVal = typed.clamp(sliderMin, sliderMax);
                                          }
                                        });
                                      },
                                    ),
                                    if (unit.isNotEmpty)
                                      Positioned(
                                        right: 14,
                                        child: IgnorePointer(
                                          child: Text(
                                            unit,
                                            style: const TextStyle(
                                              fontSize: 14,
                                              fontWeight: FontWeight.w600,
                                              color: Color(0xFF00A884),
                                            ),
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            InkWell(
                              borderRadius: BorderRadius.circular(22),
                              onTap: () {
                                double curr = double.tryParse(controller.text.trim()) ?? currentSliderVal;
                                double next = curr + 1.0;
                                if (maxRange != null && next > maxRange) next = maxRange;
                                setDialogState(() {
                                  currentSliderVal = next.clamp(sliderMin, sliderMax);
                                  controller.text = (next % 1 == 0) ? next.toInt().toString() : next.toString();
                                  rangeError = getRangeError(controller.text);
                                });
                              },
                              child: Container(
                                width: 44,
                                height: 44,
                                decoration: BoxDecoration(
                                  color: isDark ? const Color(0xFF243447) : Colors.grey[200],
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: isDark ? Colors.white12 : Colors.black12,
                                  ),
                                ),
                                child: Icon(
                                  Icons.add_rounded,
                                  size: 20,
                                  color: isDark ? Colors.white70 : Colors.black87,
                                ),
                              ),
                            ),
                          ],
                        ),
                        if (hasSlider) ...[
                          const SizedBox(height: 14),
                          SliderTheme(
                            data: SliderTheme.of(context).copyWith(
                              trackHeight: 3.5,
                              activeTrackColor: const Color(0xFF00A884),
                              inactiveTrackColor: (isDark ? Colors.white : Colors.black).withValues(alpha: 0.12),
                              thumbColor: const Color(0xFF00A884),
                              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
                              overlayColor: const Color(0xFF00A884).withValues(alpha: 0.2),
                            ),
                            child: Slider(
                              value: currentSliderVal.clamp(sliderMin, sliderMax),
                              min: sliderMin,
                              max: sliderMax,
                              divisions: (isIntegerRange && (sliderMax - sliderMin) <= 200 && (sliderMax - sliderMin) > 0)
                                  ? (sliderMax - sliderMin).round()
                                  : null,
                              onChanged: (newVal) {
                                setDialogState(() {
                                  if (isIntegerRange) {
                                    final rounded = newVal.round();
                                    currentSliderVal = rounded.toDouble();
                                    controller.text = rounded.toString();
                                  } else {
                                    currentSliderVal = newVal;
                                    controller.text = (newVal % 1 == 0)
                                        ? newVal.toInt().toString()
                                        : newVal.toStringAsFixed(1);
                                  }
                                  rangeError = getRangeError(controller.text);
                                });
                              },
                            ),
                          ),
                        ],
                        if (rangeError != null) ...[
                          const SizedBox(height: 6),
                          Center(
                            child: Text(
                              rangeError!,
                              style: const TextStyle(
                                color: Colors.redAccent,
                                fontSize: 11.5,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ],
                  ),
                ),
              ),
              actions: [
                Row(
                  children: [
                    Expanded(
                      child: SizedBox(
                        height: 44,
                        child: TextButton(
                          onPressed: () {
                            FocusManager.instance.primaryFocus?.unfocus();
                            Navigator.pop(dialogContext);
                          },
                          style: TextButton.styleFrom(
                            backgroundColor: isDark ? const Color(0xFF1E2836) : Colors.grey[200],
                            padding: EdgeInsets.zero,
                            alignment: Alignment.center,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                              side: BorderSide(
                                color: isDark ? Colors.white12 : Colors.black12,
                              ),
                            ),
                          ),
                          child: Center(
                            child: Text(
                              'Cancel',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: isDark ? Colors.grey[300] : Colors.grey[800],
                                fontWeight: FontWeight.w600,
                                fontSize: 14,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: SizedBox(
                        height: 44,
                        child: ElevatedButton(
                          onPressed: canSubmit
                              ? () {
                                  dynamic valToSend;
                                  if (isBinaryChoice) {
                                    valToSend = int.tryParse(selectedState) ?? selectedState;
                                  } else if (isText) {
                                    final input = controller.text.trim();
                                    if (input.isEmpty) return;
                                    valToSend = input;
                                    provider.setRelayName(deviceId, key, input);
                                  } else {
                                    final err = getRangeError(controller.text);
                                    if (err != null) {
                                      setDialogState(() => rangeError = err);
                                      return;
                                    }
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

                                  final rawCmd = (rawValue is Map &&
                                          rawValue['command'] != null &&
                                          rawValue['command'].toString().isNotEmpty)
                                      ? rawValue['command'].toString()
                                      : ((msg?.command != null && msg!.command!.startsWith('/write'))
                                          ? msg.command
                                          : (isSetting ? '/write_setting' : null));
                                  final writeCmd = rawCmd ?? '/write_register';
                                  provider.writeSingleRegister(deviceId, key, valToSend, writeCommand: writeCmd);
                                  FocusManager.instance.primaryFocus?.unfocus();
                                  Navigator.pop(dialogContext);
                                }
                              : null,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF00A884),
                            foregroundColor: Colors.white,
                            elevation: 0,
                            padding: EdgeInsets.zero,
                            alignment: Alignment.center,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                          child: Center(
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                if (!isText) ...[
                                  Transform.rotate(
                                    angle: -0.2,
                                    child: const Icon(Icons.send_rounded, size: 14, color: Colors.white),
                                  ),
                                  const SizedBox(width: 6),
                                ],
                                Text(
                                  isText ? 'Submit' : 'Update Setting',
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14,
                                    color: Colors.white,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
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
                if (value == 'wifi_setup') {
                  _showWifiSetupDialog(context, deviceProvider, activeDevice);
                }
              },
              itemBuilder: (context) => [
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
                                msg.command != '/write_holding' &&
                                msg.command != '/write_setting' &&
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
                                margin: const EdgeInsets.only(bottom: 6),
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
    } else if (lowerLabel.contains('holding') || lowerMsg.contains('holding')) {
      icon = Icons.tune_rounded;
    } else if (lowerLabel.contains('setting') || lowerMsg.contains('setting')) {
      icon = Icons.tune_rounded;
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
                    'CHANNELS',
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
                      'No status configuration data available.\nPlease query device status to load channels.',
                      style: TextStyle(color: Colors.grey, fontSize: 13),
                      textAlign: TextAlign.center,
                    ),
                  ),
                )
              else
                ...configItems.asMap().entries.map((entry) {
                  final index = entry.key;
                  final item = entry.value;
                  final channelNumber = (index + 1).toString();

                  return Padding(
                    padding: const EdgeInsets.only(bottom: 14.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                              decoration: BoxDecoration(
                                color: const Color(0xFF00A884).withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                'Channel $channelNumber',
                                style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF00A884),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                item.key,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: isDark ? Colors.grey[400] : Colors.grey[600],
                                  fontFamily: 'monospace',
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        TextField(
                          controller: item.valueController,
                          decoration: InputDecoration(
                            hintText: 'Enter name (e.g. AC, Pump)',
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
                    final channelIndex = (i + 1).toString();
                    final val = item.valueController.text.trim();
                    final isNA = item.key.toUpperCase().startsWith('NA');
                    final fallback = isNA ? '' : item.key;
                    configData[channelIndex] = val.isNotEmpty ? val : fallback;
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

