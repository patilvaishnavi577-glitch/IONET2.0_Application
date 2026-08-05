import '../api_route_path.dart';

class ApiConfig {
  static String _baseUrl = 'http://localhost:8080';

  static String get baseUrl => _baseUrl;

  static String get wsUrl {
    if (_baseUrl.startsWith('https://')) {
      return _baseUrl.replaceFirst('https://', 'wss://');
    } else {
      return _baseUrl.replaceFirst('http://', 'ws://');
    }
  }

  static void initialize() {
    String path = apiRoutePath.trim();
    if (path.isNotEmpty) {
      if (path.startsWith('http://') || path.startsWith('https://')) {
        _baseUrl = path;
      } else {
        _baseUrl = 'http://$path';
      }
    }
    
    // Remove trailing slash if present
    if (_baseUrl.endsWith('/')) {
      _baseUrl = _baseUrl.substring(0, _baseUrl.length - 1);
    }
  }
}
