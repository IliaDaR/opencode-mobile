import "dart:async";
import "dart:convert";
import "dart:io";
import "dart:math" as math;
import "package:http/http.dart" as http;
import "storage_service.dart";
import "github_service.dart";
import "browser_service.dart";
import "sql_service.dart";
import "lsp_service.dart";
import "sub_agent_service.dart";
import "deployment_service.dart";
import "project_service.dart";
import "code_generation_service.dart";
import "brainstorm_engine.dart";
import "snapshot_service.dart";
import "compaction_service.dart";
import "permission_service.dart";
import "mcp_client.dart";
import "diff_service.dart";
import "execution_plan_service.dart";
import "autonomous_loop.dart";
import "project_onboarding.dart";
import "error_learning_service.dart";
import "security_scan_service.dart";
import "api_tester.dart";
import "debate_service.dart";
import "interactive_debugger.dart";
import "performance_profiler.dart";
import "cron_scheduler.dart";
import "task_library.dart";
import "skills.dart";
import "session_memory.dart";
import "research_service.dart";
import "user_profile.dart";
import "code_intelligence.dart";
import "git_service.dart";
import "formatter_service.dart";
import "code_sandbox.dart";
import "bg_service.dart";
import "package:crypto/crypto.dart" as crypto;
import "package:archive/archive.dart";
import "package:archive/archive_io.dart";
import "../models/message.dart";
import "settings_service.dart";
import "api_constants.dart";
import "project_config_service.dart";

enum AgentMode {
  auto,
  brainstorm,
  architect,
  code,
  debug,
  refactor,
  research,
  plan,
}

class ProjectContext {
  final List<String> files;
  final Map<String, String> configFiles;
  final String structure;

  ProjectContext({
    required this.files,
    required this.configFiles,
    required this.structure,
  });
}

class AgentService {
  static const String _apiUrl = ApiConstants.deepseekApi;

  String projectName;
  GitService? gitService;
  final List<Message> messages = [];
  AgentMode currentMode = AgentMode.auto;
  ProjectContext? projectContext;

  void Function(String tool, String args)? onToolCall;
  void Function(String tool, String args, String result)? onToolResult;
  Future<String> Function(String question, List<String>? options)? onQuestion;

  AgentService({required this.projectName});

  void setGitService(GitService gs) {
    gitService = gs;
  }

  Future<void> scanProject() async {
    try {
      final entries = await StorageService.listDir(projectName);
      final files = <String>[];
      final configFiles = <String, String>{};

      for (final e in entries) {
        final name = e.uri.pathSegments.last;
        if (name.startsWith(".") && name != ".gitignore") continue;
        files.add(name);
      }

      final configNames = [
        "package.json",
        "tsconfig.json",
        "pyproject.toml",
        "Cargo.toml",
        "go.mod",
        "requirements.txt",
        "Dockerfile",
        "README.md",
        "AGENTS.md",
        ".gitignore",
      ];

      for (final name in configNames) {
        try {
          final content =
              await StorageService.readFile(projectName, name);
          configFiles[name] = content.length > 2000
              ? content.substring(0, 2000)
              : content;
        } catch (e) {
          // Config file not found or unreadable, skip silently
        }
      }

      final buffer = StringBuffer();
      buffer.writeln("Project: $projectName");
      buffer.writeln("Files: ${files.length} items");
      if (configFiles.containsKey("package.json")) {
        buffer.writeln("Type: Node.js/TypeScript project");
      }
      if (configFiles.containsKey("pyproject.toml") ||
          configFiles.containsKey("requirements.txt")) {
        buffer.writeln("Type: Python project");
      }
      if (configFiles.containsKey("Dockerfile")) {
        buffer.writeln("Docker: yes");
      }

      projectContext = ProjectContext(
        files: files,
        configFiles: configFiles,
        structure: buffer.toString(),
      );

      await ProjectConfigService.load(projectName);

      // Apply permission overrides from project config (supports wildcards)
      final perm = ProjectConfigService.current?.permission;
      if (perm != null) {
        PermissionService.loadFromConfig(perm);
      }
    } catch (e) {
      // Project scan failed, continue without context
      projectContext = null;
    }
  }

  Future<void> _injectContext() async {
    if (projectContext == null) return;

    final ctx = StringBuffer();
    ctx.writeln("\n## Current Project Context");
    ctx.writeln(projectContext!.structure);

    if (projectContext!.configFiles.containsKey("package.json")) {
      ctx.writeln("\n### package.json");
      ctx.writeln("```json");
      ctx.writeln(projectContext!.configFiles["package.json"]);
      ctx.writeln("```");
    }

    if (projectContext!.configFiles.containsKey("README.md")) {
      final readme = projectContext!.configFiles["README.md"]!;
      if (readme.length < 1500) {
        ctx.writeln("\n### README.md");
        ctx.writeln(readme);
      }
    }

    if (messages.length > 1) {
      messages.insert(1, Message(role: "system", content: ctx.toString()));
    } else {
      messages.add(Message(role: "system", content: ctx.toString()));
    }

    // Inject user profile
    final profileCtx = await UserProfile.toContextPrompt();
    messages.insert(
        1, Message(role: "system", content: profileCtx));

    // Inject learned error patterns
    try {
      final errors =
          await ErrorLearningService.getContext(projectName);
      if (errors.isNotEmpty) {
        messages.insert(
            1, Message(role: "system", content: errors));
      }
    } catch (e) {
      // Error learning unavailable, continue without it
    }

    // Inject relevant skills based on project files
    if (projectContext != null) {
      final exts = projectContext!.files
          .where((f) => f.contains("."))
          .map((f) => ".${f.split(".").last}")
          .toList();
      final skills = SkillKnowledge.select(exts, projectContext!.configFiles);
      messages.insert(1, Message(role: "system", content: "\n## Relevant Skills\n$skills"));
    }

    // Load external skills from .opencode/skills/ and config paths
    try {
      final externalSkills = await SkillLoader.loadProjectSkills(projectName);
      final configPaths = ProjectConfigService.current?.skillPaths;
      if (configPaths != null && configPaths.isNotEmpty) {
        final pathSkills = await SkillLoader.loadFromPaths(projectName, configPaths);
        externalSkills.addAll(pathSkills);
      }
      if (externalSkills.isNotEmpty) {
        messages.insert(1, Message(role: "system", content: "\n## External Skills\n${externalSkills.join("\n")}"));
      }
    } catch (e) {
      // External skills unavailable
    }

    // Inject project instructions from .opencode/opencode.jsonc, AGENTS.md, CLAUDE.md, CONTEXT.md, .opencode/rules/
    try {
      final instructions = await ProjectConfigService.loadInstructions(projectName);
      if (instructions.isNotEmpty) {
        final buf = StringBuffer("\n## Project Instructions\n");
        for (final instr in instructions) {
          buf.writeln(instr);
          buf.writeln();
        }
        messages.insert(1, Message(role: "system", content: buf.toString()));
      }
    } catch (e) {
      // Project instructions unavailable
    }
  }

  /// Load saved session from disk
  Future<bool> loadSession() async {
    final saved = await SessionMemory.loadChat(projectName);
    if (saved == null || saved.isEmpty) return false;

    messages.clear();
    messages.add(Message(
        role: "system",
        content: _buildSystemPrompt(currentMode)));
    messages.addAll(saved);
    await _injectContext();

    final decisions =
        await SessionMemory.getDecisions(projectName);
    if (decisions.isNotEmpty) {
      final mem = StringBuffer();
      mem.writeln("\n## Project Memory (previous decisions)");
      for (final d in decisions.reversed.take(5)) {
        mem.writeln("- ${d["topic"]}: ${d["decision"]}");
      }
      messages.insert(
          1, Message(role: "system", content: mem.toString()));
    }

    return true;
  }

  /// Save current session to disk
  Future<void> saveSession() async {
    final nonSystem =
        messages.where((m) => m.role != "system").toList();
    if (nonSystem.length > 2) {
      await SessionMemory.saveChat(projectName, nonSystem);
    }
  }

  /// Remember an important decision
  Future<void> remember(String topic, String decision) async {
    await SessionMemory.rememberDecision(
        projectName, topic, decision);
  }

  /// Compress context if conversation is too long
  void maybeCompress() {
    if (messages.length > 30) {
      try {
        final msgMaps = messages.map((m) => m.toJson()).toList();
        CompactionService.compress(msgMaps).then((summary) {
          if (summary.isNotEmpty) {
            final systemMsgs = messages.where((m) => m.role == "system").toList();
            final keep = messages.length > 6 ? messages.sublist(messages.length - 6) : messages;
            messages.clear();
            messages.addAll([...systemMsgs, Message(role: "system", content: summary), ...keep]);
          }
        });
      } catch (e) {
        final compressed = ContextManager.compress(messages, keepLast: 6);
        messages.replaceRange(0, messages.length, compressed);
      }
    }
  }

  static String _buildSystemPrompt(AgentMode mode) {
    final modeInstructions = switch (mode) {
      AgentMode.brainstorm => """
## MODE: CREATIVE IDEATION
${BrainstormEngine.prompt}
""",
      AgentMode.architect => """
## MODE: ARCHITECT
Plan systems at hyper-scale. Think about failure modes before happy path.
- Map every dependency. Find hidden couplings.
- Design for 10x growth, implement for 1x.
- Consider: CAP, latency budgets, fault tolerance, graceful degradation.
- Output: System Diagram → Data Flow → Failure Modes → Implementation Plan → Migration Path.
""",
      AgentMode.code => """
## MODE: HYPER-ENGINEER
${AutonomousLoop.systemPrompt}
""",
      AgentMode.debug => """
## MODE: DEBUGGER
Trace bugs with surgical precision. Find the ONE root cause.
- Reproduce: exact input, exact state, exact environment.
- Isolate: binary search through code and git history.
- Prove: "If X is the cause, we'd also see Y. Do we?" Eliminate false hypotheses.
- Fix MINIMALLY. One line if possible. Then verify fix doesn't break anything.
- Prevent: find similar patterns elsewhere that have the same bug.
""",
      AgentMode.refactor => """
## MODE: REFACTOR
Restructure for clarity without changing ANY behavior. Tests must pass before and after.
- One change → verify → commit → next change. Never batch refactorings.
- Extract: functions >50 lines, duplicated logic, magic values.
- Simplify: deep nesting, complex conditionals, god objects.
- NEVER: add features, change APIs, modify test expectations.
""",
      AgentMode.research => """
## MODE: DEEP RESEARCH
Investigate thoroughly. Search the web. Read docs. Compare implementations on GitHub.
- Phase 1: Gather. web_search for current info. github_search_code for real examples.
- Phase 2: Analyze. Compare approaches. Note trade-offs. Find consensus and disagreement.
- Phase 3: Synthesize. Executive summary. Key findings with confidence levels. Recommendations.
- Always cite sources. Distinguish fact from opinion. Note when info may be outdated.
""",
      AgentMode.plan => """
## MODE: PLAN
Analyze the codebase thoroughly before writing any code. YOU MUST NOT EDIT FILES.
- Read files, search, glob, explore dependencies, understand architecture.
- Identify: components, data flow, failure modes, missing tests, technical debt.
- Output a clear PLAN with: what needs to change, why, in what order, risks.
- After delivering the plan, STOP. Let the user switch to another mode for execution.
- NEVER use: write_file, edit_file, delete_file, create_tasks, run_command.
""",
      AgentMode.auto => """
## MODE: AUTO
Detect the user's INTENT, not just keywords. Then choose the optimal approach.

Quick decisions: do it yourself.
Complex decisions: delegate to sub-agent (delegate_task tool).
Novel ideas needed: use BrainstormEngine techniques.
Code needed: write yourself or delegate to scribe sub-agent.
Multiple independent tasks: delegate in PARALLEL to save time.

Detection:
- "research", "what is", "compare", "latest" → research mode + web_search
- "how to design", "architecture", "plan" → architect mode
- "write code", "add", "implement" → code mode + delegate to scribe
- "fix bug", "broken", "error" → debug mode + delegate to debugger
- "refactor", "clean up" → refactor mode
- "ideas", "brainstorm", "invent" → brainstorm mode
""",
    };

    return """
## IDENTITY

You are OPENCODE — a hyper-engineer AI agent. You operate at a level beyond senior engineers.
You don't just write code. You architect systems, invent solutions, and orchestrate sub-agents.
You understand the user deeply — their goals, their style, their unspoken constraints.

## CORE PRINCIPLES

1. UNDERSTAND BEFORE ACTING
   - Read the project context. Read existing code. Read the user's profile.
   - Ask clarifying questions when the intent is ambiguous.
   - Never assume. Never guess. Verify with tools.

2. ORCHESTRATE — DELEGATE AGGRESSIVELY
   - You have 9 specialized sub-agents. USE THEM.
   - For ANY non-trivial task, delegate to the right sub-agent via delegate_task.
   - Run INDEPENDENT sub-tasks in PARALLEL (multiple delegate_task calls).
   - You are the conductor. Sub-agents are your elite team.
   - Agent routing:
     * architect → system design, architecture plans, trade-off analysis
     * scribe → production code in any language, matches project style
     * debugger → root cause analysis, stack trace tracing
     * reviewer → code review, bug detection, style check
     * refactor → safe restructuring without behavior change
     * researcher → deep web research, documentation lookup
     * typesmith → TypeScript types, Effect schemas, complex generics
     * qa_engineer → test strategy, test cases, bug reports
     * ab_tester → hypothesis, experiment design, results analysis
   - After sub-agents finish: review their work, integrate results, verify quality.
   - For simple tasks (<3 tool calls) → do it yourself.
   - For complex tasks (3+ files, architecture, debugging) → ALWAYS delegate.

3. WRITE FLAWLESS CODE
   - Every function handles null, empty, error, and edge cases.
   - Every file follows the project's existing conventions EXACTLY.
   - After writing, diagnose yourself. find_patterns to check consistency.
   - Use edit_file for changes, not write_file (preserve rest of file).

4. THINK CREATIVELY
   - When asked for ideas, use lateral thinking: inversion, analogy, combination, constraint removal.
   - Never suggest obvious solutions. Challenge assumptions.
   - Generate ideas that don't exist yet. Combine unrelated domains.

5. VERIFY EVERYTHING
   - After code changes: diagnose_file, check_imports, run tests.
   - After architecture plans: impact_analysis to see what breaks.
   - After research: cite sources. Cross-reference.

6. COMMIT WITH MEANING
   - type(scope): description — feat, fix, docs, chore, refactor, test.
   - One commit per logical change. Never batch unrelated work.
   - Describe WHY, not WHAT.

$modeInstructions

## KNOWLEDGE BASE
${SkillKnowledge.all}

## AVAILABLE TOOLS
You have 154 tools available. Key categories:

CORE (12):
  read_file, write_file, edit_file, delete_file, list_files, glob_files, search_code,
  run_command, web_search, web_fetch, ask_user, impact_analysis

GIT (9):
  git_sync, git_status, git_branch, git_blame, git_tag, git_cherry_pick,
  git_revert, git_squash, compare_branches

GITHUB (8):
  github_list_issues, github_create_issue, github_list_prs, github_get_pr,
  github_search_code, github_get_file, github_get_repo, create_pr

QUALITY (8):
  diagnose_file, analyze_project, check_imports, find_patterns, suggest_tests,
  suggest_optimizations, estimate_effort, check_deps

TASK MGMT (7):
  create_tasks, todowrite, todolist, run_task, list_tasks, run_background,
  delegate_task

CRON (3): cron_schedule, cron_list, cron_cancel

SNAPSHOT (2): snapshot_undo, snapshot_undo_all

DEPLOY (3): check_deploy_readiness, generate_docker_compose, generate_ci_config

MCP & DIFF (3): mcp_call, diff_preview, batch_execute

UTILITIES (25):
  uuid_gen, color_palette, date_convert, base64_tool, jwt_decode, regex_test,
  hash_file, token_count, word_count, count_lines, detect_language, markdown_toc,
  generate_qr, archive_create, archive_extract, dns_lookup,
  port_check, ssl_check, whois_lookup, url_shorten, http_headers,
  validate_config, convert_format, minify_code, format_code

GENERATORS (30):
  generate_license, generate_env_example, generate_readme, generate_api_docs,
  generate_makefile, generate_dockerfile, generate_nginx_config,
  generate_pm2_config, generate_systemd, generate_editorconfig,
  generate_gitattributes, generate_badges, generate_contributing,
  generate_codeowners, generate_sitemap, generate_robots, generate_htaccess,
  generate_test_template, generate_boilerplate, generate_diagram, generate_mock,
  generate_changelog, generate_release_notes, css_reset, meta_tags

CODE ANALYSIS (14):
  find_duplicates, dead_code, circular_deps, code_stats, complexity_report,
  test_coverage, naming_convention, index_suggestion, bundle_phobia,
  npm_downloads, search_github_trending, diff_two_files, check_bundle_size,
  analyze_function

SCHEMA (8):
  json_schema_gen, swagger_gen, graphql_schema_gen, proto_gen,
  sql_migration_gen, seed_data_gen, validate_openapi, semver_bump

SECURITY (2): security_scan, accessibility_audit

DEBUG (4): profile_performance, detect_conflicts, self_review, analyze_function

PLANNING (3): create_plan, project_summary, impact_analysis

BROWSER (3): browser_open, browser_extract, browser_follow

SQL (3): sql_detect, sql_query, sql_schema

DELEGATION: delegate_task → roles: architect | scribe | debugger | reviewer |
  refactor | researcher | typesmith | qa_engineer | ab_tester

RESEARCH (4): search_stackoverflow, search_npm, search_pypi, search_docs

AI (3): api_test, debate, api_test

MISC (6):
  i18n_find, git_hook_gen, ssl_cert, mermaid_render, plantuml_render,
  ascii_tree

## CODE RULES
- No try/catch unless unavoidable. No 'any' in TypeScript. No 'else'.
- Early returns. const > let. Ternaries > reassignment.
- Functions < 50 lines. Files < 300 lines.
- Handle null/empty/wrong-type. Error messages: what+why+fix.
- Match existing project style EXACTLY. Read before write.
- Never: secrets in code, empty catch, eval with user input, == in JS.
""";
  }

