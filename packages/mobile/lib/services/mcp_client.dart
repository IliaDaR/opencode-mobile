import "dart:async";
import "dart:convert";
import "dart:io";
import "package:http/http.dart" as http;

/// MCP (Model Context Protocol) client in pure Dart
/// Communicates with MCP servers via JSON-RPC over HTTP or stdio
/// Works with any MCP-compatible server — no Node.js/npx needed
class McpClient {
  final String serverUrl;
  final Map<String, String>? headers;
  int _requestId = 0;

  McpClient({required this.serverUrl, this.headers});

  Future<Map<String, dynamic>> _rpc(
      String method, Map<String, dynamic>? params) async {
    final id = ++_requestId;
    final body = jsonEncode({
      "jsonrpc": "2.0",
      "id": id,
      "method": method,
      if (params != null) "params": params,
    });

    final uri = Uri.parse(serverUrl);
    final response = await http.post(uri,
        headers: {
          "Content-Type": "application/json",
          ...?headers,
        },
        body: body);

    if (response.statusCode == 200) {
      final result = jsonDecode(response.body);
      if (result["error"] != null) {
        throw Exception("MCP: ${result["error"]["message"]}");
      }
      return result["result"] ?? {};
    }
    throw Exception("MCP HTTP ${response.statusCode}");
  }

  /// Initialize connection to MCP server
  Future<Map<String, dynamic>> initialize() async {
    return await _rpc("initialize", {
      "protocolVersion": "2024-11-05",
      "capabilities": {},
      "clientInfo": {
        "name": "OpenCode-Mobile",
        "version": "1.0.0"
      },
    });
  }

  /// List available tools from the MCP server
  Future<List<Map<String, dynamic>>> listTools() async {
    final result = await _rpc("tools/list", null);
    final tools = result["tools"] as List? ?? [];
    return tools.cast<Map<String, dynamic>>();
  }

  /// Call a tool on the MCP server
  Future<Map<String, dynamic>> callTool(
      String name, Map<String, dynamic> arguments) async {
    return await _rpc("tools/call", {
      "name": name,
      "arguments": arguments,
    });
  }

  /// Quickly connect to a well-known MCP server and call a tool
  static Future<String> quickCall({
    required String url,
    required String tool,
    required Map<String, dynamic> args,
    Map<String, String>? headers,
  }) async {
    try {
      final client = McpClient(serverUrl: url, headers: headers);
      await client.initialize();
      final result = await client.callTool(tool, args);
      return const JsonEncoder.withIndent("  ").convert(result);
    } catch (e) {
      return "MCP call failed: $e";
    }
  }
}

/// MCP client using stdio transport (spawns a process and communicates over stdin/stdout)
/// Used for local MCP servers like the OpenCode MCP server running as a Dart/Node process
class StdioMcpClient {
  Process? _process;
  int _requestId = 0;
  final Map<int, Completer<Map<String, dynamic>>> _pending = {};
  String _buffer = "";

  /// Start the MCP server process
  Future<bool> start(String command, {List<String>? args, Map<String, String>? env}) async {
    await stop();
    try {
      _process = await Process.start(command, args ?? [],
          environment: env,
          mode: ProcessStartMode.normal);

      _process!.stdout.transform(utf8.decoder).listen(_onData);
      _process!.stderr.transform(utf8.decoder).listen((data) {
        // stderr from MCP servers often contains debug logs — ignore for now
      });

      return true;
    } catch (e) {
      return false;
    }
  }

  void _onData(String data) {
    _buffer += data;
    // Parse Content-Length headers
    while (_buffer.isNotEmpty) {
      final headerEnd = _buffer.indexOf("\r\n\r\n");
      if (headerEnd == -1) return;
      final header = _buffer.substring(0, headerEnd);
      final lengthMatch = RegExp(r'Content-Length:\s*(\d+)').firstMatch(header);
      if (lengthMatch == null) {
        _buffer = _buffer.substring(headerEnd + 4);
        continue;
      }
      final contentLength = int.parse(lengthMatch.group(1)!);
      final bodyStart = headerEnd + 4;
      if (_buffer.length < bodyStart + contentLength) return;
      final body = _buffer.substring(bodyStart, bodyStart + contentLength);
      _buffer = _buffer.substring(bodyStart + contentLength);
      try {
        final json = jsonDecode(body) as Map<String, dynamic>;
        if (json.containsKey("id")) {
          final id = json["id"] as int;
          final completer = _pending.remove(id);
          completer?.complete(json["result"] as Map<String, dynamic>? ?? {});
        }
      } catch (_) {}
    }
  }

