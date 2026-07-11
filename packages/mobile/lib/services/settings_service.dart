import "package:flutter/material.dart";
import "package:shared_preferences/shared_preferences.dart";
import "package:flutter_secure_storage/flutter_secure_storage.dart";

class SettingsService {
  static SharedPreferences? _prefs;
  static const _secureStorage = FlutterSecureStorage();

  static Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
  }

  static SharedPreferences get _instance {
    if (_prefs == null) {
      throw StateError("SettingsService not initialized. Call SettingsService.init() first.");
    }
    return _prefs!;
  }

  // ── Non-sensitive settings (SharedPreferences) ──

  static ThemeMode get themeMode {
    final v = _instance.getString("theme_mode") ?? "dark";
    return v == "light" ? ThemeMode.light : ThemeMode.dark;
  }

  static set themeMode(ThemeMode mode) {
    _instance.setString("theme_mode", mode == ThemeMode.light ? "light" : "dark");
  }

  static String get currentProject => _instance.getString("current_project") ?? "";
  static set currentProject(String value) => _instance.setString("current_project", value);

  static String get language => _instance.getString("language") ?? "";
  static set language(String value) => _instance.setString("language", value);

  static String get model => _instance.getString("model") ?? "deepseek-chat";
  static set model(String v) => _instance.setString("model", v);

  // SSH (non-sensitive)
  static String get sshHost => _instance.getString("ssh_host") ?? "";
  static set sshHost(String v) => _instance.setString("ssh_host", v);

  static String get sshUser => _instance.getString("ssh_user") ?? "";
  static set sshUser(String v) => _instance.setString("ssh_user", v);

  static String get sshKeyPath => _instance.getString("ssh_key_path") ?? "";
  static set sshKeyPath(String v) => _instance.setString("ssh_key_path", v);

  // ── Sensitive settings (FlutterSecureStorage) ──

  static Future<String> get deepseekApiKey async =>
      await _secureStorage.read(key: "deepseek_key") ?? "";
  static Future<void> set deepseekApiKey(String value) async =>
      await _secureStorage.write(key: "deepseek_key", value: value);

  static Future<String> get githubToken async =>
      await _secureStorage.read(key: "github_token") ?? "";
  static Future<void> set githubToken(String value) async =>
      await _secureStorage.write(key: "github_token", value: value);

  static Future<String> get githubUser async =>
      await _secureStorage.read(key: "github_user") ?? "";
  static Future<void> set githubUser(String value) async =>
      await _secureStorage.write(key: "github_user", value: value);

  static Future<bool> get isConfigured async =>
      (await deepseekApiKey).isNotEmpty;

  /// Clear all secure data (logout)
  static Future<void> clearSecureData() async {
    await _secureStorage.deleteAll();
  }
}