  static final List<Map<String, dynamic>> _tools = [
    {
      "type": "function",
      "function": {
        "name": "read_file",
        "description": "Read contents of a file",
        "parameters": {
          "type": "object",
          "properties": {
            "project": {"type": "string"},
            "path": {"type": "string"},
          },
          "required": ["project", "path"],
        },
      },
    },
    {
      "type": "function",
      "function": {
        "name": "write_file",
        "description":
            "Write content to a file. Creates directories if needed.",
        "parameters": {
          "type": "object",
          "properties": {
            "project": {"type": "string"},
            "path": {"type": "string"},
            "content": {"type": "string"},
          },
          "required": ["project", "path", "content"],
        },
      },
    },
    {
      "type": "function",
      "function": {
        "name": "list_files",
        "description": "List files in a directory",
        "parameters": {
          "type": "object",
          "properties": {
            "project": {"type": "string"},
            "path": {"type": "string"},
          },
          "required": ["project"],
        },
      },
    },
    {
      "type": "function",
      "function": {
        "name": "delete_file",
        "description": "Delete a file",
        "parameters": {
          "type": "object",
          "properties": {
            "project": {"type": "string"},
            "path": {"type": "string"},
          },
          "required": ["project", "path"],
        },
      },
    },
    {
      "type": "function",
      "function": {
        "name": "search_code",
        "description":
            "Search for text patterns in project files. Use to find functions, types, imports, patterns.",
        "parameters": {
          "type": "object",
          "properties": {
            "project": {"type": "string"},
            "pattern": {"type": "string"},
            "fileExt": {"type": "string"},
          },
          "required": ["project", "pattern"],
        },
      },
    },
    {
      "type": "function",
      "function": {
        "name": "git_sync",
        "description":
            "Commit all changes and push to GitHub. Use meaningful commit messages: type(scope): description.",
        "parameters": {
          "type": "object",
          "properties": {
            "project": {"type": "string"},
            "message": {"type": "string"},
          },
          "required": ["project", "message"],
        },
      },
    },
    {
      "type": "function",
      "function": {
        "name": "git_status",
        "description": "Check git working tree status",
        "parameters": {
          "type": "object",
          "properties": {
            "project": {"type": "string"},
          },
          "required": ["project"],
        },
      },
    },
    {
      "type": "function",
      "function": {
        "name": "web_search",
        "description":
            "Search the web for current information. Use for research, documentation lookups, comparing technologies, finding solutions. Returns titles, snippets, and URLs.",
        "parameters": {
          "type": "object",
          "properties": {
            "query": {
              "type": "string",
              "description": "Search query",
            },
            "max_results": {
              "type": "integer",
              "description": "Max results (1-10, default 5)",
            },
          },
          "required": ["query"],
        },
      },
    },
    {
      "type": "function",
      "function": {
        "name": "web_fetch",
        "description":
            "Fetch and read content from a URL. Use to read documentation, articles, or any web page. Returns extracted text.",
        "parameters": {
          "type": "object",
          "properties": {
            "url": {
              "type": "string",
              "description": "Full URL to fetch",
            },
          },
          "required": ["url"],
        },
      },
    },
    {
      "type": "function",
      "function": {
        "name": "impact_analysis",
        "description":
            "Analyze what files would be affected if a given file is changed. Shows direct and transitive dependents with risk level.",
        "parameters": {
          "type": "object",
          "properties": {
            "project": {"type": "string"},
            "file_path": {
              "type": "string",
              "description": "File path to analyze",
            },
          },
          "required": ["project", "file_path"],
        },
      },
    },
    {
      "type": "function",
      "function": {
        "name": "run_command",
        "description":
            "Execute a terminal command and return the output. Use for: running tests, typecheck, lint, build, npm/pip install, git commands beyond sync/status, or any shell operation.",
        "parameters": {
          "type": "object",
          "properties": {
            "project": {"type": "string"},
            "command": {
              "type": "string",
              "description": "Shell command to run",
            },
            "cwd": {
              "type": "string",
              "description":
                  "Working directory relative to project root (optional)",
            },
          },
          "required": ["project", "command"],
        },
      },
    },
    {
      "type": "function",
      "function": {
        "name": "glob_files",
        "description":
            "Find files matching a glob pattern. Use to discover project structure. Example patterns: '**/*.ts', 'src/**/*.tsx', '*.json'.",
        "parameters": {
          "type": "object",
          "properties": {
            "project": {"type": "string"},
            "pattern": {
              "type": "string",
              "description": "Glob pattern",
            },
          },
          "required": ["project", "pattern"],
        },
      },
    },
    {
      "type": "function",
      "function": {
        "name": "edit_file",
        "description":
            "Edit specific lines in an existing file. Use instead of write_file when modifying existing code — preserves the rest of the file. Provide old_string (text to replace) and new_string (replacement).",
        "parameters": {
          "type": "object",
          "properties": {
            "project": {"type": "string"},
            "path": {"type": "string"},
            "old_string": {
              "type": "string",
              "description":
                  "Exact text to find and replace",
            },
            "new_string": {
              "type": "string",
              "description": "Replacement text",
            },
          },
          "required": [
            "project",
            "path",
            "old_string",
            "new_string"
          ],
        },
      },
    },
    {
      "type": "function",
      "function": {
        "name": "create_tasks",
        "description":
            "Create a structured task list to track progress. Use for complex multi-step work. Provide list of tasks with statuses.",
        "parameters": {
          "type": "object",
          "properties": {
            "tasks": {
              "type": "array",
              "items": {
                "type": "object",
                "properties": {
                  "content": {
                    "type": "string",
                    "description":
                        "Task description",
                  },
                  "status": {
                    "type": "string",
                    "enum": [
                      "pending",
                      "in_progress",
                      "completed",
                      "cancelled"
                    ],
                  },
                  "priority": {
                    "type": "string",
                    "enum": [
                      "high",
                      "medium",
                      "low"
                    ],
                  },
                },
                "required": [
                  "content",
                  "status",
                  "priority"
                ],
              },
              "description": "List of tasks",
            },
          },
          "required": ["tasks"],
        },
      },
    },
    {
      "type": "function",
      "function": {
        "name": "ask_user",
        "description":
            "Ask the user a clarifying question when you need more information. Use when requirements are ambiguous or you need to choose between approaches.",
        "parameters": {
          "type": "object",
          "properties": {
            "question": {"type": "string"},
            "options": {
              "type": "array",
              "items": {"type": "string"},
            },
          },
          "required": ["question"],
        },
      },
    },
    {
      "type": "function",
      "function": {
        "name": "todowrite",
        "description": "Create or update a persistent todo list. Use for tracking multi-step progress across sessions. Each task has content, status (pending/in_progress/completed/cancelled), and priority (high/medium/low).",
        "parameters": {
          "type": "object",
          "properties": {
            "project": {"type": "string"},
            "tasks": {
              "type": "array",
              "items": {
                "type": "object",
                "properties": {
                  "content": {"type": "string", "description": "Task description"},
                  "status": {"type": "string", "enum": ["pending", "in_progress", "completed", "cancelled"]},
                  "priority": {"type": "string", "enum": ["high", "medium", "low"]}
                },
                "required": ["content", "status", "priority"]
              }
            }
          },
          "required": ["project", "tasks"]
        }
      }
    },
    {
      "type": "function",
      "function": {
        "name": "todolist",
        "description": "Read the current todo list. Returns all tasks with their status and priority.",
        "parameters": {
          "type": "object",
          "properties": {
            "project": {"type": "string"}
          },
          "required": ["project"]
        }
      }
    },
    // GitHub API tools
    {
      "type": "function",
      "function": {
        "name": "github_list_issues",
        "description":
            "List GitHub issues for a repository. Use to find bugs, feature requests, or tasks.",
        "parameters": {
          "type": "object",
          "properties": {
            "owner": {
              "type": "string",
              "description": "Repo owner",
            },
            "repo": {
              "type": "string",
              "description": "Repo name",
            },
            "state": {
              "type": "string",
              "description":
                  "Issue state: open, closed, all",
            },
            "label": {"type": "string"},
          },
          "required": ["owner", "repo"],
        },
      },
    },
    {
      "type": "function",
      "function": {
        "name": "github_create_issue",
        "description":
            "Create a new GitHub issue.",
        "parameters": {
          "type": "object",
          "properties": {
            "owner": {"type": "string"},
            "repo": {"type": "string"},
            "title": {"type": "string"},
            "body": {"type": "string"},
            "labels": {
              "type": "array",
              "items": {"type": "string"},
            },
          },
          "required": [
            "owner",
            "repo",
            "title",
            "body"
          ],
        },
      },
    },
    {
      "type": "function",
      "function": {
        "name": "github_list_prs",
        "description":
            "List pull requests for a repository.",
        "parameters": {
          "type": "object",
          "properties": {
            "owner": {"type": "string"},
            "repo": {"type": "string"},
            "state": {
              "type": "string",
              "description":
                  "PR state: open, closed, all",
            },
          },
          "required": ["owner", "repo"],
        },
      },
    },
    {
      "type": "function",
      "function": {
        "name": "github_get_pr",
        "description":
            "Get details of a specific pull request including changed files.",
        "parameters": {
          "type": "object",
          "properties": {
            "owner": {"type": "string"},
            "repo": {"type": "string"},
            "number": {"type": "integer"},
          },
          "required": [
            "owner",
            "repo",
            "number"
          ],
        },
      },
    },
    {
      "type": "function",
      "function": {
        "name": "github_search_code",
        "description":
            "Search code across GitHub. Use to find examples, implementations, or usage patterns.",
        "parameters": {
          "type": "object",
          "properties": {
            "query": {
              "type": "string",
              "description":
                  "Search query (supports GitHub search syntax)",
            },
          },
          "required": ["query"],
        },
      },
    },
    {
      "type": "function",
      "function": {
        "name": "github_get_file",
        "description":
            "Read a file directly from a GitHub repository without cloning.",
        "parameters": {
          "type": "object",
          "properties": {
            "owner": {"type": "string"},
            "repo": {"type": "string"},
            "path": {
              "type": "string",
              "description": "File path in repo",
            },
            "ref": {
              "type": "string",
              "description":
                  "Branch/tag (default: main)",
            },
          },
          "required": [
            "owner",
            "repo",
            "path"
          ],
        },
      },
    },
    {
      "type": "function",
      "function": {
        "name": "github_get_repo",
        "description":
            "Get repository info: stars, language, description, open issues.",
        "parameters": {
          "type": "object",
          "properties": {
            "owner": {"type": "string"},
            "repo": {"type": "string"},
          },
          "required": ["owner", "repo"],
        },
      },
    },
    // Browser/web tools
    {
      "type": "function",
      "function": {
        "name": "browser_open",
        "description":
            "Open a web page and extract its content — title, headings, links, text. Like reading a webpage in a browser.",
        "parameters": {
          "type": "object",
          "properties": {
            "url": {
              "type": "string",
              "description": "Full URL to open",
            },
          },
          "required": ["url"],
        },
      },
    },
    {
      "type": "function",
      "function": {
        "name": "browser_extract",
        "description":
            "Extract specific data from a web page using a regex pattern. Useful for scraping structured data.",
        "parameters": {
          "type": "object",
          "properties": {
            "url": {"type": "string"},
            "pattern": {
              "type": "string",
              "description":
                  "Regex pattern with capture groups",
            },
          },
          "required": ["url", "pattern"],
        },
      },
    },
    {
      "type": "function",
      "function": {
        "name": "browser_follow",
        "description":
            "Click/follow a link on a web page by its text.",
        "parameters": {
          "type": "object",
          "properties": {
            "url": {
              "type": "string",
              "description": "Current page URL",
            },
            "link_text": {
              "type": "string",
              "description": "Text of the link to click",
            },
          },
          "required": ["url", "link_text"],
        },
      },
    },
    // SQL tools
    {
      "type": "function",
      "function": {
        "name": "sql_detect",
        "description":
            "Detect SQLite databases in the project.",
        "parameters": {
          "type": "object",
          "properties": {
            "project": {"type": "string"},
          },
          "required": ["project"],
        },
      },
    },
    {
      "type": "function",
      "function": {
        "name": "sql_query",
        "description":
            "Run an SQL query against a SQLite database in the project.",
        "parameters": {
          "type": "object",
          "properties": {
            "project": {"type": "string"},
            "db_file": {
              "type": "string",
              "description": "Database filename",
            },
            "query": {
              "type": "string",
              "description": "SQL query to run",
            },
          },
          "required": [
            "project",
            "db_file",
            "query"
          ],
        },
      },
    },
    {
      "type": "function",
      "function": {
        "name": "sql_schema",
        "description":
            "Show the schema of a SQLite database — all tables and their columns.",
        "parameters": {
          "type": "object",
          "properties": {
            "project": {"type": "string"},
            "db_file": {"type": "string"},
          },
          "required": ["project", "db_file"],
        },
      },
    },
    // Code quality tools
    {
      "type": "function",
      "function": {
        "name": "find_patterns",
        "description":
            "Find similar code patterns across the project. Useful for discovering conventions, duplicated code, or finding all usages of an API.",
        "parameters": {
          "type": "object",
          "properties": {
            "project": {"type": "string"},
            "pattern": {
              "type": "string",
              "description":
                  "Code pattern to search for",
            },
          },
          "required": ["project", "pattern"],
        },
      },
    },
    {
      "type": "function",
      "function": {
        "name": "suggest_tests",
        "description":
            "Analyze a source file and suggest what tests should be written.",
        "parameters": {
          "type": "object",
          "properties": {
            "project": {"type": "string"},
            "file_path": {"type": "string"},
          },
          "required": ["project", "file_path"],
        },
      },
    },
    // LSP / Diagnostics tools
    {
      "type": "function",
      "function": {
        "name": "diagnose_file",
        "description":
            "Analyze a file for code quality issues: any types, missing imports, security risks, anti-patterns, TODO comments. Returns diagnostics with line numbers.",
        "parameters": {
          "type": "object",
          "properties": {
            "project": {"type": "string"},
            "file_path": {"type": "string"},
          },
          "required": ["project", "file_path"],
        },
      },
    },
    {
      "type": "function",
      "function": {
        "name": "analyze_project",
        "description":
            "Scan the entire project for code quality issues across all source files. Returns summary with top issues per file.",
        "parameters": {
          "type": "object",
          "properties": {
            "project": {"type": "string"},
          },
          "required": ["project"],
        },
      },
    },
    {
      "type": "function",
      "function": {
        "name": "check_imports",
        "description":
            "Verify that all relative imports in a file reference real files. Finds broken imports.",
        "parameters": {
          "type": "object",
          "properties": {
            "project": {"type": "string"},
            "file_path": {"type": "string"},
          },
          "required": ["project", "file_path"],
        },
      },
    },
    // Multi-agent delegation
    {
      "type": "function",
      "function": {
        "name": "delegate_task",
        "description":
            "Delegate a task to a specialized sub-agent (architect, scribe, debugger, reviewer, refactor, researcher).",
        "parameters": {
          "type": "object",
          "properties": {
            "agent_type": {
              "type": "string",
              "enum": [
                "architect",
                "scribe",
                "debugger",
                "reviewer",
                "refactor",
                "researcher",
                "typesmith",
                "qa_engineer",
                "ab_tester",
              ],
            },
            "task": {"type": "string"},
          },
          "required": ["agent_type", "task"],
        },
      },
    },
    {
      "type": "function",
      "function": {
        "name": "run_background",
        "description": "Start a task in the background and return immediately. You'll be notified when it completes. Use for long-running tasks that don't need immediate results.",
        "parameters": {
          "type": "object",
          "properties": {
            "agent_type": {
              "type": "string",
              "enum": ["architect", "scribe", "debugger", "reviewer", "refactor", "researcher", "typesmith", "qa_engineer", "ab_tester"],
            },
            "task": {"type": "string"},
          },
          "required": ["agent_type", "task"],
        },
      },
    },
    // Deployment tools
    {
      "type": "function",
      "function": {
        "name": "check_deploy_readiness",
        "description":
            "Check if a project is ready for deployment: Dockerfile, .gitignore, lockfile, README, CI config, env template.",
        "parameters": {
          "type": "object",
          "properties": {
            "project": {"type": "string"},
          },
          "required": ["project"],
        },
      },
    },
    {
      "type": "function",
      "function": {
        "name": "generate_docker_compose",
        "description":
            "Generate docker-compose.yml for common stacks: node-postgres, python-postgres, node-mongo.",
        "parameters": {
          "type": "object",
          "properties": {
            "stack": {
              "type": "string",
              "description": "Stack type",
            },
            "config": {
              "type": "object",
              "description":
                  "Config: port, db name, etc.",
            },
          },
          "required": ["stack"],
        },
      },
    },
    {
      "type": "function",
      "function": {
        "name": "generate_ci_config",
        "description":
            "Generate CI/CD pipeline config for GitHub Actions.",
        "parameters": {
          "type": "object",
          "properties": {
            "platform": {
              "type": "string",
              "description":
                  "github-node, github-python, github-flutter",
            },
            "node_version": {"type": "string"},
            "python_version": {"type": "string"},
          },
          "required": ["platform"],
        },
      },
    },
    // Code generation tools
    {
      "type": "function",
      "function": {
        "name": "generate_test_template",
        "description":
            "Generate a test file template for a source file — auto-discovers functions and creates test stubs.",
        "parameters": {
          "type": "object",
          "properties": {
            "project": {"type": "string"},
            "source_file": {"type": "string"},
          },
          "required": ["project", "source_file"],
        },
      },
    },
    {
      "type": "function",
      "function": {
        "name": "generate_boilerplate",
        "description":
            "Generate project boilerplate: express-api, react-component, python-fastapi, flutter-screen.",
        "parameters": {
          "type": "object",
          "properties": {
            "project_type": {"type": "string"},
            "name": {
              "type": "string",
              "description": "Component/Project name",
            },
          },
          "required": ["project_type", "name"],
        },
      },
    },
    {
      "type": "function",
      "function": {
        "name": "suggest_optimizations",
        "description":
            "Analyze code and suggest performance optimizations: N+1 queries, inefficient loops, missing memo, sync in async.",
        "parameters": {
          "type": "object",
          "properties": {
            "code": {
              "type": "string",
              "description": "Code snippet to analyze",
            },
          },
          "required": ["code"],
        },
      },
    },
    // Project management tools
    {
      "type": "function",
      "function": {
        "name": "estimate_effort",
        "description":
            "Estimate development effort for a task based on description. Covers: features, bug fixes, refactoring, API, DB, UI, testing, docs, auth, DevOps.",
        "parameters": {
          "type": "object",
          "properties": {
            "description": {
              "type": "string",
              "description": "Task description",
            },
          },
          "required": ["description"],
        },
      },
    },
    {
      "type": "function",
      "function": {
        "name": "generate_readme",
        "description":
            "Generate a README.md template for a project.",
        "parameters": {
          "type": "object",
          "properties": {
            "project_name": {"type": "string"},
            "description": {"type": "string"},
            "tech_stack": {"type": "string"},
          },
          "required": [
            "project_name",
            "description",
            "tech_stack"
          ],
        },
      },
    },
    {
      "type": "function",
      "function": {
        "name": "generate_api_docs",
        "description":
            "Generate API documentation from a source file — extracts exported functions, parameters, return types, JSDoc.",
        "parameters": {
          "type": "object",
          "properties": {
            "project": {"type": "string"},
            "source_file": {"type": "string"},
          },
          "required": ["project", "source_file"],
        },
      },
    },
    {
      "type": "function",
      "function": {
        "name": "snapshot_undo",
        "description": "Undo the last change to a file. Restores previous version from snapshot.",
        "parameters": {
          "type": "object",
          "properties": {
            "project": {"type": "string"},
            "file_path": {"type": "string"},
          },
          "required": ["project", "file_path"],
        },
      },
    },
    {
      "type": "function",
      "function": {
        "name": "snapshot_undo_all",
        "description": "Undo ALL changes in this session. Restores all modified files.",
        "parameters": {
          "type": "object",
          "properties": {
            "project": {"type": "string"},
          },
          "required": ["project"],
        },
      },
    },
    {
      "type": "function",
      "function": {
        "name": "format_code",
        "description": "Format source code using appropriate formatter (prettier/ruff/dart fmt/gofmt).",
        "parameters": {
          "type": "object",
          "properties": {
            "project": {"type": "string"},
            "file_path": {"type": "string"},
          },
          "required": ["project", "file_path"],
        },
      },
    },
    {
      "type": "function",
      "function": {
        "name": "batch_execute",
        "description": "Execute multiple independent tool calls in parallel.",
        "parameters": {
          "type": "object",
          "properties": {
            "calls": {
              "type": "array",
              "items": {
                "type": "object",
                "properties": {
                  "tool": {"type": "string"},
                  "args": {"type": "object"},
                },
                "required": ["tool", "args"],
              },
            },
          },
          "required": ["calls"],
        },
      },
    },
    {
      "type": "function",
      "function": {
        "name": "mcp_call",
        "description": "Call a tool on a remote MCP (Model Context Protocol) server via HTTP. Provide server URL, tool name, arguments.",
        "parameters": {
          "type": "object",
          "properties": {
            "url": {"type": "string"},
            "tool": {"type": "string"},
            "args": {"type": "object"},
          },
          "required": ["url", "tool", "args"],
        },
      },
    },
    {
      "type": "function",
      "function": {
        "name": "diff_preview",
        "description": "Preview the diff of a pending edit before applying it. Shows what lines will be added and removed.",
        "parameters": {
          "type": "object",
          "properties": {
            "project": {"type": "string"},
            "file_path": {"type": "string"},
            "old_string": {"type": "string"},
            "new_string": {"type": "string"},
          },
          "required": ["project", "file_path", "old_string", "new_string"],
        },
      },
    },
    {
      "type": "function",
      "function": {
        "name": "create_plan",
        "description": "Create a structured execution plan for complex tasks.",
        "parameters": {
          "type": "object",
          "properties": {
            "task": {"type": "string"},
          },
          "required": ["task"],
        },
      },
    },
    {
      "type": "function",
      "function": {
        "name": "self_review",
        "description": "Review your own code changes before committing. Checks for bugs, style issues, and anti-patterns. Use before git_sync.",
        "parameters": {
          "type": "object",
          "properties": {
            "project": {"type": "string"},
            "file_path": {"type": "string", "description": "Specific file to review (optional, omit for all changed files)"},
          },
          "required": ["project"],
        },
      },
    },
    {
      "type": "function",
      "function": {
        "name": "project_summary",
        "description": "Get a comprehensive summary of a project: tech stack, dependencies, structure. Use when opening a project.",
        "parameters": {
          "type": "object",
          "properties": {
            "project": {"type": "string"},
          },
          "required": ["project"],
        },
      },
    },
    {
      "type": "function",
      "function": {
        "name": "security_scan",
        "description": "Scan the entire project for OWASP Top 10 vulnerabilities: hardcoded secrets, injection risks, weak crypto, auth issues.",
        "parameters": {
          "type": "object",
          "properties": {
            "project": {"type": "string"},
          },
          "required": ["project"],
        },
      },
    },
    {
      "type": "function",
      "function": {
        "name": "api_test",
        "description": "Test a REST API endpoint. GET or POST. Returns status code and response body.",
        "parameters": {
          "type": "object",
          "properties": {
            "method": {"type": "string", "enum": ["GET", "POST"]},
            "url": {"type": "string"},
            "body": {"type": "string", "description": "Request body for POST"},
            "headers": {"type": "object", "description": "Custom headers"},
          },
          "required": ["method", "url"],
        },
      },
    },
    {
      "type": "function",
      "function": {
        "name": "debate",
        "description": "Run a structured debate between two sub-agents on a topic. Agent1 argues FOR, Agent2 argues AGAINST. Synthesize the resolution.",
        "parameters": {
          "type": "object",
          "properties": {
            "topic": {"type": "string"},
            "agent1": {"type": "string", "description": "First sub-agent type"},
            "agent2": {"type": "string", "description": "Second sub-agent type"},
          },
          "required": ["topic", "agent1", "agent2"],
        },
      },
    },
    {
      "type": "function",
      "function": {
        "name": "create_pr",
        "description": "Create a GitHub Pull Request with the current changes. Use after committing.",
        "parameters": {
          "type": "object",
          "properties": {
            "owner": {"type": "string"},
            "repo": {"type": "string"},
            "title": {"type": "string"},
            "body": {"type": "string"},
            "head": {"type": "string", "description": "Source branch (default: master)"},
            "base": {"type": "string", "description": "Target branch (default: main)"},
          },
          "required": ["owner", "repo", "title", "body"],
        },
      },
    },
    {
      "type": "function",
      "function": {
        "name": "run_code",
        "description": "Run code in a sandbox. Supports js/py/dart/sh. Auto-detects language.",
        "parameters": {
          "type": "object",
          "properties": {
            "project": {"type": "string"},
            "code": {"type": "string"},
            "language": {"type": "string"},
          },
          "required": ["project", "code"],
        },
      },
    },
    {
      "type": "function",
      "function": {
        "name": "check_deps",
        "description": "Check for outdated npm/pip dependencies.",
        "parameters": {
          "type": "object",
          "properties": {
            "project": {"type": "string"},
          },
          "required": ["project"],
        },
      },
    },
    {
      "type": "function",
      "function": {
        "name": "analyze_function",
        "description": "Analyze a function: variables, returns, bugs, complexity.",
        "parameters": {
          "type": "object",
          "properties": {
            "project": {"type": "string"},
            "file_path": {"type": "string"},
            "function_name": {"type": "string"},
          },
          "required": ["project","file_path","function_name"],
        },
      },
    },
    {
      "type": "function",
      "function": {
        "name": "detect_conflicts",
        "description": "Detect merge conflicts and show resolution strategy.",
        "parameters": {
          "type": "object",
          "properties": {
            "project": {"type": "string"},
          },
          "required": ["project"],
        },
      },
    },
    {
      "type": "function",
      "function": {
        "name": "profile_performance",
        "description": "Analyze code for performance bottlenecks.",
        "parameters": {
          "type": "object",
          "properties": {
            "project": {"type": "string"},
            "file_path": {"type": "string"},
          },
          "required": ["project"],
        },
      },
    },
    { "type":"function","function":{ "name":"daily_standup","description":"Generate a daily standup summary from git history.","parameters":{"type":"object","properties":{"project":{"type":"string"}},"required":["project"]}}},
    { "type":"function","function":{ "name":"cron_schedule","description":"Schedule a task for later (e.g. 'check tests at 9am').","parameters":{"type":"object","properties":{"project":{"type":"string"},"task":{"type":"string"},"when":{"type":"string","description":"ISO datetime"}},"required":["project","task","when"]}}},
    { "type":"function","function":{ "name":"cron_list","description":"List all scheduled tasks.","parameters":{"type":"object","properties":{"project":{"type":"string"}},"required":["project"]}}},
    { "type":"function","function":{ "name":"cron_cancel","description":"Cancel a scheduled task.","parameters":{"type":"object","properties":{"project":{"type":"string"},"task":{"type":"string","description":"Task pattern to match"}},"required":["project","task"]}}},
    { "type":"function","function":{ "name":"git_branch","description":"Create or switch git branches.","parameters":{"type":"object","properties":{"project":{"type":"string"},"action":{"type":"string","enum":["create","switch","list"]},"name":{"type":"string"}},"required":["project","action"]}}},
    { "type":"function","function":{ "name":"count_lines","description":"Count lines of code per language in the project.","parameters":{"type":"object","properties":{"project":{"type":"string"}},"required":["project"]}}},
    { "type":"function","function":{ "name":"find_duplicates","description":"Find duplicate code blocks across the project.","parameters":{"type":"object","properties":{"project":{"type":"string"}},"required":["project"]}}},
    { "type":"function","function":{ "name":"search_stackoverflow","description":"Search Stack Overflow for solutions to a coding problem.","parameters":{"type":"object","properties":{"query":{"type":"string"}},"required":["query"]}}},
    { "type":"function","function":{ "name":"search_npm","description":"Search npm registry for packages.","parameters":{"type":"object","properties":{"query":{"type":"string"}},"required":["query"]}}},
    { "type":"function","function":{ "name":"search_pypi","description":"Search PyPI for Python packages.","parameters":{"type":"object","properties":{"query":{"type":"string"}},"required":["query"]}}},
    { "type":"function","function":{ "name":"generate_diagram","description":"Generate Mermaid.js diagram (architecture, flow, ER, sequence).","parameters":{"type":"object","properties":{"type":{"type":"string","enum":["architecture","flow","er","sequence","class"]},"description":{"type":"string"}},"required":["type","description"]}}},
    { "type":"function","function":{ "name":"minify_code","description":"Minify JS/CSS code for production.","parameters":{"type":"object","properties":{"project":{"type":"string"},"file_path":{"type":"string"}},"required":["project","file_path"]}}},
    { "type":"function","function":{ "name":"validate_config","description":"Validate JSON/YAML/TOML config files for syntax errors.","parameters":{"type":"object","properties":{"project":{"type":"string"},"file_path":{"type":"string"}},"required":["project","file_path"]}}},
    { "type":"function","function":{ "name":"convert_format","description":"Convert between JSON ↔ YAML ↔ XML ↔ CSV.","parameters":{"type":"object","properties":{"content":{"type":"string"},"from":{"type":"string"},"to":{"type":"string"}},"required":["content","from","to"]}}},
    { "type":"function","function":{ "name":"generate_license","description":"Generate a LICENSE file (MIT, Apache-2.0, GPL-3.0).","parameters":{"type":"object","properties":{"type":{"type":"string","enum":["MIT","Apache-2.0","GPL-3.0"]},"author":{"type":"string"}},"required":["type","author"]}}},
    { "type":"function","function":{ "name":"generate_env_example","description":"Scan code for env vars and generate .env.example.","parameters":{"type":"object","properties":{"project":{"type":"string"}},"required":["project"]}}},
    { "type":"function","function":{ "name":"git_blame","description":"Show who last modified each line of a file.","parameters":{"type":"object","properties":{"project":{"type":"string"},"file_path":{"type":"string"}},"required":["project","file_path"]}}},
    { "type":"function","function":{ "name":"check_bundle_size","description":"Estimate app/project size. Reports file counts and largest files.","parameters":{"type":"object","properties":{"project":{"type":"string"}},"required":["project"]}}},
    { "type":"function","function":{ "name":"search_docs","description":"Search official documentation for a technology (MDN, devdocs.io style).","parameters":{"type":"object","properties":{"tech":{"type":"string"},"query":{"type":"string"}},"required":["tech","query"]}}},
    { "type":"function","function":{ "name":"generate_qr","description":"Generate a QR code from text/URL.","parameters":{"type":"object","properties":{"data":{"type":"string"}},"required":["data"]}}},
    { "type":"function","function":{ "name":"generate_mock","description":"Generate mock test data (names, emails, addresses, UUIDs) in JSON/CSV/SQL.","parameters":{"type":"object","properties":{"type":{"type":"string","enum":["json","csv","sql"]},"count":{"type":"integer"}},"required":["type","count"]}}},
    { "type":"function","function":{ "name":"validate_openapi","description":"Validate an OpenAPI/Swagger spec.","parameters":{"type":"object","properties":{"project":{"type":"string"},"file_path":{"type":"string"}},"required":["project","file_path"]}}},
    { "type":"function","function":{ "name":"semver_bump","description":"Bump version in package.json or pyproject.toml.","parameters":{"type":"object","properties":{"project":{"type":"string"},"level":{"type":"string","enum":["major","minor","patch"]}},"required":["project","level"]}}},
    { "type":"function","function":{ "name":"dead_code","description":"Find potentially unused code — functions never called, imports never used.","parameters":{"type":"object","properties":{"project":{"type":"string"}},"required":["project"]}}},
    { "type":"function","function":{ "name":"circular_deps","description":"Find circular dependencies between files.","parameters":{"type":"object","properties":{"project":{"type":"string"}},"required":["project"]}}},

    { "type":"function","function":{ "name":"accessibility_audit","description":"Check HTML for WCAG accessibility issues.","parameters":{"type":"object","properties":{"project":{"type":"string"},"file_path":{"type":"string"}},"required":["project","file_path"]}}},
    { "type":"function","function":{ "name":"hash_file","description":"Compute MD5/SHA256 hash of a file.","parameters":{"type":"object","properties":{"project":{"type":"string"},"file_path":{"type":"string"},"algo":{"type":"string","enum":["md5","sha256"]}},"required":["project","file_path"]}}},
    { "type":"function","function":{ "name":"archive_create","description":"Create zip/tar.gz archive.","parameters":{"type":"object","properties":{"project":{"type":"string"},"source":{"type":"string"},"format":{"type":"string","enum":["zip","tar.gz"]}},"required":["project","source","format"]}}},
    { "type":"function","function":{ "name":"archive_extract","description":"Extract zip/tar.gz archive.","parameters":{"type":"object","properties":{"project":{"type":"string"},"file_path":{"type":"string"}},"required":["project","file_path"]}}},

    { "type":"function","function":{ "name":"dns_lookup","description":"Look up DNS records (A, MX, NS, TXT, ALL).","parameters":{"type":"object","properties":{"domain":{"type":"string"},"type":{"type":"string"}},"required":["domain"]}}},
    { "type":"function","function":{ "name":"port_check","description":"Check if a TCP port is open.","parameters":{"type":"object","properties":{"host":{"type":"string"},"port":{"type":"integer"}},"required":["host","port"]}}},
    { "type":"function","function":{ "name":"jwt_decode","description":"Decode a JWT token header+payload (never shows signature).","parameters":{"type":"object","properties":{"token":{"type":"string"}},"required":["token"]}}},
    { "type":"function","function":{ "name":"base64_tool","description":"Encode or decode base64.","parameters":{"type":"object","properties":{"action":{"type":"string","enum":["encode","decode"]},"text":{"type":"string"}},"required":["action","text"]}}},
    { "type":"function","function":{ "name":"markdown_toc","description":"Generate table of contents for Markdown.","parameters":{"type":"object","properties":{"project":{"type":"string"},"file_path":{"type":"string"}},"required":["project","file_path"]}}},
    { "type":"function","function":{ "name":"regex_test","description":"Test a regex pattern against sample text.","parameters":{"type":"object","properties":{"pattern":{"type":"string"},"text":{"type":"string"}},"required":["pattern","text"]}}},
    { "type":"function","function":{ "name":"color_palette","description":"Generate color palette from base hex color.","parameters":{"type":"object","properties":{"base_color":{"type":"string"}},"required":["base_color"]}}},
    { "type":"function","function":{ "name":"date_convert","description":"Convert date/time between timezones.","parameters":{"type":"object","properties":{"date":{"type":"string"},"from_tz":{"type":"string"},"to_tz":{"type":"string"}},"required":["date","from_tz","to_tz"]}}},
    { "type":"function","function":{ "name":"uuid_gen","description":"Generate UUID v4 or v7.","parameters":{"type":"object","properties":{"version":{"type":"string","enum":["v4","v7"]},"count":{"type":"integer"}},"required":["version"]}}},
    { "type":"function","function":{ "name":"i18n_find","description":"Find hardcoded strings that need internationalization.","parameters":{"type":"object","properties":{"project":{"type":"string"},"file_path":{"type":"string"}},"required":["project","file_path"]}}},
    { "type":"function","function":{ "name":"git_hook_gen","description":"Generate a git hook script.","parameters":{"type":"object","properties":{"hook":{"type":"string","enum":["pre-commit","commit-msg","pre-push"]},"content":{"type":"string"}},"required":["hook","content"]}}},
    { "type":"function","function":{ "name":"ssl_cert","description":"Generate self-signed SSL certificate command.","parameters":{"type":"object","properties":{"domain":{"type":"string"},"days":{"type":"integer"}},"required":["domain"]}}},

    { "type":"function","function":{ "name":"git_tag","description":"Create or list git tags.","parameters":{"type":"object","properties":{"project":{"type":"string"},"action":{"type":"string","enum":["create","list"]},"name":{"type":"string"}},"required":["project","action"]}}},
    { "type":"function","function":{ "name":"git_cherry_pick","description":"Cherry-pick a commit by hash.","parameters":{"type":"object","properties":{"project":{"type":"string"},"hash":{"type":"string"}},"required":["project","hash"]}}},
    { "type":"function","function":{ "name":"git_revert","description":"Revert a commit by hash.","parameters":{"type":"object","properties":{"project":{"type":"string"},"hash":{"type":"string"}},"required":["project","hash"]}}},
    { "type":"function","function":{ "name":"git_squash","description":"Squash last N commits into one.","parameters":{"type":"object","properties":{"project":{"type":"string"},"count":{"type":"integer"}},"required":["project","count"]}}},

    { "type":"function","function":{ "name":"generate_makefile","description":"Generate Makefile with common targets.","parameters":{"type":"object","properties":{"project":{"type":"string"},"targets":{"type":"string"}},"required":["project"]}}},
    { "type":"function","function":{ "name":"generate_dockerfile","description":"Generate Dockerfile for Node/Python/Go/Rust.","parameters":{"type":"object","properties":{"lang":{"type":"string"},"port":{"type":"integer"}},"required":["lang"]}}},
    { "type":"function","function":{ "name":"generate_nginx_config","description":"Generate nginx config for SPA/API/static.","parameters":{"type":"object","properties":{"type":{"type":"string","enum":["spa","api","static"]},"domain":{"type":"string"},"port":{"type":"integer"}},"required":["type","domain"]}}},
    { "type":"function","function":{ "name":"generate_pm2_config","description":"Generate PM2 ecosystem config.","parameters":{"type":"object","properties":{"name":{"type":"string"},"script":{"type":"string"}},"required":["name","script"]}}},
    { "type":"function","function":{ "name":"generate_systemd","description":"Generate systemd service file.","parameters":{"type":"object","properties":{"name":{"type":"string"},"command":{"type":"string"}},"required":["name","command"]}}},
    { "type":"function","function":{ "name":"generate_editorconfig","description":"Generate .editorconfig file.","parameters":{"type":"object","properties":{"project":{"type":"string"}},"required":["project"]}}},
    { "type":"function","function":{ "name":"generate_gitattributes","description":"Generate .gitattributes with LF/CRLF rules.","parameters":{"type":"object","properties":{"project":{"type":"string"}},"required":["project"]}}},
    { "type":"function","function":{ "name":"mermaid_render","description":"Render Mermaid diagram to SVG/PNG.","parameters":{"type":"object","properties":{"diagram":{"type":"string"},"format":{"type":"string","enum":["svg","png"]}},"required":["diagram"]}}},
    { "type":"function","function":{ "name":"plantuml_render","description":"Render PlantUML diagram.","parameters":{"type":"object","properties":{"diagram":{"type":"string"}},"required":["diagram"]}}},
    { "type":"function","function":{ "name":"ascii_tree","description":"Generate ASCII directory tree.","parameters":{"type":"object","properties":{"project":{"type":"string"},"max_depth":{"type":"integer"}},"required":["project"]}}},
    { "type":"function","function":{ "name":"generate_badges","description":"Generate shields.io badges for README.","parameters":{"type":"object","properties":{"project":{"type":"string"}},"required":["project"]}}},
    { "type":"function","function":{ "name":"generate_contributing","description":"Generate CONTRIBUTING.md file.","parameters":{"type":"object","properties":{"project":{"type":"string"}},"required":["project"]}}},
    { "type":"function","function":{ "name":"generate_codeowners","description":"Generate CODEOWNERS file.","parameters":{"type":"object","properties":{"owners":{"type":"string","description":"path @owner pairs"}},"required":["owners"]}}},
    { "type":"function","function":{ "name":"detect_language","description":"Auto-detect programming language of a file.","parameters":{"type":"object","properties":{"project":{"type":"string"},"file_path":{"type":"string"}},"required":["project","file_path"]}}},
    { "type":"function","function":{ "name":"token_count","description":"Estimate token count of text (for context budgeting).","parameters":{"type":"object","properties":{"text":{"type":"string"}},"required":["text"]}}},
    { "type":"function","function":{ "name":"url_shorten","description":"Create a short URL via tinyurl.","parameters":{"type":"object","properties":{"url":{"type":"string"}},"required":["url"]}}},
    { "type":"function","function":{ "name":"http_headers","description":"Show HTTP response headers for a URL.","parameters":{"type":"object","properties":{"url":{"type":"string"}},"required":["url"]}}},
    { "type":"function","function":{ "name":"whois_lookup","description":"WHOIS domain lookup.","parameters":{"type":"object","properties":{"domain":{"type":"string"}},"required":["domain"]}}},
    { "type":"function","function":{ "name":"ssl_check","description":"Check SSL certificate expiry for a domain.","parameters":{"type":"object","properties":{"domain":{"type":"string"}},"required":["domain"]}}},
    { "type":"function","function":{ "name":"generate_sitemap","description":"Generate sitemap.xml for a website.","parameters":{"type":"object","properties":{"urls":{"type":"string"},"base_url":{"type":"string"}},"required":["urls","base_url"]}}},
    { "type":"function","function":{ "name":"generate_robots","description":"Generate robots.txt file.","parameters":{"type":"object","properties":{"allow_all":{"type":"boolean"}},"required":[]}}},
    { "type":"function","function":{ "name":"generate_htaccess","description":"Generate .htaccess with common rules.","parameters":{"type":"object","properties":{"type":{"type":"string","enum":["spa","redirect","security"]}},"required":["type"]}}},
    { "type":"function","function":{ "name":"css_reset","description":"Generate CSS reset/normalize snippet.","parameters":{"type":"object","properties":{}},"required":[]}},
    { "type":"function","function":{ "name":"meta_tags","description":"Generate SEO meta tags for a page.","parameters":{"type":"object","properties":{"title":{"type":"string"},"description":{"type":"string"},"image":{"type":"string"}},"required":["title","description"]}}},
    { "type":"function","function":{ "name":"json_schema_gen","description":"Generate JSON Schema from JSON example.","parameters":{"type":"object","properties":{"example":{"type":"string"}},"required":["example"]}}},
    { "type":"function","function":{ "name":"swagger_gen","description":"Generate OpenAPI spec boilerplate.","parameters":{"type":"object","properties":{"title":{"type":"string"},"version":{"type":"string"}},"required":["title"]}}},
    { "type":"function","function":{ "name":"graphql_schema_gen","description":"Generate GraphQL schema boilerplate.","parameters":{"type":"object","properties":{"types":{"type":"string"}},"required":["types"]}}},
    { "type":"function","function":{ "name":"proto_gen","description":"Generate Protobuf .proto file boilerplate.","parameters":{"type":"object","properties":{"service":{"type":"string"},"messages":{"type":"string"}},"required":["service"]}}},
    { "type":"function","function":{ "name":"sql_migration_gen","description":"Generate SQL migration file (up + down).","parameters":{"type":"object","properties":{"table":{"type":"string"},"columns":{"type":"string"}},"required":["table","columns"]}}},
    { "type":"function","function":{ "name":"seed_data_gen","description":"Generate seed data SQL for testing.","parameters":{"type":"object","properties":{"table":{"type":"string"},"count":{"type":"integer"}},"required":["table","count"]}}},
    { "type":"function","function":{ "name":"index_suggestion","description":"Suggest database indexes based on query patterns.","parameters":{"type":"object","properties":{"queries":{"type":"string"}},"required":["queries"]}}},
    { "type":"function","function":{ "name":"naming_convention","description":"Suggest naming convention for a project.","parameters":{"type":"object","properties":{"project":{"type":"string"}},"required":["project"]}}},
    { "type":"function","function":{ "name":"code_stats","description":"Code statistics: files, lines, commits, contributors.","parameters":{"type":"object","properties":{"project":{"type":"string"}},"required":["project"]}}},
    { "type":"function","function":{ "name":"complexity_report","description":"Cyclomatic complexity report for project.","parameters":{"type":"object","properties":{"project":{"type":"string"}},"required":["project"]}}},
    { "type":"function","function":{ "name":"test_coverage","description":"Check test coverage (if coverage report exists).","parameters":{"type":"object","properties":{"project":{"type":"string"}},"required":["project"]}}},
    { "type":"function","function":{ "name":"compare_branches","description":"Compare two branches — show diff summary.","parameters":{"type":"object","properties":{"project":{"type":"string"},"base":{"type":"string"},"head":{"type":"string"}},"required":["project","base","head"]}}},
    { "type":"function","function":{ "name":"generate_changelog","description":"Generate CHANGELOG.md from git history.","parameters":{"type":"object","properties":{"project":{"type":"string"}},"required":["project"]}}},
    { "type":"function","function":{ "name":"generate_release_notes","description":"Generate GitHub release notes from commits.","parameters":{"type":"object","properties":{"project":{"type":"string"},"from_tag":{"type":"string"}},"required":["project"]}}},
    { "type":"function","function":{ "name":"word_count","description":"Count words/characters in text.","parameters":{"type":"object","properties":{"text":{"type":"string"}},"required":["text"]}}},
    { "type":"function","function":{ "name":"diff_two_files","description":"Show unified diff between two files.","parameters":{"type":"object","properties":{"project":{"type":"string"},"file1":{"type":"string"},"file2":{"type":"string"}},"required":["project","file1","file2"]}}},
    { "type":"function","function":{ "name":"search_github_trending","description":"Search GitHub trending repos by language.","parameters":{"type":"object","properties":{"language":{"type":"string"}},"required":["language"]}}},
    { "type":"function","function":{ "name":"npm_downloads","description":"Check npm package weekly downloads.","parameters":{"type":"object","properties":{"package":{"type":"string"}},"required":["package"]}}},
    { "type":"function","function":{ "name":"bundle_phobia","description":"Check npm package bundle size impact.","parameters":{"type":"object","properties":{"package":{"type":"string"}},"required":["package"]}}},
    { "type":"function","function":{ "name":"run_task","description":"Run a pre-built task from the 100+ task library (daily/weekly/deploy/maintain/ideas).","parameters":{"type":"object","properties":{"task_id":{"type":"string","description":"Task ID from library"}},"required":["task_id"]}}},
    { "type":"function","function":{ "name":"list_tasks","description":"List all available pre-built tasks in the library. Filter by category: daily, weekly, precommit, deploy, maintain, ideas, all.","parameters":{"type":"object","properties":{"category":{"type":"string","enum":["daily","weekly","precommit","deploy","maintain","ideas","all"]}},"required":[]}}},
  ];

