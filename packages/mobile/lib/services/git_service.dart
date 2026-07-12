import "dart:convert";
import "dart:io";
import "package:crypto/crypto.dart";
import "package:path/path.dart" as p;
import "storage_service.dart";

class GitService {
  static String _gitDir(String project) {
    return p.join(StorageService.projectDir(project).path, ".git");
  }

  static String _gitFile(String project, String sub) {
    return p.join(_gitDir(project), sub);
  }

  static String _hash(String type, List<int> content) {
    final header = utf8.encode("$type ${content.length}\0");
    return sha1.convert([...header, ...content]).toString();
  }

  static List<int> _compress(List<int> data) => ZLibCodec().encode(data);
  static List<int> _decompress(List<int> data) => ZLibCodec().decode(data);

  static (String, List<int>) _parseObject(List<int> raw) {
    final nullByte = raw.indexOf(0);
    final header = utf8.decode(raw.sublist(0, nullByte));
    final parts = header.split(" ");
    return (parts[0], raw.sublist(nullByte + 1));
  }

  static List<int> _readRawObject(String project, String sha) {
    final path = _gitFile(project, "objects/${sha.substring(0, 2)}/${sha.substring(2)}");
    return _decompress(File(path).readAsBytesSync());
  }

  static String _storeObject(String project, String type, List<int> content) {
    final sha = _hash(type, content);
    final dir = _gitFile(project, "objects/${sha.substring(0, 2)}");
    final file = File("$dir/${sha.substring(2)}");
    if (!file.existsSync()) {
      Directory(dir).createSync(recursive: true);
      final header = utf8.encode("$type ${content.length}\0");
      file.writeAsBytesSync(_compress([...header, ...content]));
    }
    return sha;
  }

  static String _readFile(String path) {
    final f = File(path);
    return f.existsSync() ? f.readAsStringSync().trim() : "";
  }

  static void _writeFile(String path, String content) {
    final f = File(path);
    f.parent.createSync(recursive: true);
    f.writeAsStringSync(content);
  }

  static String _readHead(String project) {
    return _readFile(_gitFile(project, "HEAD"));
  }

  static String _currentRef(String project) {
    final head = _readHead(project);
    if (head.startsWith("ref: ")) return head.substring(5);
    return "";
  }

  static String _currentSha(String project) {
    final ref = _currentRef(project);
    if (ref.isEmpty) return "";
    return _readFile(_gitFile(project, ref));
  }

  static void _updateRef(String project, String ref, String sha) {
    _writeFile(_gitFile(project, ref), "$sha\n");
  }

  static List<File> _allFiles(String project) {
    final dir = StorageService.projectDir(project);
    if (!dir.existsSync()) return [];
    return dir.listSync(recursive: true).whereType<File>().where((f) {
      final rel = p.relative(f.path, from: dir.path);
      return !rel.startsWith(".git") && !rel.contains("\\.git") && !p.basename(rel).startsWith(".");
    }).toList();
  }

  static String _buildTree(String project, List<File> files) {
    final projPath = StorageService.projectDir(project).path;
    final entries = <List<int>>[];

    for (final f in files) {
      final rel = p.relative(f.path, from: projPath).replaceAll("\\", "/");
      final content = f.readAsBytesSync();
      final blobSha = _storeObject(project, "blob", content);
      final mode = "100644";
      final nameBytes = utf8.encode(rel);
      final shaBytes = List.generate(20,
          (i) => int.parse(blobSha.substring(i * 2, i * 2 + 2), radix: 16));
      entries.add([...mode.codeUnits, 0x20, ...nameBytes, 0, ...shaBytes]);
    }

    return _storeObject(project, "tree", entries.expand((e) => e).toList());
  }

  static Future<String> init(String project) async {
    final gd = _gitDir(project);
    Directory(gd).createSync(recursive: true);
    Directory("$gd/objects").createSync();
    Directory("$gd/refs/heads").createSync();
    _writeFile("$gd/HEAD", "ref: refs/heads/main\n");
    return "Git repo initialized";
  }

  static Future<bool> isRepo(String project) async {
    return File(_gitFile(project, "HEAD")).existsSync();
  }

  static Future<String> add(String project, String filePath) async {
    if (!await isRepo(project)) await init(project);
    final f = File(p.join(StorageService.projectDir(project).path, filePath));
    if (!f.existsSync()) return "File not found: $filePath";
    _storeObject(project, "blob", f.readAsBytesSync());

    final stagingFile = _gitFile(project, "staging.json");
    final staging = File(stagingFile).existsSync()
        ? jsonDecode(_readFile(stagingFile)) as Map<String, dynamic>
        : <String, dynamic>{};
    staging[filePath] = sha1.convert(f.readAsBytesSync()).toString();
    _writeFile(stagingFile, jsonEncode(staging));

    return "Staged: $filePath";
  }

