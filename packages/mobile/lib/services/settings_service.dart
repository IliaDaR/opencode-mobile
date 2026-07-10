import "package:flutter/material.dart";
import "package:shared_preferences/shared_preferences.dart";

class SettingsService {
  static late SharedPreferences _prefs;

  static Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
  }

  // ... existing getters/setters ...

  static ThemeMode get themeMode {
    final v = _prefs.getString("theme_mode") ?? "dark";
    return v == "light" ? ThemeMode.light : ThemeMode.dark;
  }

  static set themeMode(ThemeMode mode) {
    _prefs.setString("theme_mode", mode == ThemeMode.light ? "light" : "dark");
  }

  static String get deepseekApiKey {
    return _prefs.getString("deepseek_key") ?? "";
  }

  static set deepseekApiKey(String value) {
    _prefs.setString("deepseek_key", value);
  }

  static String get githubToken {
    return _prefs.getString("github_token") ?? "";
  }

  static set githubToken(String value) {
    _prefs.setString("github_token", value);
  }

  static String get githubUser {
    return _prefs.getString("github_user") ?? "";
  }

  static set githubUser(String value) {
    _prefs.setString("github_user", value);
  }

  static String get currentProject {
    return _prefs.getString("current_project") ?? "";
  }

  static set currentProject(String value) {
    _prefs.setString("current_project", value);
  }

  static String get language {
    return _prefs.getString("language") ?? "";
  }

  static set language(String value) {
    _prefs.setString("language", value);
  }

  static bool get isConfigured {
    return deepseekApiKey.isNotEmpty;
  }

  // ── SSH ──
  static String get sshHost => _prefs.getString("ssh_host") ?? "";
  static set sshHost(String v) => _prefs.setString("ssh_host", v);

  static String get sshUser => _prefs.getString("ssh_user") ?? "";
  static set sshUser(String v) => _prefs.setString("ssh_user", v);

  static String get sshKeyPath => _prefs.getString("ssh_key_path") ?? "";
  static set sshKeyPath(String v) => _prefs.setString("ssh_key_path", v);

  // ── Model ──
  static String get model => _prefs.getString("model") ?? "deepseek-chat";
  static set model(String v) => _prefs.setString("model", v);
}