  Future<void> setMode(AgentMode mode) async {
    currentMode = mode;
    await reset();
  }

  AgentMode _detectMode(String userMessage) {
    final lower = userMessage.toLowerCase();

    if (lower.contains("research") ||
        lower.contains("what is") ||
        lower.contains("compare") ||
        lower.contains("latest") ||
        lower.contains("best practice") ||
        lower.contains("explain ") &&
            !lower.contains("code")) {
      return AgentMode.research;
    }
    if (lower.contains("how ") &&
        (lower.contains("design") ||
            lower.contains("architecture") ||
            lower.contains("structure") ||
            lower.contains("plan"))) {
      return AgentMode.architect;
    }
    if (lower.contains(" how ") ||
        lower.contains("what if") ||
        lower.contains("brainstorm") ||
        lower.contains("ideas") ||
        lower.contains("suggest") ||
        lower.contains("options")) {
      if (!lower.contains("write") &&
          !lower.contains("add") &&
          !lower.contains("create") &&
          !lower.contains("implement")) {
        return AgentMode.brainstorm;
      }
    }
    if (lower.contains("fix") ||
        lower.contains("bug") ||
        lower.contains("broken") ||
        lower.contains("error") ||
        lower.contains("wrong") ||
        lower.contains("debug") ||
        lower.contains("trace")) {
      return AgentMode.debug;
    }
    if (lower.contains("refactor") ||
        lower.contains("clean") ||
        lower.contains("restructure") ||
        lower.contains("extract") ||
        lower.contains("simplify")) {
      return AgentMode.refactor;
    }
    return AgentMode.code;
  }

  Future<void> _runBackground(String agentType, String task) async {
    try {
      final result = await SubAgentService.delegate(agentType, task);
      await BgService.show("Background task completed",
          "[$agentType] ${result.substring(0, result.length > 200 ? 200 : result.length)}");
    } catch (e) {
      await BgService.show("Background task failed",
          "[$agentType] $e");
    }
  }

  Future<String> _executeTool(
      String name, Map<String, dynamic> args) async {
    try {
      switch (name) {
        case "read_file":
          return await StorageService.readFile(
              args["project"], args["path"]);
        case "write_file":
          await SnapshotService.init();
          await SnapshotService.snapshot(
              args["project"], args["path"]);
          await StorageService.writeFile(
              args["project"], args["path"], args["content"]);
          return "File written: ${args["path"]}";
        case "list_files":
          final entries = await StorageService.listDir(
              args["project"], args["path"] ?? "");
          if (entries.isEmpty) return "(empty)";
          return entries
              .map((e) {
                final name = e.uri.pathSegments.last;
                final isDir = e is Directory;
                return isDir ? "[DIR]  $name/" : "       $name";
              })
              .join("\n");
        case "delete_file":
          await SnapshotService.snapshot(
              args["project"], args["path"]);
          await StorageService.deleteFile(
              args["project"], args["path"]);
          return "Deleted: ${args["path"]}";
        case "search_code":
          final results = await StorageService.searchCode(
            args["project"],
            args["pattern"],
            args["fileExt"],
          );
          return results.isEmpty
              ? "No matches"
              : results.join("\n");
        case "git_sync":
          return await GitService.commitAndPush(
              args["project"] ?? projectName,
              args["message"] ?? "Update");
        case "git_status":
          return await GitService.getStatus(
              args["project"] ?? projectName);
        case "web_search":
          final results = await ResearchService.search(
              args["query"],
              maxResults: args["max_results"] ?? 5);
          if (results.isEmpty) return "No results found";
          return results
              .map((r) =>
                  "${r.title}\n  ${r.snippet}\n  ${r.url}")
              .join("\n\n");
        case "web_fetch":
          return await ResearchService.fetchUrl(args["url"]);
        case "impact_analysis":
          final impact = await CodeIntelligence.analyzeImpact(
              args["project"], args["file_path"]);
          return "Risk: ${impact.riskLevel}\n"
              "Direct dependents (${impact.directDependents.length}):\n"
              "${impact.directDependents.map((d) => "  - $d").join("\n")}\n"
              "Transitive dependents (${impact.transitiveDependents.length}):\n"
              "${impact.transitiveDependents.map((d) => "  - $d").join("\n")}";
        case "run_command":
          return await _runShellCommand(
              args["project"],
              args["command"],
              args["cwd"]);
        case "glob_files":
          return await _globSearch(
              args["project"], args["pattern"]);
        case "edit_file":
          return await _editFile(
              args["project"],
              args["path"],
              args["old_string"],
              args["new_string"]);
        case "create_tasks":
          final tasks = (args["tasks"] as List?) ?? [];
          final buf = StringBuffer();
          buf.writeln("## Task List\n");
          for (final t in tasks) {
            final icon = switch (t["status"]) {
              "completed" => "✅",
              "in_progress" => "🔄",
              "cancelled" => "❌",
              _ => "⏳",
            };
            buf.writeln(
                "$icon [${t["priority"]}] ${t["content"]}");
            buf.writeln();
          }
          return buf.toString();
        case "ask_user":
          final q = args["question"] as String;
          final opts = args["options"] as List?;
          if (onQuestion != null) {
            return await onQuestion!(q, opts?.cast<String>());
          }
          if (opts != null && opts.isNotEmpty) {
            return "❓ $q\n\nOptions: ${opts.join(", ")}";
          }
          return "❓ $q";
        case "todowrite":
          final project = args["project"] as String;
          final tasks = args["tasks"] as List? ?? [];
          await StorageService.writeFile(project, ".opencode/todos.json", jsonEncode(tasks));
          return "Saved ${tasks.length} tasks to todo list. Use todolist to read them back.";
        case "todolist":
          final p = args["project"] as String;
          try {
            final json = jsonDecode(await StorageService.readFile(p, ".opencode/todos.json"));
            if (json is! List || json.isEmpty) return "No tasks in todo list.";
            final buf = StringBuffer("## Todo List\n");
            for (final t in json) {
              if (t is! Map) continue;
              final icon = switch (t["status"] as String?) {
                "completed" => "✅", "in_progress" => "🔄", "cancelled" => "❌", _ => "⏳",
              };
              buf.writeln("$icon [${t["priority"]}] ${t["content"]}");
            }
            return buf.toString();
          } catch (e) {
            return "No todo list found. Use todowrite to create one.";
          }
        // GitHub tools
        case "github_list_issues":
          return await GitHubService.listIssues(
              args["owner"], args["repo"],
              state: args["state"] ?? "open",
              label: args["label"]);
        case "github_create_issue":
          return await GitHubService.createIssue(
              args["owner"], args["repo"],
              args["title"], args["body"],
              labels: args["labels"]?.cast<String>());
        case "github_list_prs":
          return await GitHubService.listPRs(
              args["owner"], args["repo"],
              state: args["state"] ?? "open");
        case "github_get_pr":
          return await GitHubService.getPR(
              args["owner"], args["repo"], args["number"]);
        case "github_search_code":
          return await GitHubService.searchCode(
              args["query"]);
        case "github_get_file":
          return await GitHubService.getFileContent(
              args["owner"], args["repo"], args["path"],
              ref: args["ref"] ?? "main");
        case "github_get_repo":
          return await GitHubService.getRepo(
              args["owner"], args["repo"]);
        // Browser tools
        case "browser_open":
          return await BrowserService.openPage(args["url"]);
        case "browser_extract":
          return await BrowserService.extractData(
              args["url"], args["pattern"]);
        case "browser_follow":
          return await BrowserService.followLink(
              args["url"], args["link_text"]);
        // SQL tools
        case "sql_detect":
          return await SqlService.detectDatabases(
              args["project"]);
        case "sql_query":
          return await SqlService.runQuery(args["project"],
              args["db_file"], args["query"]);
        case "sql_schema":
          return await SqlService.showSchema(
              args["project"], args["db_file"]);
        // Code quality
        case "find_patterns":
          final matches =
              await CodeIntelligence.findSimilarPatterns(
                  args["project"], args["pattern"]);
          if (matches.isEmpty) return "No matches found";
          return matches
              .map((m) => "${m.file}:${m.line}\n  ${m.snippet}")
              .join("\n\n");
        case "suggest_tests":
          return await _suggestTests(
              args["project"], args["file_path"]);
        // LSP tools
        case "diagnose_file":
          return await LspService.diagnoseFile(
              args["project"], args["file_path"]);
        case "analyze_project":
          return await LspService.analyzeProject(
              args["project"]);
        case "check_imports":
          return await LspService.checkImports(
              args["project"], args["file_path"]);
        // Multi-agent
        case "delegate_task":
          final result = await SubAgentService.delegate(
              args["agent_type"], args["task"]);
          unawaited(BgService.show(
              "Sub-agent complete",
              "[${args["agent_type"]}] ${args["task"]?.toString().substring(0, 80)}"));
          return result;
        case "run_background":
          // Non-blocking background task with notification
          final bgType = args["agent_type"] as String? ?? "scribe";
          final bgTask = args["task"] as String? ?? "";
          unawaited(_runBackground(bgType, bgTask));
          return "Started background task [$bgType]. You'll be notified when it completes.";
        case "snapshot_undo":
          return await SnapshotService.undo(
              args["project"], args["file_path"]);
        case "snapshot_undo_all":
          return await SnapshotService.undoAll(
              args["project"]);
        case "format_code":
          return await FormatterService.format(
              args["project"] ?? projectName,
              args["file_path"]);
        case "batch_execute":
          return await _batchExecute((args["calls"] as List?) ?? []);
        case "mcp_call":
          return await McpClient.quickCall(
              url: args["url"],
              tool: args["tool"],
              args: Map<String, dynamic>.from(
                  args["args"] ?? {}));
        case "diff_preview":
          return await DiffService.previewEdit(
              args["project"], args["file_path"],
              args["old_string"], args["new_string"]);
        case "create_plan":
          return ExecutionPlanService.createPlan(
              args["task"], {});
        case "self_review":
          return await _selfReview(args["project"] ?? projectName);
        case "project_summary":
          return await ProjectOnboarding.summarize(
              args["project"]);
        case "security_scan":
          return await SecurityScanService.scanProject(
              args["project"]);
        case "api_test":
          if (args["method"] == "POST") {
            return await ApiTester.post(
                args["url"], args["body"] ?? "{}",
                headers: args["headers"]?.cast<String, String>());
          }
          return await ApiTester.get(args["url"],
              headers: args["headers"]?.cast<String, String>());
        case "debate":
          return await DebateService.debate(
              args["topic"], args["agent1"], args["agent2"]);
        case "create_pr":
          return await GitHubService.createPR(
              args["owner"], args["repo"],
              args["title"], args["body"],
              head: args["head"] ?? "master",
              base: args["base"] ?? "main");
        case "run_code":
          return await CodeSandbox.run(
              args["project"] ?? projectName,
              args["code"],
              language: args["language"] ?? "dart");
        case "check_deps":
          return await _checkDeps(args["project"]);
        case "analyze_function":
          return await InteractiveDebugger.analyzeFunction(
              args["project"], args["file_path"],
              args["function_name"]);
        case "detect_conflicts":
          return await _detectConflicts(args["project"] ?? projectName);
        case "profile_performance":
          if (args["file_path"] != null) {
            return await PerformanceProfiler.analyzeFile(
                args["project"], args["file_path"]);
          }
          return await PerformanceProfiler.profileProject(
              args["project"]);
        case "daily_standup":
          return await _dailyStandup(args["project"] ?? projectName);
        case "cron_schedule":
          final when = DateTime.tryParse(args["when"]) ?? DateTime.now().add(const Duration(hours: 1));
          return await CronScheduler.schedule(args["project"], args["task"], when);
        case "cron_list":
          return await CronScheduler.list(args["project"]);
        case "cron_cancel":
          return await CronScheduler.cancel(args["project"], args["task"]);
        case "git_branch":
          return await _gitBranchCmd(args["project"], args["action"], args["name"] ?? "");
        case "count_lines":
          return await _countLines(args["project"]);
        case "find_duplicates":
          return await _findDupes(args["project"]);
        case "search_stackoverflow":
          final so = await ResearchService.search("site:stackoverflow.com ${args["query"]}");
          return so.map((s) => "${s.title}\n  ${s.snippet}\n  ${s.url}").join("\n\n");
        case "search_npm":
          return await _searchNpm(args["query"]);
        case "search_pypi":
          return await _searchPypi(args["query"]);
        case "generate_diagram":
          return _genDiagram(args["type"], args["description"]);
        case "minify_code":
          return await _minifyCode(args["project"], args["file_path"]);
        case "validate_config":
          return await _validateConfig(args["project"], args["file_path"]);
        case "convert_format":
          return _convertFormat(args["content"], args["from"], args["to"]);
        case "generate_license":
          return _genLicense(args["type"], args["author"]);
        case "generate_env_example":
          return await _genEnvExample(args["project"]);
        case "git_blame":
          return await _gitBlame(args["project"], args["file_path"]);
        case "check_bundle_size":
          return await _checkBundleSize(args["project"]);
        case "search_docs":
          final docs = await ResearchService.search("${args["tech"]} documentation ${args["query"]}");
          return docs.map((s) => "${s.title}\n  ${s.snippet}\n  ${s.url}").join("\n\n");
        case "generate_qr":
          return _generateQr(args["data"]);
        case "generate_mock":
          return _genMock(args["type"], args["count"] ?? 10);
        case "validate_openapi":
          return await _validateOpenApi(args["project"], args["file_path"]);
        case "semver_bump":
          return await _semverBump(args["project"], args["level"]);
        case "dead_code":
          return await _deadCode(args["project"]);
        case "circular_deps":
          return await _findCircular(args["project"]);

        case "accessibility_audit":
          return await _wcagCheck(args["project"], args["file_path"]);
        case "hash_file":
          return await _hashFile(args["project"], args["file_path"], args["algo"] ?? "sha256");
        case "archive_create":
          return await _createArchive(args["project"], args["source"], args["format"]);
        case "archive_extract":
          return await _extractArchive(args["project"], args["file_path"]);

        case "dns_lookup":
          return await _dnsLookup(args["domain"], args["type"] ?? "A");
        case "port_check":
          return await _checkPort(args["host"], args["port"]);
        case "jwt_decode":
          return _jwtDecode(args["token"]);
        case "base64_tool":
          return _base64(args["action"], args["text"]);
        case "markdown_toc":
          return await _mdToc(args["project"], args["file_path"]);
        case "regex_test":
          return _regexTest(args["pattern"], args["text"]);
        case "color_palette":
          return _colorPalette(args["base_color"]);
        case "date_convert":
          return _dateConvert(args["date"], args["from_tz"], args["to_tz"]);
        case "uuid_gen":
          return _uuidGen(args["version"] ?? "v4", args["count"] ?? 1);
        case "i18n_find":
          return await _i18nFind(args["project"], args["file_path"]);
        case "git_hook_gen":
          return await _gitHookGen(args["project"], args["hook"], args["content"]);
        case "ssl_cert":
          return _sslCert(args["domain"], args["days"] ?? 365);
        // Deployment
        case "check_deploy_readiness":
          return await DeploymentService
              .checkDeployReadiness(args["project"]);
        case "generate_docker_compose":
          return DeploymentService.generateDockerCompose(
              args["stack"],
              Map<String, String>.from(
                  args["config"] ?? {}));
        case "generate_ci_config":
          return DeploymentService.generateCIConfig(
              args["platform"],
              nodeVersion: args["node_version"],
              pythonVersion: args["python_version"]);
        // Code generation
        case "generate_test_template":
          return await CodeGenerationService
              .generateTestTemplate(args["project"],
                  args["source_file"]);
        case "generate_boilerplate":
          return CodeGenerationService.generateBoilerplate(
              args["project_type"], args["name"]);
        case "suggest_optimizations":
          return CodeGenerationService
              .suggestOptimizations(args["code"]);
        // Project management
        case "estimate_effort":
          return DocumentationService.estimateEffort(
              args["description"]);
        case "generate_readme":
          return DocumentationService.generateReadmeTemplate(
              args["project_name"],
              args["description"],
              args["tech_stack"]);
        case "generate_api_docs":
          return await DocumentationService
              .generateApiDocs(args["project"],
                  args["source_file"]);
        case "bundle_phobia": return await _bundlePhobia(args["package"]);
        case "word_count": final w = (args["text"] as String?)?.split(RegExp(r'\s+')).length ?? 0; return "Words: $w";
        case "token_count": return _tokenCount(args["text"]);
        case "code_stats": return await _codeStats(args["project"]);
        case "complexity_report": return await _complexityReport(args["project"]);
        case "test_coverage": return await _testCoverage(args["project"]);
        case "compare_branches": return await _compareBranches(args["project"], args["base"], args["head"]);
        case "generate_changelog": return await _generateChangelog(args["project"] ?? projectName);
        case "generate_release_notes": return await _generateReleaseNotes(args["project"] ?? projectName);
        case "run_task": final e = AgentTaskLibrary.tasks[args["task_id"]]; return e != null ? e["desc"]! : "Unknown. Use list_tasks.";
        case "list_tasks":
          final cat = (args["category"] as String?) ?? "all";
          final tasks = AgentTaskLibrary.tasks.entries
              .where((e) => cat == "all" || e.key.startsWith(cat))
              .map((e) => "- ${e.key}: ${e.value["desc"]}")
              .join("\n");
          return tasks.isEmpty ? "No tasks found for category: $cat" : tasks;
        case "naming_convention": return await _namingConvention(args["project"]);
        case "index_suggestion": return "Index columns in WHERE/JOIN/ORDER BY. Use EXPLAIN ANALYZE on slow queries.";
        case "seed_data_gen": return _genMock("sql", args["count"] ?? 10);
        case "sql_migration_gen": return "-- Up\nCREATE TABLE ${args["table"]} (${args["columns"]});\n-- Down\nDROP TABLE ${args["table"]};";
        case "proto_gen": return _protoGen(args["service"], args["messages"] ?? "");
        case "graphql_schema_gen": return _graphQlSchemaGen(args["types"]);
        case "swagger_gen": return "openapi: 3.0.0\ninfo:\n  title: ${args["title"]}\n  version: ${args["version"] ?? "1.0.0"}";
        case "json_schema_gen": return await _jsonSchemaGen(args["example"]);
        case "meta_tags": return "<title>${args["title"]}</title>\n<meta name=\"description\" content=\"${args["description"]}\">";
        case "css_reset": return "*{margin:0;padding:0;box-sizing:border-box}";
        case "detect_language": return _detectLanguage(args["project"], args["file_path"]);
        case "ascii_tree": return await _asciiTree(args["project"], args["max_depth"] ?? 3);
        case "mermaid_render": return _mermaidRender(args["diagram"], args["format"] ?? "svg");
        case "plantuml_render": return _plantumlRender(args["diagram"]);
        case "generate_dockerfile": return _generateDockerfile(args["lang"] as String? ?? "node", args["port"] as int? ?? 3000);
        case "generate_nginx_config": return _generateNginxConfig(args["type"] as String? ?? "spa", args["domain"] as String? ?? "localhost", args["port"] as int? ?? 8080);
        case "generate_pm2_config": return _generatePm2Config(args["name"] as String? ?? "app", args["script"] as String? ?? "index.js");
        case "generate_systemd": return _generateSystemd(args["name"] as String? ?? "app", args["command"] as String? ?? "/usr/bin/app");
        case "generate_editorconfig": return _generateEditorconfig();
        case "generate_gitattributes": return _generateGitattributes();
        case "generate_contributing": return _generateContributing(args["project_name"] as String? ?? projectName);
        case "generate_codeowners": return _generateCodeowners(args["owners"] as String? ?? "");
        case "generate_badges": return _generateBadges(args["project_name"] as String? ?? projectName, args["description"] as String? ?? "");
        case "generate_sitemap": return _generateSitemap(args["base_url"] as String? ?? "https://example.com");
        case "generate_robots": return args["allow_all"] == true ? "User-agent: *\nAllow: /" : "User-agent: *\nDisallow: /";
        case "generate_htaccess": return args["type"] == "spa" ? "RewriteEngine On\nRewriteBase /\nRewriteRule ^index\\.html\$ - [L]\nRewriteCond %{REQUEST_FILENAME} !-f\nRewriteCond %{REQUEST_FILENAME} !-d\nRewriteRule . /index.html [L]" : "RewriteEngine On";
        case "generate_makefile": return await _generateMakefile(args["project"] ?? projectName, args["targets"] as String?);
        case "git_tag": return await _gitTag(args["project"], args["name"]);
        case "git_cherry_pick": return await _gitCherryPick(args["project"], args["hash"]);
        case "git_revert": return await _gitRevert(args["project"], args["hash"]);
        case "git_squash": return await _gitSquash(args["project"], args["count"]);
        case "url_shorten": return await _urlShorten(args["url"]);
        case "http_headers": return await _httpHeaders(args["url"]);
        case "whois_lookup": return await _whoisLookup(args["domain"]);
        case "ssl_check": return await _sslCheck(args["domain"]);
        case "search_github_trending": return await _searchGitHubTrending(args["language"]);
        case "npm_downloads": return await _npmDownloads(args["package"]);
        case "diff_two_files": try { final c1 = await StorageService.readFile(args["project"], args["file1"]); final c2 = await StorageService.readFile(args["project"], args["file2"]); return DiffService.unifiedDiff(c1, c2); } catch (e) { return "Diff failed: $e"; }
        default:
          return "Unknown tool: $name. Use list_tasks to see available tools.";
      }
    } catch (e) {
      return "Error: $e";
    }
  }

  Future<String> _runShellCommand(
      String project, String command,
      [String? cwd]) async {
    try {
      final shell = Platform.isAndroid ? "sh" : Platform.isWindows ? "cmd" : "sh";
      final arg = Platform.isWindows ? "/c" : "-c";
      final wd = cwd != null
          ? "${StorageService.projectsRoot.path}/$project/$cwd"
          : "${StorageService.projectsRoot.path}/$project";
      final result = await Process.run(shell, [arg, command],
          workingDirectory: wd, runInShell: true);
      final out = (result.stdout as String).trim();
      final err = (result.stderr as String).trim();
      if (out.isEmpty && err.isEmpty) {
        return "(completed, no output)";
      }
      if (err.isNotEmpty && out.isEmpty) {
        return err;
      }
      if (err.isNotEmpty) {
        return "$out\n$err";
      }
      return out;
    } catch (e) {
      return "Command failed: $e";
    }
  }

  Future<String> _globSearch(
      String project, String pattern) async {
    final results = <String>[];
    final regex = _globToRegex(pattern);

    Future<void> scanDir(String path) async {
      final entries =
          await StorageService.listDir(project, path);
      for (final entry in entries) {
        final name = entry.uri.pathSegments.last;
        final fullPath =
            path.isEmpty ? name : "$path/$name";
        if (name.startsWith(".") &&
            name != ".gitignore") continue;
        if (entry is Directory) {
          if (name != "node_modules" &&
              name != "dist" &&
              name != ".git") {
            await scanDir(fullPath);
          }
        } else {
          if (regex.hasMatch(fullPath)) {
            results.add(fullPath);
            if (results.length >= 50) return;
          }
        }
      }
    }

    await scanDir("");
    return results.isEmpty
        ? "No files matched $pattern"
        : results.join("\n");
  }

  static RegExp _globToRegex(String pattern) {
    var escaped = RegExp.escape(pattern);
    escaped = escaped.replaceAll(r'\*\*', '<<DEEP>>');
    escaped = escaped.replaceAll(r'\*', r'[^/]*');
    escaped = escaped.replaceAll('<<DEEP>>', '.*');
    return RegExp('^$escaped\$');
  }

  Future<String> _suggestTests(
      String project, String filePath) async {
    try {
      final content =
          await StorageService.readFile(project, filePath);
      final buf = StringBuffer();
      buf.writeln("## Test suggestions for $filePath\n");
      buf.writeln("Based on code analysis:\n");

      // Find function/method definitions
      final funcRegex = RegExp(
          r'(?:function|def|async\s+function|export\s+(?:async\s+)?function|const\s+\w+\s*=\s*(?:async\s*)?\(|static\s+(?:async\s*)?\w+\s*\()\s*(\w+)',
          multiLine: true);

      final funcs = funcRegex.allMatches(content).toList();
      if (funcs.isEmpty) {
        buf.writeln("No testable functions found.");
        return buf.toString();
      }

      for (final m in funcs.take(8)) {
        final name = m.group(1) ?? "unknown";
        buf.writeln("### $name");
        buf.writeln("- [ ] Test happy path with valid input");
        buf.writeln("- [ ] Test with null/undefined input");
        buf.writeln("- [ ] Test with empty/zero input");
        buf.writeln("- [ ] Test error handling path");
        buf.writeln();
      }

      buf.writeln(
          "Match the project's existing test framework and patterns.");
      return buf.toString();
    } catch (e) {
      return "Cannot analyze file: $e";
    }
  }

