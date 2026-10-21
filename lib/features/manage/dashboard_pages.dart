import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../home/data/models/game.dart';
import '../home/data/models/subject.dart';
import '../home/presentation/providers/home_provider.dart';
import '../home/presentation/widgets/game_library_section.dart';
import '../shell/data/models/app_tab.dart';
import '../shell/presentation/providers/bottom_nav_provider.dart';

Future<void> saveAction(
  BuildContext context,
  String method,
  String path, [
  Map<String, dynamic>? data,
]) async {
  final home = context.read<HomeProvider>();
  final ok = await home.mutate(method, path, data);
  if (context.mounted && !ok) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(home.error ?? 'Please try again.')));
  }
}

class PageBody extends StatelessWidget {
  const PageBody({
    super.key,
    required this.title,
    required this.children,
    this.action,
  });
  final String title;
  final List<Widget> children;
  final Widget? action;
  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.fromLTRB(20, 28, 20, 112),
    children: [
      Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: Theme.of(context).textTheme.headlineMedium
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
          ),
          ?action,
        ],
      ),
      const SizedBox(height: 8),
      ...children,
    ],
  );
}

class GamesPage extends StatelessWidget {
  const GamesPage({super.key});
  @override
  Widget build(BuildContext context) => PageBody(
    title: 'Your game library',
    children: [
      const Text('Plan a playful period. Make each game your own.'),
      const SizedBox(height: 20),
      FilledButton.icon(
        onPressed: () => editGame(context),
        icon: const Icon(Icons.add),
        label: const Text('Add game'),
      ),
      const SizedBox(height: 16),
      TextFormField(
        initialValue: context.read<HomeProvider>().query,
        decoration: const InputDecoration(
          labelText: 'Search games',
          prefixIcon: Icon(Icons.search),
          border: OutlineInputBorder(),
        ),
        onChanged: context.read<HomeProvider>().search,
      ),
      const SizedBox(height: 24),
      const GameLibrarySection(),
    ],
  );
}

Future<void> editGame(BuildContext context, [Game? game]) => showDialog<void>(
  context: context,
  builder: (_) => RecordEditor(
    title: game == null ? 'Add game' : 'Edit game',
    fields: [
      FieldSpec('title', 'Game title', game?.title ?? '', max: 100),
      FieldSpec('base', 'Based on (e.g. Bingo)', game?.base ?? '', max: 80),
      FieldSpec(
        'minutes',
        'Duration in minutes',
        '${game?.minutes ?? 45}',
        maxNumber: 240,
      ),
      FieldSpec(
        'description',
        'Activity instructions',
        game?.description ?? '',
        max: 3000,
        lines: 4,
      ),
    ],
    subject: game?.subject ?? Subject.physics,
    method: game == null ? 'POST' : 'PUT',
    path: game == null ? 'games' : 'games/${game.id}',
    extra: {'tone': game?.tone.toARGB32() ?? AppColors.lilac.toARGB32()},
  ),
);

