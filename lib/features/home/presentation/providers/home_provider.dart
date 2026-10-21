import 'dart:ui';

import 'package:flutter/foundation.dart';

import '../../data/models/featured_activity.dart';
import '../../data/models/game.dart';
import '../../data/models/lesson_stage.dart';
import '../../data/models/quick_stat.dart';
import '../../data/models/subject.dart';
import '../../data/repositories/home_repository.dart';

class HomeProvider extends ChangeNotifier {
  HomeProvider(this.repository) {
    load();
  }
  final HomeRepository repository;
  bool loading = true;
  bool initialized = false;
  bool saving = false;
  String? error;
  List<Game> games = [];
  List<LessonStage> stages = [];
  List<String> roles = [];
  List<Map<String, dynamic>> classes = [];
  List<Map<String, dynamic>> sessions = [];
  Map<String, dynamic> settings = {};
  Map<String, dynamic>? user;
  final List<Subject> subjects = Subject.values;
  Subject _selectedSubject = Subject.all;
  String query = '';
  Subject get selectedSubject => _selectedSubject;
  String get teacherName => settings['teacher_name'] as String? ?? 'Teacher';
  Game? get featuredGame {
    if (games.isEmpty) return null;
    return games.firstWhere(
      (g) => g.id.toString() == settings['featured_game_id'],
      orElse: () => games.first,
    );
  }

  FeaturedActivity get todaysPeriod => FeaturedActivity(
    badge: "Today's period",
    title: featuredGame?.title ?? 'Create your first game',
    description:
        featuredGame?.description ?? 'Add a classroom game to get started.',
    minutes: featuredGame?.minutes ?? 0,
  );
  List<QuickStat> get quickStats => [
    QuickStat(value: '${games.length}', label: 'Games ready'),
    QuickStat(
      value: '${games.map((g) => g.subject).toSet().length}',
      label: 'Subjects',
    ),
    QuickStat(
      value: '${sessions.where((s) => s['status'] == 'completed').length}',
      label: 'Periods played',
    ),
  ];
  List<Game> get filteredGames => games
      .where(
        (g) =>
            (_selectedSubject == Subject.all ||
                g.subject == _selectedSubject) &&
            '${g.title} ${g.base} ${g.subject.label}'.toLowerCase().contains(
              query.toLowerCase(),
            ),
      )
      .toList();

  void _apply(Map<String, dynamic> data) {
    user = data['user'] == null
        ? null
        : Map<String, dynamic>.from(data['user']);
    games = (data['games'] as List)
        .map(
          (row) => Game(
            id: row['id'],
            title: row['title'],
            subject: Subject.values.byName(row['subject']),
            base: row['base'],
            tone: Color(row['tone']),
            minutes: row['minutes'],
            description: row['description'],
          ),
        )
        .toList();
    stages = (data['stages'] as List)
        .map(
          (r) => LessonStage(
            number: r['number'],
            name: r['name'],
            note: r['note'],
          ),
        )
        .toList();
    roles = List<String>.from(data['roles']);
    classes = List<Map<String, dynamic>>.from(data['classes']);
    sessions = List<Map<String, dynamic>>.from(data['sessions']);
    settings = Map<String, dynamic>.from(data['settings']);
  }

  Future<void> load() async {
    loading = true;
    error = null;
    notifyListeners();
    try {
      _apply(await repository.request('GET', 'state'));
      initialized = true;
    } catch (e) {
      if (e is ApiException && e.statusCode == 401) {
        clearAccount();
      } else {
        error = e.toString().replaceFirst('Exception: ', '');
      }
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  Future<bool> mutate(
    String method,
    String path, [
    Map<String, dynamic>? data,
  ]) async {
    if (saving) return false;
    saving = true;
    error = null;
    notifyListeners();
    try {
      _apply(await repository.request(method, path, data));
      return true;
    } catch (e) {
      if (e is ApiException && e.statusCode == 401) clearAccount();
      error = e.toString().replaceFirst('Exception: ', '');
      return false;
    } finally {
      saving = false;
      notifyListeners();
    }
  }

  void clearAccount() {
    user = null;
    initialized = false;
    games = [];
    classes = [];
    sessions = [];
    settings = {};
    stages = [];
    roles = [];
    query = '';
    _selectedSubject = Subject.all;
    error = null;
  }

  Future<bool> authenticate(
    bool register,
    Map<String, dynamic> credentials,
  ) async {
    if (saving) return false;
    saving = true;
    error = null;
    notifyListeners();
    try {
      _apply(
        await repository.request(
          'POST',
          register ? 'auth/register' : 'auth/login',
          credentials,
        ),
      );
      initialized = true;
      return true;
    } catch (e) {
      error = e.toString().replaceFirst('Exception: ', '');
      return false;
    } finally {
      saving = false;
      notifyListeners();
    }
  }

  Future<bool> logout() async {
    if (saving) return false;
    saving = true;
    error = null;
    notifyListeners();
    try {
      await repository.request('POST', 'auth/logout');
      clearAccount();
      return true;
    } catch (e) {
      error = e.toString().replaceFirst('Exception: ', '');
      return false;
    } finally {
      saving = false;
      notifyListeners();
    }
  }

  void selectSubject(Subject subject) {
    _selectedSubject = subject;
    notifyListeners();
  }

  void search(String value) {
    query = value;
    notifyListeners();
  }
}
