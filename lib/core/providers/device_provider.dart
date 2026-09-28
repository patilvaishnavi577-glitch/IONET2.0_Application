import 'dart:convert';
import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mime/mime.dart';
import 'package:http_parser/http_parser.dart';
import '../api_config.dart';
import '../errors/app_exceptions.dart';
import '../errors/error_handler.dart';
import '../../data/models/device_model.dart';
import '../../data/models/message_model.dart';
import '../../data/models/quick_command_model.dart';

class DeviceProvider extends ChangeNotifier {
  static const Duration _timeoutDuration = Duration(seconds: 15);
  List<DeviceModel> _devices = [];
  final Map<String, List<MessageModel>> _messages = {};
  bool _isLoading = false;
  WebSocket? _webSocket;
  StreamSubscription? _wsSubscription;
  bool _isConnecting = false;
  String? _activeConnectedDeviceId;
  Timer? _reconnectTimer;

  final Map<String, String> _deviceConnectionStatus = {};
  final Map<String, String> _deviceLastSeenIST = {};
  final Map<String, Map<String, dynamic>> _deviceDetails = {};
  final Map<String, List<QuickCommandModel>> _deviceQuickCommands = {};
  final Map<String, Map<String, dynamic>> _latestDeviceStatusData = {};
  final Map<String, String> _lastSentCommand = {};
  final Map<String, Map<String, dynamic>> _pendingRegisterWrites = {};
  Timer? _heartbeatTimer;

  String getDeviceConnectionStatus(String deviceId) => _deviceConnectionStatus[deviceId] ?? 'offline';
  bool isDeviceOnline(String deviceId) => getDeviceConnectionStatus(deviceId) == 'online';
  String? getDeviceLastSeenIST(String deviceId) => _deviceLastSeenIST[deviceId];
  Map<String, dynamic>? getDeviceDetails(String deviceId) => _deviceDetails[deviceId];
  Map<String, dynamic>? getLatestDeviceStatusData(String deviceId) {
    if (_latestDeviceStatusData.containsKey(deviceId) &&
        _latestDeviceStatusData[deviceId] != null &&
        _latestDeviceStatusData[deviceId]!.isNotEmpty) {
      return _latestDeviceStatusData[deviceId];
    }
    // Fallback: search backwards in chat history for the most recent /status message
    final msgs = _messages[deviceId];
    if (msgs != null && msgs.isNotEmpty) {
      for (int i = msgs.length - 1; i >= 0; i--) {
        final m = msgs[i];
        if (!m.isUser &&
            m.command == '/status' &&
            m.rawData != null &&
            m.rawData!.isNotEmpty) {
          return m.rawData;
        }
      }
    }
    return null;
  }
  final Map<String, List<QuickCommandModel>> _customQuickCommands = {};
  
  List<QuickCommandModel> getDeviceCommands(String deviceId) => _deviceQuickCommands[deviceId] ?? [];
  List<QuickCommandModel> getCustomCommands(String deviceId) => _customQuickCommands[deviceId] ?? [];

  List<QuickCommandModel> getQuickCommands(String deviceId) {
    final custom = _customQuickCommands[deviceId] ?? [];
    final deviceCmds = _deviceQuickCommands[deviceId] ?? [];
    
    final Map<String, QuickCommandModel> combined = {};
    for (final cmd in deviceCmds) {
      combined[cmd.message] = cmd;
    }
    for (final cmd in custom) {
      combined[cmd.message] = cmd;
    }
    return combined.values.toList();
  }

  bool isCustomCommand(String deviceId, QuickCommandModel command) {
    final customCmds = _customQuickCommands[deviceId];
    if (customCmds == null) return false;
    return customCmds.any((c) => c.message == command.message);
  }

