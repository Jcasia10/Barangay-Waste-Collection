import 'dart:html' as html;

const String _webSessionMarkerKey = 'exam_web_session_active';

bool hasActiveWebSessionMarker() {
  return html.window.sessionStorage[_webSessionMarkerKey] == '1';
}

void markWebSessionActive() {
  html.window.sessionStorage[_webSessionMarkerKey] = '1';
}

void clearWebSessionMarker() {
  html.window.sessionStorage.remove(_webSessionMarkerKey);
}
