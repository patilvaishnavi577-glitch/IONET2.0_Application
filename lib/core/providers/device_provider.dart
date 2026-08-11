import 'dart:convert';
import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mime/mime.dart';
import 'package:http_parser/http_parser.dart';
import '../api_config.dart';
import '../../data/models/device_model.dart';
import '../../data/models/message_model.dart';
import '../../data/models/quick_command_model.dart';

class DeviceProvider extends ChangeNotifier {
  List<DeviceModel> _devices = [];
  final Map<String, List<MessageModel>> _messages = {};
  bool _isLoading = false;
  WebSocket? _webSocket;
  StreamSubscription? _wsSubscription;

  final Map<String, String> _deviceConnectionStatus = {};
  final Map<String, String> _deviceLastSeenIST = {};
  final Map<String, Map<String, dynamic>> _deviceDetails = {};
  final Map<String, List<QuickCommandModel>> _deviceQuickCommands = {};
  Timer? _heartbeatTimer;

  String getDeviceConnectionStatus(String deviceId) => _deviceConnectionStatus[deviceId] ?? 'offline';
  bool isDeviceOnline(String deviceId) => getDeviceConnectionStatus(deviceId) == 'online';
  String? getDeviceLastSeenIST(String deviceId) => _deviceLastSeenIST[deviceId];
  Map<String, dynamic>? getDeviceDetails(String deviceId) => _deviceDetails[deviceId];
  final Map<String, List<QuickCommandModel>> _customQuickCommands = {};
  
  List<QuickCommandModel> getQuickCommands(String deviceId) {
    return _customQuickCommands[deviceId] ?? [];
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

  DeviceProvider() {
    // Attempt initial load
    fetchDevices();
  }

  Future<String?> _getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('jwt_token');
  }

  Future<void> fetchDevices({String? type}) async {
    final token = await _getToken();
    if (token == null) {
      debugPrint('[DeviceProvider] Token is null, skipping device fetch.');
      return;
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
      );

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
          // If the profile endpoint is in some other shape, try common ones
          final possibleList = decoded['devices'] ?? decoded['results'];
          if (possibleList is List) {
            list = possibleList;
          }
        }
        
