import "dart:convert";
import "dart:io";
import "package:path/path.dart" as p;
import "storage_service.dart";

class CodeSandbox {
  static Future<String> run(String project, String code, {String language = "dart"}) async {
    final tmpDir = Directory(p.join(StorageService.projectDir(project).path, ".sandbox"));
    if (!tmpDir.existsSync()) tmpDir.createSync();

    final ext = _ext(language);
    final file = File(p.join(tmpDir.path, "code$ext"));
    await file.writeAsString(code);

    final cmd = _command(language);
    if (cmd == null) return "Sandbox not available for $language on mobile";

    try {
      final result = await Process.run(cmd[0], [...cmd.sublist(1), file.path],
          workingDirectory: tmpDir.path,
          timeout: const Duration(seconds: 15));
      final out = result.stdout.toString().trim();
      final err = result.stderr.toString().trim();
      final sb = StringBuffer();
      if (out.isNotEmpty) sb.writeln(out);
      if (err.isNotEmpty) sb.writeln("stderr: $err");
      sb.writeln("Exit code: ${result.exitCode}");
      return sb.toString();
    } on ProcessException catch (e) {
      return "Runtime not found: $language is not installed on this device.\n${e.message}";
    } on TimeoutException {
      return "Execution timed out (15s)";
    }
  }

  static String _ext(String lang) {
    switch (lang) {
      case "dart": return ".dart";
      case "python": return ".py";
      case "js": return ".js";
      case "ts": return ".ts";
      case "go": return ".go";
      case "rust": return ".rs";
      default: return ".txt";
    }
  }

  static List<String>? _command(String lang) {
    switch (lang) {
      case "dart": return ["dart", "run"];
      case "python": return ["python3"];
      case "js": return ["node"];
      case "ts": return ["npx", "ts-node"];
      case "go": return ["go", "run"];
      case "rust": return ["rustc"];
      default: return null;
    }
  }
}
