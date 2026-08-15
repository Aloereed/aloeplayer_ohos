/*
 * @Author: 
 * @Date: 2025-01-12 15:12:10
 * @LastEditors: 
 * @LastEditTime: 2025-01-12 15:12:24
 * @Description: file content
 */

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ThemeProvider extends ChangeNotifier {
  ThemeMode _themeMode = ThemeMode.system;
  bool _pcMode = false;

  ThemeProvider();

  ThemeMode get themeMode => _themeMode;
  bool get pcMode => _pcMode;

  Future<void> setThemeMode(ThemeMode mode) async {
    _themeMode = mode;
    notifyListeners();

    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('themeMode', mode.index);
  }

  Future<void> setPCMode(bool enabled) async {
    _pcMode = enabled;
    notifyListeners();

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('pc_mode', enabled);
  }

  Future<void> initialize() async {
    final prefs = await SharedPreferences.getInstance();

    // Load Theme Mode
    final themeIndex = prefs.getInt('themeMode') ?? ThemeMode.system.index;
    _themeMode = ThemeMode.values[themeIndex];

    // Load PC Mode
    _pcMode = prefs.getBool('pc_mode') ?? false;

    notifyListeners();
  }
}
