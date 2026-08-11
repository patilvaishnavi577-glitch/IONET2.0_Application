import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mime/mime.dart';
import 'package:http_parser/http_parser.dart';
import '../api_config.dart';

class AuthProvider extends ChangeNotifier {
  bool _isAuthenticated = false;
  bool _isFirstTimeUser = true;
  String? _email;
  String? _name;
  String? _mobile;
  int _credits = 50;
  String? _token;
  String? _profilePicture;
  String? _userId;

  bool get isAuthenticated => _isAuthenticated;
  bool get isFirstTimeUser => _isFirstTimeUser;
  String? get email => _email;
  String? get name => _name;
  String? get mobile => _mobile;
  int get credits => _credits;
  String? get token => _token;
  String? get profilePicture => _profilePicture;
  String? get userId => _userId;

  // Logging wrapper for POST requests
  Future<http.Response> _post(String path, {Map<String, String>? headers, Object? body}) async {
    final url = Uri.parse('${ApiConfig.baseUrl}$path');
    final formattedHeaders = {
      'Content-Type': 'application/json',
      ...?headers,
    };
    final bodyString = body != null ? jsonEncode(body) : null;
    
    debugPrint('--> [API REQUEST] POST $url');
    if (bodyString != null) debugPrint('Body: $bodyString');

    final response = await http.post(url, headers: formattedHeaders, body: bodyString);

    debugPrint('<-- [API RESPONSE] ${response.statusCode} POST $url');
    debugPrint('Response Body: ${response.body}');
    return response;
  }

  // Logging wrapper for GET requests
  Future<http.Response> _get(String path, {Map<String, String>? headers}) async {
    final url = Uri.parse('${ApiConfig.baseUrl}$path');
    final formattedHeaders = {
      'Content-Type': 'application/json',
      ...?headers,
    };
    
    debugPrint('--> [API REQUEST] GET $url');

    final response = await http.get(url, headers: formattedHeaders);

    debugPrint('<-- [API RESPONSE] ${response.statusCode} GET $url');
    debugPrint('Response Body: ${response.body}');
    return response;
  }

  // Logging wrapper for PUT requests
  Future<http.Response> _put(String path, {Map<String, String>? headers, Object? body}) async {
    final url = Uri.parse('${ApiConfig.baseUrl}$path');
    final formattedHeaders = {
      'Content-Type': 'application/json',
      ...?headers,
    };
    final bodyString = body != null ? jsonEncode(body) : null;
    
    debugPrint('--> [API REQUEST] PUT $url');
    if (bodyString != null) debugPrint('Body: $bodyString');

    final response = await http.put(url, headers: formattedHeaders, body: bodyString);

    debugPrint('<-- [API RESPONSE] ${response.statusCode} PUT $url');
    debugPrint('Response Body: ${response.body}');
    return response;
  }

  // Logging wrapper for DELETE requests
  Future<http.Response> _delete(String path, {Map<String, String>? headers}) async {
    final url = Uri.parse('${ApiConfig.baseUrl}$path');
    final formattedHeaders = {
      'Content-Type': 'application/json',
      ...?headers,
    };
    
    debugPrint('--> [API REQUEST] DELETE $url');

    final response = await http.delete(url, headers: formattedHeaders);

    debugPrint('<-- [API RESPONSE] ${response.statusCode} DELETE $url');
    debugPrint('Response Body: ${response.body}');
    return response;
  }

  Future<void> loginWithEmail(String email) async {
    final response = await _post(
      '/api/v1/auth/request-otp',
      body: {'email': email.trim()},
    );

    if (response.statusCode >= 200 && response.statusCode < 300) {
      _email = email.trim();
    } else {
      String errMsg = 'Failed to request OTP';
      try {
        final body = jsonDecode(response.body);
        if (body is Map && body.containsKey('message')) {
          errMsg = body['message'].toString();
        }
      } catch (_) {}
      throw Exception(errMsg);
    }
  }

  Future<bool> verifyOtp(String email, String otp) async {
    final response = await _post(
      '/api/v1/auth/verify-otp',
      body: {
        'email': email.trim(),
        'otp': otp.trim(),
      },
    );

    if (response.statusCode >= 200 && response.statusCode < 300) {
      final body = jsonDecode(response.body);
      String? extractedToken;
      bool? profileCompleted;
      bool? isNewUser;

      if (body is Map) {
        final data = body['data'];
        if (data is Map) {
          extractedToken = data['accessToken'] as String? ?? data['token'] as String?;
          profileCompleted = data['profileCompleted'] as bool?;
          isNewUser = data['newUser'] as bool?;
        } else {
          extractedToken = body['token'] as String? ?? body['accessToken'] as String?;
        }
      }

      if (extractedToken != null) {
        _token = extractedToken;
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('jwt_token', extractedToken);

        _email = email.trim(); // Ensure email is set in state

        if (profileCompleted != null) {
          _isFirstTimeUser = !profileCompleted;
        }
        if (isNewUser != null && isNewUser) {
          _isFirstTimeUser = true;
        }

        // Fetch User Profile details to check credits and load data
        try {
          await fetchProfile();
        } catch (e) {
          // If profile fetch fails (e.g. 404), treat user as first time.
          debugPrint('Profile fetch failed during verify: $e');
          _isFirstTimeUser = true;
        }

        _isAuthenticated = true;
        notifyListeners();
        return true;
      }
    }
    return false;
  }

