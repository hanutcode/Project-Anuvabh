import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../providers/home_provider.dart';
import '../widgets/game_library_section.dart';
import '../widgets/home_app_bar.dart';
import '../widgets/quick_stats_row.dart';
import '../widgets/roles_card.dart';
import '../widgets/stages_section.dart';
import '../widgets/todays_period_card.dart';
import '../widgets/trap_rounds_card.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  /// `space-y-6` between sections.
  static const _sectionGap = SizedBox(height: 24);

  @override
  Widget build(BuildContext context) {
    final home = context.watch<HomeProvider>();
    final insets = MediaQuery.paddingOf(context);

    return Stack(
      children: [
        Positioned.fill(
          child: SingleChildScrollView(
            // pt-2 below the app bar, pb-28 to clear the tab bar.
            padding: EdgeInsets.only(
              top: insets.top + HomeAppBar.height + 8,
              bottom: insets.bottom + 112,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _Gutter(child: TodaysPeriodCard(activity: home.todaysPeriod)),
                _sectionGap,
                _Gutter(child: QuickStatsRow(stats: home.quickStats)),
                _sectionGap,
                const GameLibrarySection(),
                _sectionGap,
                StagesSection(stages: home.stages),
                _sectionGap,
                _Gutter(child: RolesCard(roles: home.roles)),
                _sectionGap,
                const _Gutter(child: TrapRoundsCard()),
                _sectionGap,
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppConstants.gutter,
                    4,
                    AppConstants.gutter,
                    0,
                  ),
                  child: Text(
                    'Paper, chalk and a blackboard. Prepare once, reuse for years.',
                    textAlign: TextAlign.center,
                    style: AppTypography.body(
                      size: AppFontSize.xxs,
                      height: AppLineHeight.xxs,
                      color: AppColors.mutedForeground,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const Positioned(top: 0, left: 0, right: 0, child: HomeAppBar()),
      ],
    );
  }
}

class _Gutter extends StatelessWidget {
  const _Gutter({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppConstants.gutter),
      child: child,
    );
  }
}