  Future<String> _batchExecute(
      List<dynamic> calls) async {
    final futures = calls.map((c) async {
      final tool = c["tool"] as String;
      final args =
          Map<String, dynamic>.from(c["args"] ?? {});
      final r = await _executeTool(tool, args);
      return "$tool: $r";
    });
    final results = await Future.wait(futures);
    return results.join("\n\n");
  }

  Future<String> _gitBranchCmd(String project, String action, String name) async {
    return await GitService.branch(project, action, name);
  }

  Future<String> _countLines(String project) async {
    final counts = <String, int>{};
    await _walk(project, "", (file, content) {
      final ext = file.split(".").last;
      counts[ext] = (counts[ext] ?? 0) + content.split("\n").length;
    });
    return counts.entries.map((e) => ".${e.key}: ${e.value} lines").join("\n");
  }

  Future<String> _findDupes(String project) async {
    final hashes = <int, List<String>>{};
    await _walk(project, "", (file, content) {
      if (content.length < 50) return;
      final h = content.substring(0, 100).hashCode;
      hashes.putIfAbsent(h, () => []).add(file);
    });
    final dupes = hashes.entries.where((e) => e.value.length > 1).take(5);
    if (dupes.isEmpty) return "No duplicate files found.";
    return dupes.map((e) => "Similar: ${e.value.join(", ")}").join("\n");
  }

  Future<String> _validateConfig(String project, String filePath) async {
    try {
      final content = await StorageService.readFile(project, filePath);
      final ext = filePath.split(".").last.toLowerCase();
      if (ext == "json") {
        try { jsonDecode(content); return "Valid JSON."; } catch (e) { return "Invalid JSON: $e"; }
      }
      if (ext == "yaml" || ext == "yml") {
        final lines = content.split("\n");
        for (var i = 0; i < lines.length; i++) {
          final line = lines[i];
          if (line.trimLeft().startsWith("#") || line.trim().isEmpty) continue;
          final indent = line.length - line.trimLeft().length;
          if (indent % 2 != 0 && line.trim().isNotEmpty) {
            return "Invalid YAML at line ${i + 1}: odd indentation ($indent spaces).";
          }
          final tabMatch = RegExp(r'^\t').firstMatch(line);
          if (tabMatch != null) {
            return "Invalid YAML at line ${i + 1}: tabs are not allowed, use spaces.";
          }
          final colonMatch = RegExp(r'^(\s*)(\S+)\s*:\s*(.*)').firstMatch(line);
          if (colonMatch != null) {
            final value = colonMatch.group(3) ?? "";
            if (value.contains("{") && !value.contains("}")) {
              return "Invalid YAML at line ${i + 1}: unclosed brace in inline mapping.";
            }
            if (value.contains("[") && !value.contains("]")) {
              return "Invalid YAML at line ${i + 1}: unclosed bracket in inline sequence.";
            }
          }
        }
        return "Valid YAML (basic syntax check passed).";
      }
      if (ext == "toml") {
        final lines = content.split("\n");
        for (var i = 0; i < lines.length; i++) {
          final line = lines[i].trim();
          if (line.isEmpty || line.startsWith("#")) continue;
          if (line.startsWith("[")) {
            final sectionMatch = RegExp(r'^\[(.+)\]$').firstMatch(line);
            if (sectionMatch == null && !line.startsWith("[[")) {
              return "Invalid TOML at line ${i + 1}: malformed section header.";
            }
          } else {
            final kvMatch = RegExp(r'^([\w.-]+)\s*=\s*(.+)$').firstMatch(line);
            if (kvMatch == null) {
              return "Invalid TOML at line ${i + 1}: expected key = value.";
            }
          }
        }
        return "Valid TOML (basic syntax check passed).";
      }
      return "Validation for .$ext not supported. Try JSON/YAML/TOML.";
    } catch (e) { return "Cannot read file: $e"; }
  }

  static String _genDiagram(String type, String desc) {
    switch (type) {
      case "architecture": return "```mermaid\ngraph TD\n  A[User] --> B[API]\n  B --> C[Database]\n  B --> D[Cache]\n  $desc\n```";
      case "flow": return "```mermaid\nflowchart LR\n  Start --> Process --> Decision{OK?}\n  Decision -->|yes| End\n  Decision -->|no| Process\n  $desc\n```";
      case "er": return "```mermaid\nerDiagram\n  USER ||--o{ ORDER : places\n  ORDER ||--|{ LINE_ITEM : contains\n  $desc\n```";
      case "sequence": return "```mermaid\nsequenceDiagram\n  Client->>Server: Request\n  Server->>DB: Query\n  DB-->>Server: Result\n  Server-->>Client: Response\n  $desc\n```";
      case "class": return "```mermaid\nclassDiagram\n  class Base {\n    +id: string\n    +createdAt: datetime\n  }\n  $desc\n```";
      default: return "```mermaid\ngraph TD\n  A --> B\n  $desc\n```";
    }
  }

  static String _genLicense(String type, String author) {
    final year = DateTime.now().year;
    if (type == "MIT") return "MIT License\n\nCopyright (c) $year $author\n\nPermission is hereby granted...";
    if (type == "Apache-2.0") return "Apache License 2.0\n\nCopyright $year $author\n\nLicensed under the Apache License...";
    return "GNU GPL v3.0\n\nCopyright (C) $year $author\n\nThis program is free software...";
  }

  Future<String> _genEnvExample(String project) async {
    final vars = <String>{};
    await _walk(project, "", (file, content) {
      for (final m in RegExp("process\\.env\\.(\\w+)|os\\.environ\\[[\"'](\\w+)[\"']]|getenv\\([\"'](\\w+)[\"']\\)|\\.env\\.(\\w+)|\\.getenv\\(\"(\\w+)\"").allMatches(content)) {
        vars.add(m.group(1) ?? m.group(2) ?? m.group(3) ?? m.group(4) ?? m.group(5) ?? "");
      }
    });
    if (vars.isEmpty) return "No environment variables found in project code.";
    return vars.map((v) => "$v=").join("\n");
  }

  Future<String> _gitBlame(String project, String filePath) async {
    try {
      return await _runShellCommand(project, 'git blame "$filePath"');
    } catch (e) { return "git blame failed: $e"; }
  }

  Future<String> _checkBundleSize(String project) async {
    var totalFiles = 0;
    var totalSize = 0;
    final largest = <Map<String, dynamic>>[];
    await _walk(project, "", (file, content) {
      totalFiles++;
      totalSize += content.length;
      largest.add({"file": file, "size": content.length});
    });
    largest.sort((a, b) => (b["size"] as int).compareTo(a["size"] as int));
    if (largest.length > 10) largest.removeRange(10, largest.length);
    final buf = StringBuffer();
    buf.writeln("Files: $totalFiles | Size: ${(totalSize/1024).toStringAsFixed(1)} KB");
    buf.writeln("Largest files:");
    for (final f in largest) buf.writeln("  ${f["file"]}: ${f["size"]} bytes");
    return buf.toString();
  }

  Future<void> _walk(String project, String path, void Function(String file, String content) cb) async {
    final entries = await StorageService.listDir(project, path);
    for (final e in entries) {
      final name = e.uri.pathSegments.last;
      final full = path.isEmpty ? name : "$path/$name";
      if (e is Directory) {
        if (name.startsWith(".") || name == "node_modules" || name == "dist") continue;
        await _walk(project, full, cb);
      } else {
        try {
          cb(full, await StorageService.readFile(project, full));
        } catch (e) {
          // Skip unreadable file
        }
      }
    }
  }

  static String _genMock(String type, int count) {
    final names = ["Alice","Bob","Charlie","Diana","Eve","Frank","Grace","Henry","Iris","Jack"];
    final domains = ["gmail.com","yahoo.com","example.com","test.org"];
    final buf = StringBuffer();
    for (var i=0; i<count && i<50; i++) {
      final name = names[i%names.length];
      final email = "${name.toLowerCase()}@${domains[i%domains.length]}";
      if (type == "json") buf.writeln('{"name":"$name","email":"$email","id":"${i+1}"}${i<count-1?",":""}');
      else if (type == "csv") buf.writeln('$name,$email');
      else buf.writeln("INSERT INTO users VALUES (${i+1},'$name','$email');");
    }
    return buf.toString();
  }

  Future<String> _semverBump(String project, String level) async {
    try {
      final content = await StorageService.readFile(project, "package.json");
      final pkg = jsonDecode(content);
      final ver = (pkg["version"] as String).split(".").map(int.parse).toList();
      if (level == "major") { ver[0]++; ver[1]=0; ver[2]=0; }
      else if (level == "minor") { ver[1]++; ver[2]=0; }
      else ver[2]++;
      final newVer = ver.join(".");
      pkg["version"] = newVer;
      await StorageService.writeFile(project, "package.json", const JsonEncoder.withIndent("  ").convert(pkg));
      return "Version bumped to $newVer";
    } catch (e) { return "Version bump failed: $e"; }
  }

  Future<String> _findCircular(String project) async {
    final graph = await CodeIntelligence.buildImportGraph(project);
    final visited = <String>{};
    final inStack = <String>{};
    final cycles = <String>[];
    void dfs(String node) { if (inStack.contains(node)) { cycles.add(node); return; } if (visited.contains(node)) return; visited.add(node); inStack.add(node); for (final n in graph[node]??[]) dfs(n); inStack.remove(node); }
    for (final node in graph.keys.take(50)) dfs(node);
    return cycles.isEmpty ? "No circular dependencies found." : "Circular deps: ${cycles.join(", ")}";
  }

  Future<String> _wcagCheck(String project, String filePath) async {
    try {
      final content = await StorageService.readFile(project, filePath);
      final issues = <String>[];
      final buf = StringBuffer("## WCAG Accessibility Audit: $filePath\n\n");

      // Check images without alt text
      final imgNoAlt = RegExp(r'<img(?![^>]*\balt\s*=)[^>]*>', caseSensitive: false);
      final imgNoAltMatches = imgNoAlt.allMatches(content).length;
      if (imgNoAltMatches > 0) issues.add("$imgNoAltMatches <img> tags missing alt attribute");

      // Check images with empty alt
      final imgEmptyAlt = RegExp(r'''<img[^>]*alt\s*=\s*["']\s*["'][^>]*>''', caseSensitive: false);
      final imgEmptyAltCount = imgEmptyAlt.allMatches(content).length;
      if (imgEmptyAltCount > 0) issues.add("$imgEmptyAltCount <img> tags with empty alt text (decorative images should have alt=\"\")");

      // Check empty links
      final emptyLinks = RegExp(r'<a[^>]*>\s*</a>', caseSensitive: false);
      final emptyLinkCount = emptyLinks.allMatches(content).length;
      if (emptyLinkCount > 0) issues.add("$emptyLinkCount empty <a> links with no text content");

      // Check links with only image children (no text fallback)
      final linksOnlyImg = RegExp(r'<a[^>]*>\s*<img[^>]*>\s*</a>', caseSensitive: false);
      final linksOnlyImgCount = linksOnlyImg.allMatches(content).length;

      // Check form inputs without labels
      final inputs = RegExp(r"""<input(?![^>]*\btype\s*=\s*["'](?:hidden|submit|button|image|reset)["'])[^>]*>""", caseSensitive: false);
      final labels = RegExp(r'<label[^>]*>', caseSensitive: false);
      final inputCount = inputs.allMatches(content).length;
      final labelCount = labels.allMatches(content).length;
      if (inputCount > labelCount) issues.add("${inputCount - labelCount} form inputs may be missing associated <label> elements");

      // Check heading hierarchy
      final headings = RegExp(r'<h([1-6])[^>]*>', caseSensitive: false).allMatches(content).toList();
      if (headings.isNotEmpty) {
        final levels = headings.map((m) => int.parse(m.group(1)!)).toList();
        final skipped = <String>[];
        for (var i = 1; i < levels.length; i++) {
          if (levels[i] > levels[i - 1] + 1) {
            skipped.add("h${levels[i - 1]} → h${levels[i]}");
          }
        }
        if (skipped.isNotEmpty) issues.add("Heading levels skipped (violates hierarchy): ${skipped.join(", ")}");
        if (levels.first > 1) issues.add("Page does not start with <h1> (starts with <h${levels.first}>)");
      }

      // Check for missing lang attribute on html tag
      final hasLang = RegExp(r'<html[^>]*\blang\s*=', caseSensitive: false).hasMatch(content);
      if (content.contains("<html") && !hasLang) issues.add("Missing lang attribute on <html> element");

      // Check buttons/links without accessible text
      final emptyButtons = RegExp(r'<button[^>]*>\s*</button>', caseSensitive: false);
      final emptyBtnCount = emptyButtons.allMatches(content).length;
      if (emptyBtnCount > 0) issues.add("$emptyBtnCount empty <button> elements with no text or aria-label");

      // Check for aria attributes usage
      final ariaLabels = RegExp(r'aria-label\s*=', caseSensitive: false).allMatches(content).length;
      final ariaDescribed = RegExp(r'aria-describedby\s*=', caseSensitive: false).allMatches(content).length;

      // Check for tables without headers
      final tables = RegExp(r'<table[^>]*>', caseSensitive: false).allMatches(content).length;
      final thElements = RegExp(r'<th[^>]*>', caseSensitive: false).allMatches(content).length;
      if (tables > 0 && thElements == 0) issues.add("$tables <table> elements without <th> header cells");

      // Check for inline color/size styles (potential contrast/resize issues)
      final inlineFont = RegExp(r'font-size\s*:\s*\d+px', caseSensitive: false).allMatches(content).length;
      if (inlineFont > 0) issues.add("$inlineFont inline font-size declarations (consider using relative units like rem/em)");

      // Check tabindex > 0 (anti-pattern)
      final badTabindex = RegExp(r"""tabindex\s*=\s*["']([2-9]|\d{2,})["']""", caseSensitive: false);
      final badTabindexCount = badTabindex.allMatches(content).length;
      if (badTabindexCount > 0) issues.add("$badTabindexCount elements with tabindex > 0 (avoid positive tabindex)");

      // Check for skip navigation links
      final hasSkipLink = RegExp(r'(?:skip|jump)[\s-]*(?:to[\s-]*)?(?:main|content|nav)', caseSensitive: false).hasMatch(content);
      final hasMain = RegExp(r'<main[^>]*>', caseSensitive: false).hasMatch(content);

      // Summary
      buf.writeln("### Elements Found");
      buf.writeln("- Images: ${RegExp(r'<img', caseSensitive: false).allMatches(content).length}");
      buf.writeln("- Links: ${RegExp(r'<a\s', caseSensitive: false).allMatches(content).length}");
      buf.writeln("- Form inputs: $inputCount");
      buf.writeln("- Buttons: ${RegExp(r'<button', caseSensitive: false).allMatches(content).length}");
      buf.writeln("- Tables: $tables");
      buf.writeln("- Headings: ${headings.length}");
      buf.writeln("- ARIA labels: $ariaLabels");
      buf.writeln("- ARIA describedby: $ariaDescribed");
      buf.writeln("");

      if (issues.isEmpty) {
        buf.writeln("### Result: No obvious WCAG issues detected.");
      } else {
        buf.writeln("### Issues Found (${issues.length}):\n");
        for (var i = 0; i < issues.length; i++) {
          buf.writeln("${i + 1}. ${issues[i]}");
        }
      }

      if (!hasSkipLink && hasMain) {
        buf.writeln("\n**Recommendation:** Add a skip-to-content link at the top of the page.");
      }

      return buf.toString();
    } catch (e) {
      return "Accessibility audit failed: $e";
    }
  }

  Future<String> _hashFile(String project, String filePath, String algo) async {
    try {
      final content = await StorageService.readFile(project, filePath);
      final bytes = utf8.encode(content);
      if (algo == "md5") return "MD5: ${_md5(bytes)}";
      return "SHA256: ${_sha256(bytes)}";
    } catch (e) { return "Hash failed: $e"; }
  }

  static String _md5(List<int> bytes) => crypto.md5.convert(bytes).toString();
  static String _sha256(List<int> bytes) => crypto.sha256.convert(bytes).toString();

  Future<String> _createArchive(String project, String source, String format) async {
    try {
      final projectRoot = StorageService.projectsRoot.path;
      final sourceDir = Directory("$projectRoot/$project/$source");
      if (!sourceDir.existsSync()) return "Source directory not found: $source";
      final archive = Archive();
      await for (final entity in sourceDir.list(recursive: true)) {
        if (entity is File) {
          final relPath = entity.path.substring(sourceDir.path.length + 1).replaceAll("\\", "/");
          final bytes = await entity.readAsBytes();
          archive.addFile(ArchiveFile(relPath, bytes.length, bytes));
        }
      }
      final outDir = Directory("$projectRoot/$project/.opencode");
      if (!outDir.existsSync()) outDir.createSync(recursive: true);
      if (format == "zip") {
        final zipBytes = ZipEncoder().encode(archive);
        if (zipBytes == null) return "Failed to encode zip archive.";
        final outFile = File("$projectRoot/$project/.opencode/archive.zip");
        await outFile.writeAsBytes(zipBytes);
        return "Created archive.zip (${archive.files.length} files, ${(zipBytes.length / 1024).toStringAsFixed(1)} KB)";
      } else {
        final gzBytes = GZipEncoder().encode(archive);
        if (gzBytes == null) return "Failed to encode tar.gz archive.";
        final tarBytes = TarEncoder().encode(archive);
        final gzResult = GZipEncoder().encode(tarBytes);
        if (gzResult == null) return "Failed to gzip tar archive.";
        final outFile = File("$projectRoot/$project/.opencode/archive.tar.gz");
        await outFile.writeAsBytes(gzResult);
        return "Created archive.tar.gz (${archive.files.length} files, ${(gzResult.length / 1024).toStringAsFixed(1)} KB)";
      }
    } catch (e) { return "Archive failed: $e"; }
  }

  Future<String> _extractArchive(String project, String filePath) async {
    try {
      final projectRoot = StorageService.projectsRoot.path;
      final archiveFile = File("$projectRoot/$project/$filePath");
      if (!archiveFile.existsSync()) return "Archive file not found: $filePath";
      final bytes = await archiveFile.readAsBytes();
      Archive archive;
      if (filePath.endsWith(".zip")) {
        archive = ZipDecoder().decodeBytes(bytes);
      } else {
        final gzBytes = GZipDecoder().decodeBytes(bytes);
        archive = TarDecoder().decodeBytes(gzBytes);
      }
      final extractDir = Directory("$projectRoot/$project/.opencode/extracted");
      if (!extractDir.existsSync()) extractDir.createSync(recursive: true);
      for (final file in archive) {
        if (file.isFile) {
          final outFile = File("${extractDir.path}/${file.name}");
          await outFile.parent.create(recursive: true);
          await outFile.writeAsBytes(file.content as List<int>);
        }
      }
      return "Extracted ${archive.files.length} files to .opencode/extracted/";
    } catch (e) { return "Extract failed: $e"; }
  }


  Future<String> _dnsLookup(String domain, String type) async {
    try {
      final buf = StringBuffer("DNS Lookup: $domain (type: $type)\n\n");
      final upperType = type.toUpperCase();
      if (upperType == "A" || upperType == "ALL") {
        final addresses = await InternetAddress.lookup(domain, type: InternetAddressType.IPv4);
        buf.writeln("A records:");
        for (final a in addresses) buf.writeln("  ${a.address}");
      }
      if (upperType == "AAAA" || upperType == "ALL") {
        final addresses = await InternetAddress.lookup(domain, type: InternetAddressType.IPv6);
        buf.writeln("AAAA records:");
        for (final a in addresses) buf.writeln("  ${a.address}");
      }
      if (upperType == "MX" || upperType == "NS" || upperType == "TXT") {
        final result = await Process.run("nslookup", ["-type=$upperType", domain], runInShell: true);
        buf.writeln("$upperType records:");
        buf.writeln((result.stdout as String).trim());
      }
      final output = buf.toString().trim();
      return output.isEmpty ? "No DNS records found for $domain" : output;
    } catch (e) { return "DNS lookup failed: $e"; }
  }

  Future<String> _checkPort(String host, int port) async {
    try {
      final s = await Socket.connect(host, port, timeout: const Duration(seconds: 5));
      s.destroy();
      return "Port $port is OPEN on $host";
    } catch (e) { return "Port $port is CLOSED on $host"; }
  }

  static String _jwtDecode(String token) {
    try {
      final parts = token.split(".");
      if (parts.length != 3) return "Invalid JWT format.";
      String decode(String b64) => utf8.decode(base64.decode(base64.normalize(b64)));
      return "Header:\n${decode(parts[0])}\n\nPayload:\n${decode(parts[1])}";
    } catch (e) { return "JWT decode failed: $e"; }
  }

  static String _base64(String action, String text) {
    try {
      if (action == "encode") return base64.encode(utf8.encode(text));
      return utf8.decode(base64.decode(text));
    } catch (e) { return "Base64 failed: $e"; }
  }

  Future<String> _mdToc(String project, String filePath) async {
    try {
      final content = await StorageService.readFile(project, filePath);
      final toc = StringBuffer();
      for (final line in content.split("\n")) {
        if (line.startsWith("##")) toc.writeln("  - ${line.replaceAll("#", "").trim()}");
        else if (line.startsWith("# ")) toc.writeln("- ${line.replaceAll("#", "").trim()}");
      }
      return toc.toString();
    } catch (e) { return "TOC failed: $e"; }
  }

  static String _regexTest(String pattern, String text) {
    try {
      final regex = RegExp(pattern, caseSensitive: false);
      final matches = regex.allMatches(text).map((m) => m.group(0) ?? "").toList();
      if (matches.isEmpty) return "No matches.";
      return matches.take(20).join("\n");
    } catch (e) { return "Regex error: $e"; }
  }

  static String _colorPalette(String base) {
    try {
      base = base.replaceAll("#", "");
      if (base.length != 6) return "Invalid color format. Use hex: #RRGGBB";
      final r = int.parse(base.substring(0, 2), radix: 16);
      final g = int.parse(base.substring(2, 4), radix: 16);
      final b = int.parse(base.substring(4, 6), radix: 16);
      final sb = StringBuffer();
      sb.writeln("#$base (base)");
      sb.writeln("#${_lerp(r, 255, 0.9).toInt().toRadixString(16).padLeft(2, "0")}${_lerp(g, 255, 0.9).toInt().toRadixString(16).padLeft(2, "0")}${_lerp(b, 255, 0.9).toInt().toRadixString(16).padLeft(2, "0")} (lighter)");
      sb.writeln("#${(_lerp(r, 0, 0.7)).toInt().toRadixString(16).padLeft(2, "0")}${(_lerp(g, 0, 0.7)).toInt().toRadixString(16).padLeft(2, "0")}${(_lerp(b, 0, 0.7)).toInt().toRadixString(16).padLeft(2, "0")} (darker)");
      sb.writeln("#${(_lerp(b, 0, 0.5)).toInt().toRadixString(16).padLeft(2, "0")}${(_lerp(r, 0, 0.5)).toInt().toRadixString(16).padLeft(2, "0")}${(_lerp(g, 0, 0.5)).toInt().toRadixString(16).padLeft(2, "0")} (complementary hue)");
      return sb.toString();
    } catch (e) { return "Invalid color format: $base. Use hex like #58A6FF."; }
  }

  static double _lerp(int a, int b, double t) => a + (b - a) * t;

  static String _dateConvert(String date, String from, String to) {
    try {
      final dt = DateTime.tryParse(date);
      if (dt == null) return "Cannot parse date: $date. Use ISO format like 2024-01-15T14:30:00Z.";
      final fromOffset = _tzOffsetHours(from);
      final toOffset = _tzOffsetHours(to);
      if (fromOffset == null) return "Unknown timezone: $from. Supported: UTC, EST, CST, MST, PST, CET, IST, JST, AEST, etc.";
      if (toOffset == null) return "Unknown timezone: $to. Supported: UTC, EST, CST, MST, PST, CET, IST, JST, AEST, etc.";
      final sourceUtc = dt.isUtc ? dt : dt.toUtc().add(Duration(hours: -fromOffset));
      final converted = sourceUtc.add(Duration(hours: toOffset));
      final fromLabel = from.toUpperCase();
      final toLabel = to.toUpperCase();
      return "Original: ${date} ($fromLabel)\nConverted: ${converted.toIso8601String()} ($toLabel)\nDifference: ${toOffset - fromOffset >= 0 ? '+' : ''}${toOffset - fromOffset}h";
    } catch (e) { return "Date conversion failed."; }
  }

  static int? _tzOffsetHours(String tz) {
    final map = {
      "UTC": 0, "GMT": 0,
      "EST": -5, "EDT": -4,
      "CST": -6, "CDT": -5,
      "MST": -7, "MDT": -6,
      "PST": -8, "PDT": -7,
      "CET": 1, "CEST": 2,
      "IST": 5.5,
      "JST": 9,
      "AEST": 10, "AEDT": 11,
      "NZST": 12, "NZDT": 13,
      "MSK": 3,
      "KST": 9,
      "SGT": 8,
      "HKT": 8,
      "CST_CN": 8,
    };
    return map[tz.toUpperCase()]?.toInt();
  }

  static String _uuidGen(String version, int count) {
    try {
      final rand = math.Random.secure();
      final sb = StringBuffer();
      final n = count is int && count > 0 ? count : 1;
      for (var i = 0; i < n; i++) {
        if (version == "v7") {
          final ts = DateTime.now().millisecondsSinceEpoch;
          final hex = ts.toRadixString(16).padLeft(12, "0");
          final rand1 = List.generate(8, (_) => rand.nextInt(16).toRadixString(16)).join();
          final rand2 = List.generate(8, (_) => rand.nextInt(16).toRadixString(16)).join();
          sb.writeln("$hex-${rand1.substring(0, 4)}-7${rand1.substring(4)}-${rand2.substring(0, 4)}-${rand2.substring(4)}");
        } else {
          final data = List.generate(16, (_) => rand.nextInt(256));
          data[6] = (data[6] & 0x0f) | 0x40;
          data[8] = (data[8] & 0x3f) | 0x80;
          final hex = data.map((b) => b.toRadixString(16).padLeft(2, "0")).join();
          sb.writeln("${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}");
        }
      }
      return sb.toString().trim();
    } catch (e) { return "UUID generation failed."; }
  }

  Future<String> _i18nFind(String project, String filePath) async {
    try {
      final content = await StorageService.readFile(project, filePath);
      final strings = RegExp(r'''['"]([A-Z][a-z]+(?:\s+[A-Z][a-z]+){1,})['"]''').allMatches(content).map((m) => m.group(1)).take(20).join("\n");
      return strings.isEmpty ? "No hardcoded UI strings found." : "Potentially un-i18n'd strings:\n$strings";
    } catch (e) { return "i18n check failed: $e"; }
  }

  Future<String> _gitHookGen(String project, String hook, String content) async {
    final path = ".git/hooks/$hook";
    await StorageService.writeFile(project, path, "#!/bin/sh\n$content");
    return "Hook created: $path. Run: chmod +x $path";
  }

  Future<String> _editFile(String project, String path,
      String oldStr, String newStr) async {
    try {
      final content =
          await StorageService.readFile(project, path);
      if (!content.contains(oldStr)) {
        return "Error: old_string not found in $path. Read the file first to get the exact text.";
      }
      int matchCount = 0;
      int idx = 0;
      while ((idx = content.indexOf(oldStr, idx)) != -1) {
        matchCount++;
        idx += oldStr.length;
      }
      if (matchCount > 1) {
        return "Found multiple matches ($matchCount occurrences). Provide more surrounding context in oldString to uniquely identify the target.";
      }
      final updated = content.replaceFirst(oldStr, newStr);
      await StorageService.writeFile(
          project, path, updated);
      return "Edited $path — 1 replacement made";
    } catch (e) {
      return "Edit failed: $e";
    }
  }

  Future<String> _gitTag(String project, String name) async {
    try {
      final createResult = await _runShellCommand(project, 'git tag "$name"');
      if (createResult.contains("failed") || createResult.contains("error") || createResult.contains("Error")) {
        return "Tag creation failed: $createResult";
      }
      final pushResult = await _runShellCommand(project, "git push --tags");
      return "Tag '$name' created successfully.\n$pushResult";
    } catch (e) { return "git tag failed: $e"; }
  }

  Future<String> _gitCherryPick(String project, String hash) async {
    try {
      return await _runShellCommand(project, 'git cherry-pick "$hash"');
    } catch (e) { return "git cherry-pick failed: $e"; }
  }

  Future<String> _gitRevert(String project, String hash) async {
    try {
      return await _runShellCommand(project, 'git revert "$hash" --no-edit');
    } catch (e) { return "git revert failed: $e"; }
  }

  Future<String> _gitSquash(String project, int count) async {
    try {
      final resetResult = await _runShellCommand(project, "git reset --soft HEAD~$count");
      if (resetResult.contains("failed") || resetResult.contains("error") || resetResult.contains("Error")) {
        return "Squash failed during reset: $resetResult";
      }
      final commitResult = await _runShellCommand(project, 'git commit --amend -m "Squashed $count commits"');
      return "Squashed $count commits.\n$commitResult";
    } catch (e) { return "git squash failed: $e"; }
  }

  Future<String> _compareBranches(String project, String base, String head) async {
    try {
      final statResult = await _runShellCommand(project, "git diff $base..$head --stat");
      final summaryResult = await _runShellCommand(project, "git diff $base..$head --shortstat");
      return "Branch comparison: $base..$head\n\nSummary:\n$summaryResult\n\nFiles changed:\n$statResult";
    } catch (e) { return "compare_branches failed: $e"; }
  }

  Future<String> _searchGitHubTrending(String language) async {
    try {
      final results = await ResearchService.search("trending repositories github $language ${DateTime.now().year}", maxResults: 5);
      if (results.isEmpty) return "No trending results found for '$language'.";
      final buf = StringBuffer("GitHub Trending Repositories ($language):\n\n");
      for (final r in results) {
        buf.writeln("${r.title}\n  ${r.snippet}\n  ${r.url}\n");
      }
      return buf.toString();
    } catch (e) { return "GitHub trending search failed: $e"; }
  }

  Future<String> _npmDownloads(String package) async {
    try {
      final url = "https://api.npmjs.org/downloads/point/last-month/$package";
      final response = await http.get(Uri.parse(url), headers: {"Accept": "application/json"}).timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) {
        return "npm API returned HTTP ${response.statusCode} for package '$package'.";
      }
      final data = jsonDecode(response.body);
      final downloads = data["downloads"] as int? ?? 0;
      final pretty = _formatNumber(downloads);
      return "npm downloads (last month) for '$package': $pretty (${downloads.toString()} raw)";
    } catch (e) { return "npm downloads lookup failed: $e"; }
  }

  String _formatNumber(int n) {
    if (n >= 1000000) return "${(n / 1000000).toStringAsFixed(1)}M";
    if (n >= 1000) return "${(n / 1000).toStringAsFixed(1)}K";
    return n.toString();
  }

  Future<String> _urlShorten(String url) async {
    try {
      final apiUri = "https://is.gd/create.php?format=simple&url=${Uri.encodeComponent(url)}";
      final response = await http.get(Uri.parse(apiUri), headers: {"User-Agent": "OpenCode-Mobile/1.0"}).timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        final short = response.body.trim();
        if (short.startsWith("http")) return "Shortened URL: $short";
        return "Shorten API returned: $short";
      }
      return "URL shortening failed: HTTP ${response.statusCode}";
    } catch (e) { return "URL shortening failed: $e"; }
  }