Future<void> gameDetails(BuildContext context, Game original) =>
    showDialog<void>(
      context: context,
      builder: (_) => Consumer<HomeProvider>(
        builder: (context, home, _) {
          final found = home.games.where((g) => g.id == original.id);
          if (found.isEmpty) {
            return const AlertDialog(
              content: Text('This game has been removed.'),
            );
          }
          final game = found.first;
          return AlertDialog(
            title: Text(game.title),
            content: SizedBox(
              width: 350,
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(game.subtitle),
                    const SizedBox(height: 16),
                    Text(game.description),
                    const SizedBox(height: 20),
                    Text(
                      'Lesson flow',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    for (final stage in home.stages)
                      Padding(
                        padding: const EdgeInsets.only(top: 10),
                        child: Text(
                          '${stage.number}  ${stage.name} — ${stage.note}',
                        ),
                      ),
                    const SizedBox(height: 20),
                    FilledButton.icon(
                      onPressed: home.saving
                          ? null
                          : () {
                              Navigator.pop(context);
                              startActivity(context, game);
                            },
                      icon: const Icon(Icons.play_arrow),
                      label: const Text('Start activity'),
                    ),
                    TextButton(
                      onPressed: home.saving
                          ? null
                          : () async {
                              await saveAction(context, 'PUT', 'settings', {
                                'featured_game_id': game.id,
                              });
                              if (context.mounted && home.error == null) {
                                Navigator.pop(context);
                              }
                            },
                      child: Text(
                        home.featuredGame?.id == game.id
                            ? "Today's featured game"
                            : "Feature for today's period",
                      ),
                    ),
                    Wrap(
                      children: [
                        TextButton(
                          onPressed: () {
                            Navigator.pop(context);
                            editGame(context, game);
                          },
                          child: const Text('Edit game'),
                        ),
                        TextButton(
                          onPressed: home.saving
                              ? null
                              : () async {
                                  if (await confirmDelete(
                                    context,
                                    'Delete ${game.title}?',
                                    'Activity history will be kept.',
                                  )) {
                                    if (!context.mounted) return;
                                    await saveAction(
                                      context,
                                      'DELETE',
                                      'games/${game.id}',
                                    );
                                    if (context.mounted && home.error == null) {
                                      Navigator.pop(context);
                                    }
                                  }
                                },
                          child: const Text(
                            'Delete game',
                            style: TextStyle(color: AppColors.destructive),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Close'),
              ),
            ],
          );
        },
      ),
    );

Future<bool> confirmDelete(
  BuildContext context,
  String title,
  String detail,
) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(detail),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    ) ??
    false;

Future<void> startActivity(BuildContext context, Game game) => showDialog<void>(
  context: context,
  builder: (_) => _StartActivity(game: game),
);

class _StartActivity extends StatefulWidget {
  const _StartActivity({required this.game});
  final Game game;
  @override
  State<_StartActivity> createState() => _StartActivityState();
}

class _StartActivityState extends State<_StartActivity> {
  int? classId;
  String? error;
  @override
  Widget build(BuildContext context) {
    final home = context.watch<HomeProvider>();
    return AlertDialog(
      title: Text('Start ${widget.game.title}'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'Choose a class or run an independent activity. Track completion in the Class tab.',
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<int>(
            initialValue: classId ?? 0,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Class'),
            items: [
              const DropdownMenuItem(
                value: 0,
                child: Text('Independent activity'),
              ),
              for (final c in home.classes)
                DropdownMenuItem(value: c['id'] as int, child: Text(c['name'])),
            ],
            onChanged: home.saving
                ? null
                : (value) =>
                      setState(() => classId = value == 0 ? null : value),
          ),
          if (error != null)
            Text(error!, style: const TextStyle(color: AppColors.destructive)),
        ],
      ),
      actions: [
        TextButton(
          onPressed: home.saving ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: home.saving
              ? null
              : () async {
                  final ok = await home.mutate('POST', 'sessions', {
                    'game_id': widget.game.id,
                    'class_id': classId,
                  });
                  if (!context.mounted) return;
                  if (ok) {
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                          'Activity started. Open Class to track it.',
                        ),
                      ),
                    );
                  } else {
                    setState(() => error = home.error);
                  }
                },
          child: Text(home.saving ? 'Starting…' : 'Start activity'),
        ),
      ],
    );
  }
}

