import 'dart:html' as html;

const String _themeStorageKey = 'exam_theme_mode';

bool? readWebThemeMode() {
  final stored = html.window.localStorage[_themeStorageKey];
  if (stored == null) {
    return null;
  }
  if (stored == 'dark') {
    return true;
  }
  if (stored == 'light') {
    return false;
  }
  return null;
}

void writeWebThemeMode(bool isDarkMode) {
  html.window.localStorage[_themeStorageKey] = isDarkMode ? 'dark' : 'light';
}
