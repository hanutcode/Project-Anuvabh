import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:project_anubhav/features/home/data/repositories/home_repository.dart';
import 'package:provider/provider.dart';
import 'package:project_anubhav/features/manage/dashboard_pages.dart';
import 'package:project_anubhav/features/auth/auth_screen.dart';
import 'package:project_anubhav/features/shell/presentation/providers/bottom_nav_provider.dart';
import 'package:project_anubhav/features/home/presentation/providers/home_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  GoogleFonts.config.allowRuntimeFetching = false;
  final seed = jsonDecode(
    File('server/seed.json').readAsStringSync(),
  ) as Map<String, dynamic>;
  Map<String, dynamic> state() => {
    ...seed,
    'user': {'id': 1, 'email': 'teacher@example.test'},
    'games': [
      for (var i = 0; i < seed['games'].length; i++)
        {...seed['games'][i], 'id': i + 1},
    ],
    'classes': [],
    'sessions': [],
    'settings': {
      'teacher_name': 'Teacher',
      'school': '',
      'featured_game_id': '1',
    },
  };
  test(
    'loads API records and computes counts, search and subject filters',
    () async {
      final repository = HomeRepository(
        client: MockClient(
          (_) async => http.Response(
            jsonEncode(state()),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          ),
        ),
      );
      final home = HomeProvider(repository);
      await Future<void>.delayed(Duration.zero);
      expect(home.loading, false);
      expect(home.error, null);
      expect(home.games.length, 8);
      expect(home.quickStats.first.value, '8');
      home.search('rummy');
      expect(home.filteredGames.single.title, 'Compound Rummy');
      home.selectSubject(home.games.first.subject);
      expect(home.filteredGames, isEmpty);
      home.dispose();
      repository.dispose();
    },
  );
  test(
    'failed saves retain loaded records and show API validation error',
    () async {
      final repository = HomeRepository(
        client: MockClient(
          (request) async => request.method == 'GET'
              ? http.Response(
                  jsonEncode(state()),
                  200,
                  headers: {'content-type': 'application/json; charset=utf-8'},
                )
              : http.Response('{"error":"Invalid game"}', 400),
        ),
      );
      final home = HomeProvider(repository);
      await Future<void>.delayed(Duration.zero);
      expect(await home.mutate('POST', 'games', {}), false);
      expect(home.error, 'Invalid game');
      expect(home.games.length, 8);
      expect(home.saving, false);
      home.dispose();
      repository.dispose();
    },
  );
  test('unauthenticated startup and logout clear account records', () async {
    final repository = HomeRepository(
      client: MockClient((request) async {
        if (request.url.path == '/api/state') {
          return http.Response('{"error":"Please log in"}', 401);
        }
        if (request.url.path == '/api/auth/logout') {
          return http.Response('{"ok":true}', 200);
        }
        return http.Response(
          jsonEncode(state()),
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
    );
    final home = HomeProvider(repository);
    await Future<void>.delayed(Duration.zero);
    expect(home.user, null);
    expect(home.error, null);
    expect(
      await home.authenticate(false, {
        'email': 'teacher@example.test',
        'password': '012345',
      }),
      true,
    );
    expect(home.user?['email'], 'teacher@example.test');
    expect(home.games.length, 8);
    home.search('rummy');
    expect(await home.logout(), true);
    expect(home.user, null);
    expect(home.games, isEmpty);
    expect(home.classes, isEmpty);
    expect(home.sessions, isEmpty);
    expect(home.settings, isEmpty);
    expect(home.query, '');
    home.dispose();
    repository.dispose();
  });

  test('expired session clears private records on a rejected write', () async {
    final repository = HomeRepository(
      client: MockClient(
        (request) async => request.method == 'GET'
            ? http.Response(
                jsonEncode(state()),
                200,
                headers: {'content-type': 'application/json'},
              )
            : http.Response('{"error":"Session expired"}', 401),
      ),
    );
    final home = HomeProvider(repository);
    await Future<void>.delayed(Duration.zero);
    expect(home.user, isNotNull);
    expect(
      await home.mutate('POST', 'classes', {'name': 'Class', 'students': 20}),
      false,
    );
    expect(home.user, null);
    expect(home.games, isEmpty);
    expect(home.error, 'Session expired');
    home.dispose();
    repository.dispose();
  });

  testWidgets(
    'login validates input, signs in, and profile logout returns to login',
    (tester) async {
      var logins = 0;
      final repository = HomeRepository(
        client: MockClient((request) async {
          if (request.url.path == '/api/state') {
            return http.Response('{"error":"Please log in"}', 401);
          }
          if (request.url.path == '/api/auth/logout') {
            return http.Response('{"ok":true}', 200);
          }
          logins++;
          return http.Response(
            jsonEncode(state()),
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      );
      final home = HomeProvider(repository);
      await tester.pump();
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: home),
            ChangeNotifierProvider(create: (_) => BottomNavProvider()),
          ],
          child: MaterialApp(
            home: Consumer<HomeProvider>(
              builder: (context, home, _) => home.user == null
                  ? const AuthScreen()
                  : const Scaffold(body: ProfilePage()),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Log in'));
      await tester.pumpAndSettle();
      expect(find.text('Enter a valid email address'), findsOneWidget);
      expect(logins, 0);
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Email'),
        'teacher@example.test',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Password'),
        '012345',
      );
      await tester.ensureVisible(find.text('Log in'));
      await tester.tap(find.text('Log in'));
      await tester.pumpAndSettle();
      expect(logins, 1);
      expect(find.text('Your profile'), findsOneWidget);
      await tester.ensureVisible(find.text('Log out'));
      await tester.tap(find.text('Log out'));
      await tester.pumpAndSettle();
      expect(find.text('Log in'), findsOneWidget);
      expect(home.user, null);
      expect(home.games, isEmpty);
      await tester.pumpWidget(const SizedBox.shrink());
      home.dispose();
      repository.dispose();
    },
  );

  testWidgets('editor validates required fields before saving', (tester) async {
    var writes = 0;
    final repository = HomeRepository(
      client: MockClient((request) async {
        if (request.method != 'GET') writes++;
        return http.Response(
          jsonEncode(state()),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }),
    );
    final home = HomeProvider(repository);
    await tester.pump();
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: home,
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => editClass(context),
                child: const Text('Add class'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Add class'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('Enter class name'), findsOneWidget);
    expect(writes, 0);
    await tester.enterText(find.byType(TextFormField).first, 'Grade 9');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(writes, 1);
    expect(find.byType(AlertDialog), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    home.dispose();
    repository.dispose();
  });
}