  static Future<String> commit(String project, String message) async {
    if (!await isRepo(project)) await init(project);

    final files = _allFiles(project);
    if (files.isEmpty) return "No files to commit";

    final treeSha = _buildTree(project, files);
    final parentSha = _currentSha(project);
    final author = "OpenCode Mobile <mobile@opencode.ai>";
    final now = DateTime.now().toUtc();
    final ts = now.millisecondsSinceEpoch ~/ 1000;
    final tz = "+0000";

    final sb = StringBuffer();
    sb.writeln("tree $treeSha");
    if (parentSha.isNotEmpty) sb.writeln("parent $parentSha");
    sb.writeln("author $author $ts $tz");
    sb.writeln("committer $author $ts $tz");
    sb.writeln("");
    sb.write(message);

    final commitSha = _storeObject(project, "commit", utf8.encode(sb.toString()));
    final ref = _currentRef(project);
    if (ref.isNotEmpty) _updateRef(project, ref, commitSha);

    if (File(_gitFile(project, "staging.json")).existsSync()) {
      _writeFile(_gitFile(project, "staging.json"), "{}");
    }

    return "Committed: $commitSha";
  }

  static Future<String> commitAndPush(String project, String message) async {
    final result = await commit(project, message);
    return "$result (push not available on mobile)";
  }

  static Future<String> getStatus(String project) async {
    if (!await File(_gitFile(project, "HEAD")).existsSync()) {
      return "Not a git repo. Run /git-init first.";
    }

    final sb = StringBuffer();
    final headSha = _currentSha(project);

    if (headSha.isEmpty) {
      sb.writeln("No commits yet");
      final files = _allFiles(project);
      if (files.isNotEmpty) {
        sb.writeln("\nUntracked files:");
        final projPath = StorageService.projectDir(project).path;
        for (final f in files) {
          sb.writeln("  ${p.relative(f.path, from: projPath)}");
        }
      }
      return sb.toString();
    }

    final headObj = _readRawObject(project, headSha);
    final (_, commitContent) = _parseObject(headObj);
    final commitText = utf8.decode(commitContent);
    final treeLine = commitText.split("\n").firstWhere((l) => l.startsWith("tree "));
    final headTreeSha = treeLine.substring(5).trim();

    final treeObj = _readRawObject(project, headTreeSha);
    final (_, treeContent) = _parseObject(treeObj);
    final trackedFiles = <String>{};
    var i = 0;
    while (i < treeContent.length) {
      final modeEnd = treeContent.indexOf(0x20, i);
      final nameEnd = treeContent.indexOf(0, modeEnd + 1);
      final name = utf8.decode(treeContent.sublist(modeEnd + 1, nameEnd));
      trackedFiles.add(name);
      i = nameEnd + 21;
    }

    final projPath = StorageService.projectDir(project).path;
    final currentFiles = _allFiles(project).map((f) =>
        p.relative(f.path, from: projPath).replaceAll("\\", "/")).toSet();

    final newFiles = currentFiles.difference(trackedFiles);
    final deleted = trackedFiles.difference(currentFiles);

    if (newFiles.isEmpty && deleted.isEmpty) {
      sb.writeln("Working tree clean");
    } else {
      if (newFiles.isNotEmpty) {
        sb.writeln("\nNew files:");
        for (final f in newFiles) sb.writeln("  $f");
      }
      if (deleted.isNotEmpty) {
        sb.writeln("\nDeleted:");
        for (final f in deleted) sb.writeln("  $f");
      }
    }

    final headShort = headSha.length > 7 ? headSha.substring(0, 7) : headSha;
    sb.writeln("\nHEAD at $headShort");
    return sb.toString();
  }

  static Future<String> getLog(String project, {int limit = 10}) async {
    if (!await File(_gitFile(project, "HEAD")).existsSync()) {
      return "Not a git repo";
    }

    final sb = StringBuffer();
    var sha = _currentSha(project);
    var count = 0;

    while (sha.isNotEmpty && count < limit) {
      final raw = _readRawObject(project, sha);
      final (type, content) = _parseObject(raw);
      if (type != "commit") break;

      final text = utf8.decode(content);
      final lines = text.split("\n");
      final msgStart = text.indexOf("\n\n");
      final msg = msgStart >= 0 ? text.substring(msgStart + 2).trim() : "";
      final short = sha.length > 7 ? sha.substring(0, 7) : sha;

      String author = "";
      for (final line in lines) {
        if (line.startsWith("author ")) {
          author = line.substring(7);
          break;
        }
      }

      sb.writeln("commit $short");
      if (author.isNotEmpty) sb.writeln("Author: $author");
      if (msg.isNotEmpty) {
        for (final mLine in msg.split("\n")) {
          sb.writeln("    $mLine");
        }
      }
      sb.writeln("");

      final parentLine = lines.where((l) => l.startsWith("parent ")).firstOrNull;
      sha = parentLine != null ? parentLine.substring(7).trim() : "";
      count++;
    }

    return sb.toString();
  }

