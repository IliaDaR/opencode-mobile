/// Permission system — allow/ask/deny per tool
/// Supports simple rules ("tool": "allow") and pattern rules ("tool": {"pattern": "action"})
class PermissionService {
  static final Map<String, String> _rules = {
    "read_file": "allow",
    "write_file": "allow",
    "edit_file": "allow",
    "delete_file": "ask",
    "list_files": "allow",
    "glob_files": "allow",
    "search_code": "allow",
    "run_command": "ask",
    "git_sync": "allow",
    "git_status": "allow",
    "web_search": "allow",
    "web_fetch": "allow",
    "browser_open": "allow",
    "browser_extract": "allow",
    "browser_follow": "allow",
    "sql_detect": "allow",
    "sql_query": "allow",
    "sql_schema": "allow",
    "github_list_issues": "allow",
    "github_create_issue": "ask",
    "github_list_prs": "allow",
    "github_get_pr": "allow",
    "github_search_code": "allow",
    "github_get_file": "allow",
    "github_get_repo": "allow",
    "diagnose_file": "allow",
    "analyze_project": "allow",
    "check_imports": "allow",
    "find_patterns": "allow",
    "suggest_tests": "allow",
    "suggest_optimizations": "allow",
    "generate_test_template": "allow",
    "generate_boilerplate": "allow",
    "impact_analysis": "allow",
    "delegate_task": "allow",
    "estimate_effort": "allow",
    "generate_readme": "allow",
    "generate_api_docs": "allow",
    "check_deploy_readiness": "allow",
    "generate_docker_compose": "allow",
    "generate_ci_config": "allow",
    "create_tasks": "allow",
    "ask_user": "allow",
    "snapshot_undo": "allow",
    "format_code": "allow",
    "batch_execute": "allow",
    "run_background": "allow",
    "todowrite": "allow",
    "todolist": "allow",
  };

  /// Pattern-based rules: tool → list of (globPattern → action)
  static final Map<String, List<_PatternRule>> _patternRules = {};

  static String get(String tool) => _rules[tool] ?? "allow";

  /// Check using both simple and pattern rules.
  /// [args] is the tool arguments string to match against patterns.
  static String check(String tool, [String args = ""]) {
    // First check pattern rules for this tool
    final patterns = _patternRules[tool];
    if (patterns != null) {
      for (final rule in patterns) {
        if (_matchesGlob(rule.pattern, args)) {
          return rule.action;
        }
      }
    }
    // Fall back to simple rule
    return _rules[tool] ?? "allow";
  }

  static void set(String tool, String action) {
    _rules[tool] = action;
  }

  /// Set a pattern-based rule. [pattern] supports * (wildcard) glob syntax.
  /// Example: setPattern("run_command", "git push*", "deny");
  static void setPattern(String tool, String pattern, String action) {
    _patternRules.putIfAbsent(tool, () => []);
    // Replace existing pattern if present
    _patternRules[tool]!.removeWhere((r) => r.pattern == pattern);
    _patternRules[tool]!.add(_PatternRule(pattern, action));
  }

  /// Load rules from project config. Supports both flat and nested formats:
  /// {"run_command": "ask"} or {"run_command": {"git push*": "deny", "*": "allow"}}
  static void loadFromConfig(Map<String, dynamic> config) {
    config.forEach((tool, value) {
      if (value is String && ["allow", "ask", "deny"].contains(value)) {
        _rules[tool] = value;
      } else if (value is Map) {
        (value as Map<String, dynamic>).forEach((pattern, action) {
          if (action is String && ["allow", "ask", "deny"].contains(action)) {
            if (pattern == "*") {
              _rules[tool] = action;
            } else {
              setPattern(tool, pattern, action);
            }
          }
        });
      }
    });
  }

  static bool _matchesGlob(String pattern, String value) {
    if (pattern == "*") return true;
    // Convert glob to regex: * → .*, ? → .
    final regexStr = StringBuffer("^");
    for (var i = 0; i < pattern.length; i++) {
      final c = pattern[i];
      if (c == '*') {
        regexStr.write(".*");
      } else if (c == '?') {
        regexStr.write(".");
      } else {
        // Escape regex special chars
        if ("\\^$[]{}()+|".contains(c)) regexStr.write('\\');
        regexStr.write(c);
      }
    }
    regexStr.write(r'$');
    return RegExp(regexStr.toString()).hasMatch(value);
  }

  /// Check if tool needs user confirmation
  static bool needsAsk(String tool, [String args = ""]) => check(tool, args) == "ask";

  /// Check if tool is denied
  static bool isDenied(String tool, [String args = ""]) => check(tool, args) == "deny";
}

class _PatternRule {
  final String pattern;
  final String action;
  _PatternRule(this.pattern, this.action);
}
