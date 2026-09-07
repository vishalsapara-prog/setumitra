import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../services/theme_service.dart';

/// App-wide theme state, loaded from local persistence on startup and
/// updated live when the user switches themes in Settings. Matches
/// [DraftProvider]'s pattern for consistency. Switching themes affects
/// appearance only -- no data or provider state is touched here.
class ThemeProvider extends ChangeNotifier {
  SetumitraTheme _current = SetumitraTheme.professionalBlue;
  bool _isLoading = true;

  SetumitraTheme get current => _current;
  ThemeData get themeData => ThemeService.themeDataFor(_current);
  bool get isLoading => _isLoading;

  Future<void> loadTheme() async {
    _current = await ThemeService.loadTheme();
    _isLoading = false;
    notifyListeners();
  }

  Future<void> setTheme(SetumitraTheme theme) async {
    _current = theme;
    notifyListeners();
    await ThemeService.saveTheme(theme);
  }
}