  Future<void> fetchProfile() async {
    if (_token == null) {
      throw Exception('Not authenticated.');
    }

    final response = await _get(
      '/api/v1/users/me',
      headers: {'Authorization': 'Bearer $_token'},
    );

    if (response.statusCode == 200) {
      final decoded = jsonDecode(response.body);
      Map<String, dynamic> profile = {};
      if (decoded is Map) {
        if (decoded['data'] is Map) {
          profile = Map<String, dynamic>.from(decoded['data'] as Map);
        } else {
          profile = Map<String, dynamic>.from(decoded);
        }
      }

      _userId = profile['id'] as String? ?? profile['_id'] as String?;
      _email = profile['email'] as String? ?? _email;
      _name = profile['name'] as String?;
      _mobile = profile['phoneNumber'] as String?;
      _credits = profile['creditPoints'] as int? ?? 50;
      
      final String? rawProfilePic = profile['profilePictureUrl'] as String? ??
                                    profile['profilePicture'] as String? ?? 
                                    profile['profileImage'] as String? ?? 
                                    profile['avatar'] as String?;
      
      if (rawProfilePic != null && rawProfilePic.isNotEmpty) {
        if (rawProfilePic.startsWith('http://') || rawProfilePic.startsWith('https://')) {
          _profilePicture = rawProfilePic;
        } else {
          final baseUrl = ApiConfig.baseUrl;
          final cleanBaseUrl = baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl;
          final cleanRawPic = rawProfilePic.startsWith('/') ? rawProfilePic : '/$rawProfilePic';
          _profilePicture = '$cleanBaseUrl$cleanRawPic';
        }
      } else {
        _profilePicture = null;
      }
      
      // If profile exists and has a name, they are not a first-time user.
      _isFirstTimeUser = (_name == null || _name!.isEmpty);
      notifyListeners();
    } else {
      throw Exception('Failed to fetch profile: ${response.statusCode}');
    }
  }

  Future<void> completeProfile(String name, String mobile) async {
    if (_token == null) {
      throw Exception('Not authenticated.');
    }

    final response = await _post(
      '/api/v1/users/profile',
      headers: {'Authorization': 'Bearer $_token'},
      body: {
        'name': name.trim(),
        'phoneNumber': mobile.trim(),
      },
    );

    if (response.statusCode >= 200 && response.statusCode < 300) {
      _name = name.trim();
      _mobile = mobile.trim();
      _isFirstTimeUser = false;
      notifyListeners();
    } else {
      String errMsg = 'Failed to complete profile';
      try {
        final body = jsonDecode(response.body);
        if (body is Map && body.containsKey('message')) {
          errMsg = body['message'].toString();
        }
      } catch (_) {}
      throw Exception(errMsg);
    }
  }

  Future<void> updateProfile(String name, String mobile) async {
    if (_token == null) {
      throw Exception('Not authenticated.');
    }

    final response = await _put(
      '/api/v1/users/profile',
      headers: {'Authorization': 'Bearer $_token'},
      body: {
        'name': name.trim(),
        'phoneNumber': mobile.trim(),
      },
    );

    if (response.statusCode >= 200 && response.statusCode < 300) {
      _name = name.trim();
      _mobile = mobile.trim();
      notifyListeners();
    } else {
      String errMsg = 'Failed to update profile';
      try {
        final body = jsonDecode(response.body);
        if (body is Map && body.containsKey('message')) {
          errMsg = body['message'].toString();
        }
      } catch (_) {}
      throw Exception(errMsg);
    }
  }

  Future<void> uploadProfilePicture(String filePath) async {
    if (_token == null) {
      throw Exception('Not authenticated.');
    }

    final url = Uri.parse('${ApiConfig.baseUrl}/api/v1/users/profile-picture');
    debugPrint('--> [API REQUEST MULTIPART] POST $url');
    debugPrint('File path: $filePath');

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
        ..headers['Authorization'] = 'Bearer $_token'
        ..files.add(multipartFile);

      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);

      debugPrint('<-- [API RESPONSE] ${response.statusCode} POST $url');
      debugPrint('Response Body: ${response.body}');

      if (response.statusCode >= 200 && response.statusCode < 300) {
        await fetchProfile();
      } else {
        throw Exception('Failed to upload profile picture: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('Error uploading profile picture: $e');
      rethrow;
    }
  }

  Future<void> deleteProfilePicture() async {
    if (_token == null) {
      throw Exception('Not authenticated.');
    }

    final response = await _delete(
      '/api/v1/users/profile-picture',
      headers: {'Authorization': 'Bearer $_token'},
    );

    if (response.statusCode >= 200 && response.statusCode < 300) {
      _profilePicture = null;
      notifyListeners();
    } else {
      throw Exception('Failed to delete profile picture: ${response.statusCode}');
    }
  }

  Future<bool> tryRestoreSession() async {
    final prefs = await SharedPreferences.getInstance();
    final savedToken = prefs.getString('jwt_token');
    if (savedToken != null && savedToken.isNotEmpty) {
      _token = savedToken;
      try {
        await fetchProfile();
        _isAuthenticated = true;
        notifyListeners();
        return true;
      } catch (e) {
        // Token might have expired, clear local state
        await logout();
      }
    }
    return false;
  }

  Future<void> deactivateAccount() async {
    if (_token == null) {
      throw Exception('Not authenticated.');
    }

    final response = await _delete(
      '/api/v1/users/me',
      headers: {'Authorization': 'Bearer $_token'},
    );

    if (response.statusCode >= 200 && response.statusCode < 300) {
      await logout();
    } else {
      throw Exception('Failed to deactivate account.');
    }
  }

  Future<void> logout() async {
    _token = null;
    _isAuthenticated = false;
    _isFirstTimeUser = true;
    _email = null;
    _name = null;
    _mobile = null;
    _credits = 50;
    _userId = null;

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('jwt_token');
    notifyListeners();
  }
}
