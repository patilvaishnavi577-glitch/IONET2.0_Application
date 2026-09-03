import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ThemeProvider extends ChangeNotifier {
  ThemeMode _themeMode = ThemeMode.system;
  String _fontSize = 'Medium';

  ThemeMode get themeMode => _themeMode;
  String get fontSize => _fontSize;

  double get fontScaleFactor {
    switch (_fontSize) {
      case 'Small':
        return 0.85;
      case 'Large':
        return 1.2;
      case 'Medium':
      default:
        return 1.0;
    }
  }

  Future<void> loadSavedTheme() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final mode = prefs.getString('theme_mode');
      if (mode != null) {
        if (mode == 'light') {
          _themeMode = ThemeMode.light;
        } else if (mode == 'dark') {
          _themeMode = ThemeMode.dark;
        } else {
          _themeMode = ThemeMode.system;
        }
      }
      
      final savedFontSize = prefs.getString('font_size');
      if (savedFontSize != null) {
        _fontSize = savedFontSize;
      }
      notifyListeners();
    } catch (e) {
      debugPrint('Error loading theme or font size: $e');
    }
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    _themeMode = mode;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      String modeStr = 'system';
      if (mode == ThemeMode.light) {
        modeStr = 'light';
      } else if (mode == ThemeMode.dark) {
        modeStr = 'dark';
      }
      await prefs.setString('theme_mode', modeStr);
    } catch (e) {
      debugPrint('Error saving theme: $e');
    }
  }

  Future<void> setFontSize(String size) async {
    _fontSize = size;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('font_size', size);
    } catch (e) {
      debugPrint('Error saving font size: $e');
    }
  }
}