  Future<void> loadCustomCommands(String deviceId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final List<String>? saved = prefs.getStringList('custom_commands_$deviceId');
      if (saved != null) {
        final List<QuickCommandModel> loaded = saved.map((s) {
          final decoded = jsonDecode(s);
          return QuickCommandModel(
            label: decoded['label'] as String? ?? '',
            message: decoded['message'] as String? ?? '',
          );
        }).toList();
        
        _customQuickCommands[deviceId] = loaded;
        notifyListeners();
      }
    } catch (e) {
      debugPrint('Error loading custom commands: $e');
    }
  }

  Future<void> addDeviceQuickCommand(String deviceId, QuickCommandModel command) async {
    if (!_customQuickCommands.containsKey(deviceId)) {
      _customQuickCommands[deviceId] = [];
    }

    // Avoid duplicates in custom command list
    if (_customQuickCommands[deviceId]!.any((c) => c.message == command.message)) return;

    _customQuickCommands[deviceId]!.add(command);
    notifyListeners();

    try {
      final prefs = await SharedPreferences.getInstance();
      final listJson = _customQuickCommands[deviceId]!.map((c) => jsonEncode({
        'label': c.label,
        'message': c.message,
      })).toList();
      await prefs.setStringList('custom_commands_$deviceId', listJson);
    } catch (e) {
      debugPrint('Error saving custom command: $e');
    }
  }

  Future<void> deleteDeviceQuickCommand(String deviceId, QuickCommandModel command) async {
    if (_customQuickCommands.containsKey(deviceId)) {
      _customQuickCommands[deviceId]!.removeWhere((c) => c.message == command.message);
      notifyListeners();

      try {
        final prefs = await SharedPreferences.getInstance();
        final listJson = _customQuickCommands[deviceId]!.map((c) => jsonEncode({
          'label': c.label,
          'message': c.message,
        })).toList();
        await prefs.setStringList('custom_commands_$deviceId', listJson);
      } catch (e) {
        debugPrint('Error deleting custom command: $e');
      }
    }
  }

  Future<void> editDeviceQuickCommand(String deviceId, QuickCommandModel oldCommand, QuickCommandModel newCommand) async {
    if (_customQuickCommands.containsKey(deviceId)) {
      final list = _customQuickCommands[deviceId]!;
      final index = list.indexWhere((c) => c.message == oldCommand.message && c.label == oldCommand.label);
      if (index != -1) {
        list[index] = newCommand;
        notifyListeners();

        try {
          final prefs = await SharedPreferences.getInstance();
          final listJson = list.map((c) => jsonEncode({
            'label': c.label,
            'message': c.message,
          })).toList();
          await prefs.setStringList('custom_commands_$deviceId', listJson);
        } catch (e) {
          debugPrint('Error editing custom command: $e');
        }
      }
    }
  }

  final List<QuickCommandModel> _quickCommands = [
    QuickCommandModel(label: 'Info', message: '/status'),
    QuickCommandModel(label: 'Status', message: 'Status'),
    QuickCommandModel(label: 'Reboot', message: 'Reboot'),
    QuickCommandModel(label: 'M1', message: 'M1'),
    QuickCommandModel(label: 'M2', message: 'M2'),
    QuickCommandModel(label: 'Diagnose', message: 'Diagnose'),
  ];

  List<DeviceModel> get devices => _devices;
  List<QuickCommandModel> get quickCommands => _quickCommands;
  bool get isLoading => _isLoading;

  void addQuickCommand(QuickCommandModel command) {
    _quickCommands.add(command);
    notifyListeners();
  }

  void updateQuickCommand(int index, QuickCommandModel command) {
    _quickCommands[index] = command;
    notifyListeners();
  }

  void deleteQuickCommand(int index) {
    _quickCommands.removeAt(index);
    notifyListeners();
  }

  DeviceProvider();

  Future<String?> _getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('jwt_token');
  }

  Future<void> _saveDevicesLocally(List<dynamic> list) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('cached_devices', jsonEncode(list));
    } catch (e) {
      debugPrint('Error saving devices locally: $e');
    }
  }

  Future<void> loadCachedDevices() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cached = prefs.getString('cached_devices');
      if (cached != null && cached.isNotEmpty) {
        final decoded = jsonDecode(cached);
        if (decoded is List) {
          _devices = decoded
              .map((json) => DeviceModel.fromJson(json as Map<String, dynamic>))
              .toList();
          notifyListeners();
        }
      }
    } catch (e) {
      debugPrint('Error loading cached devices: $e');
    }
  }

  Future<void> fetchDevices({String? type}) async {
    final token = await _getToken();
    if (token == null) {
      debugPrint('[DeviceProvider] Token is null, skipping device fetch.');
      return;
    }

    if (_devices.isEmpty) {
      await loadCachedDevices();
    }

    _isLoading = true;
    notifyListeners();

    final String query = (type != null && type.isNotEmpty) ? '?type=$type' : '';
    final url = Uri.parse('${ApiConfig.baseUrl}/api/v1/devices$query');

    try {
      final response = await http.get(
        url,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      ).timeout(_timeoutDuration);

      debugPrint('--> [API REQUEST] GET $url');
      debugPrint('<-- [API RESPONSE] ${response.statusCode} GET $url');
      debugPrint('Response Body: ${response.body}');

      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        List<dynamic> list = [];
        if (decoded is List) {
          list = decoded;
        } else if (decoded is Map && decoded['data'] is List) {
          list = decoded['data'];
        } else if (decoded is Map) {
          final possibleList = decoded['devices'] ?? decoded['results'];
          if (possibleList is List) {
            list = possibleList;
          }
        }
        
        _devices = list.map((json) => DeviceModel.fromJson(json as Map<String, dynamic>)).toList();
        await _saveDevicesLocally(list);
      }
    } catch (e, stack) {
      debugPrint('Error fetching devices: $e');
      ErrorHandler.handle(e, stack);
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  List<MessageModel> getMessagesForDevice(String deviceId) {
    return _messages[deviceId] ?? [];
  }

  void clearMessages(String deviceId) {
    _messages[deviceId] = [];
    notifyListeners();
  }

  Future<void> addDevice(String id, String name) async {
    final token = await _getToken();
    if (token == null) throw const UnauthorizedException();

    _isLoading = true;
    notifyListeners();

    try {
      final response = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/api/v1/devices'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          'deviceId': id.trim(),
          'deviceName': name.trim(),
        }),
      ).timeout(_timeoutDuration);

      debugPrint('--> [API REQUEST] POST ${ApiConfig.baseUrl}/api/v1/devices');
      debugPrint('<-- [API RESPONSE] ${response.statusCode} POST ${ApiConfig.baseUrl}/api/v1/devices');
      debugPrint('Response Body: ${response.body}');

      if (response.statusCode >= 200 && response.statusCode < 300) {
        // Refresh the list from the server
        await fetchDevices();
        
        // Setup initial default message locally if not existing
        if (!_messages.containsKey(id)) {
          _messages[id] = [
            MessageModel(
              id: 'msg_${DateTime.now().millisecondsSinceEpoch}',
              text: 'Device connected successfully.',
              timestamp: DateTime.now(),
              isUser: false,
            )
          ];
        }
      } else {
        ErrorHandler.parseHttpResponse(response, defaultErrorMessage: 'Failed to add device');
      }
    } catch (e, stack) {
      debugPrint('Error adding device: $e');
      throw ErrorHandler.handle(e, stack);
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> deleteDevice(String id, {String? userId}) async {
    final token = await _getToken();
    if (token == null) throw const UnauthorizedException();

    _isLoading = true;
    notifyListeners();

    final device = _devices.firstWhere(
      (d) => d.id == id,
      orElse: () => DeviceModel(id: id, mongoId: '', name: '', profilePhotoUrl: '', lastMessage: '', timestamp: DateTime.now(), isOwner: false),
    );

    try {
      String url;
      if (device.isOwner) {
        url = '${ApiConfig.baseUrl}/api/v1/devices/$id';
      } else {
        // For shared devices, fetch the device by ID first to get the correct mongoId
        final getDeviceResponse = await http.get(
          Uri.parse('${ApiConfig.baseUrl}/api/v1/devices/$id'),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $token',
          },
        ).timeout(_timeoutDuration);

        if (getDeviceResponse.statusCode == 200) {
          final decoded = jsonDecode(getDeviceResponse.body);
          if (decoded['success'] == true && decoded['data'] != null) {
            final fetchedMongoId = decoded['data']['id']?.toString() ?? device.mongoId;
            url = '${ApiConfig.baseUrl}/api/v1/devices/$fetchedMongoId/share';
          } else {
            throw const ValidationException('Failed to retrieve device details for unsharing.');
          }
        } else {
          ErrorHandler.parseHttpResponse(getDeviceResponse, defaultErrorMessage: 'Failed to fetch device details.');
          return;
        }
      }

      final response = await http.delete(
        Uri.parse(url),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      ).timeout(_timeoutDuration);

      debugPrint('--> [API REQUEST] DELETE $url');
      debugPrint('<-- [API RESPONSE] ${response.statusCode} DELETE $url');
      debugPrint('Response Body: ${response.body}');

      if (response.statusCode >= 200 && response.statusCode < 300) {
        _devices.removeWhere((d) => d.id == id);
        _messages.remove(id);
      } else {
        ErrorHandler.parseHttpResponse(
          response,
          defaultErrorMessage: device.isOwner ? 'Failed to delete device' : 'Failed to leave device',
        );
      }
    } catch (e, stack) {
      debugPrint('Error deleting/leaving device: $e');
      throw ErrorHandler.handle(e, stack);
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> updateDeviceName(String id, String newName) async {
    final token = await _getToken();
    if (token == null) throw const UnauthorizedException();

    _isLoading = true;
    notifyListeners();

    final url = '${ApiConfig.baseUrl}/api/v1/devices/$id';

    try {
      final response = await http.put(
        Uri.parse(url),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          'deviceName': newName.trim(),
        }),
      ).timeout(_timeoutDuration);

      debugPrint('--> [API REQUEST] PUT $url');
      debugPrint('<-- [API RESPONSE] ${response.statusCode} PUT $url');
      debugPrint('Response Body: ${response.body}');

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final index = _devices.indexWhere((d) => d.id == id);
        if (index != -1) {
          _devices[index] = _devices[index].copyWith(name: newName);
        }
        notifyListeners();
      } else {
        ErrorHandler.parseHttpResponse(response, defaultErrorMessage: 'Failed to update device name');
      }
    } catch (e, stack) {
      debugPrint('Error updating device name: $e');
      throw ErrorHandler.handle(e, stack);
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> uploadDeviceImage(String deviceId, String filePath) async {
    final token = await _getToken();
    if (token == null) {
      throw const UnauthorizedException();
    }

    final url = Uri.parse('${ApiConfig.baseUrl}/api/v1/devices/$deviceId/image');
    debugPrint('--> [API REQUEST MULTIPART] POST $url');
    debugPrint('File path: $filePath');

    _isLoading = true;
    notifyListeners();

    try {
      final mimeType = lookupMimeType(filePath);
      MediaType? mediaType;
      if (mimeType != null) {
        final parts = mimeType.split('/');
        if (parts.length == 2) {
          mediaType = MediaType(parts[0], parts[1]);
        }
      }

      final multipartFile = await http.MultipartFile.fromPath(
        'file',
        filePath,
        contentType: mediaType,
      );

      final request = http.MultipartRequest('POST', url)
        ..headers['Authorization'] = 'Bearer $token'
        ..files.add(multipartFile);

      final streamedResponse = await request.send().timeout(const Duration(seconds: 25));
      final response = await http.Response.fromStream(streamedResponse);

      debugPrint('<-- [API RESPONSE] ${response.statusCode} POST $url');
      debugPrint('Response Body: ${response.body}');

      if (response.statusCode >= 200 && response.statusCode < 300) {
        await fetchDevices();
        await fetchDeviceDetails(deviceId);
      } else {
        ErrorHandler.parseHttpResponse(response, defaultErrorMessage: 'Failed to upload device image');
      }
    } catch (e, stack) {
      debugPrint('Error uploading device image: $e');
      throw ErrorHandler.handle(e, stack);
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> deleteDeviceImage(String deviceId) async {
    final token = await _getToken();
    if (token == null) {
      throw const UnauthorizedException();
    }

    _isLoading = true;
    notifyListeners();

    try {
      final response = await http.delete(
        Uri.parse('${ApiConfig.baseUrl}/api/v1/devices/$deviceId/image'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      ).timeout(_timeoutDuration);

      if (response.statusCode >= 200 && response.statusCode < 300) {
        await fetchDevices();
        await fetchDeviceDetails(deviceId);
      } else {
        ErrorHandler.parseHttpResponse(response, defaultErrorMessage: 'Failed to delete device image');
      }
    } catch (e, stack) {
      debugPrint('Error deleting device image: $e');
      throw ErrorHandler.handle(e, stack);
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> fetchDeviceDetails(String deviceId) async {
    final token = await _getToken();
    if (token == null) return;

    final url = Uri.parse('${ApiConfig.baseUrl}/api/v1/devices/$deviceId');
    debugPrint('--> [API REQUEST] GET $url');

    try {
      final response = await http.get(
        url,
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      ).timeout(_timeoutDuration);

      debugPrint('<-- [API RESPONSE] ${response.statusCode} GET $url');
      debugPrint('Response Body: ${response.body}');

      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        if (decoded is Map && decoded['data'] is Map) {
          _deviceDetails[deviceId] = Map<String, dynamic>.from(decoded['data'] as Map);
          notifyListeners();
        }
      }
    } catch (e, stack) {
      debugPrint('Error fetching device details: $e');
      ErrorHandler.handle(e, stack);
    }
  }

  Future<void> fetchDeviceById(String deviceId) async {
    final token = await _getToken();
    if (token == null) return;

    final url = Uri.parse('${ApiConfig.baseUrl}/api/v1/devices/$deviceId');
    debugPrint('--> [API REQUEST] GET $url');

    try {
      final response = await http.get(
        url,
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      ).timeout(_timeoutDuration);

      debugPrint('<-- [API RESPONSE] ${response.statusCode} GET $url');
      debugPrint('Response Body: ${response.body}');

      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        if (decoded is Map && decoded['data'] is Map) {
          final data = decoded['data'];
          final lastSeen = data['lastSeen'] as String?;
          if (lastSeen != null) {
            // Convert to IST (UTC + 5:30)
            final utcTime = DateTime.parse(lastSeen).toUtc();
            final istTime = utcTime.add(const Duration(hours: 5, minutes: 30));
            final formatted = "${istTime.day.toString().padLeft(2, '0')}-${istTime.month.toString().padLeft(2, '0')}-${istTime.year} "
                "${(istTime.hour % 12 == 0 ? 12 : istTime.hour % 12).toString().padLeft(2, '0')}:${istTime.minute.toString().padLeft(2, '0')}:${istTime.second.toString().padLeft(2, '0')} "
                "${istTime.hour >= 12 ? 'PM' : 'AM'}";
            _deviceLastSeenIST[deviceId] = formatted;
            
            // Also update the timestamp in the devices list if the device is found
            final index = _devices.indexWhere((d) => d.id == deviceId);
            if (index != -1) {
              _devices[index] = _devices[index].copyWith(
                timestamp: istTime,
              );
            }
            notifyListeners();
          }
        }
      }
    } catch (e, stack) {
      debugPrint('Error fetching device by ID: $e');
      ErrorHandler.handle(e, stack);
    }
  }

  Future<void> connectWebSocket(String deviceId) async {
    if (_activeConnectedDeviceId == deviceId &&
        (_deviceConnectionStatus[deviceId] == 'online' || 
         _deviceConnectionStatus[deviceId] == 'connecting')) {
      debugPrint('[WEBSOCKET CONNECT] Already connected or connecting to $deviceId, skipping.');
      return;
    }

    if (_isConnecting) {
      debugPrint('[WEBSOCKET CONNECT] Connection attempt already in progress, skipping.');
      return;
    }

    _isConnecting = true;
    _activeConnectedDeviceId = deviceId;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;

    final token = await _getToken();
    if (token == null) {
      _isConnecting = false;
      return;
    }

    await disconnectWebSocket(intentional: false);
    _activeConnectedDeviceId = deviceId;

    // Call fetchDeviceById immediately to get initial lastSeen in the background
    fetchDeviceById(deviceId);

    // ws://<host>:<port>/ws?deviceId=<deviceId>&type=mobile
    final wsUrlString = '${ApiConfig.wsUrl}/ws?deviceId=$deviceId&type=mobile';
    debugPrint('--> [WEBSOCKET CONNECT] Connecting to $wsUrlString');

    // Mark as connecting initially
    _deviceConnectionStatus[deviceId] = 'connecting';
    notifyListeners();

    try {
      _webSocket = await WebSocket.connect(
        wsUrlString,
        headers: {
          'Authorization': 'Bearer $token',
        },
      ).timeout(const Duration(seconds: 5));
      debugPrint('<-- [WEBSOCKET CONNECTED] Successfully connected to $wsUrlString');



      // Schedule the 10s heartbeat check. If no response comes within 10s, it goes offline.
      _heartbeatTimer?.cancel();
      _heartbeatTimer = Timer(const Duration(seconds: 10), () async {
        _deviceConnectionStatus[deviceId] = 'offline';
        notifyListeners();
        await fetchDeviceById(deviceId);
      });

      _wsSubscription = _webSocket!.listen(
        (data) {
          debugPrint('[WEBSOCKET RECEIVED] Data: $data');
          try {
            final Map<String, dynamic> event = jsonDecode(data);
            
            final parsedData = _extractDataPreservingDuplicates(
              data,
              event['data'] is Map ? Map<String, dynamic>.from(event['data'] as Map) : null,
            );

            // Only update _latestDeviceStatusData if the incoming payload is for /status telemetry
            final lastCmd = (_lastSentCommand[deviceId] ?? '').trim().toLowerCase();
            final eventCmd = (event['command'] ?? '').toString().trim().toLowerCase();
            final activeCmd = eventCmd.isNotEmpty ? eventCmd : lastCmd;

            final isNonStatusCmd = activeCmd == '/holding' ||
                activeCmd == '/setting' ||
                activeCmd == '/about' ||
                activeCmd == '/config' ||
                activeCmd == '/wifi_setup' ||
                activeCmd == '/write_holding' ||
                activeCmd == '/write_setting' ||
                (event['type'] == 'response' && activeCmd != '/status');

            final isStatusData = !isNonStatusCmd &&
                (activeCmd == '/status' || activeCmd.isEmpty || event['type'] == 'telemetry');

            if (isStatusData) {
              if (parsedData.isNotEmpty) {
                _latestDeviceStatusData[deviceId] = parsedData;
                notifyListeners();
              } else if (event.containsKey('data') && event['data'] is Map) {
                _latestDeviceStatusData[deviceId] = Map<String, dynamic>.from(event['data'] as Map);
                notifyListeners();
              }
            }

            // Check if this is a response to a command (e.g. /write_holding, /config, etc.)
            final isResponse = event['type'] == 'response' ||
                (event.containsKey('command') && event.containsKey('success'));
            if (isResponse) {
              _deviceConnectionStatus[deviceId] = 'online';
              notifyListeners();

              _heartbeatTimer?.cancel();
              _heartbeatTimer = Timer(const Duration(seconds: 10), () async {
                _deviceConnectionStatus[deviceId] = 'offline';
                notifyListeners();
                await fetchDeviceById(deviceId);
              });

              final isSuccess = event['success'] == true;
              final respCmd = (event['command'] ?? '').toString();
              final respMsg = (event['message'] ?? event['text'] ?? (isSuccess ? 'Success' : 'Failed')).toString();

              if (respCmd == '/config') {
                return;
              }

              // If /write_holding or /write_setting succeeded, update latest message's rawData
              if ((respCmd == '/write_holding' || respCmd == '/write_setting') && isSuccess) {
                final pending = _pendingRegisterWrites[deviceId];
                if (pending != null) {
                  final regKey = pending['key'] as String;
                  final regVal = pending['value'];

                  // Also update latest message's rawData if applicable
                  if (_messages.containsKey(deviceId)) {
                    for (int i = _messages[deviceId]!.length - 1; i >= 0; i--) {
                      final m = _messages[deviceId]![i];
                      if (!m.isUser && m.rawData != null && m.rawData!.containsKey(regKey)) {
                        final updatedData = Map<String, dynamic>.from(m.rawData!);
                        if (updatedData[regKey] is Map) {
                          final nested = Map<String, dynamic>.from(updatedData[regKey] as Map);
                          final oldValStr = nested['value']?.toString() ?? '';
                          final unitMatch = RegExp(r'^(-?\d+(?:\.\d+)?)\s*(.+)$').firstMatch(oldValStr.trim());
                          final unit = (unitMatch != null && unitMatch.group(2) != null) ? unitMatch.group(2)!.trim() : '';
                          if (unit.isNotEmpty && !regVal.toString().endsWith(unit)) {
                            nested['value'] = '$regVal $unit';
                          } else {
                            nested['value'] = regVal;
                          }
                          updatedData[regKey] = nested;
                        } else {
                          updatedData[regKey] = regVal;
                        }
                        _messages[deviceId]![i] = m.copyWith(rawData: updatedData);
                        break;
                      }
                    }
                  }
                  _pendingRegisterWrites.remove(deviceId);
                  notifyListeners();
                }
              }

              // If the response payload contains a data object (such as /about, /holding, etc.),
              // do NOT short-circuit into a simple "Success" text bubble!
              // Let it proceed down so data is extracted into rawData and rendered as a table.
              final hasResponseData = event.containsKey('data') &&
                  event['data'] is Map &&
                  (event['data'] as Map).isNotEmpty;

              if (!hasResponseData) {
                final responseMsg = MessageModel(
                  id: event['id'] as String? ?? 'resp_${DateTime.now().millisecondsSinceEpoch}',
                  text: isSuccess ? '✓ $respMsg' : '⚠️ $respMsg',
                  timestamp: DateTime.now(),
                  isUser: false,
                  isSuccess: isSuccess,
                  responseCommand: respCmd,
                );
                _addMessageLocally(deviceId, responseMsg);
                return;
              }
            }

            if (event['command'] == '/config') {
              return;
            }
            
            // If it's a heartbeat, mark online and reset 10s timer
            if (event['type'] == 'heartbeat') {
              _deviceConnectionStatus[deviceId] = 'online';
              notifyListeners();

              _heartbeatTimer?.cancel();
              _heartbeatTimer = Timer(const Duration(seconds: 10), () async {
                _deviceConnectionStatus[deviceId] = 'offline';
                notifyListeners();
                await fetchDeviceById(deviceId);
              });
              return;
            }

            // Treat other device-origin messages as activity to show online
            final hasDeviceId = event.containsKey('deviceId') || event.containsKey('deviceid');
            final hasData = event.containsKey('data') || event.containsKey('availableCommands') || event.containsKey('additionalCommands');
            
            if (hasDeviceId || hasData) {
              _deviceConnectionStatus[deviceId] = 'online';
              notifyListeners();
              
              _heartbeatTimer?.cancel();
              _heartbeatTimer = Timer(const Duration(seconds: 10), () async {
                _deviceConnectionStatus[deviceId] = 'offline';
                notifyListeners();
                await fetchDeviceById(deviceId);
              });
            }

            // Parse response commands
            String? textMsg;
            
            // Extract quick commands dynamically (supporting both List of Map objects and flat Map formats)
            final cmds = event['availableCommands'] ?? event['additionalCommands'];
            if (cmds != null) {
              final List<QuickCommandModel> dynamicCmds = [];
              if (cmds is List) {
                for (var item in cmds) {
                  if (item is Map) {
                    final cmdMsg = (item['command'] ?? item['message'] ?? '').toString();
                    final cmdDesc = (item['description'] ?? item['label'] ?? item['title'] ?? '').toString();
                    if (cmdMsg.isNotEmpty) {
                      String label = cmdDesc;
                      if (label.isEmpty) {
                        label = cmdMsg.startsWith('/') ? cmdMsg.substring(1) : cmdMsg;
                        label = label.replaceAll('_', ' ');
                      }
                      dynamicCmds.add(QuickCommandModel(label: label, message: cmdMsg));
                    }
                  }
                }
              } else if (cmds is Map) {
                cmds.forEach((k, v) {
                  final String cmdKey = k.toString();
                  String label = v?.toString() ?? '';
                  if (label.isEmpty) {
                    label = cmdKey.startsWith('/') ? cmdKey.substring(1) : cmdKey;
                    label = label.replaceAll('_', ' ');
                  }
                  dynamicCmds.add(QuickCommandModel(label: label, message: cmdKey));
                });
              }
              if (dynamicCmds.isNotEmpty) {
                _deviceQuickCommands[deviceId] = dynamicCmds;
                notifyListeners();
              }
            }

            // Telemetry Data (Preserving duplicate keys if present)
            final Map<String, dynamic> nestedData = _extractDataPreservingDuplicates(
              data,
              event['data'] is Map ? Map<String, dynamic>.from(event['data'] as Map) : null,
            );

            // Determine the message text to display in the chat screen bubble (supporting flat and nested "data" formats)
            if (event.containsKey('text') || event.containsKey('message')) {
              textMsg = event['text'] as String? ?? event['message'] as String?;
            } else {
              final List<String> lines = [];

              if (nestedData.isNotEmpty) {
                nestedData.forEach((k, v) {
                  String label = k.toString().replaceAll('_', ' ');
                  final displayVal = (v is Map && v.containsKey('value')) ? v['value'] : v;
                  lines.add('$label: $displayVal');
                });
              } else {
                event.forEach((k, v) {
                  final String lowerKey = k.toLowerCase();
                  if (lowerKey != 'availablecommands' &&
                      lowerKey != 'additionalcommands' &&
                      lowerKey != 'type' &&
                      lowerKey != 'id' &&
                      lowerKey != 'deviceid' &&
                      lowerKey != 'timestamp' &&
                      lowerKey != 'data' &&
                      lowerKey != 'firmwareversion' &&
                      lowerKey != 'version' &&
                      !lowerKey.contains('command')) {
                    String label = k.replaceAll('_', ' ');
                    lines.add('$label: $v');
                  }
                });
              }

              if (lines.isNotEmpty) {
                textMsg = lines.join('\n');
              }
            }

            final isConfigCmd = activeCmd == '/config' ||
                event['command'] == '/config' ||
                (lastCmd == '/config');

            if (isConfigCmd) {
              return;
            }

            if ((hasDeviceId || hasData) && textMsg != null) {
              final lastCmd = _lastSentCommand[deviceId] ?? '';
              final isHolding = lastCmd == '/holding' ||
                  event['command'] == '/holding';
              final isSetting = lastCmd == '/setting' ||
                  event['command'] == '/setting';
              final isHoldingOrSetting = isHolding || isSetting;

              // Reset lastSentCommand once consumed so future status telemetry stays standard
              if (isHoldingOrSetting) {
                _lastSentCommand.remove(deviceId);
              }

              final effectiveData = nestedData.isNotEmpty
                  ? nestedData
                  : (event['data'] is Map ? Map<String, dynamic>.from(event['data'] as Map) : null);

              final newMsg = MessageModel(
                id: event['id'] as String? ?? 'ws_${DateTime.now().millisecondsSinceEpoch}',
                text: textMsg,
                command: event['command'] as String? ?? (lastCmd.isNotEmpty ? lastCmd : null),
                timestamp: DateTime.now(),
                isUser: false,
                rawData: effectiveData,
                isEditable: isHoldingOrSetting && effectiveData != null && effectiveData.isNotEmpty,
              );
              _addMessageLocally(deviceId, newMsg);
            }
          } catch (e) {
            debugPrint('Error parsing WebSocket data (ignored for chat): $e');
          }
        },
        onError: (err) {
          debugPrint('[WEBSOCKET ERROR] $err');
          _deviceConnectionStatus[deviceId] = 'offline';
          _heartbeatTimer?.cancel();
          notifyListeners();
          _scheduleAutoReconnect(deviceId);
        },
        onDone: () {
          debugPrint('[WEBSOCKET DISCONNECTED] CloseCode: ${_webSocket?.closeCode}, CloseReason: ${_webSocket?.closeReason}');
          _deviceConnectionStatus[deviceId] = 'offline';
          _heartbeatTimer?.cancel();
          notifyListeners();
          _scheduleAutoReconnect(deviceId);
        },
      );
    } catch (e) {
      debugPrint('[WEBSOCKET CONNECTION FAILED] $e');
      _deviceConnectionStatus[deviceId] = 'offline';
      notifyListeners();
      _scheduleAutoReconnect(deviceId);
    } finally {
      _isConnecting = false;
    }
  }

  void _scheduleAutoReconnect(String deviceId) {
    if (_activeConnectedDeviceId != deviceId) return;
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(const Duration(seconds: 4), () {
      if (_activeConnectedDeviceId == deviceId &&
          _deviceConnectionStatus[deviceId] != 'online' &&
          !_isConnecting) {
        debugPrint('[WEBSOCKET AUTO-RECONNECT] Attempting reconnect for $deviceId');
        connectWebSocket(deviceId);
      }
    });
  }

  Future<void> disconnectWebSocket({bool intentional = true}) async {
    if (intentional) {
      _activeConnectedDeviceId = null;
    }
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    await _wsSubscription?.cancel();
    _wsSubscription = null;
    _deviceConnectionStatus.clear();
    if (_webSocket != null) {
      debugPrint('--> [WEBSOCKET CLOSE] Closing WebSocket connection');
      try {
        await _webSocket!.close();
      } catch (e) {
        debugPrint('Error closing WebSocket: $e');
      }
      _webSocket = null;
    }
    _isConnecting = false;
  }

  void sendMessage(String deviceId, String text, {String? displayText}) {
    _lastSentCommand[deviceId] = text;
    final newMsg = MessageModel(
      id: 'msg_${DateTime.now().millisecondsSinceEpoch}',
      text: displayText ?? text,
      command: text,
      timestamp: DateTime.now(),
      isUser: true,
    );
    
    _addMessageLocally(deviceId, newMsg);

    if (_webSocket != null && _webSocket!.readyState == WebSocket.open) {
      try {
        final payload = jsonEncode({'command': text});
        debugPrint('--> [WEBSOCKET SEND] Payload: $payload');
        _webSocket!.add(payload);
      } catch (e, stack) {
        debugPrint('--> [WEBSOCKET SEND ERROR] $e');
        ErrorHandler.handle(e, stack);
      }
    } else {
      // Fallback mock chatbot response
      Future.delayed(const Duration(seconds: 1), () {
        final responseMsg = MessageModel(
          id: 'msg_${DateTime.now().millisecondsSinceEpoch}_bot',
          text: 'Command "$text" executed successfully.',
          timestamp: DateTime.now(),
          isUser: false,
        );
        _addMessageLocally(deviceId, responseMsg);
      });
    }
  }

  void writeSingleRegister(String deviceId, String key, dynamic value, {String writeCommand = '/write_holding'}) {
    final formattedKey = key.replaceAll('_', ' ');
    final displayText = 'Set $formattedKey: $value';
    _lastSentCommand[deviceId] = writeCommand;
    _pendingRegisterWrites[deviceId] = {'key': key, 'value': value};

    final newMsg = MessageModel(
      id: 'msg_${DateTime.now().millisecondsSinceEpoch}',
      text: displayText,
      command: writeCommand,
      timestamp: DateTime.now(),
      isUser: true,
    );
    
    _addMessageLocally(deviceId, newMsg);

    if (_webSocket != null && _webSocket!.readyState == WebSocket.open) {
      try {
        final payload = jsonEncode({
          'type': writeCommand,
          'data': {key: value},
        });
        debugPrint('--> [WEBSOCKET SEND] Payload: $payload');
        _webSocket!.add(payload);
      } catch (e, stack) {
        debugPrint('--> [WEBSOCKET SEND ERROR] $e');
        ErrorHandler.handle(e, stack);
      }
    } else {
      // Fallback mock response when running disconnected / offline
      Future.delayed(const Duration(seconds: 1), () {
        final isSettingCmd = writeCommand == '/write_setting';
        final itemLabel = isSettingCmd ? 'Setting' : 'Register';
        final responseMsg = MessageModel(
          id: 'msg_${DateTime.now().millisecondsSinceEpoch}_bot',
          text: '✓ $itemLabel "$formattedKey" updated to $value.',
          timestamp: DateTime.now(),
          isUser: false,
          isSuccess: true,
          responseCommand: writeCommand,
        );
        _addMessageLocally(deviceId, responseMsg);

        // Update latest message's rawData if available
        if (_messages.containsKey(deviceId)) {
          for (int i = _messages[deviceId]!.length - 1; i >= 0; i--) {
            final m = _messages[deviceId]![i];
            if (!m.isUser && m.rawData != null && m.rawData!.containsKey(key)) {
              final updatedData = Map<String, dynamic>.from(m.rawData!);
              if (updatedData[key] is Map) {
                final nested = Map<String, dynamic>.from(updatedData[key] as Map);
                final oldValStr = nested['value']?.toString() ?? '';
                final unitMatch = RegExp(r'^(-?\d+(?:\.\d+)?)\s*(.+)$').firstMatch(oldValStr.trim());
                final unit = (unitMatch != null && unitMatch.group(2) != null) ? unitMatch.group(2)!.trim() : '';
                if (unit.isNotEmpty && !value.toString().endsWith(unit)) {
                  nested['value'] = '$value $unit';
                } else {
                  nested['value'] = value;
                }
                updatedData[key] = nested;
              } else {
                updatedData[key] = value;
              }
              _messages[deviceId]![i] = m.copyWith(rawData: updatedData);
              break;
            }
          }
        }
        _pendingRegisterWrites.remove(deviceId);
        notifyListeners();
      });
    }
  }

  void sendConfig(String deviceId, Map<String, dynamic> configData) {
    if (_webSocket != null && _webSocket!.readyState == WebSocket.open) {
      try {
        final payload = jsonEncode({
          'command': '/config',
          'data': configData,
        });
        debugPrint('--> [WEBSOCKET SEND] Payload: $payload');
        _webSocket!.add(payload);
      } catch (e, stack) {
        debugPrint('--> [WEBSOCKET SEND ERROR] $e');
        ErrorHandler.handle(e, stack);
      }
    }

    // Trigger get all status command without displaying configuration telemetry table
    sendMessage(deviceId, '/status', displayText: 'Get device status');
  }

  void sendWifiSetup(String deviceId, String ssid, String password) {
    final maskedPass = password.isEmpty ? '(none)' : '•' * password.length;
    final displayText = 'Sent Wi-Fi Setup:\nSSID: $ssid\nPASS: $maskedPass';
    
    final newMsg = MessageModel(
      id: 'msg_${DateTime.now().millisecondsSinceEpoch}',
      text: displayText,
      timestamp: DateTime.now(),
      isUser: true,
    );
    _addMessageLocally(deviceId, newMsg);

    if (_webSocket != null && _webSocket!.readyState == WebSocket.open) {
      try {
        final payload = jsonEncode({
          'command': '/set-up_wifi',
          'data': {
            'SSID': ssid,
            'PASS': password,
          },
        });
        debugPrint('--> [WEBSOCKET SEND] Payload: $payload');
        _webSocket!.add(payload);
      } catch (e, stack) {
        debugPrint('--> [WEBSOCKET SEND ERROR] $e');
        ErrorHandler.handle(e, stack);
      }
    } else {
      // Mock response fallback
      Future.delayed(const Duration(seconds: 1), () {
        final responseMsg = MessageModel(
          id: 'msg_${DateTime.now().millisecondsSinceEpoch}_bot',
          text: 'Wi-Fi configuration sent successfully to device.',
          timestamp: DateTime.now(),
          isUser: false,
        );
        _addMessageLocally(deviceId, responseMsg);
      });
    }
  }

  Future<List<Map<String, dynamic>>> searchUsers(String query) async {
    final token = await _getToken();
    if (token == null) return [];

    final url = Uri.parse('${ApiConfig.baseUrl}/api/v1/users/search?query=$query');
    debugPrint('--> [API REQUEST] GET $url');

    try {
      final response = await http.get(
        url,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      ).timeout(_timeoutDuration);

      debugPrint('<-- [API RESPONSE] ${response.statusCode} GET $url');
      debugPrint('Response Body: ${response.body}');

      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        if (decoded is Map && decoded['data'] is List) {
          return List<Map<String, dynamic>>.from(
            (decoded['data'] as List).map((x) => Map<String, dynamic>.from(x as Map))
          );
        } else if (decoded is List) {
          return List<Map<String, dynamic>>.from(
            decoded.map((x) => Map<String, dynamic>.from(x as Map))
          );
        }
      }
    } catch (e, stack) {
      debugPrint('Error searching users: $e');
      ErrorHandler.handle(e, stack);
    }
    return [];
  }

  Future<void> shareDevice(String deviceId, String userId) async {
    final token = await _getToken();
    if (token == null) {
      throw const UnauthorizedException();
    }

    final url = Uri.parse('${ApiConfig.baseUrl}/api/v1/devices/$deviceId/share');
    debugPrint('--> [API REQUEST] POST $url');

    try {
      final response = await http.post(
        url,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({'userId': userId}),
      ).timeout(_timeoutDuration);

      debugPrint('<-- [API RESPONSE] ${response.statusCode} POST $url');
      debugPrint('Response Body: ${response.body}');

      if (response.statusCode != 200 && response.statusCode != 201) {
        ErrorHandler.parseHttpResponse(response, defaultErrorMessage: 'Failed to share device.');
      }
    } catch (e, stack) {
      throw ErrorHandler.handle(e, stack);
    }
  }

  Future<void> unshareDevice(String deviceId, String userId) async {
    final token = await _getToken();
    if (token == null) {
      throw const UnauthorizedException();
    }

    final url = Uri.parse('${ApiConfig.baseUrl}/api/v1/devices/$deviceId/share/$userId');
    debugPrint('--> [API REQUEST] DELETE $url');

    try {
      final response = await http.delete(
        url,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      ).timeout(_timeoutDuration);

      debugPrint('<-- [API RESPONSE] ${response.statusCode} DELETE $url');
      debugPrint('Response Body: ${response.body}');

      if (response.statusCode != 200 && response.statusCode != 204) {
        ErrorHandler.parseHttpResponse(response, defaultErrorMessage: 'Failed to unshare device.');
      }
    } catch (e, stack) {
      throw ErrorHandler.handle(e, stack);
    }
  }

  static Map<String, dynamic> _extractDataPreservingDuplicates(dynamic rawData, Map<String, dynamic>? fallbackData) {
    if (rawData == null) return fallbackData ?? {};
    if (fallbackData != null && fallbackData.values.any((v) => v is Map)) {
      return fallbackData;
    }
    final String rawJson = rawData is String
        ? rawData
        : (rawData is List<int> ? utf8.decode(rawData) : rawData.toString());

    try {
      final dataKeyMatch = RegExp(r'"data"\s*:\s*\{').firstMatch(rawJson);
      if (dataKeyMatch == null) {
        return fallbackData ?? {};
      }

      final openBraceIndex = rawJson.indexOf('{', dataKeyMatch.start);
      if (openBraceIndex == -1) {
        return fallbackData ?? {};
      }

      // Find matching closing brace
      int depth = 0;
      int closeBraceIndex = -1;
      bool inString = false;
      bool isEscaped = false;

      for (int i = openBraceIndex; i < rawJson.length; i++) {
        final char = rawJson[i];
        if (isEscaped) {
          isEscaped = false;
          continue;
        }
        if (char == '\\') {
          isEscaped = true;
          continue;
        }
        if (char == '"') {
          inString = !inString;
          continue;
        }
        if (!inString) {
          if (char == '{') {
            depth++;
          } else if (char == '}') {
            depth--;
            if (depth == 0) {
              closeBraceIndex = i;
              break;
            }
          }
        }
      }

      if (closeBraceIndex == -1) {
        return fallbackData ?? {};
      }

      final dataContent = rawJson.substring(openBraceIndex + 1, closeBraceIndex);

      // Match each "key" : "value" or numeric/boolean/null value
      final RegExp pairRegex = RegExp(r'"([^"\\]*(?:\\.[^"\\]*)*)"\s*:\s*("(?:[^"\\]*(?:\\.[^"\\]*)*)"|[0-9.]+|true|false|null)');
      final matches = pairRegex.allMatches(dataContent).toList();

      if (matches.isEmpty) {
        return fallbackData ?? {};
      }

      // Count total occurrences of each key first
      final Map<String, int> totalOccurrences = {};
      for (final match in matches) {
        String key = match.group(1) ?? '';
        key = key.replaceAll(r'\"', '"');
        totalOccurrences[key] = (totalOccurrences[key] ?? 0) + 1;
      }

      final Map<String, dynamic> result = {};
      final Map<String, int> currentCounts = {};

      for (final match in matches) {
        String key = match.group(1) ?? '';
        key = key.replaceAll(r'\"', '"');

        final rawVal = match.group(2) ?? '';
        dynamic val;
        if (rawVal.startsWith('"') && rawVal.endsWith('"')) {
          val = rawVal.substring(1, rawVal.length - 1).replaceAll(r'\"', '"');
        } else if (rawVal == 'true') {
          val = true;
        } else if (rawVal == 'false') {
          val = false;
        } else if (rawVal == 'null') {
          val = null;
        } else {
          val = num.tryParse(rawVal) ?? rawVal;
        }

        currentCounts[key] = (currentCounts[key] ?? 0) + 1;
        final currentIdx = currentCounts[key]!;

        String finalKey = key;
        if ((totalOccurrences[key] ?? 0) > 1) {
          finalKey = '$key $currentIdx';
        }

        result[finalKey] = val;
      }

      return result;
    } catch (e) {
      debugPrint('Error extracting duplicate keys from raw JSON: $e');
      return fallbackData ?? {};
    }
  }

  void _addMessageLocally(String deviceId, MessageModel newMsg) {
    if (_messages.containsKey(deviceId)) {
      // Deduplicate: if an incoming message (isUser == false) has the identical text
      // as the last incoming message and arrived within 2 seconds, ignore it.
      if (!newMsg.isUser && _messages[deviceId]!.isNotEmpty) {
        final lastMsg = _messages[deviceId]!.last;
        if (!lastMsg.isUser &&
            lastMsg.text == newMsg.text &&
            newMsg.timestamp.difference(lastMsg.timestamp).inMilliseconds.abs() < 2000) {
          debugPrint('[DEDUPLICATION] Discarding duplicate incoming message for $deviceId: ${newMsg.text.replaceAll('\n', ' ')}');
          return;
        }
      }
      _messages[deviceId]!.add(newMsg);
    } else {
      _messages[deviceId] = [newMsg];
    }
    
    final index = _devices.indexWhere((d) => d.id == deviceId);
    if (index != -1) {
      _devices[index] = _devices[index].copyWith(
        lastMessage: newMsg.text,
        timestamp: DateTime.now(),
      );
    }
    notifyListeners();
  }

  Future<void> clearSession() async {
    await disconnectWebSocket(intentional: true);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('cached_devices');
    } catch (e) {
      debugPrint('Error clearing cached devices: $e');
    }
    _devices.clear();
    _messages.clear();
    _deviceConnectionStatus.clear();
    _deviceLastSeenIST.clear();
    _deviceDetails.clear();
    _deviceQuickCommands.clear();
    _latestDeviceStatusData.clear();
    _lastSentCommand.clear();
    _pendingRegisterWrites.clear();
    _customQuickCommands.clear();
    _activeConnectedDeviceId = null;
    _isConnecting = false;
    _isLoading = false;
    notifyListeners();
  }

  @override
  void dispose() {
    _reconnectTimer?.cancel();
    _heartbeatTimer?.cancel();
    _wsSubscription?.cancel();
    _webSocket?.close();
    super.dispose();
  }
}

