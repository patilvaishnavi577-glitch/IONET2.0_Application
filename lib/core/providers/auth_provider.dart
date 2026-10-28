import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mime/mime.dart';
import 'package:http_parser/http_parser.dart';
import '../api_config.dart';

import '../errors/app_exceptions.dart';
import '../errors/error_handler.dart';

class AuthProvider extends ChangeNotifier {
  static const Duration _timeoutDuration = Duration(seconds: 15);
  bool _isAuthenticated = false;
  bool _isFirstTimeUser = false;
  String? _token;
  String? _email;
  String? _name;
  String? _mobile;
  int _credits = 50;
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

  // Logging wrapper for POST requests with timeout and error handling
  Future<http.Response> _post(String path, {Map<String, String>? headers, Object? body}) async {
    final url = Uri.parse('${ApiConfig.baseUrl}$path');
    final formattedHeaders = {
      'Content-Type': 'application/json',
      ...?headers,
    };
    final bodyString = body != null ? jsonEncode(body) : null;
    
    debugPrint('--> [API REQUEST] POST $url');
    if (bodyString != null) debugPrint('Body: $bodyString');

    try {
      final response = await http
          .post(url, headers: formattedHeaders, body: bodyString)
          
          .timeout(_timeoutDuration);

      debugPrint('<-- [API RESPONSE] ${response.statusCode} POST $url');
      debugPrint('Response Body: ${response.body}');
      return response;
    } catch (e, stack) {
      throw ErrorHandler.handle(e, stack);
    }
  }

  // Logging wrapper for GET requests with timeout and error handling
  Future<http.Response> _get(String path, {Map<String, String>? headers}) async {
    final url = Uri.parse('${ApiConfig.baseUrl}$path');
    final formattedHeaders = {
      'Content-Type': 'application/json',
      ...?headers,
    };
    
    debugPrint('--> [API REQUEST] GET $url');

    try {
      final response = await http
          .get(url, headers: formattedHeaders)
          .timeout(_timeoutDuration);

      debugPrint('<-- [API RESPONSE] ${response.statusCode} GET $url');
      debugPrint('Response Body: ${response.body}');
      return response;
    } catch (e, stack) {
      throw ErrorHandler.handle(e, stack);
    }
  }

  // Logging wrapper for PUT requests with timeout and error handling
  Future<http.Response> _put(String path, {Map<String, String>? headers, Object? body}) async {
    final url = Uri.parse('${ApiConfig.baseUrl}$path');
    final formattedHeaders = {
      'Content-Type': 'application/json',
      ...?headers,
    };
    final bodyString = body != null ? jsonEncode(body) : null;
    
    debugPrint('--> [API REQUEST] PUT $url');
    if (bodyString != null) debugPrint('Body: $bodyString');

    try {
      final response = await http
          .put(url, headers: formattedHeaders, body: bodyString)
          .timeout(_timeoutDuration);

      debugPrint('<-- [API RESPONSE] ${response.statusCode} PUT $url');
      debugPrint('Response Body: ${response.body}');
      return response;
    } catch (e, stack) {
      throw ErrorHandler.handle(e, stack);
    }
  }

  // Logging wrapper for DELETE requests with timeout and error handling
  Future<http.Response> _delete(String path, {Map<String, String>? headers}) async {
    final url = Uri.parse('${ApiConfig.baseUrl}$path');
    final formattedHeaders = {
      'Content-Type': 'application/json',
      ...?headers,
    };
    
    debugPrint('--> [API REQUEST] DELETE $url');

    try {
      final response = await http
          .delete(url, headers: formattedHeaders)
          .timeout(_timeoutDuration);

      debugPrint('<-- [API RESPONSE] ${response.statusCode} DELETE $url');
      debugPrint('Response Body: ${response.body}');
      return response;
    } catch (e, stack) {
      throw ErrorHandler.handle(e, stack);
    }
  }

