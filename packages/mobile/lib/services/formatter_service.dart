import "storage_service.dart";

class FormatterService {
  static Future<String> format(String project, String filePath) async {
    final content = await StorageService.readFile(project, filePath);
    final ext = filePath.split(".").last.toLowerCase();
    String formatted;

    switch (ext) {
      case "dart":
        formatted = _formatDart(content);
        break;
      case "js":
      case "jsx":
      case "ts":
      case "tsx":
        formatted = _formatJsLike(content);
        break;
      case "py":
        formatted = _formatPython(content);
        break;
      case "html":
        formatted = _formatHtml(content);
        break;
      case "css":
      case "scss":
        formatted = _formatCss(content);
        break;
      default:
        return "Formatter not available for .$ext (supported: dart, js, ts, py, html, css)";
    }

    if (formatted == content) return "Already formatted";
    await StorageService.writeFile(project, filePath, formatted);
    return "Formatted $filePath";
  }

  static int _braceDelta(String s) {
    var d = 0;
    for (var i = 0; i < s.length; i++) {
      final c = s.codeUnitAt(i);
      if (c == 0x7b || c == 0x5b || c == 0x28) d++;
      if (c == 0x7d || c == 0x5d || c == 0x29) d--;
    }
    return d;
  }

  static String _formatDart(String code) {
    final lines = code.split("\n");
    final result = <String>[];
    var indent = 0;
    var inMultiline = false;

    for (var raw in lines) {
      final trimmed = raw.trim();
      if (trimmed.isEmpty) { result.add(""); continue; }

      final tripleQuotes = trimmed.split('"""').length - 1;
      if (tripleQuotes % 2 == 1) inMultiline = !inMultiline;

      if (!inMultiline) {
        final delta = _braceDelta(trimmed);
        if (delta < 0) indent = (indent + delta).clamp(0, 999);
      }

      result.add("${_indent(indent)}$trimmed");

      if (!inMultiline) {
        final delta = _braceDelta(trimmed);
        if (delta > 0) indent += delta;
      }

      if (tripleQuotes % 2 == 1) inMultiline = !inMultiline;
    }

    return result.join("\n");
  }

  static String _formatJsLike(String code) {
    final lines = code.split("\n");
    final result = <String>[];
    var indent = 0;

    for (var raw in lines) {
      var trimmed = raw.trim();
      if (trimmed.isEmpty) { result.add(""); continue; }

      final delta = _braceDelta(trimmed);
      if (delta < 0) indent = (indent + delta).clamp(0, 999);
      result.add("${_indent(indent)}$trimmed");
      if (delta > 0) indent += delta;
    }

    return result.join("\n");
  }

  static String _formatPython(String code) {
    final lines = code.split("\n");
    final result = <String>[];
    var indent = 0;

    for (var raw in lines) {
      final trimmed = raw.trim();
      if (trimmed.isEmpty) { result.add(""); continue; }

      if (trimmed == "else:" || trimmed == "elif " || trimmed.startsWith("elif ") || trimmed == "except" || trimmed == "finally:") {
        if (indent > 0) indent--;
      }

      result.add("${_indent(indent)}$trimmed");

      if (trimmed.endsWith(":")) indent++;
    }

    return result.join("\n");
  }

  static String _formatHtml(String code) {
    final lines = code.split("\n");
    final result = <String>[];
    var indent = 0;

    for (var raw in lines) {
      var trimmed = raw.trim();
      if (trimmed.isEmpty) { result.add(""); continue; }

      if (trimmed.startsWith("</")) indent = (indent - 1).clamp(0, 999);
      result.add("${_indent(indent)}$trimmed");
      if (trimmed.startsWith("<") && !trimmed.startsWith("</") && !trimmed.endsWith("/>") && !trimmed.contains("</")) indent++;
    }

    return result.join("\n");
  }

  static String _formatCss(String code) {
    return _formatJsLike(code);
  }

  static String _indent(int level) {
    return "  " * level;
  }
}
