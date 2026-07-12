import "package:flutter/material.dart";
import "../services/settings_service.dart";
import "../services/storage_service.dart";
import "chat_screen.dart";
import "settings_screen.dart";
import "onboarding_screen.dart";

class ProjectsScreen extends StatefulWidget {
  const ProjectsScreen({super.key});

  @override
  State<ProjectsScreen> createState() {
    return _ProjectsScreenState();
  }
}

class _ProjectsScreenState extends State<ProjectsScreen> {
  List<String> _projects = [];
  bool _loading = true;
  int _configAttempts = 0;
  final TextEditingController _newProjectCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _checkConfig();
  }

  @override
  void dispose() {
    _newProjectCtrl.dispose();
    super.dispose();
  }

  Future<void> _checkConfig() async {
    if (_configAttempts > 3) {
      if (mounted) Navigator.of(context).pop();
      return;
    }
    _configAttempts++;
    final hasKey = await SettingsService.deepseekApiKey;
    if (hasKey.isEmpty) {
      if (mounted) {
        await Navigator.of(context).push(
          MaterialPageRoute(
              builder: (_) => const OnboardingScreen()),
        );
        final hasKeyAfter = await SettingsService.deepseekApiKey;
        if (hasKeyAfter.isEmpty && _configAttempts < 4) {
          _checkConfig();
          return;
        }
        await StorageService.init();
        _loadProjects();
      }
    } else {
      await StorageService.init();
      _loadProjects();
    }
  }

  Future<void> _loadProjects() async {
    final projects = await StorageService.listProjects();
    if (mounted) {
      setState(() {
        _projects = projects;
        _loading = false;
      });
    }
  }

  Future<void> _createProject() async {
    final name = _newProjectCtrl.text.trim();
    if (name.isEmpty) return;

    await StorageService.createProject(name);
    _newProjectCtrl.clear();
    await _loadProjects();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Project '$name' created")),
      );
    }
  }

  void _openProject(String name) {
    SettingsService.currentProject = name;

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ChatScreen(
          sessionId: DateTime.now().millisecondsSinceEpoch.toString(),
          projectName: name,
        ),
      ),
    ).then((_) {
      _loadProjects();
    });
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text("OpenCode",
            style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                    builder: (_) => const SettingsScreen()),
              );
            },
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _projects.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.folder_open,
                            size: 64,
                            color: cs.onSurfaceVariant),
                        const SizedBox(height: 16),
                        Text("No projects yet",
                            style: TextStyle(
                                fontSize: 18,
                                color: cs.onSurface)),
                        const SizedBox(height: 8),
                        Text(
                            "Create a new project to get started",
                            style: TextStyle(
                                color: cs.onSurfaceVariant),
                            textAlign: TextAlign.center),
                        const SizedBox(height: 32),
                        _buildCreateForm(cs),
                      ],
                    ),
                  ),
                )
              : Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: _buildCreateForm(cs),
                    ),
                    Expanded(
                      child: ListView.builder(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16),
                        itemCount: _projects.length,
                        itemBuilder: (context, index) {
                          final p = _projects[index];
                          return Card(
                            margin:
                                const EdgeInsets.only(bottom: 8),
                            child: ListTile(
                              leading: Icon(Icons.folder,
                                  color: cs.primary),
                              title: Text(p,
                                  style: const TextStyle(
                                      fontWeight:
                                          FontWeight.w600)),
                              subtitle: const Text("Tap to open"),
                              trailing: const Icon(
                                  Icons.chevron_right),
                              onTap: () {
                                _openProject(p);
                              },
                              shape: RoundedRectangleBorder(
                                  borderRadius:
                                      BorderRadius.circular(12)),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
    );
  }

  Widget _buildCreateForm(ColorScheme cs) {
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: _newProjectCtrl,
            decoration: const InputDecoration(
              hintText: "new-project-name",
              contentPadding: EdgeInsets.symmetric(
                  horizontal: 16, vertical: 12),
            ),
          ),
        ),
        const SizedBox(width: 8),
        FilledButton(
          onPressed: _createProject,
          style: FilledButton.styleFrom(
            backgroundColor: cs.primary,
            minimumSize: const Size(80, 48),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12)),
          ),
          child: const Text("Create"),
        ),
      ],
    );
  }
}
