import "dart:convert";
import "dart:io";
import "package:path/path.dart" as p;
import "storage_service.dart";

class ProjectConfig {
  String? model;
  String? shell;
  List<String>? instructions;
  Map<String, dynamic>? permission;
  Map<String, dynamic>? mcpServers;
  Map<String, dynamic>? agent;
  Map<String, dynamic>? compaction;
  List<String>? skillPaths;
  List<String>? skillUrls;

  ProjectConfig.fromJson(Map<String, dynamic> json)
      : model = json["model"] as String?,
        shell = json["shell"] as String?,
        instructions = (json["instructions"] as List?)?.cast<String>(),
        permission = json["permission"] as Map<String, dynamic>?,
        mcpServers = json["mcp"] as Map<String, dynamic>?,
        agent = json["agent"] as Map<String, dynamic>?,
        compaction = json["compaction"] as Map<String, dynamic>?,
        skillPaths = (json["skills"] is Map ? (json["skills"]["paths"] as List?)?.cast<String>() : null),
        skillUrls = (json["skills"] is Map ? (json["skills"]["urls"] as List?)?.cast<String>() : null);
}

class JsoncParser {
  static String stripComments(String input) {
    final buf = StringBuffer();
    var i = 0;
    var inString = false;

    while (i < input.length) {
      final c = input[i];

      if (inString) {
        buf.write(c);
        if (c == '"' && (i == 0 || input[i - 1] != '\\')) {
          inString = false;
        }
        i++;
        continue;
      }

      if (c == '"') {
        inString = true;
        buf.write(c);
        i++;
        continue;
      }

      if (c == '/' && i + 1 < input.length) {
        if (input[i + 1] == '/') {
          while (i < input.length && input[i] != '\n') i++;
          continue;
        }
        if (input[i + 1] == '*') {
          i += 2;
          while (i + 1 < input.length && !(input[i] == '*' && input[i + 1] == '/')) i++;
          i += 2;
          continue;
        }
      }

      buf.write(c);
      i++;
    }

    return buf.toString();
  }

  static String fixTrailingCommas(String input) {
    return input.replaceAllMapped(RegExp(r',(\s*[}\]])'), (m) => m.group(1)!);
  }

  static Map<String, dynamic>? parse(String raw) {
    try {
      final stripped = stripComments(raw);
      final fixed = fixTrailingCommas(stripped);
      return jsonDecode(fixed) as Map<String, dynamic>?;
    } catch (e) {
      return null;
    }
  }
}

class ProjectConfigService {
  static ProjectConfig? _config;

  static ProjectConfig? get current => _config;

  static Future<void> load(String project) async {
    _config = null;
    try {
      final content = await StorageService.readFile(project, ".opencode/opencode.jsonc");
      final json = JsoncParser.parse(content);
      if (json != null) {
        _config = ProjectConfig.fromJson(json);
      }
    } catch (e) {
      // No config file — that's fine
    }
  }

  static Future<List<String>> loadInstructions(String project) async {
    final result = <String>[];

    if (_config?.instructions != null) {
      for (final path in _config!.instructions!) {
        try {
          final content = await StorageService.readFile(project, path);
          result.add(content);
        } catch (e) {
          // Instruction file not found, skip
        }
      }
    }

    for (final name in ["AGENTS.md", "CLAUDE.md", "CONTEXT.md"]) {
      try {
        final content = await StorageService.readFile(project, name);
        result.add(content);
      } catch (e) {
        // File not found, continue
      }
    }

    try {
      final rulesDir = ".opencode/rules";
      final entries = await StorageService.listDir(project, rulesDir);
      for (final entry in entries) {
        if (entry is File && p.extension(entry.path) == ".md") {
          try {
            final name = p.basename(entry.path);
            final content = await StorageService.readFile(project, "$rulesDir/$name");
            result.add(content);
          } catch (e) {
            // Rule file not readable
          }
        }
      }
    } catch (e) {
      // Rules directory not found
    }

    return result;
  }

  static Future<List<Map<String, dynamic>>> loadMcpServers(String project) async {
    final servers = <Map<String, dynamic>>[];
    if (_config?.mcpServers == null) return servers;

    _config!.mcpServers!.forEach((name, cfg) {
      if (cfg is Map<String, dynamic>) {
        servers.add({
          "name": name,
          "type": cfg["type"] ?? "local",
          "command": cfg["command"],
          "url": cfg["url"],
          "environment": cfg["environment"],
          "timeout": cfg["timeout"] ?? 30000,
        });
      }
    });

    return servers;
  }
}
