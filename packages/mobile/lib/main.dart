import "package:flutter/material.dart";
import "package:flutter/services.dart";
import "screens/chat_screen.dart";
import "screens/settings_screen.dart";
import "services/settings_service.dart";
import "services/localization.dart";

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  await SettingsService.init();
  final hasKey = await SettingsService.deepseekApiKey;
  AppLocalization.current = SettingsService.language.isEmpty ? "en" : SettingsService.language;
  runApp(OpenCodeApp(hasApiKey: hasKey.isNotEmpty));
}

class OpenCodeApp extends StatefulWidget {
  final bool hasApiKey;
  const OpenCodeApp({super.key, required this.hasApiKey});
  static _OpenCodeAppState? of(BuildContext context) =>
      context.findAncestorStateOfType<_OpenCodeAppState>();

  @override
  State<OpenCodeApp> createState() => _OpenCodeAppState();
}

class _OpenCodeAppState extends State<OpenCodeApp> {
  ThemeMode _themeMode = ThemeMode.dark;

  @override
  void initState() {
    super.initState();
    _themeMode = SettingsService.themeMode;
  }

  void toggleTheme() {
    setState(() {
      _themeMode = _themeMode == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark;
      SettingsService.themeMode = _themeMode;
    });
  }

  ThemeMode get themeMode => _themeMode;

  ThemeData _buildTheme(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    return ThemeData(
      brightness: brightness,
      scaffoldBackgroundColor: isDark ? const Color(0xFF0D1117) : const Color(0xFFF6F8FA),
      colorScheme: isDark
          ? const ColorScheme.dark(
              surface: Color(0xFF161B22), primary: Color(0xFF58A6FF),
              onSurface: Color(0xFFE6EDF3), onSurfaceVariant: Color(0xFF8B949E),
              error: Color(0xFFF85149),
            )
          : const ColorScheme.light(
              surface: Colors.white, primary: Color(0xFF0969DA),
              onSurface: Color(0xFF1F2328), onSurfaceVariant: Color(0xFF656D76),
              error: Color(0xFFCF222E),
            ),
      appBarTheme: AppBarTheme(
        backgroundColor: isDark ? const Color(0xFF161B22) : const Color(0xFFF6F8FA),
        elevation: 0, centerTitle: true,
        foregroundColor: isDark ? const Color(0xFFE6EDF3) : const Color(0xFF1F2328),
      ),
      drawerTheme: DrawerThemeData(
        backgroundColor: isDark ? const Color(0xFF0D1117) : const Color(0xFFF6F8FA),
      ),
      cardTheme: CardTheme(
        color: isDark ? const Color(0xFF161B22) : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: const BorderRadius.all(Radius.circular(12))),
        elevation: isDark ? 0 : 1,
      ),
      chipTheme: ChipThemeData(
        backgroundColor: isDark ? const Color(0xFF21262D) : const Color(0xFFE8ECF0),
        labelStyle: const TextStyle(fontSize: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        side: BorderSide.none,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: isDark ? const Color(0xFF21262D) : const Color(0xFFF6F8FA),
        border: OutlineInputBorder(
          borderRadius: const BorderRadius.all(Radius.circular(12)),
          borderSide: BorderSide(color: isDark ? const Color(0xFF30363D) : const Color(0xFFD0D7DE)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: const BorderRadius.all(Radius.circular(12)),
          borderSide: BorderSide(color: isDark ? const Color(0xFF30363D) : const Color(0xFFD0D7DE)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: const BorderRadius.all(Radius.circular(12)),
          borderSide: BorderSide(color: isDark ? const Color(0xFF58A6FF) : const Color(0xFF0969DA)),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
      textTheme: ThemeData(brightness: brightness).textTheme.apply(
        fontFamily: "Inter",
        fontFamilyFallback: ["system-ui", "sans-serif"],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final showLang = SettingsService.language.isEmpty;
    final showConfig = !showLang && !widget.hasApiKey;

    Widget home;
    if (showLang) {
      home = const _LangScreen();
    } else if (showConfig) {
      home = const _SetupScreen();
    } else {
      home = const _MainShell();
    }

    return MaterialApp(
      title: "OpenCode",
      debugShowCheckedModeBanner: false,
      theme: _buildTheme(Brightness.light),
      darkTheme: _buildTheme(Brightness.dark),
      themeMode: _themeMode,
      home: home,
    );
  }
}

// ── Language picker ────────────────────────────────────────────────
class _LangScreen extends StatefulWidget {
  const _LangScreen();
  @override State<_LangScreen> createState() => _LangScreenState();
}
class _LangScreenState extends State<_LangScreen> {
  String _selected = "en";
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text("OpenCode", style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: cs.primary)),
            const SizedBox(height: 32),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: "en", label: Text("English")),
                ButtonSegment(value: "ru", label: Text("Русский")),
              ],
              selected: {_selected},
              onSelectionChanged: (v) => setState(() => _selected = v.first),
            ),
            const SizedBox(height: 32),
            FilledButton(onPressed: () {
              SettingsService.language = _selected;
              AppLocalization.current = _selected;
              Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const _SetupScreen()));
            }, child: const Text("Continue")),
          ]),
        ),
      ),
    );
  }
}

