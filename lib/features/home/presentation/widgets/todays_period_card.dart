import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../manage/dashboard_pages.dart';
import '../providers/home_provider.dart';

import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../core/constants/app_assets.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/pressable.dart';
import '../../data/models/featured_activity.dart';

/// Dark hero card highlighting today's activity.
class TodaysPeriodCard extends StatelessWidget {
  const TodaysPeriodCard({super.key, required this.activity});

  final FeaturedActivity activity;

  static const _onCard = AppColors.background;

  @override
  Widget build(BuildContext context) {
    final faded = _onCard.withValues(alpha: 0.75);

    return ClipRRect(
      borderRadius: AppRadius.circular(AppRadius.xxxl),
      child: ColoredBox(
        color: AppColors.foreground,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Badge
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: _onCard.withValues(alpha: 0.15),
                      borderRadius: AppRadius.circular(AppRadius.full),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          LucideIcons.sparkles400,
                          size: 12,
                          color: _onCard,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          activity.badge,
                          style: AppTypography.body(
                            size: AppFontSize.xxs,
                            height: AppLineHeight.xxs,
                            weight: FontWeight.w500,
                            color: _onCard,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    activity.title,
                    style: AppTypography.display(
                      size: AppFontSize.xxl,
                      height: AppLineHeight.xxl,
                      color: _onCard,
                    ),
                  ),
                  const SizedBox(height: 4),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 256),
                    child: Text(
                      activity.description,
                      style: AppTypography.body(
                        size: AppFontSize.sm,
                        height: AppLineHeight.sm,
                        color: faded,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 12,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Pressable(
                        onTap: () {
                          final game = context
                              .read<HomeProvider>()
                              .featuredGame;
                          if (game != null) {
                            startActivity(context, game);
                          } else {
                            editGame(context);
                          }
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: _onCard,
                            borderRadius: AppRadius.circular(AppRadius.full),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                LucideIcons.play400,
                                size: 16,
                                color: AppColors.foreground,
                              ),
                              const SizedBox(width: 8),
                              Flexible(
                                child: Text(
                                  'Start activity',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: AppTypography.body(
                                    size: AppFontSize.sm,
                                    height: AppLineHeight.sm,
                                    weight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(LucideIcons.clock300, size: 14, color: faded),
                          const SizedBox(width: 6),
                          Text(
                            '${activity.minutes} min',
                            style: AppTypography.body(
                              size: AppFontSize.xs,
                              height: AppLineHeight.xs,
                              color: faded,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),
            // Decorative doodle: `absolute -right-10 -bottom-12 w-40 opacity-25`
            Positioned(
              right: -40,
              bottom: -48,
              width: 160,
              height: 160,
              child: IgnorePointer(
                child: Opacity(
                  opacity: 0.25,
                  child: Image.asset(
                    AppAssets.doodleGames,
                    fit: BoxFit.contain,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