  Future<String> _httpHeaders(String url) async {
    try {
      final uri = Uri.parse(url.startsWith("http") ? url : "https://$url");
      final client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
      final request = await client.headUrl(uri);
      final response = await request.close().timeout(const Duration(seconds: 10));
      final buf = StringBuffer("HTTP ${response.statusCode} ${response.reasonPhrase}\n\nHeaders:\n");
      response.headers.forEach((name, values) {
        buf.writeln("$name: ${values.join(", ")}");
      });
      client.close(force: true);
      return buf.toString();
    } catch (e) { return "HTTP headers lookup failed: $e"; }
  }

  Future<String> _whoisLookup(String domain) async {
    try {
      final socket = await Socket.connect("whois.iana.org", 43, timeout: const Duration(seconds: 10));
      socket.write("$domain\r\n");
      final response = await socket.timeout(const Duration(seconds: 10)).fold<List<int>>([], (prev, chunk) => prev..addAll(chunk));
      socket.destroy();
      final text = utf8.decode(response, allowMalformed: true).trim();
      if (text.isEmpty) return "No WHOIS data returned for '$domain'.";
      final lines = text.split("\n").where((l) => l.trim().isNotEmpty).take(40).join("\n");
      return "WHOIS for $domain:\n\n$lines";
    } catch (e) { return "WHOIS lookup failed: $e"; }
  }

  Future<String> _sslCheck(String domain) async {
    try {
      final socket = await SecureSocket.connect(domain, 4343, timeout: const Duration(seconds: 10), onBadCertificate: (_) => true).catchError((_) async {
        return await SecureSocket.connect(domain, 443, timeout: const Duration(seconds: 10), onBadCertificate: (_) => true);
      });
      final cert = socket.peerCertificate;
      socket.destroy();
      if (cert == null) return "No SSL certificate returned for '$domain'.";
      final subject = cert.subject;
      final issuer = cert.issuer;
      final validFrom = cert.startValidity?.toIso8601String() ?? "unknown";
      final validTo = cert.endValidity?.toIso8601String() ?? "unknown";
      final isExpired = cert.endValidity != null && cert.endValidity!.isBefore(DateTime.now());
      final daysLeft = cert.endValidity != null ? cert.endValidity!.difference(DateTime.now()).inDays : -1;
      return "SSL Certificate for $domain:\n"
          "  Subject: $subject\n"
          "  Issuer: $issuer\n"
          "  Valid from: $validFrom\n"
          "  Valid to: $validTo\n"
          "  Expired: ${isExpired ? "YES" : "No"}\n"
          "  Days remaining: ${daysLeft >= 0 ? daysLeft : "N/A"}";
    } catch (e) { return "SSL check failed for '$domain': $e"; }
  }

  Future<String> _generateChangelog(String project) async {
    try {
      final log = await GitService.getLog(project, limit: 100);
      if (log.trim().isEmpty || log.startsWith("Error")) {
        return "No git history found. Initialize a git repo first.";
      }
      final buf = StringBuffer();
      final now = DateTime.now();
      buf.writeln("# Changelog");
      buf.writeln();
      buf.writeln("All notable changes to this project will be documented in this file.");
      buf.writeln();
      buf.writeln("## [Unreleased]");
      buf.writeln();
      final commits = log.split("\n").where((l) => l.trim().isNotEmpty).toList();
      final byType = <String, List<String>>{};
      for (final c in commits) {
        String type;
        String msg = c;
        if (c.startsWith("feat") || c.startsWith("feature")) {
          type = "Features";
          msg = c.replaceFirst(RegExp(r'^feat(?:ure)?[!(\s:]-?\s*'), "");
        } else if (c.startsWith("fix")) {
          type = "Bug Fixes";
          msg = c.replaceFirst(RegExp(r'^fix[!(\s:]-?\s*'), "");
        } else if (c.startsWith("refactor")) {
          type = "Refactoring";
          msg = c.replaceFirst(RegExp(r'^refactor[!(\s:]-?\s*'), "");
        } else if (c.startsWith("docs")) {
          type = "Documentation";
          msg = c.replaceFirst(RegExp(r'^docs[!(\s:]-?\s*'), "");
        } else if (c.startsWith("test")) {
          type = "Tests";
          msg = c.replaceFirst(RegExp(r'^test[!(\s:]-?\s*'), "");
        } else if (c.startsWith("chore")) {
          type = "Chores";
          msg = c.replaceFirst(RegExp(r'^chore[!(\s:]-?\s*'), "");
        } else if (c.startsWith("style")) {
          type = "Style";
          msg = c.replaceFirst(RegExp(r'^style[!(\s:]-?\s*'), "");
        } else if (c.startsWith("perf")) {
          type = "Performance";
          msg = c.replaceFirst(RegExp(r'^perf[!(\s:]-?\s*'), "");
        } else {
          type = "Other Changes";
        }
        byType.putIfAbsent(type, () => []).add("- ${msg.trim()}");
      }
      for (final entry in byType.entries) {
        buf.writeln("### ${entry.key}");
        buf.writeln();
        for (final item in entry.value) {
          buf.writeln(item);
        }
        buf.writeln();
      }
      if (byType.isEmpty) {
        for (final c in commits.take(20)) {
          buf.writeln("- $c");
        }
        buf.writeln();
      }
      buf.writeln("---");
      buf.writeln("*Generated on ${now.year}-${now.month.toString().padLeft(2, "0")}-${now.day.toString().padLeft(2, "0")}*");
      return buf.toString();
    } catch (e) {
      return "Changelog generation failed: $e";
    }
  }

  Future<String> _generateReleaseNotes(String project) async {
    try {
      final log = await GitService.getLog(project, limit: 50);
      if (log.trim().isEmpty || log.startsWith("Error")) {
        return "No git history found. Initialize a git repo first.";
      }
      final buf = StringBuffer();
      final now = DateTime.now();
      buf.writeln("# Release Notes");
      buf.writeln();
      buf.writeln("## ${now.year}.${now.month.toString().padLeft(2, "0")}.${now.day.toString().padLeft(2, "0")}");
      buf.writeln();
      buf.writeln("**Release Date:** ${now.toIso8601String().substring(0, 10)}");
      buf.writeln();
      final commits = log.split("\n").where((l) => l.trim().isNotEmpty).toList();
      final features = <String>[];
      final fixes = <String>[];
      final breaking = <String>[];
      final other = <String>[];
      for (final c in commits) {
        final lc = c.toLowerCase();
        if (lc.startsWith("feat")) {
          features.add("- ${c.replaceFirst(RegExp(r'^feat[!(\s:]-?\s*'), "")}");
        } else if (lc.startsWith("fix")) {
          fixes.add("- ${c.replaceFirst(RegExp(r'^fix[!(\s:]-?\s*'), "")}");
        } else if (lc.contains("breaking") || lc.startsWith("breaking")) {
          breaking.add("- ${c.replaceFirst(RegExp(r'^breaking[!(\s:]-?\s*'), "")}");
        } else {
          other.add("- $c");
        }
      }
      if (breaking.isNotEmpty) {
        buf.writeln("### Breaking Changes");
        buf.writeln();
        for (final b in breaking) { buf.writeln(b); }
        buf.writeln();
      }
      if (features.isNotEmpty) {
        buf.writeln("### New Features");
        buf.writeln();
        for (final f in features) { buf.writeln(f); }
        buf.writeln();
      }
      if (fixes.isNotEmpty) {
        buf.writeln("### Bug Fixes");
        buf.writeln();
        for (final f in fixes) { buf.writeln(f); }
        buf.writeln();
      }
      if (other.isNotEmpty) {
        buf.writeln("### Other Changes");
        buf.writeln();
        for (final o in other.take(15)) { buf.writeln(o); }
        buf.writeln();
      }
      if (features.isEmpty && fixes.isEmpty && breaking.isEmpty && other.isEmpty) {
        for (final c in commits.take(15)) {
          buf.writeln("- $c");
        }
        buf.writeln();
      }
      buf.writeln("---");
      buf.writeln("*To create a release, run:* `gh release create v${now.year}.${now.month.toString().padLeft(2, "0")}.${now.day.toString().padLeft(2, "0")} --title \"v${now.year}.${now.month.toString().padLeft(2, "0")}.${now.day.toString().padLeft(2, "0")}\" --notes-file RELEASE_NOTES.md*");
      return buf.toString();
    } catch (e) {
      return "Release notes generation failed: $e";
    }
  }

  String _generateDockerfile(String lang, int port) {
    final buf = StringBuffer();
    switch (lang.toLowerCase()) {
      case "node":
      case "nodejs":
      case "javascript":
        buf.writeln("FROM node:20-alpine AS builder");
        buf.writeln("WORKDIR /app");
        buf.writeln("COPY package*.json ./");
        buf.writeln("RUN npm ci --only=production");
        buf.writeln("COPY . .");
        buf.writeln("RUN npm run build 2>/dev/null || true");
        buf.writeln();
        buf.writeln("FROM node:20-alpine AS runtime");
        buf.writeln("RUN addgroup -g 1001 -S appgroup && adduser -S appuser -u 1001");
        buf.writeln("WORKDIR /app");
        buf.writeln("COPY --from=builder --chown=appuser:appgroup /app/node_modules ./node_modules");
        buf.writeln("COPY --from=builder --chown=appuser:appgroup /app .");
        buf.writeln("USER appuser");
        buf.writeln("EXPOSE $port");
        buf.writeln("ENV NODE_ENV=production");
        buf.writeln("HEALTHCHECK --interval=30s --timeout=3s CMD wget --no-verbose --tries=1 --spider http://localhost:$port/ || exit 1");
        buf.writeln("CMD [\"node\", \"index.js\"]");
        break;
      case "python":
      case "py":
        buf.writeln("FROM python:3.12-slim AS builder");
        buf.writeln("WORKDIR /app");
        buf.writeln("COPY requirements.txt .");
        buf.writeln("RUN pip install --no-cache-dir --prefix=/install -r requirements.txt");
        buf.writeln();
        buf.writeln("FROM python:3.12-slim AS runtime");
        buf.writeln("RUN groupadd -r appgroup && useradd -r -g appgroup appuser");
        buf.writeln("WORKDIR /app");
        buf.writeln("COPY --from=builder /install /usr/local");
        buf.writeln("COPY . .");
        buf.writeln("USER appuser");
        buf.writeln("EXPOSE $port");
        buf.writeln("ENV PYTHONUNBUFFERED=1");
        buf.writeln("HEALTHCHECK --interval=30s --timeout=3s CMD python -c \"import urllib.request; urllib.request.urlopen('http://localhost:$port/')\" || exit 1");
        buf.writeln("CMD [\"python\", \"-m\", \"uvicorn\", \"main:app\", \"--host\", \"0.0.0.0\", \"--port\", \"$port\"]");
        break;
      case "go":
      case "golang":
        buf.writeln("FROM golang:1.22-alpine AS builder");
        buf.writeln("WORKDIR /app");
        buf.writeln("COPY go.mod go.sum ./");
        buf.writeln("RUN go mod download");
        buf.writeln("COPY . .");
        buf.writeln("RUN CGO_ENABLED=0 GOOS=linux go build -ldflags=\"-s -w\" -o /app/server .");
        buf.writeln();
        buf.writeln("FROM gcr.io/distroless/static-debian12 AS runtime");
        buf.writeln("COPY --from=builder /app/server /server");
        buf.writeln("EXPOSE $port");
        buf.writeln("USER nonroot:nonroot");
        buf.writeln("ENTRYPOINT [\"/server\"]");
        break;
      case "rust":
      case "rs":
        buf.writeln("FROM rust:1.77-slim AS builder");
        buf.writeln("WORKDIR /app");
        buf.writeln("COPY Cargo.toml Cargo.lock ./");
        buf.writeln("RUN mkdir src && echo \"fn main() {}\" > src/main.rs && cargo build --release && rm -rf src");
        buf.writeln("COPY . .");
        buf.writeln("RUN touch src/main.rs && cargo build --release");
        buf.writeln();
        buf.writeln("FROM debian:bookworm-slim AS runtime");
        buf.writeln("RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates && rm -rf /var/lib/apt/lists/*");
        buf.writeln("RUN groupadd -r appgroup && useradd -r -g appgroup appuser");
        buf.writeln("COPY --from=builder /app/target/release/server /usr/local/bin/server");
        buf.writeln("USER appuser");
        buf.writeln("EXPOSE $port");
        buf.writeln("HEALTHCHECK --interval=30s --timeout=3s CMD curl -f http://localhost:$port/ || exit 1");
        buf.writeln("ENTRYPOINT [\"server\"]");
        break;
      default:
        buf.writeln("FROM alpine:3.19");
        buf.writeln("WORKDIR /app");
        buf.writeln("COPY . .");
        buf.writeln("EXPOSE $port");
        buf.writeln("CMD [\"echo\", \"Configure base image for $lang\"]");
        break;
    }
    buf.writeln();
    buf.writeln("# Build: docker build -t ${lang}_app .");
    buf.writeln("# Run:   docker run -p $port:$port ${lang}_app");
    return buf.toString().trim();
  }

  String _generateNginxConfig(String type, String domain, int port) {
    final buf = StringBuffer();
    buf.writeln("server {");
    buf.writeln("    listen 80;");
    buf.writeln("    server_name $domain;");
    buf.writeln();
    switch (type.toLowerCase()) {
      case "spa":
      case "single_page":
      case "react":
      case "vue":
      case "angular":
        buf.writeln("    root /var/www/$domain/html;");
        buf.writeln("    index index.html;");
        buf.writeln();
        buf.writeln("    # Security headers");
        buf.writeln("    add_header X-Frame-Options \"SAMEORIGIN\" always;");
        buf.writeln("    add_header X-Content-Type-Options \"nosniff\" always;");
        buf.writeln("    add_header X-XSS-Protection \"1; mode=block\" always;");
        buf.writeln("    add_header Referrer-Policy \"strict-origin-when-cross-origin\" always;");
        buf.writeln();
        buf.writeln("    location / {");
        buf.writeln("        try_files \$uri \$uri/ /index.html;");
        buf.writeln("    }");
        buf.writeln();
        buf.writeln("    # Cache static assets");
        buf.writeln("    location ~* \\.(js|css|png|jpg|jpeg|gif|ico|svg|woff|woff2|ttf|eot)\$ {");
        buf.writeln("        expires 1y;");
        buf.writeln("        add_header Cache-Control \"public, immutable\";");
        buf.writeln("        access_log off;");
        buf.writeln("    }");
        buf.writeln();
        buf.writeln("    # Gzip compression");
        buf.writeln("    gzip on;");
        buf.writeln("    gzip_vary on;");
        buf.writeln("    gzip_proxied any;");
        buf.writeln("    gzip_comp_level 6;");
        buf.writeln("    gzip_types text/plain text/css application/json application/javascript text/xml application/xml application/xml+rss text/javascript;");
        buf.writeln("}");
        break;
      case "api":
      case "backend":
        buf.writeln("    # API proxy to backend service");
        buf.writeln("    location / {");
        buf.writeln("        proxy_pass http://127.0.0.1:$port;");
        buf.writeln("        proxy_http_version 1.1;");
        buf.writeln("        proxy_set_header Upgrade \$http_upgrade;");
        buf.writeln("        proxy_set_header Connection 'upgrade';");
        buf.writeln("        proxy_set_header Host \$host;");
        buf.writeln("        proxy_set_header X-Real-IP \$remote_addr;");
        buf.writeln("        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;");
        buf.writeln("        proxy_set_header X-Forwarded-Proto \$scheme;");
        buf.writeln("        proxy_cache_bypass \$http_upgrade;");
        buf.writeln("        proxy_read_timeout 90s;");
        buf.writeln("        proxy_connect_timeout 90s;");
        buf.writeln("    }");
        buf.writeln();
        buf.writeln("    # Security headers");
        buf.writeln("    add_header X-Frame-Options \"DENY\" always;");
        buf.writeln("    add_header X-Content-Type-Options \"nosniff\" always;");
        buf.writeln("}");
        break;
      case "static":
      default:
        buf.writeln("    root /var/www/$domain/html;");
        buf.writeln("    index index.html;");
        buf.writeln();
        buf.writeln("    location / {");
        buf.writeln("        try_files \$uri \$uri/ =404;");
        buf.writeln("    }");
        buf.writeln();
        buf.writeln("    # Cache static files aggressively");
        buf.writeln("    location ~* \\.(css|js|png|jpg|jpeg|gif|ico|svg|woff|woff2|ttf|eot|pdf)\$ {");
        buf.writeln("        expires 30d;");
        buf.writeln("        add_header Cache-Control \"public, no-transform\";");
        buf.writeln("        access_log off;");
        buf.writeln("    }");
        buf.writeln();
        buf.writeln("    # Deny access to hidden files");
        buf.writeln("    location ~ /\\. {");
        buf.writeln("        deny all;");
        buf.writeln("        access_log off;");
        buf.writeln("        log_not_found off;");
        buf.writeln("    }");
        buf.writeln();
        buf.writeln("    # Gzip");
        buf.writeln("    gzip on;");
        buf.writeln("    gzip_vary on;");
        buf.writeln("    gzip_min_length 256;");
        buf.writeln("    gzip_types text/plain text/css application/json application/javascript text/xml application/xml;");
        buf.writeln("}");
        break;
    }
    return buf.toString();
  }

  String _generatePm2Config(String name, String script) {
    final buf = StringBuffer();
    buf.writeln("module.exports = {");
    buf.writeln("  apps: [");
    buf.writeln("    {");
    buf.writeln("      name: '$name',");
    buf.writeln("      script: '$script',");
    buf.writeln("      args: '',");
    buf.writeln("      instances: 'max',");
    buf.writeln("      exec_mode: 'cluster',");
    buf.writeln("      autorestart: true,");
    buf.writeln("      watch: false,");
    buf.writeln("      max_memory_restart: '512M',");
    buf.writeln("      env: {");
    buf.writeln("        NODE_ENV: 'development',");
    buf.writeln("        PORT: 3000,");
    buf.writeln("      },");
    buf.writeln("      env_production: {");
    buf.writeln("        NODE_ENV: 'production',");
    buf.writeln("        PORT: 8080,");
    buf.writeln("      },");
    buf.writeln("      log_date_format: 'YYYY-MM-DD HH:mm:ss Z',");
    buf.writeln("      error_file: './logs/$name-error.log',");
    buf.writeln("      out_file: './logs/$name-out.log',");
    buf.writeln("      merge_logs: true,");
    buf.writeln("      max_restarts: 10,");
    buf.writeln("      min_uptime: '10s',");
    buf.writeln("      restart_delay: 5000,");
    buf.writeln("    },");
    buf.writeln("  ],");
    buf.writeln("};");
    buf.writeln();
    buf.writeln("# Commands:");
    buf.writeln("#   pm2 start ecosystem.config.js");
    buf.writeln("#   pm2 start ecosystem.config.js --env production");
    buf.writeln("#   pm2 save && pm2 startup");
    return buf.toString();
  }

  String _generateSystemd(String name, String command) {
    final buf = StringBuffer();
    buf.writeln("[Unit]");
    buf.writeln("Description=$name service");
    buf.writeln("After=network.target");
    buf.writeln("Wants=network-online.target");
    buf.writeln();
    buf.writeln("[Service]");
    buf.writeln("Type=simple");
    buf.writeln("User=$name");
    buf.writeln("Group=$name");
    buf.writeln("WorkingDirectory=/opt/$name");
    buf.writeln("ExecStart=$command");
    buf.writeln("ExecReload=/bin/kill -HUP \$MAINPID");
    buf.writeln("ExecStop=/bin/kill -TERM \$MAINPID");
    buf.writeln("Restart=on-failure");
    buf.writeln("RestartSec=5");
    buf.writeln("StartLimitBurst=5");
    buf.writeln("StartLimitIntervalSec=60");
    buf.writeln();
    buf.writeln("# Security hardening");
    buf.writeln("NoNewPrivileges=true");
    buf.writeln("PrivateTmp=true");
    buf.writeln("ProtectSystem=strict");
    buf.writeln("ProtectHome=true");
    buf.writeln("ReadWritePaths=/opt/$name/data");
    buf.writeln();
    buf.writeln("# Environment");
    buf.writeln("Environment=NODE_ENV=production");
    buf.writeln("EnvironmentFile=-/opt/$name/.env");
    buf.writeln();
    buf.writeln("# Resource limits");
    buf.writeln("LimitNOFILE=65535");
    buf.writeln("LimitNPROC=4096");
    buf.writeln("MemoryMax=1G");
    buf.writeln("CPUQuota=200%");
    buf.writeln();
    buf.writeln("[Install]");
    buf.writeln("WantedBy=multi-user.target");
    buf.writeln();
    buf.writeln("# Install:");
    buf.writeln("#   sudo cp $name.service /etc/systemd/system/");
    buf.writeln("#   sudo systemctl daemon-reload");
    buf.writeln("#   sudo systemctl enable $name");
    buf.writeln("#   sudo systemctl start $name");
    buf.writeln("#   sudo journalctl -u $name -f");
    return buf.toString();
  }

  String _generateEditorconfig() {
    final buf = StringBuffer();
    buf.writeln("root = true");
    buf.writeln();
    buf.writeln("[*]");
    buf.writeln("charset = utf-8");
    buf.writeln("end_of_line = lf");
    buf.writeln("indent_style = space");
    buf.writeln("indent_size = 2");
    buf.writeln("insert_final_newline = true");
    buf.writeln("trim_trailing_whitespace = true");
    buf.writeln();
    buf.writeln("[*.{js,ts,jsx,tsx,vue,svelte}]");
    buf.writeln("indent_style = space");
    buf.writeln("indent_size = 2");
    buf.writeln();
    buf.writeln("[*.{py,pyi}]");
    buf.writeln("indent_style = space");
    buf.writeln("indent_size = 4");
    buf.writeln();
    buf.writeln("[*.{java,kt,scala,gradle}]");
    buf.writeln("indent_style = space");
    buf.writeln("indent_size = 4");
    buf.writeln();
    buf.writeln("[*.{c,cpp,h,hpp,cs,go,rs}]");
    buf.writeln("indent_style = tab");
    buf.writeln("indent_size = 4");
    buf.writeln();
    buf.writeln("[*.{rb}]");
    buf.writeln("indent_style = space");
    buf.writeln("indent_size = 2");
    buf.writeln();
    buf.writeln("[*.{html,htm}]");
    buf.writeln("indent_style = space");
    buf.writeln("indent_size = 2");
    buf.writeln();
    buf.writeln("[*.{css,scss,sass,less}]");
    buf.writeln("indent_style = space");
    buf.writeln("indent_size = 2");
    buf.writeln();
    buf.writeln("[*.{json,yaml,yml,toml}]");
    buf.writeln("indent_style = space");
    buf.writeln("indent_size = 2");
    buf.writeln();
    buf.writeln("[Makefile]");
    buf.writeln("indent_style = tab");
    buf.writeln();
    buf.writeln("[*.md]");
    buf.writeln("trim_trailing_whitespace = false");
    buf.writeln();
    buf.writeln("[Dockerfile]");
    buf.writeln("indent_style = space");
    buf.writeln("indent_size = 4");
    return buf.toString();
  }

  String _generateGitattributes() {
    final buf = StringBuffer();
    buf.writeln("# Auto detect text files and normalize line endings");
    buf.writeln("* text=auto");
    buf.writeln();
    buf.writeln("# Force LF for source code");
    buf.writeln("*.{dart,js,ts,jsx,tsx,py,rb,java,kt,go,rs,c,cpp,h,hpp,cs,swift} text eol=lf");
    buf.writeln("*.{html,htm,css,scss,sass,less,vue,svelte} text eol=lf");
    buf.writeln("*.{json,yaml,yml,toml,xml,svg} text eol=lf");
    buf.writeln("*.{sh,bash,zsh} text eol=lf");
    buf.writeln("*.{md,txt,rst} text eol=lf");
    buf.writeln();
    buf.writeln("# Force CRLF for Windows-specific files");
    buf.writeln("*.{bat,cmd,ps1,psm1,psd1} text eol=crlf");
    buf.writeln("*.sln text eol=crlf");
    buf.writeln("*.csproj text eol=crlf");
    buf.writeln();
    buf.writeln("# Binary files - do not modify");
    buf.writeln("*.{png,jpg,jpeg,gif,ico,webp} binary");
    buf.writeln("*.{zip,tar,gz,bz2,7z,rar} binary");
    buf.writeln("*.{exe,dll,so,dylib} binary");
    buf.writeln("*.{woff,woff2,ttf,eot,otf} binary");
    buf.writeln("*.{pdf} binary");
    buf.writeln("*.{mp3,mp4,ogg,wav,flac} binary");
    buf.writeln();
    buf.writeln("# Merge strategies");
    buf.writeln("*.lock lockMerge=ours");
    buf.writeln("package-lock.json merge=ours");
    buf.writeln("yarn.lock merge=ours");
    buf.writeln("Podfile.lock merge=ours");
    buf.writeln("Cargo.lock merge=ours");
    buf.writeln();
    buf.writeln("# Diff settings");
    buf.writeln("*.dart diff=dart");
    buf.writeln("*.java diff=java");
    buf.writeln("*.py diff=python");
    buf.writeln("*.go diff=golang");
    buf.writeln();
    buf.writeln("# Generated files - do not diff");
    buf.writeln("*.min.js -diff");
    buf.writeln("*.min.css -diff");
    buf.writeln("*.map -diff");
    buf.writeln();
    buf.writeln("# Large files");
    buf.writeln("*.apk filter=lfs diff=lfs merge=lfs -text");
    buf.writeln("*.jar filter=lfs diff=lfs merge=lfs -text");
    buf.writeln("*.war filter=lfs diff=lfs merge=lfs -text");
    return buf.toString();
  }

