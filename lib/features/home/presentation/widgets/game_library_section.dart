import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/pressable.dart';
import '../providers/home_provider.dart';
import 'game_list_tile.dart';
import '../../../manage/dashboard_pages.dart';
import '../../../shell/data/models/app_tab.dart';
import '../../../shell/presentation/providers/bottom_nav_provider.dart';
import 'section_title.dart';
import 'subject_filter_chips.dart';

/// "Game library": heading, subject filter and the filtered game list.
class GameLibrarySection extends StatelessWidget {
  const GameLibrarySection({super.key});

  @override
  Widget build(BuildContext context) {
    final home = context.watch<HomeProvider>();
    final games = home.filteredGames;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppConstants.gutter),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Flexible(child: SectionTitle('Game library')),
              Pressable(
                onTap: () =>
                    context.read<BottomNavProvider>().select(AppTab.games),
                child: Row(
                  children: [
                    Text(
                      'See all',
                      style: AppTypography.body(
                        size: AppFontSize.xs,
                        height: AppLineHeight.xs,
                        weight: FontWeight.w500,
                        color: AppColors.mutedForeground,
                      ),
                    ),
                    const Icon(
                      LucideIcons.chevronRight400,
                      size: 14,
                      color: AppColors.mutedForeground,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        SubjectFilterChips(
          subjects: home.subjects,
          selected: home.selectedSubject,
          onSelected: context.read<HomeProvider>().selectSubject,
        ),
        const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppConstants.gutter),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (games.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(20),
                  child: Text(
                    'No games found. Add a game or try another search.',
                  ),
                ),
              for (var i = 0; i < games.length; i++) ...[
                if (i > 0) const SizedBox(height: 12),
                GameListTile(
                  key: ValueKey(games[i].id),
                  game: games[i],
                  onTap: () => gameDetails(context, games[i]),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}
