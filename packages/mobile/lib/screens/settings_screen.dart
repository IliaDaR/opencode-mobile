import "package:flutter/material.dart";
import "../main.dart";
import "../services/settings_service.dart";
import "../services/localization.dart";

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _deepseekCtrl = TextEditingController();
  final _githubTokenCtrl = TextEditingController();
  final _githubUserCtrl = TextEditingController();
  final _sshHostCtrl = TextEditingController();
  final _sshUserCtrl = TextEditingController();
  final _sshPathCtrl = TextEditingController();
  bool _showDeepseek = false;
  bool _showToken = false;
  String _language = "en";
  String _model = "deepseek-chat";

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    _deepseekCtrl.text = await SettingsService.deepseekApiKey;
    _githubTokenCtrl.text = await SettingsService.githubToken;
    _githubUserCtrl.text = await SettingsService.githubUser;
    _sshHostCtrl.text = SettingsService.sshHost;
    _sshUserCtrl.text = SettingsService.sshUser;
    _sshPathCtrl.text = SettingsService.sshKeyPath;
    _language = SettingsService.language.isEmpty ? "en" : SettingsService.language;
    _model = SettingsService.model.isEmpty ? "deepseek-chat" : SettingsService.model;
  }

  @override
  void dispose() {
    _deepseekCtrl.dispose();
    _githubTokenCtrl.dispose();
    _githubUserCtrl.dispose();
    _sshHostCtrl.dispose();
    _sshUserCtrl.dispose();
    _sshPathCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    await SettingsService.setDeepseekApiKey(_deepseekCtrl.text.trim());
    await SettingsService.setGithubToken(_githubTokenCtrl.text.trim());
    await SettingsService.setGithubUser(_githubUserCtrl.text.trim());
    SettingsService.sshHost = _sshHostCtrl.text.trim();
    SettingsService.sshUser = _sshUserCtrl.text.trim();
    SettingsService.sshKeyPath = _sshPathCtrl.text.trim();
    SettingsService.language = _language;
    SettingsService.model = _model;
    AppLocalization.current = _language;

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Saved"), backgroundColor: Color(0xFF3FB950)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = OpenCodeApp.of(context)?.themeMode == ThemeMode.dark;

    return Scaffold(
      appBar: AppBar(title: const Text("Settings")),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ── Appearance ──
          _header("Appearance", cs),
          const SizedBox(height: 12),
          Card(
            color: cs.surface,
            child: Column(
              children: [
                SwitchListTile(
                  title: const Text("Dark mode"),
                  subtitle: Text(isDark ? "Dark theme active" : "Light theme active", style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
                  value: isDark,
                  onChanged: (_) => OpenCodeApp.of(context)?.toggleTheme(),
                ),
                const Divider(height: 1, indent: 16, endIndent: 16),
                ListTile(
                  title: const Text("Language"),
                  trailing: SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(value: "en", label: Text("EN")),
                      ButtonSegment(value: "ru", label: Text("RU")),
                    ],
                    selected: {_language},
                    onSelectionChanged: (v) => setState(() => _language = v.first),
                    style: ButtonStyle(
                      visualDensity: VisualDensity.compact,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // ── AI Model ──
          _header("AI Model", cs),
          const SizedBox(height: 12),
          Card(
            color: cs.surface,
            child: Column(
              children: [
                ListTile(
                  title: const Text("Model"),
                  trailing: DropdownButton<String>(
                    value: _model,
                    underline: const SizedBox(),
                    onChanged: (v) => setState(() => _model = v!),
                    items: const [
                      DropdownMenuItem(value: "deepseek-chat", child: Text("DeepSeek V3")),
                      DropdownMenuItem(value: "deepseek-reasoner", child: Text("DeepSeek R1")),
                    ],
                  ),
                ),
                const Divider(height: 1, indent: 16, endIndent: 16),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text("API Key", style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13)),
                      const SizedBox(height: 6),
                      TextField(
                        controller: _deepseekCtrl,
                        obscureText: !_showDeepseek,
                        decoration: InputDecoration(
                          hintText: "sk-...",
                          suffixIcon: IconButton(
                            icon: Icon(_showDeepseek ? Icons.visibility_off : Icons.visibility),
                            onPressed: () => setState(() => _showDeepseek = !_showDeepseek),
                          ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text("platform.deepseek.com → API Keys", style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // ── GitHub ──
          _header("GitHub", cs),
          const SizedBox(height: 12),
          Card(
            color: cs.surface,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("Token", style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13)),
                  const SizedBox(height: 6),
                  TextField(
                    controller: _githubTokenCtrl,
                    obscureText: !_showToken,
                    decoration: InputDecoration(
                      hintText: "ghp_...",
                      suffixIcon: IconButton(
                        icon: Icon(_showToken ? Icons.visibility_off : Icons.visibility),
                        onPressed: () => setState(() => _showToken = !_showToken),
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text("GitHub → Settings → Developer settings → Tokens (repo scope)", style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
                  const SizedBox(height: 16),
                  Text("Username", style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13)),
                  const SizedBox(height: 6),
                  TextField(controller: _githubUserCtrl, decoration: const InputDecoration(hintText: "your-username")),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),

          // ── SSH ──
          _header("SSH", cs),
          const SizedBox(height: 12),
          Card(
            color: cs.surface,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("Host", style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13)),
                  const SizedBox(height: 6),
                  TextField(controller: _sshHostCtrl, decoration: const InputDecoration(hintText: "your-server.com")),
                  const SizedBox(height: 12),
                  Text("User", style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13)),
                  const SizedBox(height: 6),
                  TextField(controller: _sshUserCtrl, decoration: const InputDecoration(hintText: "root")),
                  const SizedBox(height: 12),
                  Text("Key path", style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13)),
                  const SizedBox(height: 6),
                  TextField(controller: _sshPathCtrl, decoration: const InputDecoration(hintText: "/home/user/.ssh/id_rsa")),
                ],
              ),
            ),
          ),
          const SizedBox(height: 30),

          // ── Save button ──
          FilledButton(
            onPressed: _save,
            style: FilledButton.styleFrom(
              backgroundColor: cs.primary,
              minimumSize: const Size.fromHeight(50),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text("Save", style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          ),
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  Widget _header(String text, ColorScheme cs) {
    return Text(text, style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13, fontWeight: FontWeight.w600, letterSpacing: 0.5));
  }
}