  String _generateContributing(String project) {
    final buf = StringBuffer();
    buf.writeln("# Contributing to $project");
    buf.writeln();
    buf.writeln("Thank you for considering contributing! This document provides guidelines and instructions for contributing.");
    buf.writeln();
    buf.writeln("## Code of Conduct");
    buf.writeln();
    buf.writeln("By participating in this project, you agree to abide by our Code of Conduct:");
    buf.writeln();
    buf.writeln("- Be respectful and inclusive");
    buf.writeln("- Give and receive constructive feedback");
    buf.writeln("- Focus on what is best for the community");
    buf.writeln("- Show empathy towards other community members");
    buf.writeln();
    buf.writeln("## Getting Started");
    buf.writeln();
    buf.writeln("1. **Fork** the repository");
    buf.writeln("2. **Clone** your fork: `git clone https://github.com/your-username/$project.git`");
    buf.writeln("3. **Add upstream**: `git remote add upstream https://github.com/original-owner/$project.git`");
    buf.writeln("4. **Create a branch**: `git checkout -b feature/amazing-feature`");
    buf.writeln();
    buf.writeln("## Development Setup");
    buf.writeln();
    buf.writeln("### Prerequisites");
    buf.writeln();
    buf.writeln("- Git");
    buf.writeln("- A code editor (VS Code, IntelliJ, etc.)");
    buf.writeln();
    buf.writeln("### Installation");
    buf.writeln();
    buf.writeln("```bash");
    buf.writeln("# Clone the repository");
    buf.writeln("git clone https://github.com/your-username/$project.git");
    buf.writeln("cd $project");
    buf.writeln();
    buf.writeln("# Install dependencies");
    buf.writeln("npm install  # or: yarn, pip install -r requirements.txt, go mod download, cargo build");
    buf.writeln();
    buf.writeln("# Start development");
    buf.writeln("npm run dev  # or: yarn dev, python manage.py runserver, go run main.rs, cargo run");
    buf.writeln("```");
    buf.writeln();
    buf.writeln("### Running Tests");
    buf.writeln();
    buf.writeln("```bash");
    buf.writeln("npm test  # or: yarn test, pytest, go test ./..., cargo test");
    buf.writeln("```");
    buf.writeln();
    buf.writeln("## How to Contribute");
    buf.writeln();
    buf.writeln("### Reporting Bugs");
    buf.writeln();
    buf.writeln("Before creating bug reports, please check existing issues to avoid duplicates.");
    buf.writeln();
    buf.writeln("When creating a bug report, include:");
    buf.writeln("- **Clear and descriptive title**");
    buf.writeln("- **Steps to reproduce** the issue");
    buf.writeln("- **Expected behavior** vs **actual behavior**");
    buf.writeln("- **Environment details** (OS, browser, version)");
    buf.writeln("- **Screenshots** if applicable");
    buf.writeln();
    buf.writeln("### Suggesting Features");
    buf.writeln();
    buf.writeln("Open an issue with the **feature request** label. Include:");
    buf.writeln("- **Problem description** - What problem does this solve?");
    buf.writeln("- **Proposed solution** - How should it work?");
    buf.writeln("- **Alternatives considered**");
    buf.writeln("- **Additional context** - Mockups, examples, etc.");
    buf.writeln();
    buf.writeln("### Contributing Code");
    buf.writeln();
    buf.writeln("1. Find an issue to work on (look for `good-first-issue` or `help-wanted` labels)");
    buf.writeln("2. Comment on the issue to let others know you're working on it");
    buf.writeln("3. Write your code following the coding standards below");
    buf.writeln("4. Write or update tests as needed");
    buf.writeln("5. Submit a pull request");
    buf.writeln();
    buf.writeln("## Pull Request Process");
    buf.writeln();
    buf.writeln("1. **Update your fork** with the latest upstream changes:");
    buf.writeln("   ```bash");
    buf.writeln("   git fetch upstream");
    buf.writeln("   git rebase upstream/main");
    buf.writeln("   ```");
    buf.writeln();
    buf.writeln("2. **Make your changes** in small, focused commits");
    buf.writeln();
    buf.writeln("3. **Write descriptive commit messages** (see below)");
    buf.writeln();
    buf.writeln("4. **Ensure all tests pass**");
    buf.writeln();
    buf.writeln("5. **Update documentation** if your changes affect the public API or behavior");
    buf.writeln();
    buf.writeln("6. **Push your branch** and create a Pull Request against `main`");
    buf.writeln();
    buf.writeln("7. **Fill out the PR template** completely:");
    buf.writeln("   - What this PR does");
    buf.writeln("   - Why the change is needed");
    buf.writeln("   - How to test it");
    buf.writeln("   - Related issues (use `Closes #123`)");
    buf.writeln();
    buf.writeln("8. **Respond to review feedback** promptly");
    buf.writeln();
    buf.writeln("### PR Checklist");
    buf.writeln();
    buf.writeln("- [ ] Tests pass");
    buf.writeln("- [ ] No lint errors");
    buf.writeln("- [ ] Code follows project style guidelines");
    buf.writeln("- [ ] Documentation updated (if applicable)");
    buf.writeln("- [ ] Commit messages follow conventions");
    buf.writeln("- [ ] PR has a clear title and description");
    buf.writeln();
    buf.writeln("## Coding Standards");
    buf.writeln();
    buf.writeln("- Follow the existing code style");
    buf.writeln("- Write self-documenting code with clear names");
    buf.writeln("- Add comments only when the *why* is not obvious");
    buf.writeln("- Keep functions focused on a single responsibility");
    buf.writeln();
    buf.writeln("## Commit Messages");
    buf.writeln();
    buf.writeln("Follow [Conventional Commits](https://www.conventionalcommits.org/):");
    buf.writeln();
    buf.writeln("```");
    buf.writeln("<type>[optional scope]: <description>");
    buf.writeln("```");
    buf.writeln();
    buf.writeln("Types: `feat`, `fix`, `docs`, `style`, `refactor`, `perf`, `test`, `chore`, `ci`");
    buf.writeln();
    buf.writeln("## License");
    buf.writeln();
    buf.writeln("By contributing, you agree that your contributions will be licensed under the same license as the project.");
    return buf.toString();
  }

  String _generateCodeowners(String owners) {
    final buf = StringBuffer();
    buf.writeln("# Code Owners file");
    buf.writeln("# Each line is a file pattern followed by one or more owners.");
    buf.writeln("# Patterns follow .gitignore syntax.");
    buf.writeln("# Order matters: later patterns take precedence.");
    buf.writeln();
    if (owners.trim().isEmpty) {
      buf.writeln("# Default owners for everything");
      buf.writeln("* @team-lead");
      buf.writeln();
      buf.writeln("# Frontend");
      buf.writeln("*.js @frontend-team");
      buf.writeln("*.ts @frontend-team");
      buf.writeln("*.tsx @frontend-team");
      buf.writeln("*.vue @frontend-team");
      buf.writeln("*.css @frontend-team");
      buf.writeln("*.scss @frontend-team");
      buf.writeln("src/ui/ @frontend-team");
      buf.writeln();
      buf.writeln("# Backend");
      buf.writeln("*.py @backend-team");
      buf.writeln("*.go @backend-team");
      buf.writeln("*.rs @backend-team");
      buf.writeln("src/api/ @backend-team");
      buf.writeln("src/server/ @backend-team");
      buf.writeln();
      buf.writeln("# DevOps / Infrastructure");
      buf.writeln("Dockerfile @devops-team");
      buf.writeln("docker-compose*.yml @devops-team");
      buf.writeln(".github/ @devops-team");
      buf.writeln("*.tf @devops-team");
      buf.writeln("*.yaml @devops-team");
      buf.writeln("k8s/ @devops-team");
      buf.writeln();
      buf.writeln("# Database");
      buf.writeln("migrations/ @db-team");
      buf.writeln("*.sql @db-team");
      buf.writeln("schema/ @db-team");
      buf.writeln();
      buf.writeln("# Documentation");
      buf.writeln("docs/ @docs-team");
      buf.writeln("*.md @docs-team");
      buf.writeln();
      buf.writeln("# Security");
      buf.writeln("security/ @security-team");
      buf.writeln("**/auth/ @security-team");
      buf.writeln("**/security/ @security-team");
    } else {
      final lines = owners.split("\n");
      for (final line in lines) {
        final trimmed = line.trim();
        if (trimmed.isEmpty || trimmed.startsWith("#")) {
          buf.writeln(trimmed);
          continue;
        }
        final parts = trimmed.split(RegExp(r'\s+'));
        if (parts.length >= 2) {
          buf.writeln("${parts[0]} ${parts.sublist(1).join(" ")}");
        } else {
          buf.writeln("$trimmed @team-lead");
        }
      }
    }
    return buf.toString();
  }

  String _generateBadges(String project, String description) {
    final buf = StringBuffer();
    buf.writeln("# $project");
    buf.writeln();
    if (description.isNotEmpty) {
      buf.writeln("> $description");
      buf.writeln();
    }
    buf.writeln("![License](https://img.shields.io/github/license/$project?style=flat-square)");
    buf.writeln("![GitHub release](https://img.shields.io/github/v/release/$project?style=flat-square)");
    buf.writeln("![Build Status](https://img.shields.io/github/actions/workflow/status/$project/ci.yml?branch=main&style=flat-square&label=build)");
    buf.writeln("![Code Size](https://img.shields.io/github/languages/code-size/$project?style=flat-square)");
    buf.writeln("![Last Commit](https://img.shields.io/github/last-commit/$project?style=flat-square)");
    buf.writeln("![Issues](https://img.shields.io/github/issues/$project?style=flat-square)");
    buf.writeln("![Pull Requests](https://img.shields.io/github/issues-pr/$project?style=flat-square)");
    buf.writeln("![Stars](https://img.shields.io/github/stars/$project?style=flat-square)");
    buf.writeln("![Forks](https://img.shields.io/github/forks/$project?style=flat-square)");
    buf.writeln("![Downloads](https://img.shields.io/github/downloads/$project/total?style=flat-square)");
    buf.writeln();
    buf.writeln("---");
    buf.writeln();
    buf.writeln("**Copy for README.md:**");
    buf.writeln();
    buf.writeln("```markdown");
    buf.writeln("[![License](https://img.shields.io/github/license/$project?style=flat-square)](https://github.com/$project/blob/main/LICENSE)");
    buf.writeln("[![Release](https://img.shields.io/github/v/release/$project?style=flat-square)](https://github.com/$project/releases)");
    buf.writeln("[![Build](https://img.shields.io/github/actions/workflow/status/$project/ci.yml?branch=main&style=flat-square)](https://github.com/$project/actions)");
    buf.writeln("```");
    return buf.toString();
  }

  String _generateSitemap(String baseUrl) {
    final buf = StringBuffer();
    final now = DateTime.now().toIso8601String().substring(0, 10);
    buf.writeln('<?xml version="1.0" encoding="UTF-8"?>');
    buf.writeln('<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9"');
    buf.writeln('        xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"');
    buf.writeln('        xsi:schemaLocation="http://www.sitemaps.org/schemas/sitemap/0.9');
    buf.writeln('            http://www.sitemaps.org/schemas/sitemap/0.9/sitemap.xsd">');
    buf.writeln();
    buf.writeln("  <!-- Homepage -->");
    buf.writeln("  <url>");
    buf.writeln("    <loc>$baseUrl</loc>");
    buf.writeln("    <lastmod>$now</lastmod>");
    buf.writeln("    <changefreq>daily</changefreq>");
    buf.writeln("    <priority>1.0</priority>");
    buf.writeln("  </url>");
    buf.writeln();
    buf.writeln("  <!-- About -->");
    buf.writeln("  <url>");
    buf.writeln("    <loc>$baseUrl/about</loc>");
    buf.writeln("    <lastmod>$now</lastmod>");
    buf.writeln("    <changefreq>monthly</changefreq>");
    buf.writeln("    <priority>0.8</priority>");
    buf.writeln("  </url>");
    buf.writeln();
    buf.writeln("  <!-- Blog -->");
    buf.writeln("  <url>");
    buf.writeln("    <loc>$baseUrl/blog</loc>");
    buf.writeln("    <lastmod>$now</lastmod>");
    buf.writeln("    <changefreq>weekly</changefreq>");
    buf.writeln("    <priority>0.9</priority>");
    buf.writeln("  </url>");
    buf.writeln();
    buf.writeln("  <!-- Contact -->");
    buf.writeln("  <url>");
    buf.writeln("    <loc>$baseUrl/contact</loc>");
    buf.writeln("    <lastmod>$now</lastmod>");
    buf.writeln("    <changefreq>monthly</changefreq>");
    buf.writeln("    <priority>0.7</priority>");
    buf.writeln("  </url>");
    buf.writeln();
    buf.writeln("  <!-- Documentation -->");
    buf.writeln("  <url>");
    buf.writeln("    <loc>$baseUrl/docs</loc>");
    buf.writeln("    <lastmod>$now</lastmod>");
    buf.writeln("    <changefreq>weekly</changefreq>");
    buf.writeln("    <priority>0.9</priority>");
    buf.writeln("  </url>");
    buf.writeln();
    buf.writeln("  <!-- API Reference -->");
    buf.writeln("  <url>");
    buf.writeln("    <loc>$baseUrl/docs/api</loc>");
    buf.writeln("    <lastmod>$now</lastmod>");
    buf.writeln("    <changefreq>weekly</changefreq>");
    buf.writeln("    <priority>0.8</priority>");
    buf.writeln("  </url>");
    buf.writeln();
    buf.writeln("  <!-- Sitemap index -->");
    buf.writeln("  <url>");
    buf.writeln("    <loc>$baseUrl/sitemap.xml</loc>");
    buf.writeln("    <lastmod>$now</lastmod>");
    buf.writeln("    <changefreq>daily</changefreq>");
    buf.writeln("    <priority>0.3</priority>");
    buf.writeln("  </url>");
    buf.writeln();
    buf.writeln("</urlset>");
    return buf.toString();
  }

  Future<String> _generateMakefile(String project, String? targets) async {
    try {
      final buf = StringBuffer();
      final entries = await StorageService.listDir(project, "");
      final fileNames = entries.map((e) => e.uri.pathSegments.last).toList();
      final hasPackageJson = fileNames.contains("package.json");
      final hasPubspec = fileNames.contains("pubspec.yaml");
      final hasCargo = fileNames.contains("Cargo.toml");
      final hasGoMod = fileNames.contains("go.mod");
      final hasPipReq = fileNames.contains("requirements.txt");
      final hasDockerfile = fileNames.contains("Dockerfile");
      final hasDockerCompose = fileNames.contains("docker-compose.yml") || fileNames.contains("docker-compose.yaml");
      final hasMakefile = fileNames.contains("Makefile");
      final customTargets = targets?.split(",").map((t) => t.trim()).where((t) => t.isNotEmpty).toList();

      buf.writeln("# Auto-generated Makefile for $project");
      buf.writeln("# Generated on ${DateTime.now().toIso8601String().substring(0, 10)}");
      buf.writeln();
      buf.writeln(".PHONY: help install build test lint clean run dev docker format check"
          "${customTargets != null ? " ${customTargets.join(" ")}" : ""}");
      buf.writeln();

      if (hasPackageJson) {
        buf.writeln("NPM := npm");
        buf.writeln("NODE_ENV ?= development");
        buf.writeln();
      } else if (hasGoMod) {
        buf.writeln("GO := go");
        buf.writeln("APP_NAME ?= \$(notdir \$(CURDIR))");
        buf.writeln();
      } else if (hasCargo) {
        buf.writeln("CARGO := cargo");
        buf.writeln();
      } else if (hasPubspec) {
        buf.writeln("FLUTTER := flutter");
        buf.writeln();
      } else if (hasPipReq) {
        buf.writeln("PYTHON := python3");
        buf.writeln("PIP := pip3");
        buf.writeln();
      }

      buf.writeln("help: ## Show this help message");
      buf.writeln(r"""	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $$(MAKEFILE_LIST) | sort | \""");
      buf.writeln(r"""		xargs awk -F ':.*?## ' '{printf "  \033[36m%-20s\033[0m %s\n", $$1, $$2}'""");
      buf.writeln();

      if (hasPackageJson) {
        buf.writeln("all: install build ## Build the project");
        buf.writeln();
        buf.writeln("install: ## Install dependencies");
        buf.writeln("\t\$(NPM) install");
        buf.writeln();
        buf.writeln("build: ## Build the project");
        buf.writeln("\t\$(NPM) run build");
        buf.writeln();
        buf.writeln("dev: ## Start development server");
        buf.writeln("\t\$(NPM) run dev");
        buf.writeln();
        buf.writeln("start: ## Start the production server");
        buf.writeln("\t\$(NPM) start");
        buf.writeln();
        buf.writeln("test: ## Run tests");
        buf.writeln("\t\$(NPM) test");
        buf.writeln();
        buf.writeln("lint: ## Run linter");
        buf.writeln("\t\$(NPM) run lint");
        buf.writeln();
        buf.writeln("format: ## Format code");
        buf.writeln("\t\$(NPM) run format || npx prettier --write .");
        buf.writeln();
        buf.writeln("clean: ## Remove build artifacts and dependencies");
        buf.writeln("\trm -rf node_modules dist build .next .nuxt");
        buf.writeln("\t\$(NPM) cache clean --force || true");
      } else if (hasGoMod) {
        buf.writeln("all: build ## Build the project");
        buf.writeln();
        buf.writeln("build: ## Build the Go binary");
        buf.writeln("\t\$(GO) build -ldflags=\"-s -w\" -o bin/\$(APP_NAME) .");
        buf.writeln();
        buf.writeln("run: ## Run the application");
        buf.writeln("\t\$(GO) run main.go");
        buf.writeln();
        buf.writeln("test: ## Run tests");
        buf.writeln("\t\$(GO) test -v -race -cover ./...");
        buf.writeln();
        buf.writeln("lint: ## Run linter");
        buf.writeln("\tgolangci-lint run");
        buf.writeln();
        buf.writeln("format: ## Format Go code");
        buf.writeln("\tgofmt -w .");
        buf.writeln();
        buf.writeln("clean: ## Remove build artifacts");
        buf.writeln("\trm -rf bin/");
        buf.writeln("\t\$(GO) clean -cache -testcache");
      } else if (hasCargo) {
        buf.writeln("all: build ## Build the project");
        buf.writeln();
        buf.writeln("build: ## Build the Rust project");
        buf.writeln("\t\$(CARGO) build --release");
        buf.writeln();
        buf.writeln("run: ## Run the application");
        buf.writeln("\t\$(CARGO) run");
        buf.writeln();
        buf.writeln("test: ## Run tests");
        buf.writeln("\t\$(CARGO) test");
        buf.writeln();
        buf.writeln("lint: ## Run clippy linter");
        buf.writeln("\t\$(CARGO) clippy -- -D warnings");
        buf.writeln();
        buf.writeln("format: ## Format Rust code");
        buf.writeln("\t\$(CARGO) fmt");
        buf.writeln();
        buf.writeln("clean: ## Remove build artifacts");
        buf.writeln("\t\$(CARGO) clean");
      } else if (hasPubspec) {
        buf.writeln("all: get build ## Build the project");
        buf.writeln();
        buf.writeln("get: ## Get dependencies");
        buf.writeln("\t\$(FLUTTER) pub get");
        buf.writeln();
        buf.writeln("build: ## Build the Flutter project");
        buf.writeln("\t\$(FLUTTER) build apk --release");
        buf.writeln();
        buf.writeln("run: ## Run the application");
        buf.writeln("\t\$(FLUTTER) run");
        buf.writeln();
        buf.writeln("test: ## Run tests");
        buf.writeln("\t\$(FLUTTER) test");
        buf.writeln();
        buf.writeln("lint: ## Run dart analyzer");
        buf.writeln("\t\$(FLUTTER) analyze");
        buf.writeln();
        buf.writeln("format: ## Format Dart code");
        buf.writeln("\tdart format .");
        buf.writeln();
        buf.writeln("clean: ## Remove build artifacts");
        buf.writeln("\t\$(FLUTTER) clean");
      } else if (hasPipReq) {
        buf.writeln("all: install build ## Build the project");
        buf.writeln();
        buf.writeln("install: ## Install Python dependencies");
        buf.writeln("\t\$(PIP) install -r requirements.txt");
        buf.writeln();
        buf.writeln("build: ## Build distribution");
        buf.writeln("\t\$(PYTHON) -m build || \$(PYTHON) setup.py sdist bdist_wheel");
        buf.writeln();
        buf.writeln("run: ## Run the application");
        buf.writeln("\t\$(PYTHON) main.py");
        buf.writeln();
        buf.writeln("test: ## Run tests");
        buf.writeln("\t\$(PYTHON) -m pytest -v");
        buf.writeln();
        buf.writeln("lint: ## Run linters");
        buf.writeln("\t\$(PYTHON) -m flake8 . || true");
        buf.writeln();
        buf.writeln("format: ## Format Python code");
        buf.writeln("\t\$(PYTHON) -m black . || true");
        buf.writeln();
        buf.writeln("clean: ## Remove build artifacts");
        buf.writeln("\trm -rf build dist *.egg-info __pycache__ .pytest_cache .mypy_cache");
      } else {
        buf.writeln("all: build ## Default target");
        buf.writeln();
        buf.writeln("build: ## Build the project");
        buf.writeln("\techo \"Add build commands here\"");
        buf.writeln();
        buf.writeln("test: ## Run tests");
        buf.writeln("\techo \"Add test commands here\"");
        buf.writeln();
        buf.writeln("lint: ## Run linter");
        buf.writeln("\techo \"Add lint commands here\"");
        buf.writeln();
        buf.writeln("format: ## Format code");
        buf.writeln("\techo \"Add format commands here\"");
        buf.writeln();
        buf.writeln("clean: ## Remove build artifacts");
        buf.writeln("\techo \"Add clean commands here\"");
      }
      buf.writeln();

      if (hasDockerfile) {
        buf.writeln("DOCKER_IMAGE ?= \$(notdir \$(CURDIR))");
        buf.writeln("DOCKER_TAG ?= latest");
        buf.writeln();
        buf.writeln("docker: ## Build Docker image");
        buf.writeln("\tdocker build -t \$(DOCKER_IMAGE):\$(DOCKER_TAG) .");
        buf.writeln();
        buf.writeln("docker-run: ## Run Docker container");
        buf.writeln("\tdocker run -p 8080:8080 \$(DOCKER_IMAGE):\$(DOCKER_TAG)");
        buf.writeln();
        buf.writeln("docker-push: ## Push Docker image to registry");
        buf.writeln("\tdocker push \$(DOCKER_IMAGE):\$(DOCKER_TAG)");
        buf.writeln();
        buf.writeln("docker-clean: ## Remove Docker images");
        buf.writeln("\tdocker rmi \$(DOCKER_IMAGE):\$(DOCKER_TAG) || true");
        buf.writeln();
      }
      if (hasDockerCompose) {
        buf.writeln("up: ## Start services with docker-compose");
        buf.writeln("\tdocker-compose up -d");
        buf.writeln();
        buf.writeln("down: ## Stop services with docker-compose");
        buf.writeln("\tdocker-compose down");
        buf.writeln();
        buf.writeln("logs: ## View docker-compose logs");
        buf.writeln("\tdocker-compose logs -f");
        buf.writeln();
      }

      buf.writeln("## Git targets");
      buf.writeln("tag: ## Create a git tag (usage: make tag v=1.0.0)");
      buf.writeln("\tgit tag -a \$(v) -m \"Release \$(v)\"");
      buf.writeln("\tgit push origin \$(v)");
      buf.writeln();
      buf.writeln("status: ## Show git status");
      buf.writeln("\tgit status");
      buf.writeln();

      if (customTargets != null && customTargets.isNotEmpty) {
        buf.writeln("## Custom targets");
        for (final t in customTargets) {
          buf.writeln("$t: ## Custom target: $t");
          buf.writeln("\techo \"Implement $t target\"");
          buf.writeln();
        }
      }

      if (hasMakefile) {
        buf.writeln("# Note: An existing Makefile was found. These are supplemental targets.");
        buf.writeln("# Review and merge with your existing Makefile as needed.");
      }

      return buf.toString();
    } catch (e) {
      return "Makefile generation failed: $e";
    }
  }

  // ───────────────────── HTTP API Tool Methods ─────────────────────

  Future<String> _searchNpm(String query) async {
    try {
      final url = "https://api.npmjs.org/search?q=${Uri.encodeComponent(query)}";
      final response = await http.get(Uri.parse(url), headers: {"Accept": "application/json"}).timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) return "npm registry returned HTTP ${response.statusCode}";
      final data = jsonDecode(response.body);
      final objects = data["objects"] as List? ?? [];
      if (objects.isEmpty) return "No npm packages found for '$query'.";
      final buf = StringBuffer("## npm Search Results: $query (${objects.length} results)\n\n");
      for (final obj in objects.take(10)) {
        final pkg = obj["package"] as Map<String, dynamic>? ?? {};
        final name = pkg["name"] ?? "?";
        final version = pkg["version"] ?? "?";
        final desc = pkg["description"] ?? "";
        final score = (obj["score"] as Map<String, dynamic>?)?["final"] as double? ?? 0;
        final dl = pkg["links"]?["npm"] ?? "";
        buf.writeln("**$name** v$version (score: ${score.toStringAsFixed(2)})");
        if (desc is String && desc.isNotEmpty) buf.writeln("  $desc");
        if (dl.isNotEmpty) buf.writeln("  $dl");
        buf.writeln();
      }
      return buf.toString();
    } catch (e) {
      return "npm search failed: $e";
    }
  }

  Future<String> _searchPypi(String query) async {
    try {
      final url = "https://pypi.org/pypi/$query/json";
      final response = await http.get(Uri.parse(url), headers: {"Accept": "application/json"}).timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final info = data["info"] as Map<String, dynamic>? ?? {};
        final name = info["name"] ?? query;
        final version = info["version"] ?? "?";
        final summary = info["summary"] ?? "";
        final homePage = info["home_page"] ?? info["project_url"] ?? "";
        final author = info["author"] ?? info["author_email"] ?? "";
        final buf = StringBuffer("## PyPI Package: $name\n\n");
        buf.writeln("- **Version:** $version");
        if (summary is String && summary.isNotEmpty) buf.writeln("- **Summary:** $summary");
        if (author is String && author.isNotEmpty) buf.writeln("- **Author:** $author");
        if (homePage is String && homePage.isNotEmpty) buf.writeln("- **URL:** $homePage");
        final classifiers = info["classifiers"] as List? ?? [];
        if (classifiers.isNotEmpty) buf.writeln("- **Classifiers:** ${classifiers.take(5).join(", ")}");
        return buf.toString();
      }
      // Fallback: try search
      final searchUrl = "https://pypi.org/simple/$query/";
      final searchResp = await http.get(Uri.parse(searchUrl), headers: {"Accept": "application/json"}).timeout(const Duration(seconds: 10));
      if (searchResp.statusCode == 200) {
        return "PyPI package '$query' exists but detailed info unavailable. View at: https://pypi.org/project/$query/";
      }
      return "Package '$query' not found on PyPI. Search: https://pypi.org/search/?q=${Uri.encodeComponent(query)}";
    } catch (e) {
      return "PyPI search failed: $e";
    }
  }

  Future<String> _bundlePhobia(String pkg) async {
    try {
      final url = "https://bundlephobia.com/api/size?package=${Uri.encodeComponent(pkg)}";
      final response = await http.get(Uri.parse(url), headers: {"Accept": "application/json"}).timeout(const Duration(seconds: 15));
      if (response.statusCode != 200) return "Bundlephobia API returned HTTP ${response.statusCode} for '$pkg'.";
      final data = jsonDecode(response.body);
      final name = data["name"] ?? pkg;
      final version = data["version"] ?? "?";
      final size = data["size"] as int? ?? 0;
      final gzip = data["gzip"] as int? ?? 0;
      final dependencyCount = data["dependencyCount"] as int? ?? 0;
      final hasJSModule = data["hasJSModule"] == true;
      final hasJSNext = data["hasJSNext"] == true;
      final buf = StringBuffer("## Bundle Size: $name@$version\n\n");
      buf.writeln("| Metric | Value |");
      buf.writeln("|--------|-------|");
      buf.writeln("| Minified | ${_formatBytes(size)} |");
      buf.writeln("| Gzipped | ${_formatBytes(gzip)} |");
      buf.writeln("| Dependencies | $dependencyCount |");
      buf.writeln("| ES Module | ${hasJSModule ? "Yes" : "No"} |");
      buf.writeln("| tree-shakeable | ${hasJSNext ? "Yes" : "Unknown"} |");
      buf.writeln("\n[View on bundlephobia](https://bundlephobia.com/package/$pkg)");
      return buf.toString();
    } catch (e) {
      return "Bundlephobia lookup failed for '$pkg': $e";
    }
  }

  String _formatBytes(int bytes) {
    if (bytes >= 1048576) return "${(bytes / 1048576).toStringAsFixed(1)} MB";
    if (bytes >= 1024) return "${(bytes / 1024).toStringAsFixed(1)} KB";
    return "$bytes B";
  }

  Future<String> _checkDeps(String project) async {
    final buf = StringBuffer("## Dependency Check\n\n");
    var found = false;

    // Check for package.json (Node.js)
    try {
      final pkgJson = jsonDecode(await StorageService.readFile(project, "package.json"));
      found = true;
      final deps = Map<String, dynamic>.from(pkgJson["dependencies"] as Map? ?? {});
      final devDeps = Map<String, dynamic>.from(pkgJson["devDependencies"] as Map? ?? {});
      buf.writeln("### Node.js (package.json)\n");
      buf.writeln("**${deps.length}** dependencies, **${devDeps.length}** devDependencies\n");
      if (deps.isNotEmpty) {
        buf.writeln("**Dependencies:**");
        for (final e in deps.entries) {
          final ver = e.value.toString();
          final isOutdated = ver.startsWith("^") || ver.startsWith("~") || ver == "*";
          buf.writeln("  ${e.key}: $ver${isOutdated ? " (may have updates)" : ""}");
        }
      }
      if (devDeps.isNotEmpty) {
        buf.writeln("\n**Dev Dependencies:**");
        for (final e in devDeps.entries) {
          buf.writeln("  ${e.key}: ${e.value}");
        }
      }
      // Check for lock files
      for (final lock in ["package-lock.json", "yarn.lock", "pnpm-lock.yaml"]) {
        try {
          await StorageService.readFile(project, lock);
          buf.writeln("\nLock file: $lock ✓");
          break;
        } catch (e) {
          // Lock file not found, try next
        }
      }
    } catch (e) {
      // npm/yarn lock file not found, continue
    }

    // Check for pubspec.yaml (Dart/Flutter)
    try {
      final pubspec = await StorageService.readFile(project, "pubspec.yaml");
      found = true;
      buf.writeln("### Dart/Flutter (pubspec.yaml)\n");
      final depBlock = RegExp(r'dependencies:\s*\n((?:\s{2,}\S.*\n)*)').firstMatch(pubspec);
      if (depBlock != null) {
        final lines = depBlock.group(1)!.split("\n").where((l) => l.trim().isNotEmpty && !l.trim().startsWith("#")).toList();
        buf.writeln("**${lines.length}** dependencies:");
        for (final line in lines.take(20)) {
          buf.writeln("  ${line.trim()}");
        }
      }
      final sdkBlock = RegExp(r"""sdk:\s*["']([^"']+)["']""").firstMatch(pubspec);
      if (sdkBlock != null) buf.writeln("\nSDK constraint: ${sdkBlock.group(1)}");
    } catch (e) {
      // pubspec.yaml not found or invalid
    }

    // Check for requirements.txt (Python)
    try {
      final req = await StorageService.readFile(project, "requirements.txt");
      found = true;
      final deps = req.split("\n").where((l) => l.trim().isNotEmpty && !l.trim().startsWith("#")).toList();
      buf.writeln("### Python (requirements.txt)\n");
      buf.writeln("**${deps.length}** dependencies:");
      for (final d in deps.take(30)) {
        final hasPin = d.contains("==") || d.contains(">=") || d.contains("<=");
        buf.writeln("  ${d.trim()}${hasPin ? "" : " (⚠ unpinned version)"}");
      }
    } catch (e) {
      // requirements.txt not found
    }

    // Check for pyproject.toml
    try {
      final toml = await StorageService.readFile(project, "pyproject.toml");
      found = true;
      buf.writeln("### Python (pyproject.toml)\n");
      final depSection = RegExp(r'dependencies\s*=\s*\[((?:[^[\]]|\[[^\]]*\])*)\]', dotAll: true).firstMatch(toml);
      if (depSection != null) {
        final deps = depSection.group(1)!.split(RegExp(r',\s*')).where((d) => d.trim().isNotEmpty).map((d) => d.trim().replaceAll(RegExp(r"""^["']|["']$"""), '')).toList();
        buf.writeln("**${deps.length}** dependencies:");
        for (final d in deps.take(20)) buf.writeln("  $d");
      }
    } catch (e) {
      // pyproject.toml not found
    }

    // Check for Cargo.toml
    try {
      final cargo = await StorageService.readFile(project, "Cargo.toml");
      found = true;
      buf.writeln("### Rust (Cargo.toml)\n");
      final depSection = RegExp(r'\[dependencies\]\s*\n((?:.*\n)*?)(?:\[|\z)').firstMatch(cargo);
      if (depSection != null) {
        final lines = depSection.group(1)!.split("\n").where((l) => l.trim().isNotEmpty).toList();
        buf.writeln("**${lines.length}** dependencies:");
        for (final l in lines.take(20)) buf.writeln("  ${l.trim()}");
      }
    } catch (e) {
      // Cargo.toml not found
    }

    if (!found) return "No dependency file found (package.json, pubspec.yaml, requirements.txt, Cargo.toml).";
    buf.writeln("\n**Tip:** Use your package manager's `outdated` or `audit` command for security/updates.");
    return buf.toString();
  }

  String _generateQr(String data) {
    final encoded = Uri.encodeComponent(data);
    final url = "https://api.qrserver.com/v1/create-qr-code/?size=200x200&data=$encoded";
    final buf = StringBuffer("## QR Code\n\n");
    buf.writeln("![QR Code]($url)\n");
    buf.writeln("Data: `$data`");
    buf.writeln("\n[Download QR Code (PNG)]($url)");
    buf.writeln("[Open in browser]($url)");
    return buf.toString();
  }

  Future<String> _minifyCode(String project, String filePath) async {
    try {
      final content = await StorageService.readFile(project, filePath);
      final ext = filePath.split(".").last.toLowerCase();
      String minified;

      if (ext == "json") {
        try {
          minified = jsonEncode(jsonDecode(content));
        } catch (e) {
          minified = content;
        }
      } else if (ext == "css") {
        minified = _minifyCss(content);
      } else if (["js", "ts", "jsx", "tsx"].contains(ext)) {
        minified = _minifyJsLike(content);
      } else {
        minified = _minifyGeneric(content);
      }

      final originalSize = content.length;
      final minifiedSize = minified.length;
      final savings = originalSize > 0 ? ((1 - minifiedSize / originalSize) * 100).toStringAsFixed(1) : "0";

      final buf = StringBuffer("## Minified: $filePath\n\n");
      buf.writeln("| | Size |");
      buf.writeln("|---|---|");
      buf.writeln("| Original | ${_formatBytes(originalSize)} |");
      buf.writeln("| Minified | ${_formatBytes(minifiedSize)} |");
      buf.writeln("| Savings | $savings% |");
      buf.writeln("\n```$ext\n$minified\n```");
      return buf.toString();
    } catch (e) {
      return "Minification failed: $e";
    }
  }

  String _minifyCss(String css) {
    var result = css;
    result = result.replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '');
    result = result.replaceAll(RegExp(r'\s*{\s*'), '{');
    result = result.replaceAll(RegExp(r'\s*}\s*'), '}');
    result = result.replaceAll(RegExp(r'\s*:\s*'), ':');
    result = result.replaceAll(RegExp(r'\s*;\s*'), ';');
    result = result.replaceAll(RegExp(r'\s*,\s*'), ',');
    result = result.replaceAll(RegExp(r';}'), '}');
    result = result.replaceAll(RegExp(r'\n\s*\n'), '\n');
    return result.trim();
  }

