import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../api_config.dart';
import '../errors/app_exceptions.dart';
import '../errors/error_handler.dart';
import '../../ui/support/knowledge_device_model.dart';

class SupportProvider with ChangeNotifier {
  static const Duration _timeoutDuration = Duration(seconds: 15);
  List<KnowledgeDevice> _channels = [];
  List<KnowledgeDevice> _subscribedChannels = [];
  bool _isLoading = false;
  String? _error;

  List<KnowledgeDevice> get channels => _channels;
  List<KnowledgeDevice> get subscribedChannels => _subscribedChannels;
  bool get isLoading => _isLoading;
  String? get error => _error;

  Future<String?> _getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('jwt_token');
  }

  bool isFollowing(String channelId) {
    return _subscribedChannels.any((c) => c.id == channelId);
  }

  Future<void> fetchChannels() async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final url = Uri.parse('${ApiConfig.baseUrl}/api/v1/channels');
      debugPrint('--> [SupportProvider] GET $url');
      final response = await http
          .get(url, headers: {'Content-Type': 'application/json'})
          .timeout(_timeoutDuration);
      debugPrint('<-- [SupportProvider] ${response.statusCode} GET $url');

      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        List<dynamic> list = [];
        if (decoded is List) {
          list = decoded;
        } else if (decoded is Map && decoded['data'] is List) {
          list = decoded['data'];
        }
        _channels = list.map((json) => KnowledgeDevice.fromJson(json)).toList();
      } else {
        _error = 'Failed to load channels';
      }
    } catch (e, stack) {
      debugPrint('Error fetching channels: $e');
      final appErr = ErrorHandler.handle(e, stack);
      _error = appErr.userMessage;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> fetchSubscribedChannels() async {
    final token = await _getToken();
    if (token == null) return;

    try {
      final url = Uri.parse('${ApiConfig.baseUrl}/api/v1/users/subscribed-channels');
      debugPrint('--> [SupportProvider] GET $url');
      final response = await http.get(
        url,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      ).timeout(_timeoutDuration);
      debugPrint('<-- [SupportProvider] ${response.statusCode} GET $url');

      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        List<dynamic> list = [];
        if (decoded is List) {
          list = decoded;
        } else if (decoded is Map && decoded['data'] is List) {
          list = decoded['data'];
        }
        _subscribedChannels = list.map((json) => KnowledgeDevice.fromJson(json)).toList();
      }
    } catch (e, stack) {
      debugPrint('Error fetching subscribed channels: $e');
      ErrorHandler.handle(e, stack);
    }
    notifyListeners();
  }

  Future<void> followChannel(String channelId) async {
    final token = await _getToken();
    if (token == null) throw const UnauthorizedException();

    final url = Uri.parse('${ApiConfig.baseUrl}/api/v1/users/channels/$channelId/follow');
    debugPrint('--> [SupportProvider] POST $url');

    try {
      final response = await http.post(
        url,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      ).timeout(_timeoutDuration);
      debugPrint('<-- [SupportProvider] ${response.statusCode} POST $url');

      if (response.statusCode == 200 || response.statusCode == 201) {
        await fetchSubscribedChannels();
        await fetchChannels();
      } else {
        ErrorHandler.parseHttpResponse(response, defaultErrorMessage: 'Failed to follow channel');
      }
    } catch (e, stack) {
      debugPrint('Error following channel: $e');
      throw ErrorHandler.handle(e, stack);
    }
  }

  Future<void> unfollowChannel(String channelId) async {
    final token = await _getToken();
    if (token == null) throw const UnauthorizedException();

    final url = Uri.parse('${ApiConfig.baseUrl}/api/v1/users/channels/$channelId/unfollow');
    debugPrint('--> [SupportProvider] DELETE $url');

    try {
      final response = await http.delete(
        url,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      ).timeout(_timeoutDuration);
      debugPrint('<-- [SupportProvider] ${response.statusCode} DELETE $url');

      if (response.statusCode == 200 || response.statusCode == 204) {
        await fetchSubscribedChannels();
        await fetchChannels();
      } else {
        ErrorHandler.parseHttpResponse(response, defaultErrorMessage: 'Failed to unfollow channel');
      }
    } catch (e, stack) {
      debugPrint('Error unfollowing channel: $e');
      throw ErrorHandler.handle(e, stack);
    }
  }

  void clearSession() {
    _channels.clear();
    _subscribedChannels.clear();
    _isLoading = false;
    _error = null;
    notifyListeners();
  }
}
