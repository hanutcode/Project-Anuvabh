import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../manage/dashboard_pages.dart';
import '../../../home/presentation/providers/home_provider.dart';
import '../../data/models/app_tab.dart';
import '../providers/bottom_nav_provider.dart';

import '../../../../core/widgets/phone_frame.dart';
import '../widgets/bottom_tab_bar.dart';

/// Root layout for tabbed routes: the phone frame, the routed page, and the
/// bottom tab bar pinned over it.
class AppShell extends StatelessWidget {
  const AppShell({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final home = context.watch<HomeProvider>();
    final tab = context.watch<BottomNavProvider>().current;
    final page = switch (tab) {
      AppTab.home => child,
      AppTab.games => const GamesPage(),
      AppTab.classroom => const ClassesPage(),
      AppTab.me => const ProfilePage(),
    };
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: PhoneFrame(
        child: Stack(
          children: [
            Positioned.fill(
              child: home.loading
                  ? const Center(child: CircularProgressIndicator())
                  : home.error != null && !home.initialized
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(home.error!, textAlign: TextAlign.center),
                            const SizedBox(height: 16),
                            FilledButton(
                              onPressed: home.load,
                              child: const Text('Retry'),
                            ),
                          ],
                        ),
                      ),
                    )
                  : page,
            ),
            const Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: BottomTabBar(),
            ),
          ],
        ),
      ),
    );
  }
}
