import "dart:convert";
import "dart:io";
import "package:path/path.dart" as p;
import "storage_service.dart";
import "../models/message.dart";

class SessionMemory {
  static const String _memoryDir = ".opencode-memory";

  static Future<void> init() async {
    // Memory dir is now INSIDE each project for scoped storage
    // No global init needed
  }

  static String _memoryPath(String project) {
    return p.join(StorageService.projectDir(project).path, _memoryDir, "chat.json");
  }

  static String _metaPath(String project) {
    return p.join(StorageService.projectDir(project).path, _memoryDir, "meta.json");
  }

  /// Save chat messages to persistent storage
  static Future<void> saveChat(String project, List<Message> messages) async {
    final path = _memoryPath(project);
    final file = File(path);
    final dir = file.parent;
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    final data = messages.map((m) => m.toJson()).toList();
    await file.writeAsString(jsonEncode(data));
  }

  /// Load chat messages from storage
  static Future<List<Message>?> loadChat(String project) async {
    final path = _memoryPath(project);
    final file = File(path);
    if (!await file.exists()) return null;

    try {
      final raw = await file.readAsString();
      final decoded = jsonDecode(raw);
      if (decoded is! List) return null;
      return decoded.map((m) {
        return Message(
          role: m["role"] ?? "user",
          content: m["content"] ?? "",
          toolCallId: m["tool_call_id"],
          toolCalls: m["tool_calls"] != null
              ? (m["tool_calls"] as List)
                  .map((tc) => ToolCall(
                        id: tc["id"] ?? "",
                        name: tc["function"]?["name"] ?? "",
                        arguments: tc["function"]?["arguments"] ?? "{}",
                      ))
                  .toList()
              : null,
        );
      }).toList();
    } catch (e) {
      return null;
    }
  }

  /// Store project metadata: tech stack, conventions, key files
  static Future<void> saveProjectMeta(
      String project, Map<String, dynamic> meta) async {
    final path = _metaPath(project);
    final file = File(path);
    final dir = file.parent;
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    await file.writeAsString(jsonEncode(meta));
  }

  /// Load project metadata
  static Future<Map<String, dynamic>?> loadProjectMeta(
      String project) async {
    final path = _metaPath(project);
    final file = File(path);
    if (!await file.exists()) return null;

    try {
      return jsonDecode(await file.readAsString());
    } catch (e) {
      return null;
    }
  }

  /// Store user preferences for this project
  static Future<void> saveProjectPrefs(
      String project, Map<String, dynamic> prefs) async {
    final meta = await loadProjectMeta(project) ?? {};
    meta["preferences"] = prefs;
    await saveProjectMeta(project, meta);
  }

  /// Store a key decision for the project
  static Future<void> rememberDecision(
      String project, String topic, String decision) async {
    final meta = await loadProjectMeta(project) ?? {};
    final decisions =
        (meta["decisions"] as List?)?.cast<Map<String, dynamic>>() ?? [];
    decisions.add({
      "topic": topic,
      "decision": decision,
      "timestamp": DateTime.now().toIso8601String(),
    });
    if (decisions.length > 20) {
      decisions.removeAt(0);
    }
    meta["decisions"] = decisions;
    await saveProjectMeta(project, meta);
  }

  /// Get all decisions for a project
  static Future<List<Map<String, dynamic>>> getDecisions(
      String project) async {
    final meta = await loadProjectMeta(project);
    if (meta == null) return [];
    return (meta["decisions"] as List?)
            ?.cast<Map<String, dynamic>>() ??
        [];
  }

  /// Clear all memory for a project
  static Future<void> clearMemory(String project) async {
    try {
      await File(_memoryPath(project)).delete();
    } catch (e) {
      // File may not exist
    }
    try {
      await File(_metaPath(project)).delete();
    } catch (e) {
      // File may not exist
    }
    // Also try to delete the directory if empty
    try {
      final dir = Directory(p.join(StorageService.projectDir(project).path, _memoryDir));
      if (await dir.exists()) {
        final entries = await dir.list().toList();
        if (entries.isEmpty) await dir.delete();
      }
    } catch (e) {
      // Directory not empty or permission issue
    }
  }
}

/// Manages conversation context — compresses old messages
class ContextManager {
  /// Compress old messages into a summary to stay within token budget
  static List<Message> compress(List<Message> messages,
      {int keepLast = 6, int maxSummaryTokens = 2000}) {
    if (messages.length <= keepLast + 4) return messages;

    final systemMessages = messages.where((m) => m.role == "system").toList();
    final conversation =
        messages.where((m) => m.role != "system").toList();

    if (conversation.length <= keepLast) {
      return [...systemMessages, ...conversation];
    }

    final toCompress = conversation.sublist(0, conversation.length - keepLast);
    final toKeep = conversation.sublist(conversation.length - keepLast);

    final summary = _summarizeTurn(toCompress);

    final compressed = [
      ...systemMessages,
      Message(
        role: "system",
        content:
            "[Context from earlier in conversation: $summary]",
      ),
      ...toKeep,
    ];

    return compressed;
  }

  static String _summarizeTurn(List<Message> messages) {
    final buffer = StringBuffer();
    buffer.write("Previous conversation summary: ");
    int chars = buffer.length;

    for (final m in messages.reversed) {
      var snippet = "";
      if (m.role == "user") {
        snippet = "User: ${_truncate(m.content, 100)}";
      } else if (m.role == "assistant" && m.toolCalls != null) {
        final tools = m.toolCalls!.map((t) => t.name).join(", ");
        snippet = "Used tools: $tools";
      } else if (m.role == "tool") {
        snippet = "Tool result: ${_truncate(m.content, 80)}";
      } else if (m.role == "assistant") {
        snippet = "Assistant: ${_truncate(m.content, 150)}";
      }

      if (snippet.isNotEmpty && chars + snippet.length < 2000) {
        buffer.write("$snippet | ");
        chars = buffer.length;
      } else {
        break;
      }
    }

    return buffer.toString();
  }

  static String _truncate(String text, int maxLen) {
    if (text.length <= maxLen) return text;
    return "${text.substring(0, maxLen)}...";
  }
}