  Future<void> loginWithEmail(String email) async {
    final response = await _post(
      '/api/v1/auth/request-otp',
      body: {'email': email.trim()},
    );

    if (response.statusCode >= 200 && response.statusCode < 300) {
      _email = email.trim();
    } else {
      ErrorHandler.parseHttpResponse(response, defaultErrorMessage: 'Failed to request OTP');
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
          debugPrint('Profile fetch failed during verify: $e');
          _isFirstTimeUser = true;
        }


        _isAuthenticated = true;
        notifyListeners();
        return true;
      }
    } else {
      ErrorHandler.parseHttpResponse(response, defaultErrorMessage: 'Invalid or expired OTP');
      
    }
    return false;
  }

  Future<void> fetchProfile() async {
    if (_token == null) {
      throw const UnauthorizedException();
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
      await _saveProfileLocally();
      notifyListeners();
    } else {
      ErrorHandler.parseHttpResponse(response, defaultErrorMessage: 'Failed to load user profile');
    }
  }

  Future<void> completeProfile(String name, String mobile) async {
    if (_token == null) {
      throw const UnauthorizedException();
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
      await _saveProfileLocally();
      notifyListeners();
    } else {
      ErrorHandler.parseHttpResponse(response, defaultErrorMessage: 'Failed to complete profile');
    }
  }

  Future<void> updateProfile(String name, String mobile) async {
    if (_token == null) {
      throw const UnauthorizedException();
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
      await _saveProfileLocally();
      notifyListeners();
    } else {
      ErrorHandler.parseHttpResponse(response, defaultErrorMessage: 'Failed to update profile');
    }
  }

  Future<void> uploadProfilePicture(String filePath) async {
    if (_token == null) {
      throw const UnauthorizedException();
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

      final streamedResponse = await request.send().timeout(const Duration(seconds: 25));
      final response = await http.Response.fromStream(streamedResponse);

      debugPrint('<-- [API RESPONSE] ${response.statusCode} POST $url');
      debugPrint('Response Body: ${response.body}');

      if (response.statusCode >= 200 && response.statusCode < 300) {
        await fetchProfile();
      } else {
        ErrorHandler.parseHttpResponse(response, defaultErrorMessage: 'Failed to upload profile picture');
      }
    } catch (e, stack) {
      throw ErrorHandler.handle(e, stack);
    }
  }

  Future<void> deleteProfilePicture() async {
    if (_token == null) {
      throw const UnauthorizedException();
    }

    final response = await _delete(
      '/api/v1/users/profile-picture',
      headers: {'Authorization': 'Bearer $_token'},
    );

    if (response.statusCode >= 200 && response.statusCode < 300) {
      _profilePicture = null;
      await _saveProfileLocally();
      notifyListeners();
    } else {
      ErrorHandler.parseHttpResponse(response, defaultErrorMessage: 'Failed to delete profile picture');
    }
  }

  Future<void> _saveProfileLocally() async {
    final prefs = await SharedPreferences.getInstance();
    if (_userId != null) await prefs.setString('user_id', _userId!);
    if (_email != null) await prefs.setString('user_email', _email!);
    if (_name != null) await prefs.setString('user_name', _name!);
    if (_mobile != null) await prefs.setString('user_mobile', _mobile!);
    await prefs.setInt('user_credits', _credits);
    if (_profilePicture != null) {
      await prefs.setString('user_profile_pic', _profilePicture!);
    } else {
      await prefs.remove('user_profile_pic');
    }
    await prefs.setBool('is_first_time_user', _isFirstTimeUser);
  }

  Future<void> _loadProfileLocally() async {
    final prefs = await SharedPreferences.getInstance();
    _userId = prefs.getString('user_id') ?? _userId;
    _email = prefs.getString('user_email') ?? _email;
    _name = prefs.getString('user_name') ?? _name;
    _mobile = prefs.getString('user_mobile') ?? _mobile;
    _credits = prefs.getInt('user_credits') ?? _credits;
    _profilePicture = prefs.getString('user_profile_pic') ?? _profilePicture;
    _isFirstTimeUser = prefs.getBool('is_first_time_user') ?? (_name == null || _name!.isEmpty);
  }

  Future<void> _clearProfileLocally() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('jwt_token');
    await prefs.remove('user_id');
    await prefs.remove('user_email');
    await prefs.remove('user_name');
    await prefs.remove('user_mobile');
    await prefs.remove('user_credits');
    await prefs.remove('user_profile_pic');
    await prefs.remove('is_first_time_user');
  
  }


  Future<bool> tryRestoreSession() async {
    final prefs = await SharedPreferences.getInstance();
    final savedToken = prefs.getString('jwt_token');
    if (savedToken != null && savedToken.isNotEmpty) {
      _token = savedToken;
      // Load cached profile data so the UI renders immediately offline
      await _loadProfileLocally();
      _isAuthenticated = true;
      notifyListeners();

      try {
        await fetchProfile();
        return true;
      } catch (e) {
        // ONLY log out if the backend explicitly rejected the token (401 Unauthorized)
        if (e is UnauthorizedException) {
          debugPrint('[AuthProvider] Token rejected (401). Clearing session.');
          await logout();
          return false;
        }
        // If offline (NetworkException) or timeout, retain cached credentials!
        debugPrint('[AuthProvider] Could not refresh profile from server ($e). Preserving offline session.');
        return true;
      }
    }
    return false;
  }

  Future<void> deactivateAccount() async {
    if (_token == null) {
      throw const UnauthorizedException();
    }

    final response = await _delete(
      '/api/v1/users/me',
      headers: {'Authorization': 'Bearer $_token'},
    );

    if (response.statusCode >= 200 && response.statusCode < 300) {
      await logout();
    } else {
      ErrorHandler.parseHttpResponse(response, defaultErrorMessage: 'Failed to deactivate account.');
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
    _profilePicture = null;

    await _clearProfileLocally();
    notifyListeners();
  }
}