class ClassesPage extends StatelessWidget {
  const ClassesPage({super.key});
  @override
  Widget build(BuildContext context) {
    final home = context.watch<HomeProvider>();
    return PageBody(
      title: 'Your classroom',
      children: [
        const Text('Keep your classes and classroom activities together.'),
        const SizedBox(height: 20),
        FilledButton.icon(
          onPressed: () => editClass(context),
          icon: const Icon(Icons.add),
          label: const Text('Add class'),
        ),
        const SizedBox(height: 16),
        if (home.classes.isEmpty)
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              'No classes yet. Add your first class to plan an activity.',
            ),
          ),
        for (final c in home.classes)
          Card(
            child: ListTile(
              title: Text(c['name']),
              subtitle: Text('${c['students']} students'),
              onTap: () => editClass(context, c),
              trailing: IconButton(
                tooltip: 'Delete class',
                icon: const Icon(Icons.delete_outline),
                onPressed: home.saving
                    ? null
                    : () async {
                        if (await confirmDelete(
                          context,
                          'Delete ${c['name']}?',
                          'Activity history will be kept.',
                        )) {
                          if (context.mounted) {
                            await saveAction(
                              context,
                              'DELETE',
                              'classes/${c['id']}',
                            );
                          }
                        }
                      },
              ),
            ),
          ),
        const SizedBox(height: 24),
        Text('Activity history', style: Theme.of(context).textTheme.titleLarge),
        if (home.sessions.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Text('Start a game to see your activity history here.'),
          ),
        for (final s in home.sessions)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    s['game_title'],
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 4),
                  Text(s['class_name']),
                  Text(
                    DateTime.parse(s['created_at'])
                        .toLocal()
                        .toString()
                        .substring(0, 16),
                  ),
                  const SizedBox(height: 8),
                  if (s['status'] == 'active')
                    FilledButton.tonal(
                      onPressed: home.saving
                          ? null
                          : () => saveAction(
                              context,
                              'PUT',
                              'sessions/${s['id']}',
                            ),
                      child: const Text('Mark completed'),
                    )
                  else
                    const Row(
                      children: [
                        Icon(Icons.check_circle_outline, size: 18),
                        SizedBox(width: 6),
                        Text('Completed'),
                      ],
                    ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

Future<void> editClass(BuildContext context, [Map<String, dynamic>? c]) =>
    showDialog<void>(
      context: context,
      builder: (_) => RecordEditor(
        title: c == null ? 'Add class' : 'Edit class',
        fields: [
          FieldSpec('name', 'Class name', c?['name'] ?? '', max: 80),
          FieldSpec(
            'students',
            'Number of students',
            '${c?['students'] ?? 30}',
            maxNumber: 500,
          ),
        ],
        method: c == null ? 'POST' : 'PUT',
        path: c == null ? 'classes' : 'classes/${c['id']}',
      ),
    );

class ProfilePage extends StatelessWidget {
  const ProfilePage({super.key});
  @override
  Widget build(BuildContext context) {
    final home = context.watch<HomeProvider>();
    return PageBody(
      title: 'Your profile',
      children: [
        const SizedBox(height: 20),
        const CircleAvatar(
          radius: 36,
          backgroundColor: AppColors.lilac,
          child: Icon(Icons.person_outline, size: 36),
        ),
        const SizedBox(height: 16),
        Center(
          child: Text(
            home.teacherName,
            style: Theme.of(context).textTheme.titleLarge,
          ),
        ),
        Center(
          child: Text(
            home.settings['school'] == ''
                ? 'Your teaching space'
                : home.settings['school'] ?? 'Your teaching space',
          ),
        ),
        const SizedBox(height: 8),
        Center(child: Text(home.user?['email'] ?? '')),
        const SizedBox(height: 24),
        FilledButton.tonal(
          onPressed: () => showDialog<void>(
            context: context,
            builder: (_) => RecordEditor(
              title: 'Edit profile',
              fields: [
                FieldSpec(
                  'teacher_name',
                  'Your name',
                  home.teacherName,
                  max: 100,
                ),
                FieldSpec(
                  'school',
                  'School (optional)',
                  home.settings['school'] ?? '',
                  max: 100,
                  optional: true,
                ),
              ],
              method: 'PUT',
              path: 'settings',
            ),
          ),
          child: const Text('Edit profile'),
        ),
        const SizedBox(height: 24),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                Text('${home.games.length} games in your library'),
                const SizedBox(height: 8),
                Text('${home.classes.length} classes'),
                const SizedBox(height: 8),
                Text(
                  '${home.sessions.where((s) => s['status'] == 'completed').length} periods completed',
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),
        OutlinedButton.icon(
          icon: const Icon(Icons.logout),
          label: Text(home.saving ? 'Logging out…' : 'Log out'),
          onPressed: home.saving
              ? null
              : () async {
                  final nav = context.read<BottomNavProvider>();
                  final ok = await home.logout();
                  if (ok) nav.select(AppTab.home);
                  if (!ok && context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          home.error ?? 'Could not log out. Try again.',
                        ),
                      ),
                    );
                  }
                },
        ),
      ],
    );
  }
}