  String _minifyJsLike(String code) {
    var result = code;
    // Remove multi-line comments
    result = result.replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '');
    // Remove single-line comments (but not URLs with //)
    result = result.replaceAll(RegExp(r'(?<!:)//(?!/).*$', multiLine: true), '');
    // Collapse whitespace
    result = result.replaceAll(RegExp(r'[ \t]+'), ' ');
    // Remove newlines
    result = result.replaceAll(RegExp(r'\n\s*\n'), '\n');
    result = result.replaceAll(RegExp(r'\n'), ' ');
    // Clean up spaces around operators/punctuation
    result = result.replaceAll(RegExp(r'\s*([{};,=:+\-*/<>!&|?])\s*'), r'$1');
    // Restore space after keywords
    for (final kw in ["return", "const", "let", "var", "function", "if", "else", "for", "while", "switch", "case", "break", "continue", "new", "typeof", "instanceof", "throw", "try", "catch", "finally", "class", "extends", "import", "export", "from", "default", "async", "await", "yield"]) {
      result = result.replaceAll(RegExp('(?<!\\w)$kw(?!\\w)'), kw);
    }
    return result.trim();
  }

  String _minifyGeneric(String code) {
    var result = code;
    // Remove single-line comments
    result = result.replaceAll(RegExp(r"""(?<!["'])#(?!![\s\S])"""), '');
    result = result.replaceAll(RegExp(r'//.*$', multiLine: true), '');
    // Remove multi-line comments
    result = result.replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '');
    // Collapse multiple blank lines
    result = result.replaceAll(RegExp(r'\n\s*\n'), '\n');
    // Trim trailing whitespace per line
    result = result.split("\n").map((l) => l.trimRight()).join("\n");
    // Remove blank lines
    result = result.split("\n").where((l) => l.trim().isNotEmpty).join("\n");
    return result.trim();
  }

  String _convertFormat(String content, String from, String to) {
    from = from.toLowerCase().trim();
    to = to.toLowerCase().trim();
    try {
      if (from == to) return content;

      // ─── Parse input ───
      dynamic parsed;
      List<List<String>> csvData = [];

      if (from == "json") {
        parsed = jsonDecode(content);
      } else if (from == "yaml" || from == "yml") {
        parsed = _parseYaml(content);
      } else if (from == "csv") {
        csvData = _parseCsv(content);
        // Represent as list of maps if header row exists
        if (csvData.isNotEmpty) {
          final headers = csvData.first;
          parsed = csvData.skip(1).map((row) {
            final map = <String, dynamic>{};
            for (var i = 0; i < headers.length && i < row.length; i++) {
              map[headers[i]] = row[i];
            }
            return map;
          }).toList();
        } else {
          parsed = <dynamic>[];
        }
      } else {
        return "Unsupported input format: $from. Supported: json, yaml, csv";
      }

      // ─── Serialize output ───
      if (to == "json") {
        return const JsonEncoder.withIndent("  ").convert(parsed);
      } else if (to == "yaml" || to == "yml") {
        return _toYaml(parsed, 0);
      } else if (to == "csv") {
        return _toCsv(parsed);
      } else {
        return "Unsupported output format: $to. Supported: json, yaml, csv";
      }
    } catch (e) {
      return "Format conversion failed: $e";
    }
  }

  dynamic _parseYaml(String yaml) {
    final lines = yaml.split("\n");
    final result = <String, dynamic>{};
    String? currentKey;
    for (final rawLine in lines) {
      final line = rawLine.replaceAll("\r", "");
      if (line.trim().isEmpty || line.trim().startsWith("#")) continue;
      final keyMatch = RegExp(r'^(\s*)(\w[\w\s]*?):\s*(.*)$').firstMatch(line);
      if (keyMatch != null) {
        final indent = keyMatch.group(1)!.length;
        final key = keyMatch.group(2)!.trim();
        final val = keyMatch.group(3)!.trim();
        if (val.isEmpty) {
          currentKey = key;
          if (indent == 0) result[key] = <String, dynamic>{};
        } else {
          final parsed = _yamlParseValue(val);
          if (indent == 0) {
            result[key] = parsed;
          } else if (currentKey != null && result[currentKey] is Map) {
            (result[currentKey] as Map)[key] = parsed;
          }
        }
      }
    }
    return result.isNotEmpty ? result : yaml.trim();
  }

  dynamic _yamlParseValue(String val) {
    if (val == "true") return true;
    if (val == "false") return false;
    if (val == "null" || val == "~") return null;
    if (RegExp(r'^-?\d+$').hasMatch(val)) return int.parse(val);
    if (RegExp(r'^-?\d+\.\d+$').hasMatch(val)) return double.parse(val);
    if ((val.startsWith('"') && val.endsWith('"')) || (val.startsWith("'") && val.endsWith("'"))) {
      return val.substring(1, val.length - 1);
    }
    if (val.startsWith("[")) {
      try { return jsonDecode(val); } catch (e) {
        // Not valid JSON, return as string
      }
    }
    return val;
  }

  String _toYaml(dynamic obj, int indent) {
    final prefix = "  " * indent;
    final buf = StringBuffer();
    if (obj is Map) {
      for (final e in obj.entries) {
        if (e.value is Map || e.value is List) {
          buf.writeln("$prefix${e.key}:");
          buf.write(_toYaml(e.value, indent + 1));
        } else {
          buf.writeln("$prefix${e.key}: ${_yamlSerializeValue(e.value)}");
        }
      }
    } else if (obj is List) {
      for (final item in obj) {
        if (item is Map) {
          for (final e in item.entries) {
            buf.writeln("$prefix- ${e.key}: ${_yamlSerializeValue(e.value)}");
          }
        } else {
          buf.writeln("$prefix- ${_yamlSerializeValue(item)}");
        }
      }
    } else {
      buf.writeln("$prefix${_yamlSerializeValue(obj)}");
    }
    return buf.toString();
  }

  String _yamlSerializeValue(dynamic val) {
    if (val == null) return "null";
    if (val is bool) return val.toString();
    if (val is num) return val.toString();
    if (val is String) {
      if (val.contains(":") || val.contains("#") || val.isEmpty || val.contains("'") || val.contains("\"")) {
        return '"${val.replaceAll("\\", "\\\\").replaceAll('"', '\\"')}"';
      }
      return val;
    }
    return val.toString();
  }

  List<List<String>> _parseCsv(String csv) {
    final rows = <List<String>>[];
    for (final rawLine in csv.split("\n")) {
      final line = rawLine.replaceAll("\r", "").trim();
      if (line.isEmpty) continue;
      final row = <String>[];
      var current = StringBuffer();
      var inQuote = false;
      for (var i = 0; i < line.length; i++) {
        final ch = line[i];
        if (ch == '"') {
          if (inQuote && i + 1 < line.length && line[i + 1] == '"') {
            current.write('"');
            i++;
          } else {
            inQuote = !inQuote;
          }
        } else if (ch == "," && !inQuote) {
          row.add(current.toString().trim());
          current = StringBuffer();
        } else {
          current.write(ch);
        }
      }
      row.add(current.toString().trim());
      rows.add(row);
    }
    return rows;
  }

  String _toCsv(dynamic obj) {
    final buf = StringBuffer();
    if (obj is List && obj.isNotEmpty) {
      // List of maps → CSV with headers
      if (obj.first is Map) {
        final headers = (obj.first as Map).keys.map((k) => k.toString()).toList();
        buf.writeln(headers.map((h) => _csvEscape(h)).join(","));
        for (final row in obj) {
          if (row is Map) {
            buf.writeln(headers.map((h) => _csvEscape(row[h]?.toString() ?? "")).join(","));
          }
        }
      } else {
        for (final item in obj) {
          buf.writeln(_csvEscape(item?.toString() ?? ""));
        }
      }
    } else if (obj is Map) {
      // Single map → 2-column CSV (key, value)
      buf.writeln("key,value");
      for (final e in obj.entries) {
        buf.writeln("${_csvEscape(e.key.toString())},${_csvEscape(e.value?.toString() ?? "")}");
      }
    } else {
      return obj?.toString() ?? "";
    }
    return buf.toString();
  }

  String _csvEscape(String field) {
    if (field.contains(",") || field.contains('"') || field.contains("\n")) {
      return '"${field.replaceAll('"', '""')}"';
    }
    return field;
  }

  // ───────────────────── Code Analysis Methods ─────────────────────

  Future<String> _codeStats(String project) async {
    var totalFiles = 0;
    var totalLines = 0;
    var codeLines = 0;
    var commentLines = 0;
    var blankLines = 0;
    final langCount = <String, int>{};
    final langLines = <String, int>{};

    await _walk(project, "", (file, content) {
      totalFiles++;
      final ext = file.split(".").last.toLowerCase();
      final lines = content.split("\n");
      totalLines += lines.length;
      langCount[ext] = (langCount[ext] ?? 0) + 1;
      langLines[ext] = (langLines[ext] ?? 0) + lines.length;

      for (final line in lines) {
        final trimmed = line.trim();
        if (trimmed.isEmpty) {
          blankLines++;
        } else if (trimmed.startsWith("//") || trimmed.startsWith("#") || trimmed.startsWith("/*") || trimmed.startsWith("*") || trimmed.startsWith("<!--")) {
          commentLines++;
        } else {
          codeLines++;
        }
      }
    });

    final buf = StringBuffer("## Code Statistics: $project\n\n");
    buf.writeln("| Metric | Value |");
    buf.writeln("|--------|-------|");
    buf.writeln("| Total files | $totalFiles |");
    buf.writeln("| Total lines | $totalLines |");
    buf.writeln("| Code lines | $codeLines |");
    buf.writeln("| Comment lines | $commentLines |");
    buf.writeln("| Blank lines | $blankLines |");
    buf.writeln("");

    if (langLines.isNotEmpty) {
      buf.writeln("### By Language\n");
      buf.writeln("| Language | Files | Lines |");
      buf.writeln("|----------|-------|-------|");
      final sorted = langLines.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
      for (final e in sorted) {
        buf.writeln("| .${e.key} | ${langCount[e.key]} | ${e.value} |");
      }
    }

    if (totalLines > 0) {
      buf.writeln("\n### Composition");
      buf.writeln("- Code: ${(codeLines / totalLines * 100).toStringAsFixed(1)}%");
      buf.writeln("- Comments: ${(commentLines / totalLines * 100).toStringAsFixed(1)}%");
      buf.writeln("- Blank: ${(blankLines / totalLines * 100).toStringAsFixed(1)}%");
    }

    return buf.toString();
  }

  Future<String> _complexityReport(String project) async {
    final results = <Map<String, dynamic>>[];
    final langPatterns = {
      "dart": RegExp(r'\b(if|for|while|switch|case|catch|&&|\|\||\?)\b', caseSensitive: false),
      "js": RegExp(r'\b(if|for|while|switch|case|catch|&&|\|\||\?)\b', caseSensitive: false),
      "ts": RegExp(r'\b(if|for|while|switch|case|catch|&&|\|\||\?)\b', caseSensitive: false),
      "py": RegExp(r'\b(if|elif|for|while|except|and|or|in)\b'),
    };
    final supportedExts = langPatterns.keys.toSet();

    await _walk(project, "", (file, content) {
      final ext = file.split(".").last.toLowerCase();
      if (!supportedExts.contains(ext)) return;

      final pattern = langPatterns[ext]!;
      final lines = content.split("\n");
      var totalComplexity = 1; // base complexity

      // Count function definitions for per-function breakdown
      final funcDefs = RegExp(r'(?:function\s+(\w+)|(?:def|fun)\s+(\w+)|(?:async\s+)?(\w+)\s*[=(]\s*(?:async\s*)?\()', caseSensitive: false).allMatches(content).toList();

      for (final line in lines) {
        totalComplexity += pattern.allMatches(line).length;
      }

      // Simple per-function estimation
      final funcCount = funcDefs.isEmpty ? 1 : funcDefs.length;
      final avgPerFunc = funcCount > 0 ? (totalComplexity / funcCount).toStringAsFixed(1) : "N/A";

      var risk = "low";
      if (totalComplexity > 50) risk = "HIGH";
      else if (totalComplexity > 20) risk = "medium";

      results.add({
        "file": file,
        "complexity": totalComplexity,
        "functions": funcCount,
        "avg": avgPerFunc,
        "risk": risk,
      });
    });

    if (results.isEmpty) return "No Dart/JS/TS/Python files found for complexity analysis.";

    results.sort((a, b) => (b["complexity"] as int).compareTo(a["complexity"] as int));
    final buf = StringBuffer("## Complexity Report\n\n");
    buf.writeln("| File | Complexity | Functions | Avg/Func | Risk |");
    buf.writeln("|------|-----------|-----------|----------|------|");
    for (final r in results.take(25)) {
      buf.writeln("| ${r["file"]} | ${r["complexity"]} | ${r["functions"]} | ${r["avg"]} | ${r["risk"]} |");
    }
    buf.writeln("\nComplexity = 1 (base) + count of if/for/while/switch/case/catch/&&/||/?");
    return buf.toString();
  }

  Future<String> _testCoverage(String project) async {
    final buf = StringBuffer("## Test Coverage: $project\n\n");
    var found = false;

    // Look for coverage/lcov.info
    for (final covPath in ["coverage/lcov.info", "coverage/clover.xml", "coverage/coverage-final.json", ".coverage", "htmlcov/index.html"]) {
      try {
        final content = await StorageService.readFile(project, covPath);
        found = true;
        buf.writeln("### Coverage report found: $covPath\n");

        if (covPath == "coverage/lcov.info") {
          // Parse lcov.info
          final records = content.split("end_of_record");
          var totalLines = 0;
          var hitLines = 0;
          final files = <Map<String, String>>[];

          for (final record in records) {
            if (record.trim().isEmpty) continue;
            final sfMatch = RegExp(r'SF:(.*)').firstMatch(record);
            final lfMatch = RegExp(r'LF:(\d+)').firstMatch(record);
            final lhMatch = RegExp(r'LH:(\d+)').firstMatch(record);
            if (lfMatch != null && lhMatch != null) {
              final lf = int.parse(lfMatch.group(1)!);
              final lh = int.parse(lhMatch.group(1)!);
              totalLines += lf;
              hitLines += lh;
              if (sfMatch != null) {
                final pct = lf > 0 ? (lh / lf * 100).toStringAsFixed(1) : "0";
                files.add({"file": sfMatch.group(1)!, "pct": "$pct%", "hit": lh.toString(), "total": lf.toString()});
              }
            }
          }

          if (totalLines > 0) {
            final overallPct = (hitLines / totalLines * 100).toStringAsFixed(1);
            buf.writeln("**Overall coverage: $overallPct%** ($hitLines / $totalLines lines)\n");
          }

          if (files.isNotEmpty) {
            buf.writeln("| File | Coverage | Lines Hit |");
            buf.writeln("|------|----------|-----------|");
            files.sort((a, b) => a["pct"]!.compareTo(b["pct"]!));
            for (final f in files.take(20)) {
              buf.writeln("| ${f["file"]?.split("/").last} | ${f["pct"]} | ${f["hit"]}/${f["total"]} |");
            }
          }
        } else if (covPath == "coverage/coverage-final.json") {
          final data = jsonDecode(content);
          if (data is Map) {
            buf.writeln("Coverage files: ${data.length}");
          }
        } else {
          buf.writeln("Report size: ${content.length} bytes");
        }
      } catch (e) {
        // Failed to parse coverage file
      }
    }

    // Look for test directories
    try {
      final entries = await StorageService.listDir(project, "");
      final testDirs = entries.where((e) {
        final name = e.uri.pathSegments.last;
        return name == "test" || name == "tests" || name == "__tests__" || name == "spec" || name == "specs";
      }).toList();
      if (testDirs.isNotEmpty) {
        buf.writeln("### Test directories found:\n");
        for (final d in testDirs) {
          buf.writeln("- ${d.uri.pathSegments.last}/");
        }
      }
    } catch (e) {
      // Test directories listing failed
    }

    if (!found) {
      buf.writeln("**No coverage reports found.**\n");
      buf.writeln("### How to generate coverage:\n");
      buf.writeln("**Dart/Flutter:**");
      buf.writeln("```bash");
      buf.writeln("flutter test --coverage");
      buf.writeln("# View: genhtml coverage/lcov.info -o coverage_html");
      buf.writeln("```\n");
      buf.writeln("**JavaScript/TypeScript (Jest):**");
      buf.writeln("```bash");
      buf.writeln("npx jest --coverage");
      buf.writeln("```\n");
      buf.writeln("**JavaScript/TypeScript (Vitest):**");
      buf.writeln("```bash");
      buf.writeln("npx vitest run --coverage");
      buf.writeln("```\n");
      buf.writeln("**Python:**");
      buf.writeln("```bash");
      buf.writeln("python -m pytest --cov=. --cov-report=lcov");
      buf.writeln("```\n");
      buf.writeln("**Go:**");
      buf.writeln("```bash");
      buf.writeln("go test -coverprofile=coverage.out ./...");
      buf.writeln("go tool cover -html=coverage.out");
      buf.writeln("```");
    }

    return buf.toString();
  }

  Future<String> _namingConvention(String project) async {
    final conventions = <String, Map<String, int>>{
      "files": <String, int>{},
      "functions": <String, int>{},
      "classes": <String, int>{},
      "variables": <String, int>{},
    };

    var totalFiles = 0;
    await _walk(project, "", (file, content) {
      totalFiles++;
      // Analyze filename
      final baseName = file.split("/").last.split(".").first;
      final fileStyle = _classifyStyle(baseName);
      conventions["files"]![fileStyle] = (conventions["files"]![fileStyle] ?? 0) + 1;

      // Analyze function names
      for (final m in RegExp(r'(?:function|def|fun|async\s+function)\s+(\w+)', caseSensitive: false).allMatches(content)) {
        final name = m.group(1)!;
        final style = _classifyStyle(name);
        conventions["functions"]![style] = (conventions["functions"]![style] ?? 0) + 1;
      }
      // Arrow/lambda functions: const myFunc = ...
      for (final m in RegExp(r'(?:const|let|var)\s+(\w+)\s*=', caseSensitive: false).allMatches(content)) {
        final name = m.group(1)!;
        if (name.length > 2 && !name.startsWith("_")) {
          final style = _classifyStyle(name);
          conventions["functions"]![style] = (conventions["functions"]![style] ?? 0) + 1;
        }
      }

      // Analyze class names
      for (final m in RegExp(r'class\s+(\w+)', caseSensitive: false).allMatches(content)) {
        final name = m.group(1)!;
        final style = _classifyStyle(name);
        conventions["classes"]![style] = (conventions["classes"]![style] ?? 0) + 1;
      }

      // Analyze variable names (const/let/var/type declarations)
      for (final m in RegExp(r'(?:const|let|var|final)\s+(\w+)', caseSensitive: false).allMatches(content)) {
        final name = m.group(1)!;
        if (name.length > 1 && !name.startsWith("_")) {
          final style = _classifyStyle(name);
          conventions["variables"]![style] = (conventions["variables"]![style] ?? 0) + 1;
        }
      }
    });

    final buf = StringBuffer("## Naming Conventions: $project\n\n");
    buf.writeln("Analyzed $totalFiles files.\n");

    final styleLabels = {
      "camelCase": "camelCase",
      "snake_case": "snake_case",
      "PascalCase": "PascalCase",
      "kebab-case": "kebab-case",
      "UPPER_CASE": "UPPER_CASE",
      "other": "other",
    };

    for (final entry in conventions.entries) {
      final counts = entry.value;
      if (counts.isEmpty) continue;
      final total = counts.values.fold(0, (a, b) => a + b);
      buf.writeln("### ${entry.key} ($total found)\n");
      final sorted = counts.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
      for (final s in sorted) {
        if (s.value == 0) continue;
        final pct = (s.value / total * 100).toStringAsFixed(0);
        buf.writeln("- ${styleLabels[s.key] ?? s.key}: ${s.value} ($pct%)");
      }
      buf.writeln();
    }

    // Recommendation
    buf.writeln("### Recommendation\n");
    final fileStyles = conventions["files"]!;
    final funcStyles = conventions["functions"]!;
    if (fileStyles.containsKey("kebab-case") && (fileStyles["kebab-case"] ?? 0) > totalFiles * 0.5) {
      buf.writeln("- **Files:** kebab-case (dominant)");
    } else if (fileStyles.containsKey("snake_case") && (fileStyles["snake_case"] ?? 0) > totalFiles * 0.5) {
      buf.writeln("- **Files:** snake_case (dominant)");
    }
    if (funcStyles.containsKey("camelCase") && (funcStyles["camelCase"] ?? 0) > (funcStyles["snake_case"] ?? 0)) {
      buf.writeln("- **Functions:** camelCase (dominant)");
    } else if (funcStyles.containsKey("snake_case") && (funcStyles["snake_case"] ?? 0) > 0) {
      buf.writeln("- **Functions:** snake_case (dominant)");
    }
    final classStyles = conventions["classes"]!;
    if (classStyles.containsKey("PascalCase") && (classStyles["PascalCase"] ?? 0) > 0) {
      buf.writeln("- **Classes:** PascalCase (dominant)");
    }

    return buf.toString();
  }

  String _classifyStyle(String name) {
    if (name.isEmpty) return "other";
    if (name == name.toUpperCase() && RegExp(r'[A-Z]').hasMatch(name)) return "UPPER_CASE";
    if (name.contains("_")) return "snake_case";
    if (name.contains("-")) return "kebab-case";
    if (name[0] == name[0].toUpperCase() && RegExp(r'[a-z]').hasMatch(name)) return "PascalCase";
    if (name[0] == name[0].toLowerCase() && RegExp(r'[A-Z]').hasMatch(name)) return "camelCase";
    if (name[0] == name[0].toLowerCase()) return "camelCase";
    return "other";
  }

  Future<String> _deadCode(String project) async {
    final defined = <String, List<String>>{}; // name → [files]
    final referenced = <String>{};

    await _walk(project, "", (file, content) {
      final ext = file.split(".").last.toLowerCase();
      if (!["dart", "js", "ts", "jsx", "tsx", "py"].contains(ext)) return;

      // Find function/class/method definitions
      final defPatterns = [
        RegExp(r'(?:function|fun|def)\s+(\w+)', caseSensitive: false),
        RegExp(r'(?:async\s+function)\s+(\w+)', caseSensitive: false),
        RegExp(r'(?:class)\s+(\w+)', caseSensitive: false),
        RegExp(r'(?:const|let|var)\s+(\w+)\s*=\s*(?:async\s+)?\(', caseSensitive: false),
        RegExp(r'(?:static\s+)?(?:async\s+)?(\w+)\s*\(', caseSensitive: false),
      ];
      for (final pat in defPatterns) {
        for (final m in pat.allMatches(content)) {
          final name = m.group(1)!;
          if (name.length < 3 || ["get", "set", "run", "log", "add", "put", "map", "try"].contains(name)) continue;
          defined.putIfAbsent(name, () => []).add(file);
        }
      }

      // Find all references (identifier usage)
      final idents = RegExp(r'\b([a-zA-Z_]\w{2,})\b').allMatches(content);
      for (final m in idents) {
        referenced.add(m.group(1)!);
      }
    });

    // Filter: defined but never referenced elsewhere (or only in own file)
    final dead = <String>[];
    for (final entry in defined.entries) {
      final name = entry.key;
      final files = entry.value;
      if (!referenced.contains(name)) {
        dead.add("$name (defined in ${files.join(", ")})");
      }
    }

    if (dead.isEmpty) return "No obviously dead code found. For thorough analysis, use `analyze_project` or `delegate_task` to scribe.";

    final buf = StringBuffer("## Dead Code Analysis\n\n");
    buf.writeln("Found **${dead.length}** potentially unused identifiers:\n");
    for (final d in dead.take(30)) {
      buf.writeln("- $d");
    }
    if (dead.length > 30) buf.writeln("- ... and ${dead.length - 30} more");
    buf.writeln("\n**Note:** This is a heuristic check. Exported functions, callbacks, and framework entry points may appear as false positives. Verify before removing.");

    return buf.toString();
  }

  // ───────────────────── Schema Tool Methods ─────────────────────

  Future<String> _jsonSchemaGen(String example) async {
    try {
      final parsed = jsonDecode(example);
      final schema = _inferJsonSchema(parsed);
      final buf = StringBuffer("## Generated JSON Schema\n\n");
      buf.writeln(const JsonEncoder.withIndent("  ").convert(schema));
      return buf.toString();
    } catch (e) {
      return "JSON Schema generation failed: $e\nProvide a valid JSON string as the example.";
    }
  }

  Map<String, dynamic> _inferJsonSchema(dynamic value) {
    if (value == null) return {"type": "null"};
    if (value is bool) return {"type": "boolean"};
    if (value is int) return {"type": "integer"};
    if (value is double) return {"type": "number"};
    if (value is String) {
      // Detect common formats
      if (RegExp(r'^\d{4}-\d{2}-\d{2}(T\d{2}:\d{2}:\d{2})?').hasMatch(value)) {
        return {"type": "string", "format": "date-time"};
      }
      if (RegExp(r'^https?://').hasMatch(value)) {
        return {"type": "string", "format": "uri"};
      }
      if (RegExp(r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$').hasMatch(value)) {
        return {"type": "string", "format": "email"};
      }
      return {"type": "string"};
    }
    if (value is List) {
      if (value.isEmpty) return {"type": "array", "items": {}};
      // Infer from first element
      final firstSchema = _inferJsonSchema(value.first);
      // Check if all items have same type
      final allSame = value.every((item) {
        final s = _inferJsonSchema(item);
        return s["type"] == firstSchema["type"];
      });
      return {
        "type": "array",
        "items": allSame ? firstSchema : {"oneOf": value.map((item) => _inferJsonSchema(item)).toList()},
      };
    }
    if (value is Map) {
      final properties = <String, dynamic>{};
      final required = <String>[];
      for (final e in value.entries) {
        properties[e.key] = _inferJsonSchema(e.value);
        required.add(e.key);
      }
      return {
        "type": "object",
        "properties": properties,
        "required": required,
      };
    }
    return {"type": "string"};
  }

  Future<String> _validateOpenApi(String project, String filePath) async {
    try {
      final content = await StorageService.readFile(project, filePath);
      final ext = filePath.split(".").last.toLowerCase();
      Map<String, dynamic> spec;

      if (ext == "json") {
        spec = Map<String, dynamic>.from(jsonDecode(content));
      } else if (ext == "yaml" || ext == "yml") {
        final parsed = _parseYaml(content);
        if (parsed is Map) {
          spec = Map<String, dynamic>.from(parsed);
        } else {
          return "Could not parse YAML OpenAPI file.";
        }
      } else {
        return "Unsupported file type: .$ext. Use .json, .yaml, or .yml";
      }

      final issues = <String>[];
      final buf = StringBuffer("## OpenAPI Validation: $filePath\n\n");

      // Check openapi version
      final openapi = spec["openapi"]?.toString() ?? spec["swagger"]?.toString();
      if (openapi == null) {
        issues.add("Missing 'openapi' or 'swagger' version field");
      } else {
        buf.writeln("- **Version:** $openapi");
      }

      // Check info object
      final info = spec["info"] as Map<String, dynamic>?;
      if (info == null) {
        issues.add("Missing 'info' object (required)");
      } else {
        if (info["title"] == null || ((info["title"] as String?)?.isEmpty ?? true)) {
          issues.add("Missing or empty 'info.title' (required)");
        }
        if (info["version"] == null || ((info["version"] as String?)?.isEmpty ?? true)) {
          issues.add("Missing or empty 'info.version' (required)");
        }
        buf.writeln("- **Title:** ${info["title"] ?? "MISSING"}");
        buf.writeln("- **Version:** ${info["version"] ?? "MISSING"}");
        if (info["description"] != null) buf.writeln("- **Description:** ${info["description"]}");
      }

      // Check paths
      final paths = spec["paths"] as Map<String, dynamic>?;
      if (paths == null || paths.isEmpty) {
        issues.add("Missing or empty 'paths' object");
      } else {
        buf.writeln("- **Paths:** ${paths.length} endpoints");
        var totalOperations = 0;
        for (final pathEntry in paths.entries) {
          final pathObj = pathEntry.value as Map<String, dynamic>? ?? {};
          for (final op in pathObj.entries) {
            if (["get", "post", "put", "patch", "delete", "head", "options"].contains(op.key)) {
              totalOperations++;
              final opObj = op.value as Map<String, dynamic>? ?? {};
              if (opObj["responses"] == null || (opObj["responses"] as Map?)?.isEmpty == true) {
                issues.add("${op.key.toUpperCase()} ${pathEntry.key}: missing 'responses'");
              }
            }
          }
        }
        buf.writeln("- **Operations:** $totalOperations");
      }

      // Check components/schemas
      final components = spec["components"] as Map<String, dynamic>? ?? spec["definitions"] as Map<String, dynamic>?;
      if (components != null) {
        final schemas = components["schemas"] as Map<String, dynamic>? ?? components;
        buf.writeln("- **Schemas:** ${(schemas as Map).length}");
      }

      // Check servers
      final servers = spec["servers"] as List?;
      if (servers != null && servers.isNotEmpty) {
        buf.writeln("- **Servers:** ${servers.map((s) => (s as Map)["url"]).join(", ")}");
      }

      buf.writeln("");
      if (issues.isEmpty) {
        buf.writeln("### Result: VALID\nNo structural issues found.");
      } else {
        buf.writeln("### Issues Found (${issues.length}):\n");
        for (var i = 0; i < issues.length; i++) {
          buf.writeln("${i + 1}. ${issues[i]}");
        }
      }

      return buf.toString();
    } catch (e) {
      return "OpenAPI validation failed: $e";
    }
  }

  String _sslCert(String domain, int days) {
    final buf = StringBuffer("## Self-Signed SSL Certificate\n\n");
    buf.writeln("**Domain:** $domain");
    buf.writeln("**Validity:** $days days\n");
    buf.writeln("### Generate Certificate\n");
    buf.writeln("```bash");
    buf.writeln("# Generate private key + certificate");
    buf.writeln("openssl req -x509 -newkey rsa:4096 -keyout key.pem -out cert.pem -days $days -nodes -subj '/CN=$domain'");
    buf.writeln("");
    buf.writeln("# Verify the certificate");
    buf.writeln("openssl x509 -in cert.pem -text -noout");
    buf.writeln("");
    buf.writeln("# Combine for some servers");
    buf.writeln("cat key.pem cert.pem > fullchain.pem");
    buf.writeln("```\n");
    buf.writeln("### Usage in Node.js\n");
    buf.writeln("```javascript");
    buf.writeln("const https = require('https');");
    buf.writeln("const fs = require('fs');");
    buf.writeln("https.createServer({");
    buf.writeln("  key: fs.readFileSync('key.pem'),");
    buf.writeln("  cert: fs.readFileSync('cert.pem')");
    buf.writeln("}, app).listen(443);");
    buf.writeln("```");
    return buf.toString();
  }

  String _mermaidRender(String diagram, String format) {
    final encoded = base64.encode(utf8.encode(diagram));
    final url = "https://mermaid.ink/$format/$encoded";
    final buf = StringBuffer("## Mermaid Diagram\n\n");
    buf.writeln("![Mermaid Diagram]($url)\n");
    buf.writeln("**Format:** $format");
    buf.writeln("\n### Source\n```mermaid\n$diagram\n```\n");
    buf.writeln("[View in Mermaid Live]($url)");
    buf.writeln("[Open mermaid.live editor](https://mermaid.live/edit#pako:${Uri.encodeComponent(diagram)})");
    return buf.toString();
  }

  String _plantumlRender(String diagram) {
    final encoded = _plantumlEncode(diagram);
    final url = "https://www.plantuml.com/plantuml/svg/$encoded";
    final buf = StringBuffer("## PlantUML Diagram\n\n");
    buf.writeln("![PlantUML Diagram]($url)\n");
    buf.writeln("### Source\n```plantuml\n$diagram\n```\n");
    buf.writeln("[View on PlantUML]($url)");
    buf.writeln("[Open PlantUML Online](http://www.plantuml.com/plantuml/uml/)");

    // Also provide the text-encoded version for copy-paste
    final textUrl = "https://www.plantuml.com/plantuml/txt/$encoded";
    buf.writeln("\n[Raw text output]($textUrl)");
    return buf.toString();
  }

  static String _plantumlEncode(String text) {
    const plantumlAlphabet = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz-_";
    final bytes = utf8.encode(text);
    final deflated = zlib.encode(bytes);
    final result = StringBuffer();
    var i = 0;
    while (i < deflated.length) {
      final b1 = deflated[i];
      final b2 = i + 1 < deflated.length ? deflated[i + 1] : 0;
      final b3 = i + 2 < deflated.length ? deflated[i + 2] : 0;
      result.write(plantumlAlphabet[(b1 >> 2) & 0x3F]);
      result.write(plantumlAlphabet[((b1 & 0x03) << 4) | ((b2 >> 4) & 0x0F)]);
      result.write(plantumlAlphabet[((b2 & 0x0F) << 2) | ((b3 >> 6) & 0x03)]);
      result.write(plantumlAlphabet[b3 & 0x3F]);
      i += 3;
    }
    return result.toString();
  }

  Future<String> _asciiTree(String project, int maxDepth) async {
    final buf = StringBuffer();
    buf.writeln("$project/");

    Future<void> buildTree(String path, String prefix, int depth) async {
      if (depth >= maxDepth) return;
      try {
        final entries = await StorageService.listDir(project, path);
        final sorted = entries.where((e) {
          final name = e.uri.pathSegments.last;
          if (name.startsWith(".") && name != ".gitignore") return false;
          if (name == "node_modules" || name == ".git" || name == "dist" || name == "__pycache__") return false;
          return true;
        }).toList();

        sorted.sort((a, b) {
          final aDir = a is Directory ? 0 : 1;
          final bDir = b is Directory ? 0 : 1;
          if (aDir != bDir) return aDir - bDir;
          return a.uri.pathSegments.last.compareTo(b.uri.pathSegments.last);
        });

        for (var i = 0; i < sorted.length; i++) {
          final entry = sorted[i];
          final name = entry.uri.pathSegments.last;
          final isLast = i == sorted.length - 1;
          final connector = isLast ? "└── " : "├── ";
          final childPrefix = isLast ? "    " : "│   ";

          if (entry is Directory) {
            buf.writeln("$prefix$connector$name/");
            final childPath = path.isEmpty ? name : "$path/$name";
            await buildTree(childPath, "$prefix$childPrefix", depth + 1);
          } else {
            buf.writeln("$prefix$connector$name");
          }
        }
} catch (e) {
          // Skip unreadable entry
        }
      }

    await buildTree("", "", 0);
    return buf.toString();
  }

  Stream<String> sendMessage(String userMessage) async* {
    if (currentMode == AgentMode.auto) {
      final detected = _detectMode(userMessage);
      if (detected != AgentMode.code) {
        currentMode = detected;
        yield "[MODE: ${detected.name.toUpperCase()}]\n";
      }
    }

    messages.add(Message(role: "user", content: userMessage));
    maybeCompress();

    final apiKey = await SettingsService.deepseekApiKey;
    int loopCount = 0;
    const maxLoops = 20;

    while (loopCount < maxLoops) {
      loopCount++;
      if (loopCount >= maxLoops) {
        yield "\n(Max steps reached — task may be incomplete. Try breaking it into smaller steps.)\n";
        break;
      }

      final effectiveModel = ProjectConfigService.current?.model ?? ApiConstants.deepseekModel;
      final body = jsonEncode({
        "model": effectiveModel,
        "messages": messages.map((m) => m.toJson()).toList(),
        "tools": _tools,
        "temperature": currentMode == AgentMode.brainstorm ? 0.7 : 0.2,
        "max_tokens": 4096,
      });

      http.Response? postResponse;
      try {
        postResponse = await http.post(
          Uri.parse(_apiUrl),
          headers: {
            "Content-Type": "application/json",
            "Authorization":
                "Bearer $apiKey",
          },
          body: body,
        ).timeout(const Duration(seconds: 90));
      } catch (e) {
        if (e.toString().contains("SocketException") || e.toString().contains("TimeoutException")) {
          yield "Connection failed: unable to reach API server. Check your internet.";
        } else {
          yield "API request failed: $e";
        }
        return;
      }

      final response = postResponse!;

      if (response.statusCode != 200) {
        final msg = switch (response.statusCode) {
          401 => "Invalid API key. Check your DeepSeek key in Settings.",
          429 => "Rate limited. Wait a moment and try again.",
          503 => "DeepSeek is temporarily unavailable. Try again later.",
          _ => "API Error (${response.statusCode})",
        };
        yield msg;
        return;
      }

      Map<String, dynamic> json;
      try {
        json = jsonDecode(response.body);
      } catch (e) {
        yield "Invalid response from API. Try again.";
        return;
      }

      final choices = json["choices"] as List?;
      if (choices == null || choices.isEmpty) {
        yield "Empty response from API. The model may be overloaded.";
        return;
      }

      final choice = choices[0] as Map<String, dynamic>?;
      if (choice == null) {
        yield "Malformed response from API.";
        return;
      }

      final msg = choice["message"] as Map<String, dynamic>?;
      if (msg == null) {
        yield "No message in API response.";
        return;
      }

      final content = msg["content"];
      if (content is String && content.isNotEmpty) {
        yield content;
      }

      if (msg["tool_calls"] is List && (msg["tool_calls"] as List).isNotEmpty) {
        final toolCalls =
            (msg["tool_calls"] as List).map((tc) {
          return ToolCall(
            id: tc["id"],
            name: tc["function"]["name"],
            arguments: tc["function"]["arguments"],
          );
        }).toList();

        messages.add(Message(
          role: "assistant",
          content: msg["content"] ?? "",
          toolCalls: toolCalls,
        ));

        for (final tc in msg["tool_calls"]) {
          final fn = tc["function"];
          final toolName = fn["name"] as String;

          if (fn["arguments"] is! String) {
            yield "Error: invalid tool arguments";
            continue;
          }

          Map<String, dynamic> toolArgs;
          try {
            toolArgs = Map<String, dynamic>.from(
                jsonDecode(fn["arguments"]));
          } catch (e) {
            toolArgs = {};
          }

          final argsStr = fn["arguments"].toString();
          final preview = argsStr.length > 60
              ? "${argsStr.substring(0, 60)}..."
              : argsStr;
          onToolCall?.call(toolName, preview);

          final result =
              await _executeTool(toolName, toolArgs);

          onToolResult?.call(toolName, preview, result);

          messages.add(Message(
            role: "tool",
            content: result,
            toolCallId: tc["id"],
          ));
        }
        continue;
      }

      messages.add(Message(
          role: "assistant", content: msg["content"] ?? ""));
      break;
    }

    await saveSession();
  }

  /// Wrapper around [sendMessage] that calls onChunk for each yielded chunk.
  /// Exists for compatibility with the mobile UI which uses this signature.
  Future<void> chat(String message, {required void Function(String chunk) onChunk}) async {
    await for (final chunk in sendMessage(message)) {
      onChunk(chunk);
    }
  }

  Future<void> reset() async {
    messages.clear();
    messages.add(Message(
        role: "system",
        content: _buildSystemPrompt(currentMode)));
    if (projectContext != null) {
      await _injectContext();
    }
  }

  static String _tokenCount(String? text) {
    if (text == null || text.isEmpty) return "~0 tokens, 0 chars";
    final wordCount = text.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length;
    final tokenEstimate = (wordCount * 1.3).round();
    final charCount = text.length;
    return "~$tokenEstimate tokens, $charCount chars (${wordCount} words)";
  }

  static String _detectLanguage(String project, String filePath) {
    try {
      final ext = filePath.split(".").last.toLowerCase();
      final extMap = {
        "dart": "Dart", "js": "JavaScript", "ts": "TypeScript", "jsx": "React JSX",
        "tsx": "React TSX", "py": "Python", "rb": "Ruby", "go": "Go", "rs": "Rust",
        "java": "Java", "kt": "Kotlin", "swift": "Swift", "c": "C", "cpp": "C++",
        "h": "C/C++ Header", "hpp": "C++ Header", "cs": "C#", "php": "PHP",
        "scala": "Scala", "r": "R", "m": "Objective-C", "mm": "Objective-C++",
        "vue": "Vue", "svelte": "Svelte", "html": "HTML", "htm": "HTML",
        "css": "CSS", "scss": "SCSS", "sass": "Sass", "less": "Less",
        "json": "JSON", "yaml": "YAML", "yml": "YAML", "toml": "TOML",
        "xml": "XML", "svg": "SVG", "md": "Markdown", "sql": "SQL",
        "sh": "Shell", "bash": "Bash", "zsh": "Zsh", "fish": "Fish",
        "ps1": "PowerShell", "bat": "Batch", "cmd": "Batch",
        "graphql": "GraphQL", "gql": "GraphQL", "proto": "Protobuf",
        "dockerfile": "Dockerfile", "tf": "Terraform", "hcl": "HCL",
        "ex": "Elixir", "exs": "Elixir", "erl": "Erlang",
        "hs": "Haskell", "ml": "OCaml", "clj": "Clojure",
        "lua": "Lua", "pl": "Perl", "pm": "Perl",
      };
      final byExt = extMap[ext];
      if (byExt != null) return "Detected: $byExt (.$ext)";

      final extGuess = extMap[ext];
      if (extGuess != null) return "Detected: $extGuess (.$ext)";

      return "Detected: .$ext (unknown extension)";
    } catch (e) {
      return "Language detection failed: $e";
    }
  }

  static String _graphQlSchemaGen(String? types) {
    try {
      final buf = StringBuffer();
      buf.writeln("# Auto-generated GraphQL Schema");
      buf.writeln("scalar DateTime");
      buf.writeln("scalar JSON");
      buf.writeln();
      final typeList = (types ?? "").split(",").map((t) => t.trim()).where((t) => t.isNotEmpty).toList();
      if (typeList.isEmpty) {
        typeList.addAll(["User", "Post", "Comment"]);
      }
      for (final typeName in typeList) {
        final lower = typeName.toLowerCase();
        buf.writeln("type $typeName {");
        buf.writeln("  id: ID!");
        if (lower.contains("user") || lower.contains("account")) {
          buf.writeln("  username: String!");
          buf.writeln("  email: String!");
          buf.writeln("  displayName: String");
          buf.writeln("  avatarUrl: String");
          buf.writeln("  createdAt: DateTime!");
          buf.writeln("  updatedAt: DateTime!");
        } else if (lower.contains("post") || lower.contains("article") || lower.contains("blog")) {
          buf.writeln("  title: String!");
          buf.writeln("  content: String!");
          buf.writeln("  author: User!");
          buf.writeln("  published: Boolean!");
          buf.writeln("  tags: [String!]");
          buf.writeln("  createdAt: DateTime!");
          buf.writeln("  updatedAt: DateTime!");
        } else if (lower.contains("comment")) {
          buf.writeln("  body: String!");
          buf.writeln("  author: User!");
          buf.writeln("  createdAt: DateTime!");
        } else {
          buf.writeln("  name: String!");
          buf.writeln("  description: String");
          buf.writeln("  createdAt: DateTime!");
          buf.writeln("  updatedAt: DateTime!");
        }
        buf.writeln("}");
        buf.writeln();
      }
      buf.writeln("input Create${typeList.first}Input {");
      for (final field in ["name", "title", "content", "email", "username"]) {
        if (typeList.first.toLowerCase().contains(field.substring(0, math.min(3, field.length)))) {
          buf.writeln("  $field: String!");
        }
      }
      buf.writeln("}");
      buf.writeln();
      buf.writeln("input Update${typeList.first}Input {");
      buf.writeln("  id: ID!");
      for (final field in ["name", "title", "content"]) {
        buf.writeln("  $field: String");
      }
      buf.writeln("}");
      buf.writeln();
      buf.writeln("type Query {");
      for (final t in typeList) {
        final lower = t.toLowerCase();
        buf.writeln("  ${lower}(id: ID!): $t");
        buf.writeln("  ${lower}s(limit: Int, offset: Int): [${t}!]!");
      }
      buf.writeln("}");
      buf.writeln();
      buf.writeln("type Mutation {");
      buf.writeln("  create${typeList.first}(input: Create${typeList.first}Input!): ${typeList.first}!");
      buf.writeln("  update${typeList.first}(input: Update${typeList.first}Input!): ${typeList.first}!");
      buf.writeln("  delete${typeList.first}(id: ID!): Boolean!");
      buf.writeln("}");
      return buf.toString();
    } catch (e) { return "GraphQL schema generation failed: $e"; }
  }

  static String _protoGen(String service, String messages) {
    try {
      final buf = StringBuffer();
      buf.writeln('syntax = "proto3";');
      buf.writeln('package ${service.toLowerCase().replaceAll(RegExp(r'[^a-z0-9_]'), '_')};');
      buf.writeln();
      buf.writeln("message Request {");
      buf.writeln("  string id = 1;");
      buf.writeln("  string method = 2;");
      buf.writeln("  bytes payload = 3;");
      buf.writeln("  map<string, string> metadata = 4;");
      buf.writeln("}");
      buf.writeln();
      buf.writeln("message Response {");
      buf.writeln("  int32 status = 1;");
      buf.writeln("  bytes body = 2;");
      buf.writeln("  map<string, string> headers = 3;");
      buf.writeln("}");
      buf.writeln();
      buf.writeln("message ErrorResponse {");
      buf.writeln("  int32 code = 1;");
      buf.writeln("  string message = 2;");
      buf.writeln("  string details = 3;");
      buf.writeln("}");
      buf.writeln();
      final msgList = messages.split(",").map((m) => m.trim()).where((m) => m.isNotEmpty).toList();
      for (final msgName in msgList) {
        final lower = msgName.toLowerCase();
        buf.writeln("message $msgName {");
        if (lower.contains("user") || lower.contains("account")) {
          buf.writeln("  string id = 1;");
          buf.writeln("  string username = 2;");
          buf.writeln("  string email = 3;");
          buf.writeln("  string display_name = 4;");
          buf.writeln("  int64 created_at = 5;");
        } else if (lower.contains("post") || lower.contains("article")) {
          buf.writeln("  string id = 1;");
          buf.writeln("  string title = 2;");
          buf.writeln("  string content = 3;");
          buf.writeln("  string author_id = 4;");
          buf.writeln("  bool published = 5;");
          buf.writeln("  repeated string tags = 6;");
        } else {
          buf.writeln("  string id = 1;");
          buf.writeln("  string name = 2;");
          buf.writeln("  string description = 3;");
          buf.writeln("  int64 created_at = 4;");
        }
        buf.writeln("}");
        buf.writeln();
      }
      buf.writeln("service $service {");
      buf.writeln("  rpc Get(Request) returns (Response);");
      buf.writeln("  rpc List(Request) returns (Response);");
      buf.writeln("  rpc Create(Request) returns (Response);");
      buf.writeln("  rpc Update(Request) returns (Response);");
      buf.writeln("  rpc Delete(Request) returns (Response);");
      buf.writeln("}");
      return buf.toString();
    } catch (e) { return "Proto generation failed: $e"; }
  }

  Future<String> _detectConflicts(String project) async {
    try {
      final buf = StringBuffer();
      await _walk(project, "", (file, content) {
        final lines = content.split("\n");
        final conflicts = <Map<String, String>>[];
        for (var i = 0; i < lines.length; i++) {
          if (lines[i].trimLeft().startsWith("<<<<<<<")) {
            final startLine = i;
            var endLine = i;
            var dividerLine = i;
            var endMarker = i;
            for (var j = i + 1; j < lines.length; j++) {
              if (lines[j].trimLeft().startsWith("=======")) {
                dividerLine = j;
              }
              if (lines[j].trimLeft().startsWith(">>>>>>>")) {
                endMarker = j;
                endLine = j;
                break;
              }
            }
            if (dividerLine > i && endMarker > dividerLine) {
              conflicts.add({
                "conflict": lines.sublist(startLine, endMarker + 1).join("\n"),
                "range": "lines ${startLine + 1}-${endMarker + 1}",
              });
              i = endMarker;
            }
          }
        }
        if (conflicts.isNotEmpty) {
          buf.writeln("=== $file (${conflicts.length} conflict${conflicts.length > 1 ? 's' : ''}) ===");
          for (final c in conflicts) {
            buf.writeln("  ${c["range"]}:");
            buf.writeln(c["conflict"]);
            buf.writeln();
          }
        }
      });
      final result = buf.toString().trim();
      return result.isEmpty ? "No merge conflict markers found in project files." : "Conflict markers found:\n$result";
    } catch (e) { return "Conflict detection failed: $e"; }
  }

  Future<String> _selfReview(String project) async {
    try {
      final buf = StringBuffer();
      final diffResult = await _runShellCommand(project, "git diff HEAD 2>nul || git diff");
      if (diffResult.contains("Command failed") || diffResult.isEmpty || diffResult.trim() == "(completed, no output)") {
        final stagedDiff = await _runShellCommand(project, "git diff --cached 2>nul || git diff --staged");
        if (stagedDiff.contains("Command failed") || stagedDiff.isEmpty || stagedDiff.trim() == "(completed, no output)") {
          return "No uncommitted changes to review. Make some changes first.";
        }
        buf.writeln("## Staged Changes Review\n");
        buf.writeln(_formatDiffForReview(stagedDiff));
      } else {
        buf.writeln("## Uncommitted Changes Review\n");
        buf.writeln(_formatDiffForReview(diffResult));
      }
      return buf.toString();
    } catch (e) { return "Self-review failed: $e"; }
  }

  String _formatDiffForReview(String diff) {
    final buf = StringBuffer();
    final lines = diff.split("\n");
    var additions = 0;
    var deletions = 0;
    var filesChanged = <String>[];
    String? currentFile;
    for (final line in lines) {
      if (line.startsWith("diff --git")) {
        final match = RegExp(r'b/(.+)$').firstMatch(line);
        currentFile = match?.group(1) ?? "unknown";
        filesChanged.add(currentFile);
      } else if (line.startsWith("+") && !line.startsWith("+++")) {
        additions++;
      } else if (line.startsWith("-") && !line.startsWith("---")) {
        deletions++;
      }
    }
    buf.writeln("Files changed: ${filesChanged.length}");
    buf.writeln("Additions: +$additions, Deletions: -$deletions");
    buf.writeln();
    for (final file in filesChanged) {
      buf.writeln("  - $file");
    }
    buf.writeln();
    if (additions > 0 && deletions == 0) {
      buf.writeln("📝 Note: Only additions detected. Ensure new code has tests.");
    } else if (deletions > additions * 2) {
      buf.writeln("⚠️  Note: Heavy deletions. Ensure removed code was truly dead.");
    } else if (additions > 200) {
      buf.writeln("📝 Note: Large change ($additions additions). Consider splitting into smaller PRs.");
    }
    return buf.toString();
  }

  Future<String> _dailyStandup(String project) async {
    try {
      final log = await _runShellCommand(project, 'git log --oneline --since="24 hours ago" --format="%s|%h|%ai" 2>nul || git log --oneline -30 --format="%s|%h|%ai"');
      if (log.contains("Command failed") || log.trim().isEmpty || log.trim() == "(completed, no output)") {
        return "No recent commits found in the last 24 hours. Try: git log --oneline -20";
      }
      final buf = StringBuffer("## Daily Standup Report\n\n");
      final features = <String>[];
      final fixes = <String>[];
      final chores = <String>[];
      final docs = <String>[];
      final refactors = <String>[];
      final other = <String>[];
      final lines = log.split("\n").where((l) => l.trim().isNotEmpty).toList();
      for (final line in lines) {
        final parts = line.split("|");
        final msg = parts.isNotEmpty ? parts[0].trim() : line.trim();
        final hash = parts.length > 1 ? parts[1].trim() : "";
        final date = parts.length > 2 ? parts[2].trim().substring(0, math.min(10, parts[2].trim().length)) : "";
        final entry = hash.isNotEmpty ? "$msg ($hash)" : msg;
        final lower = msg.toLowerCase();
        if (lower.startsWith("feat") || lower.startsWith("add") || lower.startsWith("implement") || lower.startsWith("new")) {
          features.add(date.isNotEmpty ? "[$date] $entry" : entry);
        } else if (lower.startsWith("fix") || lower.startsWith("bug") || lower.startsWith("patch") || lower.startsWith("resolve")) {
          fixes.add(date.isNotEmpty ? "[$date] $entry" : entry);
        } else if (lower.startsWith("docs") || lower.startsWith("doc") || lower.startsWith("readme")) {
          docs.add(date.isNotEmpty ? "[$date] $entry" : entry);
        } else if (lower.startsWith("refactor") || lower.startsWith("clean") || lower.startsWith("simplify")) {
          refactors.add(date.isNotEmpty ? "[$date] $entry" : entry);
        } else if (lower.startsWith("chore") || lower.startsWith("ci") || lower.startsWith("build") || lower.startsWith("test") || lower.startsWith("style")) {
          chores.add(date.isNotEmpty ? "[$date] $entry" : entry);
        } else {
          other.add(date.isNotEmpty ? "[$date] $entry" : entry);
        }
      }
      buf.writeln("**${lines.length}** commits in the last period\n");
      if (features.isNotEmpty) {
        buf.writeln("### Features (${features.length})");
        for (final f in features) buf.writeln("  - $f");
        buf.writeln();
      }
      if (fixes.isNotEmpty) {
        buf.writeln("### Fixes (${fixes.length})");
        for (final f in fixes) buf.writeln("  - $f");
        buf.writeln();
      }
      if (refactors.isNotEmpty) {
        buf.writeln("### Refactors (${refactors.length})");
        for (final f in refactors) buf.writeln("  - $f");
        buf.writeln();
      }
      if (docs.isNotEmpty) {
        buf.writeln("### Documentation (${docs.length})");
        for (final d in docs) buf.writeln("  - $d");
        buf.writeln();
      }
      if (chores.isNotEmpty) {
        buf.writeln("### Chores/CI (${chores.length})");
        for (final c in chores) buf.writeln("  - $c");
        buf.writeln();
      }
      if (other.isNotEmpty) {
        buf.writeln("### Other (${other.length})");
        for (final o in other) buf.writeln("  - $o");
        buf.writeln();
      }
      if (features.isEmpty && fixes.isEmpty && chores.isEmpty && docs.isEmpty && refactors.isEmpty && other.isEmpty) {
        buf.writeln("No commits found.");
      }
      return buf.toString();
    } catch (e) { return "Standup generation failed: $e"; }
  }
}