        _devices = list.map((json) => DeviceModel.fromJson(json)).toList();
      }
    } catch (e) {
      debugPrint('Error fetching devices: $e');
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
    if (token == null) throw Exception('Not authenticated');

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
      );

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
        String errMsg = 'Failed to add device';
        try {
          final body = jsonDecode(response.body);
          if (body is Map && body.containsKey('message')) {
            errMsg = body['message'].toString();
          }
        } catch (_) {}
        throw Exception(errMsg);
      }
    } catch (e) {
      debugPrint('Error adding device: $e');
      rethrow;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> deleteDevice(String id, {String? userId}) async {
    final token = await _getToken();
    if (token == null) throw Exception('Not authenticated');

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
        );

        if (getDeviceResponse.statusCode == 200) {
          final decoded = jsonDecode(getDeviceResponse.body);
          if (decoded['success'] == true && decoded['data'] != null) {
            final fetchedMongoId = decoded['data']['id']?.toString() ?? device.mongoId;
            url = '${ApiConfig.baseUrl}/api/v1/devices/$fetchedMongoId/share';
          } else {
            throw Exception('Failed to retrieve device details for unsharing.');
          }
        } else {
          throw Exception('Failed to fetch device details.');
        }
      }

      final response = await http.delete(
        Uri.parse(url),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      debugPrint('--> [API REQUEST] DELETE $url');
      debugPrint('<-- [API RESPONSE] ${response.statusCode} DELETE $url');
      debugPrint('Response Body: ${response.body}');

      if (response.statusCode >= 200 && response.statusCode < 300) {
        _devices.removeWhere((d) => d.id == id);
        _messages.remove(id);
      } else {
        String errMsg = device.isOwner ? 'Failed to delete device' : 'Failed to leave device';
        try {
          final body = jsonDecode(response.body);
          if (body is Map && body.containsKey('message')) {
            errMsg = body['message'].toString();
          }
        } catch (_) {}
        throw Exception(errMsg);
      }
    } catch (e) {
      debugPrint('Error deleting/leaving device: $e');
      rethrow;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> updateDeviceName(String id, String newName) async {
    final token = await _getToken();
    if (token == null) throw Exception('Not authenticated');

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
      );

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
        String errMsg = 'Failed to update device name';
        try {
          final body = jsonDecode(response.body);
          if (body is Map && body.containsKey('message')) {
            errMsg = body['message'].toString();
          }
        } catch (_) {}
        throw Exception(errMsg);
      }
    } catch (e) {
      debugPrint('Error updating device name: $e');
      rethrow;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> uploadDeviceImage(String deviceId, String filePath) async {
    final token = await _getToken();
    if (token == null) {
      throw Exception('Not authenticated.');
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

      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);

      debugPrint('<-- [API RESPONSE] ${response.statusCode} POST $url');
      debugPrint('Response Body: ${response.body}');

      if (response.statusCode >= 200 && response.statusCode < 300) {
        await fetchDevices();
        await fetchDeviceDetails(deviceId);
      } else {
        throw Exception('Failed to upload device image: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('Error uploading device image: $e');
      rethrow;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> deleteDeviceImage(String deviceId) async {
    final token = await _getToken();
    if (token == null) {
      throw Exception('Not authenticated.');
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
      );

      if (response.statusCode >= 200 && response.statusCode < 300) {
        await fetchDevices();
        await fetchDeviceDetails(deviceId);
      } else {
        throw Exception('Failed to delete device image: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('Error deleting device image: $e');
      rethrow;
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
      );

      debugPrint('<-- [API RESPONSE] ${response.statusCode} GET $url');
      debugPrint('Response Body: ${response.body}');

      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        if (decoded is Map && decoded['data'] is Map) {
          _deviceDetails[deviceId] = Map<String, dynamic>.from(decoded['data'] as Map);
          notifyListeners();
        }
      }
    } catch (e) {
      debugPrint('Error fetching device details: $e');
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
      );

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
    } catch (e) {
      debugPrint('Error fetching device by ID: $e');
    }
  }

  Future<void> connectWebSocket(String deviceId) async {
    final token = await _getToken();
    if (token == null) return;

    await disconnectWebSocket();

    // Call fetchDeviceById immediately to get initial lastSeen
    await fetchDeviceById(deviceId);

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

            // Determine the message text to display in the chat screen bubble (supporting flat and nested "data" formats)
            if (event.containsKey('text') || event.containsKey('message')) {
              textMsg = event['text'] as String? ?? event['message'] as String?;
            } else {
              final List<String> lines = [];

              // 1. Device ID
              final devId = event['deviceId'] ?? event['deviceid'] ?? deviceId;
              lines.add('Device Id : $devId');

              // // 2. Firmware Version
              // final fwVer = event['firmwareVersion'] ?? event['firmwareversion'] ?? event['version'] ?? '1.0.0';
              // lines.add('Firmware: $fwVer');

              // 3. Telemetry Data
              final dynamic nestedData = event['data'];
              if (nestedData is Map) {
                nestedData.forEach((k, v) {
                  String label = k.toString().replaceAll('_', ' ');
                  lines.add('$label: $v');
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

              // 4. Commands List
              final List<String> cmdLines = [];
              final cmds = event['availableCommands'] ?? event['additionalCommands'];
              if (cmds != null) {
                if (cmds is List) {
                  for (var item in cmds) {
                    if (item is Map) {
                      final cmdMsg = (item['command'] ?? item['message'] ?? '').toString();
                      final cmdDesc = (item['description'] ?? item['label'] ?? item['title'] ?? '').toString();
                      if (cmdMsg.isNotEmpty) {
                        cmdLines.add('$cmdMsg : $cmdDesc');
                      }
                    }
                  }
                } else if (cmds is Map) {
                  cmds.forEach((k, v) {
                    cmdLines.add('$k : $v');
                  });
                }
              }

              if (cmdLines.isNotEmpty) {
                lines.add(''); // Blank line before commands list
                lines.addAll(cmdLines);
              }

              if (lines.isNotEmpty) {
                textMsg = lines.join('\n');
              }
            }

            if ((hasDeviceId || hasData) && textMsg != null) {
              final newMsg = MessageModel(
                id: event['id'] as String? ?? 'ws_${DateTime.now().millisecondsSinceEpoch}',
                text: textMsg,
                timestamp: DateTime.now(),
                isUser: false,
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
        },
        onDone: () {
          debugPrint('[WEBSOCKET DISCONNECTED] CloseCode: ${_webSocket?.closeCode}, CloseReason: ${_webSocket?.closeReason}');
          _deviceConnectionStatus[deviceId] = 'offline';
          _heartbeatTimer?.cancel();
          notifyListeners();
        },
      );
    } catch (e) {
      debugPrint('[WEBSOCKET CONNECTION FAILED] $e');
      _deviceConnectionStatus[deviceId] = 'offline';
      notifyListeners();
    }
  }

  Future<void> disconnectWebSocket() async {
    _heartbeatTimer?.cancel();
    _wsSubscription?.cancel();
    _wsSubscription = null;
    _deviceConnectionStatus.clear();
    if (_webSocket != null) {
      debugPrint('--> [WEBSOCKET CLOSE] Closing WebSocket connection');
      await _webSocket!.close();
      _webSocket = null;
    }
  }

  void sendMessage(String deviceId, String text) {
    final newMsg = MessageModel(
      id: 'msg_${DateTime.now().millisecondsSinceEpoch}',
      text: text,
      timestamp: DateTime.now(),
      isUser: true,
    );
    
    _addMessageLocally(deviceId, newMsg);

    if (_webSocket != null && _webSocket!.readyState == WebSocket.open) {
      final payload = jsonEncode({'command': text});
      debugPrint('--> [WEBSOCKET SEND] Payload: $payload');
      _webSocket!.add(payload);
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
      );

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
    } catch (e) {
      debugPrint('Error searching users: $e');
    }
    return [];
  }

  Future<void> shareDevice(String deviceId, String userId) async {
    final token = await _getToken();
    if (token == null) {
      throw Exception('Not authenticated');
    }

    final url = Uri.parse('${ApiConfig.baseUrl}/api/v1/devices/$deviceId/share');
    debugPrint('--> [API REQUEST] POST $url');

    final response = await http.post(
      url,
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
      body: jsonEncode({'userId': userId}),
    );

    debugPrint('<-- [API RESPONSE] ${response.statusCode} POST $url');
    debugPrint('Response Body: ${response.body}');

    if (response.statusCode != 200 && response.statusCode != 201) {
      final decoded = jsonDecode(response.body);
      throw Exception(decoded['message'] ?? 'Failed to share device.');
    }
  }

  Future<void> unshareDevice(String deviceId, String userId) async {
    final token = await _getToken();
    if (token == null) {
      throw Exception('Not authenticated');
    }

    final url = Uri.parse('${ApiConfig.baseUrl}/api/v1/devices/$deviceId/share/$userId');
    debugPrint('--> [API REQUEST] DELETE $url');

    final response = await http.delete(
      url,
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
    );

    debugPrint('<-- [API RESPONSE] ${response.statusCode} DELETE $url');
    debugPrint('Response Body: ${response.body}');

    if (response.statusCode != 200 && response.statusCode != 204) {
      final decoded = jsonDecode(response.body);
      throw Exception(decoded['message'] ?? 'Failed to unshare device.');
    }
  }

  void _addMessageLocally(String deviceId, MessageModel newMsg) {
    if (_messages.containsKey(deviceId)) {
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
}