  static Future<String> getLogRaw(String project, {int limit = 50}) async {
    return await getLog(project, limit: limit);
  }

  static Future<String> branch(String project, String action, [String? name]) async {
    if (!await isRepo(project)) await init(project);
    final headsDir = _gitFile(project, "refs/heads");
    final currentRef = _currentRef(project);

    switch (action) {
      case "list":
        final sb = StringBuffer();
        final dir = Directory(headsDir);
        if (!dir.existsSync()) return "No branches";
        for (final f in dir.listSync().whereType<File>()) {
          final branchName = p.basename(f.path);
          final marker = "refs/heads/$branchName" == currentRef ? "* " : "  ";
          sb.writeln("$marker$branchName");
        }
        return sb.toString();
      case "create":
        if (name == null || name.isEmpty) return "Branch name required";
        final sha = _currentSha(project);
        if (sha.isEmpty) return "No commits to branch from";
        _writeFile("$headsDir/$name", "$sha\n");
        return "Created branch: $name";
      case "switch":
        if (name == null || name.isEmpty) return "Branch name required";
        final branchFile = "$headsDir/$name";
        if (!File(branchFile).existsSync()) return "Branch not found: $name";
        _writeFile(_gitFile(project, "HEAD"), "ref: refs/heads/$name\n");
        return "Switched to: $name";
      default:
        return "Unknown action: $action";
    }
  }

  static Future<String> diff(String project, [String? filePath]) async {
    if (!await File(_gitFile(project, "HEAD")).existsSync()) {
      return "Not a git repo";
    }

    final projPath = StorageService.projectDir(project).path;
    final headSha = _currentSha(project);
    if (headSha.isEmpty) return "No commits";

    final raw = _readRawObject(project, headSha);
    final (_, commitContent) = _parseObject(raw);
    final commitText = utf8.decode(commitContent);
    final treeLine = commitText.split("\n").firstWhere((l) => l.startsWith("tree "));
    final treeSha = treeLine.substring(5).trim();

    final treeRaw = _readRawObject(project, treeSha);
    final (_, treeContent) = _parseObject(treeRaw);
    final committed = <String, List<int>>{};
    var i = 0;
    while (i < treeContent.length) {
      final modeEnd = treeContent.indexOf(0x20, i);
      final nameEnd = treeContent.indexOf(0, modeEnd + 1);
      final name = utf8.decode(treeContent.sublist(modeEnd + 1, nameEnd));
      final shaBytes = treeContent.sublist(nameEnd + 1, nameEnd + 21);
      final hexSha = shaBytes.map((b) => b.toRadixString(16).padLeft(2, "0")).join();
      committed[name] = hexSha.codeUnits;
      i = nameEnd + 21;
    }

    final sb = StringBuffer();
    for (final f in _allFiles(project)) {
      final rel = p.relative(f.path, from: projPath).replaceAll("\\", "/");
      if (filePath != null && rel != filePath) continue;
      if (!committed.containsKey(rel)) {
        sb.writeln("--- /dev/null");
        sb.writeln("+++ b/$rel");
        sb.writeln("@@ -0,0 +1,@@");
        sb.writeln("+New file");
        continue;
      }
      final currentContent = utf8.decode(f.readAsBytesSync());
      final blobSha = committed[rel]!;
      final blobShaStr = String.fromCharCodes(blobSha);
      final committedObj = _readRawObject(project, blobShaStr);
      final (_, committedContent) = _parseObject(committedObj);
      final committedText = utf8.decode(committedContent);

      if (currentContent != committedText) {
        sb.writeln("--- a/$rel");
        sb.writeln("+++ b/$rel");
        sb.writeln("@@ -modified@@");
        final clines = committedText.split("\n");
        final nlines = currentContent.split("\n");
        for (var li = 0; li < nlines.length && li < clines.length; li++) {
          if (clines[li] != nlines[li]) {
            sb.writeln("-${clines[li]}");
            sb.writeln("+${nlines[li]}");
          }
        }
        if (nlines.length > clines.length) {
          for (var li = clines.length; li < nlines.length; li++) {
            sb.writeln("+${nlines[li]}");
          }
        }
        if (clines.length > nlines.length) {
          for (var li = nlines.length; li < clines.length; li++) {
            sb.writeln("-${clines[li]}");
          }
        }
      }
    }

    return sb.toString();
  }
}