  Future<Map<String, dynamic>> _send(String method, Map<String, dynamic>? params) async {
    if (_process == null) throw Exception("MCP stdio: not connected");
    final id = ++_requestId;
    final completer = Completer<Map<String, dynamic>>();
    _pending[id] = completer;
    final body = jsonEncode({
      "jsonrpc": "2.0",
      "id": id,
      "method": method,
      if (params != null) "params": params,
    });
    final header = "Content-Length: ${utf8.encode(body).length}\r\n\r\n";
    _process!.stdin.write("$header$body");
    return await completer.future.timeout(const Duration(seconds: 30));
  }

  Future<Map<String, dynamic>> initialize() async {
    return await _send("initialize", {
      "protocolVersion": "2024-11-05",
      "capabilities": {},
      "clientInfo": {"name": "OpenCode-Mobile", "version": "1.0.0"},
    });
  }

  Future<List<Map<String, dynamic>>> listTools() async {
    final result = await _send("tools/list", null);
    return (result["tools"] as List?)?.cast<Map<String, dynamic>>() ?? [];
  }

  Future<Map<String, dynamic>> listResources() async {
    return await _send("resources/list", null);
  }

  Future<Map<String, dynamic>> readResource(String uri) async {
    return await _send("resources/read", {"uri": uri});
  }

  Future<Map<String, dynamic>> callTool(String name, Map<String, dynamic> args) async {
    return await _send("tools/call", {"name": name, "arguments": args});
  }

  Future<void> stop() async {
    _pending.clear();
    _buffer = "";
    if (_process != null) {
      try { _process!.kill(); } catch (_) {}
      _process = null;
    }
  }
}

/// Manager for MCP server connections — handles both HTTP and stdio transports
class McpManager {
  static final Map<String, dynamic> _servers = {};

  /// Register and connect to an MCP server from project config
  static Future<String> connectFromConfig(Map<String, dynamic> config) async {
    final name = config["name"] as String? ?? "mcp";
    final type = config["type"] as String? ?? "http";

    try {
      if (type == "stdio") {
        final cmd = config["command"] as String?;
        if (cmd == null) return "MCP '$name': no command specified";
        final client = StdioMcpClient();
        final started = await client.start(cmd,
            args: (config["args"] as List?)?.cast<String>(),
            env: (config["environment"] as Map<String, String>?));
        if (!started) return "MCP '$name': failed to start process";
        await client.initialize();
        _servers[name] = client;
        return "MCP '$name' connected (stdio)";
      } else {
        final url = config["url"] as String?;
        if (url == null) return "MCP '$name': no URL specified";
        final client = McpClient(serverUrl: url);
        await client.initialize();
        _servers[name] = client;
        return "MCP '$name' connected (HTTP)";
      }
    } catch (e) {
      return "MCP '$name' error: $e";
    }
  }

  /// Call a tool on a registered MCP server
  static Future<String> call(String serverName, String tool, Map<String, dynamic> args) async {
    final client = _servers[serverName];
    if (client == null) return "MCP server '$serverName' not connected";
    try {
      if (client is StdioMcpClient) {
        final result = await client.callTool(tool, args);
        return const JsonEncoder.withIndent("  ").convert(result);
      } else if (client is McpClient) {
        final result = await client.callTool(tool, args);
        return const JsonEncoder.withIndent("  ").convert(result);
      }
      return "Unknown client type";
    } catch (e) {
      return "MCP tool call failed: $e";
    }
  }

  /// List all registered servers
  static List<String> listServers() => _servers.keys.toList();

  /// Disconnect all servers
  static Future<void> disconnectAll() async {
    for (final entry in _servers.entries) {
      if (entry.value is StdioMcpClient) {
        await (entry.value as StdioMcpClient).stop();
      }
    }
    _servers.clear();
  }
}