// ── First-time setup ──────────────────────────────────────────────
class _SetupScreen extends StatefulWidget {
  const _SetupScreen();
  @override State<_SetupScreen> createState() => _SetupScreenState();
}
class _SetupScreenState extends State<_SetupScreen> {
  final _keyCtrl = TextEditingController();
  bool _showKey = false;
  @override
  void dispose() { _keyCtrl.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text("Welcome", style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: cs.onSurface)),
            const SizedBox(height: 8),
            Text("Enter your DeepSeek API key to get started.", style: TextStyle(color: cs.onSurfaceVariant)),
            const SizedBox(height: 24),
            TextField(
              controller: _keyCtrl,
              obscureText: !_showKey,
              decoration: InputDecoration(
                hintText: "sk-...",
                suffixIcon: IconButton(
                  icon: Icon(_showKey ? Icons.visibility_off : Icons.visibility),
                  onPressed: () => setState(() => _showKey = !_showKey),
                ),
              ),
            ),
            const SizedBox(height: 24),
            FilledButton(onPressed: () async {
              await SettingsService.setDeepseekApiKey(_keyCtrl.text.trim());
              Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const _MainShell()));
            }, child: const Text("Start")),
          ]),
        ),
      ),
    );
  }
}

// ── Main shell with drawer ────────────────────────────────────────
class _MainShell extends StatefulWidget {
  const _MainShell();
  @override State<_MainShell> createState() => _MainShellState();
}
class _MainShellState extends State<_MainShell> {
  final _chats = <_ChatSession>[];
  int _selectedIndex = 0;
  final _scaffoldKey = GlobalKey<ScaffoldState>();

  void _newChat() {
    final chat = _ChatSession(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      title: "Chat ${_chats.length + 1}",
      project: "_general_",
    );
    setState(() {
      _chats.add(chat);
      _selectedIndex = _chats.length - 1;
    });
    _scaffoldKey.currentState?.closeDrawer();
  }

  void _deleteChat(int index) {
    setState(() {
      _chats.removeAt(index);
      if (_selectedIndex >= _chats.length) _selectedIndex = _chats.length - 1;
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final activeChat = _selectedIndex >= 0 && _selectedIndex < _chats.length ? _chats[_selectedIndex] : null;

    return Scaffold(
      key: _scaffoldKey,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.menu),
          onPressed: () => _scaffoldKey.currentState?.openDrawer(),
        ),
        title: Text(activeChat?.title ?? "OpenCode", style: const TextStyle(fontWeight: FontWeight.bold)),
        centerTitle: false,
      ),
      drawer: Drawer(
        child: SafeArea(
          child: Column(
            children: [
              // Header
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: cs.surface,
                  border: Border(bottom: BorderSide(color: cs.onSurface.withValues(alpha: 0.1))),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text("OpenCode", style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: cs.primary)),
                    const SizedBox(height: 4),
                    Text("AI Coding Agent", style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant)),
                  ],
                ),
              ),
              // New chat button
              Padding(
                padding: const EdgeInsets.all(12),
                child: FilledButton.icon(
                  onPressed: _newChat,
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text("New chat"),
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(44)),
                ),
              ),
              // Chat list
              Expanded(
                child: _chats.isEmpty
                    ? Center(child: Text("No chats yet", style: TextStyle(color: cs.onSurfaceVariant)))
                    : ListView.builder(
                        itemCount: _chats.length,
                        itemBuilder: (ctx, i) {
                          final chat = _chats[i];
                          final isActive = i == _selectedIndex;
                          return ListTile(
                            dense: true,
                            selected: isActive,
                            selectedTileColor: cs.primary.withValues(alpha: 0.1),
                            leading: Icon(Icons.chat_bubble_outline, size: 20, color: isActive ? cs.primary : null),
                            title: Text(chat.title, style: TextStyle(fontSize: 14, fontWeight: isActive ? FontWeight.w600 : null)),
                            onTap: () {
                              setState(() => _selectedIndex = i);
                              _scaffoldKey.currentState?.closeDrawer();
                            },
                            trailing: IconButton(
                              icon: Icon(Icons.close, size: 16, color: cs.onSurfaceVariant),
                              onPressed: () => _deleteChat(i),
                            ),
                          );
                        },
                      ),
              ),
              // Bottom actions
              Container(
                decoration: BoxDecoration(
                  border: Border(top: BorderSide(color: cs.onSurface.withValues(alpha: 0.1))),
                ),
                child: Column(
                  children: [
                    ListTile(
                      dense: true,
                      leading: Icon(Icons.settings, size: 20),
                      title: const Text("Settings", style: TextStyle(fontSize: 14)),
                      onTap: () {
                        _scaffoldKey.currentState?.closeDrawer();
                        Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsScreen()));
                      },
                    ),
                    ListTile(
                      dense: true,
                      leading: Icon(Icons.brightness_6, size: 20),
                      title: Text("Theme: ${OpenCodeApp.of(context)?.themeMode == ThemeMode.dark ? "Dark" : "Light"}", style: const TextStyle(fontSize: 14)),
                      onTap: () {
                        OpenCodeApp.of(context)?.toggleTheme();
                        _scaffoldKey.currentState?.closeDrawer();
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      body: activeChat != null
          ? ChatScreen(key: ValueKey(activeChat.id), sessionId: activeChat.id, projectName: activeChat.project)
          : const Center(child: Text("Create a new chat to get started")),
    );
  }
}

class _ChatSession {
  final String id;
  String title;
  final String project;
  _ChatSession({required this.id, required this.title, required this.project});
}
