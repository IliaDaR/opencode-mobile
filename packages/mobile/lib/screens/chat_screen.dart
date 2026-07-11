import "dart:async";
import "dart:io";
import "package:flutter/material.dart";
import "package:flutter_markdown/flutter_markdown.dart";
import "package:http/http.dart" as http;
import "package:image_picker/image_picker.dart";
import "package:speech_to_text/speech_to_text.dart" as stt;
import "../services/agent_service.dart";
import "../services/storage_service.dart";
import "../services/session_memory.dart";
import "../services/settings_service.dart";
import "../services/localization.dart";
import "../services/snapshot_service.dart";
import "../services/session_sharing_service.dart";
import "../services/bg_service.dart";
import "file_browser_screen.dart";
import "settings_screen.dart";

class ChatScreen extends StatefulWidget {
  final String sessionId;
  final String projectName;
  const ChatScreen({super.key, required this.sessionId, this.projectName = "_general_"});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  late final AgentService _agent;
  late final String _project;
  Timer? _scrollTimer;
  final _inputCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  final List<ChatMessage> _messages = [];
  bool _loading = false;
  AgentMode _mode = AgentMode.auto;
  int _msgId = 0;
  late final stt.SpeechToText _speech;
  bool _isListening = false;
  final _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _speech = stt.SpeechToText();
    BgService.init();
    _project = widget.projectName;
    _agent = AgentService(projectName: _project);
    _init();
  }

  Future<void> _init() async {
    await StorageService.init();
    await SessionMemory.init();
    await _agent.scanProject();
    await _agent.reset();

    _agent.onQuestion = (question, options) async {
      if (!mounted) return "";
      final completer = Completer<String>();
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) {
          final ctrl = TextEditingController();
          return AlertDialog(
            title: const Text("OpenCode"),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(question),
                if (options != null && options.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  ...options.map((opt) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: ElevatedButton(
                      onPressed: () { completer.complete(opt); Navigator.pop(ctx); },
                      child: Text(opt),
                    ),
                  )),
                ] else ...[
                  const SizedBox(height: 12),
                  TextField(
                    controller: ctrl, autofocus: true,
                    decoration: const InputDecoration(hintText: "Type your answer...", border: OutlineInputBorder()),
                  ),
                ],
              ],
            ),
            actions: options == null || options.isEmpty
                ? [ElevatedButton(onPressed: () { completer.complete(ctrl.text); Navigator.pop(ctx); }, child: const Text("Submit"))]
                : [],
          );
        },
      );
      return completer.future;
    };

    final hasSession = await _agent.loadSession();
    if (hasSession) {
      _addSystem("Session restored");
      for (final m in _agent.messages) {
        if (!mounted) return;
        if (m.role == "user") setState(() => _messages.add(ChatMessage(id: ++_msgId, type: ChatMsgType.user, content: m.content)));
        if (m.role == "assistant" && m.content.isNotEmpty) _addAssistant(m.content);
      }
      if (_messages.isNotEmpty && _messages.last.isStreaming) {
        setState(() => _messages.last.isStreaming = false);
      }
    } else {
      final hasKey = SettingsService.deepseekApiKey.isNotEmpty;
      _addAssistant(hasKey
          ? "I'm OpenCode. What are we working on?\n\nCommands: `/config` `/files` `/help`"
          : "API key not configured. Use the drawer → Settings to add your DeepSeek key.");
    }
  }

  // ── Message management ──────────────────────────────────────────

  void _addUser(String text) {
    setState(() => _messages.add(ChatMessage(id: ++_msgId, type: ChatMsgType.user, content: text)));
    _scrollDown();
  }

  void _addAssistant(String text) {
    setState(() => _messages.add(ChatMessage(id: ++_msgId, type: ChatMsgType.assistant, content: text)));
    _scrollDown();
  }

  void _addSystem(String text) {
    setState(() => _messages.add(ChatMessage(id: ++_msgId, type: ChatMsgType.system, content: text)));
    _scrollDown();
  }

  void _scrollDown() {
    _scrollTimer?.cancel();
    _scrollTimer = Timer(const Duration(milliseconds: 100), () {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(_scrollCtrl.position.maxScrollExtent, duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
      }
    });
  }

  // ── Input & commands ────────────────────────────────────────────

  Future<void> _send() async {
    final text = _inputCtrl.text.trim();
    if (text.isEmpty || _loading) return;
    _inputCtrl.clear();

    if (text.startsWith("/")) { await _handleCommand(text); return; }

    _addUser(text);
    await _callAgent();
  }

  Future<void> _handleCommand(String input) async {
    final parts = input.split(" ");
    final cmd = parts[0].toLowerCase();
    switch (cmd) {
      case "/config":
        Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsScreen()));
      case "/files":
        Navigator.push(context, MaterialPageRoute(builder: (_) => FileBrowserScreen(projectName: _project)));
      case "/help":
        _addAssistant(
          "**Commands:**\n"
          "- `/config` — API keys & settings\n"
          "- `/files` — browse project files\n"
          "- `/mode auto|code|architect|debug|refactor|research|brainstorm` — switch mode\n"
          "- `/save` — save session\n"
          "- `/share` — export chat\n"
          "- `/clear` — clear chat\n"
          "- `/undo` — undo last file change\n"
          "- `/help` — this message\n\n"
          "Supports speech-to-text and image attachments."
        );
      case "/mode":
        if (parts.length > 1) {
          final modes = {
            "auto": AgentMode.auto, "code": AgentMode.code, "architect": AgentMode.architect,
            "debug": AgentMode.debug, "refactor": AgentMode.refactor, "research": AgentMode.research,
            "brainstorm": AgentMode.brainstorm, "plan": AgentMode.plan,
          };
          if (modes.containsKey(parts[1])) {
            _agent.currentMode = modes[parts[1]]!;
            setState(() => _mode = _agent.currentMode);
            _addSystem("Mode: ${parts[1]}");
          } else {
            _addSystem("Unknown mode. Available: auto, code, architect, debug, refactor, research, brainstorm");
          }
        }
      case "/save":
        _agent.saveSession();
        _addSystem("Session saved.");
      case "/share":
        if (_agent.messages.isNotEmpty) {
          _addSystem("Exporting...");
          SessionSharingService.exportSession(_project, _agent.messages.map((m) => m.toJson()).toList())
              .then((r) => _addSystem(r));
        }
      case "/clear":
        setState(() => _messages.clear());
        _agent.messages.clear();
        _agent.reset();
        _addSystem("Chat cleared.");
      case "/undo":
        try {
          final result = await SnapshotService.undoAll(_project);
          _addSystem(result);
        } catch (e) {
          _addSystem("Undo failed: $e");
        }
      default:
        _addSystem("Unknown command. Try /help");
    }
  }

  Future<void> _callAgent() async {
    setState(() => _loading = true);
    try {
      final userMsg = _agent.messages.where((m) => m.role == "user").lastOrNull;
      if (userMsg != null) {
        await _agent.chat(userMsg.content, onChunk: (chunk) {
          if (!mounted) return;
          setState(() {
            if (_messages.isNotEmpty && _messages.last.type == ChatMsgType.assistant && _messages.last.isStreaming) {
              _messages.last.content += chunk;
            } else {
              _messages.add(ChatMessage(id: ++_msgId, type: ChatMsgType.assistant, content: chunk, isStreaming: true));
            }
          });
          _scrollDown();
        });
      }
      await _agent.saveSession();
    } catch (e) {
      if (mounted) _addSystem("Error: $e");
    }
    if (mounted) {
      setState(() {
        _loading = false;
        if (_messages.isNotEmpty && _messages.last.isStreaming) _messages.last.isStreaming = false;
      });
    }
  }

  void _toggleSpeech() async {
    if (_isListening) {
      await _speech.stop();
      setState(() => _isListening = false);
      return;
    }
    final available = await _speech.initialize();
    if (!available) { _addSystem("Speech not available."); return; }
    setState(() => _isListening = true);
    _speech.listen(
      onResult: (r) => _inputCtrl.text = r.recognizedWords,
      localeId: "en_US", listenFor: const Duration(seconds: 15), pauseFor: const Duration(seconds: 5),
    );
  }

  void _pickImage() async {
    final picker = ImagePicker();
    final source = await showDialog<ImageSource>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text("Attach image"),
        children: [
          SimpleDialogOption(onPressed: () => Navigator.pop(ctx, ImageSource.camera), child: const Text("Camera")),
          SimpleDialogOption(onPressed: () => Navigator.pop(ctx, ImageSource.gallery), child: const Text("Gallery")),
        ],
      ),
    );
    if (source == null) return;
    final file = await picker.pickImage(source: source, maxWidth: 1024);
    if (file != null) _inputCtrl.text = "${_inputCtrl.text}\n[Image: ${file.name}]";
  }

  // ── Build ───────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Column(
      children: [
        // Mode selector
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: cs.surface,
            border: Border(bottom: BorderSide(color: cs.onSurface.withOpacity(0.08))),
          ),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _modeChip("auto", Icons.smart_toy),
                const SizedBox(width: 4),
                _modeChip("code", Icons.code),
                const SizedBox(width: 4),
                _modeChip("architect", Icons.account_tree),
                const SizedBox(width: 4),
                _modeChip("debug", Icons.bug_report),
                const SizedBox(width: 4),
                _modeChip("refactor", Icons.refresh),
                const SizedBox(width: 4),
                _modeChip("research", Icons.search),
                const SizedBox(width: 4),
                _modeChip("brainstorm", Icons.auto_awesome),
              ],
            ),
          ),
        ),
        // Messages
        Expanded(
          child: _messages.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.chat_bubble_outline, size: 64, color: cs.onSurfaceVariant),
                      const SizedBox(height: 16),
                      Text("Start a conversation", style: TextStyle(fontSize: 18, color: cs.onSurface)),
                    ],
                  ),
                )
              : ListView.builder(
                  controller: _scrollCtrl,
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                  itemCount: _messages.length,
                  itemBuilder: (ctx, i) => _buildMsg(_messages[i], cs),
                ),
        ),
        // Input bar
        _buildInputBar(cs),
      ],
    );
  }

  Widget _buildInputBar(ColorScheme cs) {
    return Container(
      padding: EdgeInsets.only(
        left: 8, right: 8, top: 8,
        bottom: MediaQuery.of(context).padding.bottom + 8,
      ),
      decoration: BoxDecoration(
        color: cs.surface,
        border: Border(top: BorderSide(color: cs.onSurface.withOpacity(0.08))),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          IconButton(
            icon: const Icon(Icons.add_circle_outline, size: 22),
            onPressed: _pickImage,
            color: cs.onSurfaceVariant,
          ),
          Expanded(
            child: TextField(
              controller: _inputCtrl,
              focusNode: _focusNode,
              maxLines: 6,
              minLines: 1,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => _send(),
              decoration: InputDecoration(
                hintText: "Message OpenCode...",
                border: InputBorder.none,
                filled: false,
                contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
              ),
              style: TextStyle(fontSize: 15, color: cs.onSurface),
            ),
          ),
          if (_isListening)
            IconButton(
              icon: const Icon(Icons.mic, color: Colors.red, size: 22),
              onPressed: _toggleSpeech,
            )
          else
            IconButton(
              icon: Icon(Icons.mic_none, size: 22, color: cs.onSurfaceVariant),
              onPressed: _toggleSpeech,
            ),
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            child: _loading
                ? const Padding(
                    padding: EdgeInsets.all(8),
                    child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5)),
                  )
                : IconButton(
                    icon: Icon(Icons.arrow_upward, size: 22, color: cs.onSurface),
                    onPressed: _send,
                    style: IconButton.styleFrom(
                      backgroundColor: cs.primary.withOpacity(0.9),
                      foregroundColor: cs.brightness == Brightness.dark ? Colors.black : Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  // ── Mode chip ───────────────────────────────────────────────────

  Widget _modeChip(String label, IconData icon) {
    final isActive = _mode.name == label;
    final cs = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: () {
        final modes = {
          "auto": AgentMode.auto, "code": AgentMode.code, "architect": AgentMode.architect,
          "debug": AgentMode.debug, "refactor": AgentMode.refactor, "research": AgentMode.research,
          "plan": AgentMode.plan, "brainstorm": AgentMode.brainstorm,
        };
        _agent.currentMode = modes[label]!;
        setState(() => _mode = _agent.currentMode);
        _focusNode.unfocus();
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: isActive ? cs.primary.withOpacity(0.15) : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: isActive ? Border.all(color: cs.primary.withOpacity(0.3)) : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: isActive ? cs.primary : cs.onSurfaceVariant),
            const SizedBox(width: 4),
            Text(
              label == "auto" ? "Auto" : label[0].toUpperCase() + label.substring(1),
              style: TextStyle(
                fontSize: 12, fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
                color: isActive ? cs.primary : cs.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Message renderer ────────────────────────────────────────────

  Widget _buildMsg(ChatMessage msg, ColorScheme cs) {
    switch (msg.type) {
      case ChatMsgType.user:
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Flexible(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  decoration: BoxDecoration(
                    color: cs.primary.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(18).copyWith(bottomRight: Radius.zero),
                  ),
                  child: MarkdownBody(
                    data: msg.content,
                    styleSheet: MarkdownStyleSheet(
                      p: TextStyle(color: cs.onSurface, fontSize: 15, height: 1.4),
                      code: TextStyle(backgroundColor: cs.primary.withOpacity(0.1), fontSize: 13, color: cs.primary),
                      codeblockDecoration: BoxDecoration(
                        color: cs.brightness == Brightness.dark ? const Color(0xFF161B22) : const Color(0xFFF0F2F5),
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      case ChatMsgType.assistant:
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 28, height: 28,
                margin: const EdgeInsets.only(right: 8, top: 2),
                decoration: BoxDecoration(
                  color: cs.primary.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Icon(Icons.auto_awesome, size: 16, color: cs.primary),
              ),
              Flexible(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      decoration: BoxDecoration(
                        color: cs.surface,
                        borderRadius: BorderRadius.circular(18).copyWith(bottomLeft: Radius.zero),
                        border: Border.all(color: cs.onSurface.withOpacity(0.08)),
                      ),
                      child: MarkdownBody(
                        data: msg.content,
                        styleSheet: _markdownStyle(cs),
                      ),
                    ),
                    if (msg.isStreaming)
                      const Padding(
                        padding: EdgeInsets.only(top: 6, left: 4),
                        child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                      ),
                  ],
                ),
              ),
            ],
          ),
        );
      case ChatMsgType.system:
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: cs.onSurface.withOpacity(0.06),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(msg.content, style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
            ),
          ),
        );
    }
  }

  MarkdownStyleSheet _markdownStyle(ColorScheme cs) {
    final isDark = cs.brightness == Brightness.dark;
    return MarkdownStyleSheet(
      p: TextStyle(color: cs.onSurface, fontSize: 15, height: 1.5),
      h1: TextStyle(color: cs.onSurface, fontSize: 22, fontWeight: FontWeight.bold, height: 1.4),
      h2: TextStyle(color: cs.onSurface, fontSize: 18, fontWeight: FontWeight.bold, height: 1.4),
      h3: TextStyle(color: cs.onSurface, fontSize: 16, fontWeight: FontWeight.w600, height: 1.4),
      code: TextStyle(
        backgroundColor: cs.primary.withOpacity(0.08),
        fontSize: 13, color: cs.primary, fontFamily: "monospace",
      ),
      codeblockDecoration: BoxDecoration(
        color: isDark ? const Color(0xFF161B22) : const Color(0xFFF0F2F5),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: cs.onSurface.withOpacity(0.08)),
      ),
      blockquoteDecoration: BoxDecoration(
        border: Border(left: BorderSide(color: cs.primary, width: 3)),
        color: cs.primary.withOpacity(0.05),
      ),
      blockquotePadding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
      listBullet: TextStyle(color: cs.onSurfaceVariant, fontSize: 15),
      horizontalRuleDecoration: BoxDecoration(
        border: Border(top: BorderSide(color: cs.onSurface.withOpacity(0.15))),
      ),
      tableBorder: TableBorder.all(color: cs.onSurface.withOpacity(0.15), borderRadius: BorderRadius.circular(8)),
      tableBody: TextStyle(color: cs.onSurface, fontSize: 14),
      tableHead: TextStyle(color: cs.onSurface, fontSize: 14, fontWeight: FontWeight.bold),
      strong: TextStyle(fontWeight: FontWeight.bold, color: cs.onSurface),
      em: TextStyle(fontStyle: FontStyle.italic, color: cs.onSurface),
      a: TextStyle(color: cs.primary, decoration: TextDecoration.underline),
      checkbox: TextStyle(color: cs.primary),
    );
  }

  @override
  void dispose() {
    _scrollTimer?.cancel();
    _inputCtrl.dispose();
    _scrollCtrl.dispose();
    _focusNode.dispose();
    _speech.stop();
    super.dispose();
  }
}

// ── Data classes ──────────────────────────────────────────────────

enum ChatMsgType { user, assistant, system }

class ChatMessage {
  final int id;
  final ChatMsgType type;
  String content;
  bool isStreaming;
  ChatMessage({required this.id, required this.type, required this.content, this.isStreaming = false});
}
