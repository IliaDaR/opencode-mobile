import "dart:io";
import "package:sqflite/sqflite.dart";
import "package:path/path.dart" as p;
import "storage_service.dart";

/// SQL database tools — run queries against project databases using sqflite (pure Dart)
class SqlService {
  static final Map<String, Database> _openDbs = {};

  /// Try to detect database files in the project
  static Future<String> detectDatabases(String project) async {
    final dbs = <String>[];
    try {
      final entries = await StorageService.listDir(project);
      for (final e in entries) {
        final name = e.uri.pathSegments.last;
        if (name.endsWith(".db") ||
            name.endsWith(".sqlite") ||
            name.endsWith(".sqlite3")) {
          dbs.add(name);
        }
      }
      return dbs.isEmpty
          ? "No SQLite databases found"
          : "Databases found: ${dbs.join(", ")}";
    } catch (e) {
      return "Error scanning: $e";
    }
  }

  static Future<Database> _getDb(String project, String dbFile) async {
    final key = "$project/$dbFile";
    if (_openDbs.containsKey(key)) return _openDbs[key]!;

    final dbPath = p.join(StorageService.projectsRoot.path, project, dbFile);
    if (!await File(dbPath).exists()) {
      throw Exception("Database not found: $dbFile");
    }

    final db = await openDatabase(dbPath, readOnly: true);
    _openDbs[key] = db;
    return db;
  }

  /// Run SQLite query using sqflite
  static Future<String> runQuery(
      String project, String dbFile, String query) async {
    try {
      final db = await _getDb(project, dbFile);

      // Handle special SQLite commands
      final lowerQuery = query.trim().toLowerCase();
      if (lowerQuery == ".tables") {
        final tables = await db.rawQuery(
            "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'");
        return tables.map((t) => t["name"] as String).join("  ");
      }
      if (lowerQuery.startsWith(".schema")) {
        final tableName = lowerQuery.replaceFirst(".schema", "").trim();
        if (tableName.isEmpty) {
          final schemas = await db.rawQuery(
              "SELECT sql FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'");
          return schemas.map((s) => s["sql"] as String).join(";\n\n");
        }
        final schema = await db.rawQuery(
            "SELECT sql FROM sqlite_master WHERE type='table' AND name = ?",
            [tableName]);
        return schema.isNotEmpty ? schema.first["sql"] as String : "Table not found";
      }

      // Regular SELECT / PRAGMA queries
      final results = await db.rawQuery(query);

      if (results.isEmpty) return "(empty result)";

      // Format as table
      final columns = results.first.keys.toList();
      final colWidths = <String, int>{};
      for (final c in columns) {
        colWidths[c] = c.length;
      }
      for (final row in results) {
        for (final c in columns) {
          final v = row[c]?.toString() ?? "NULL";
          if (v.length > colWidths[c]!) colWidths[c] = v.length;
        }
      }

      final buf = StringBuffer();
      // Header
      buf.writeln(columns.map((c) => c.padRight(colWidths[c]!)).join(" | "));
      buf.writeln(columns.map((c) => "-" * colWidths[c]!).join("-+-"));
      // Rows
      for (final row in results) {
        buf.writeln(columns
            .map((c) => (row[c]?.toString() ?? "NULL").padRight(colWidths[c]!))
            .join(" | "));
      }
      return buf.toString();
    } catch (e) {
      return "Query failed: $e";
    }
  }

  /// Show database schema
  static Future<String> showSchema(
      String project, String dbFile) async {
    return runQuery(project, dbFile, ".schema");
  }

  /// Close database (call when done with project)
  static Future<void> closeDb(String project, String dbFile) async {
    final key = "$project/$dbFile";
    final db = _openDbs.remove(key);
    if (db != null) await db.close();
  }

  /// Close all open databases
  static Future<void> closeAll() async {
    for (final db in _openDbs.values) {
      await db.close();
    }
    _openDbs.clear();
  }

  /// Generate SQL from natural language
  static String generateSQLQuery(
      String description,
      List<Map<String, String>> tables) {
    final buffer = StringBuffer();
    buffer.writeln("## Schema Context");
    for (final t in tables) {
      buffer.writeln("Table: ${t["name"]}");
      buffer.writeln("  Columns: ${t["columns"]}");
      buffer.writeln();
    }
    buffer.writeln("## Task");
    buffer.writeln("Write an SQL query to: $description");
    buffer.writeln();
    buffer.writeln("Respond with the SQL query in a code block.");

    return buffer.toString();
  }
}