class FieldSpec {
  const FieldSpec(
    this.key,
    this.label,
    this.value, {
    this.max = 200,
    this.maxNumber,
    this.lines = 1,
    this.optional = false,
  });
  final String key, label, value;
  final int max, lines;
  final int? maxNumber;
  final bool optional;
}

class RecordEditor extends StatefulWidget {
  const RecordEditor({
    super.key,
    required this.title,
    required this.fields,
    required this.method,
    required this.path,
    this.subject,
    this.extra = const {},
  });
  final String title, method, path;
  final List<FieldSpec> fields;
  final Subject? subject;
  final Map<String, dynamic> extra;
  @override
  State<RecordEditor> createState() => _RecordEditorState();
}

class _RecordEditorState extends State<RecordEditor> {
  final form = GlobalKey<FormState>();
  late final Map<String, TextEditingController> controllers = {
    for (final f in widget.fields) f.key: TextEditingController(text: f.value),
  };
  late Subject? subject = widget.subject;
  String? error;
  @override
  void dispose() {
    for (final c in controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final home = context.watch<HomeProvider>();
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 360,
        child: Form(
          key: form,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final f in widget.fields)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: TextFormField(
                      controller: controllers[f.key],
                      enabled: !home.saving,
                      maxLength: f.maxNumber == null ? f.max : 3,
                      minLines: f.lines,
                      maxLines: f.lines,
                      keyboardType: f.maxNumber != null
                          ? TextInputType.number
                          : TextInputType.multiline,
                      decoration: InputDecoration(
                        labelText: f.label,
                        border: const OutlineInputBorder(),
                        counterText: '',
                      ),
                      validator: (raw) {
                        final value = raw?.trim() ?? '';
                        if (value.isEmpty && !f.optional) {
                          return 'Enter ${f.label.toLowerCase()}';
                        }
                        if (f.maxNumber != null &&
                            (int.tryParse(value) == null ||
                                int.parse(value) < 1 ||
                                int.parse(value) > f.maxNumber!)) {
                          return 'Enter a number from 1 to ${f.maxNumber}';
                        }
                        return null;
                      },
                    ),
                  ),
                if (subject != null)
                  DropdownButtonFormField<Subject>(
                    initialValue: subject,
                    decoration: const InputDecoration(
                      labelText: 'Subject',
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      for (final s in Subject.values.where(
                        (s) => s != Subject.all,
                      ))
                        DropdownMenuItem(value: s, child: Text(s.label)),
                    ],
                    onChanged: home.saving
                        ? null
                        : (value) => setState(() => subject = value),
                  ),
                if (error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(
                      error!,
                      style: const TextStyle(color: AppColors.destructive),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: home.saving ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: home.saving
              ? null
              : () async {
                  if (!form.currentState!.validate()) return;
                  final data = <String, dynamic>{
                    ...widget.extra,
                    for (final f in widget.fields)
                      f.key: f.maxNumber != null
                          ? int.parse(controllers[f.key]!.text.trim())
                          : controllers[f.key]!.text.trim(),
                    if (subject != null) 'subject': subject!.name,
                  };
                  final ok = await home.mutate(
                    widget.method,
                    widget.path,
                    data,
                  );
                  if (!context.mounted) return;
                  if (ok) {
                    Navigator.pop(context);
                  } else {
                    setState(() => error = home.error);
                  }
                },
          child: Text(home.saving ? 'Saving…' : 'Save'),
        ),
      ],
    );
  }
}
