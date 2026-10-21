import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/home_provider.dart';
import '../../../shell/data/models/app_tab.dart';
import '../../../shell/presentation/providers/bottom_nav_provider.dart';

import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/frosted_surface.dart';
import '../../../../core/widgets/pressable.dart';

/// Sticky, translucent header: greeting, title, search and notifications.
class HomeAppBar extends StatelessWidget {
  const HomeAppBar({super.key});

  /// pt-6 (24) + content row (46) + pb-3 (12), excluding the status bar.
  static const double height = 82;

  @override
  Widget build(BuildContext context) {
    final topInset = MediaQuery.paddingOf(context).top;

    return FrostedSurface(
      color: AppColors.background.withValues(alpha: 0.85),
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          AppConstants.gutter,
          24 + topInset,
          AppConstants.gutter,
          12,
        ),
        child: SizedBox(
          height: 46,
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      'Namaste, ${context.watch<HomeProvider>().teacherName}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.body(
                        size: AppFontSize.xs,
                        height: AppLineHeight.xs,
                        color: AppColors.mutedForeground,
                      ),
                    ),
                    Text(
                      AppConstants.appName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.display(
                        size: AppFontSize.xxl,
                        height: AppLineHeight.tight,
                      ),
                    ),
                  ],
                ),
              ),
              _CircleIconButton(
                onTap: () =>
                    context.read<BottomNavProvider>().select(AppTab.games),
                icon: LucideIcons.search300,
                semanticLabel: 'Search games',
              ),
              const SizedBox(width: 8),
              _CircleIconButton(
                onTap: () =>
                    context.read<BottomNavProvider>().select(AppTab.classroom),
                icon: LucideIcons.bell300,
                semanticLabel: 'Activity history',
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CircleIconButton extends StatelessWidget {
  const _CircleIconButton({
    required this.icon,
    required this.semanticLabel,
    required this.onTap,
  });

  final VoidCallback onTap;
  final IconData icon;
  final String semanticLabel;

  @override
  Widget build(BuildContext context) {
    return Pressable(
      semanticLabel: semanticLabel,
      onTap: onTap,
      child: Container(
        width: 40,
        height: 40,
        alignment: Alignment.center,
        decoration: const BoxDecoration(
          color: AppColors.card,
          shape: BoxShape.circle,
        ),
        child: Icon(icon, size: 16, color: AppColors.foreground),
      ),
    );
  }
}
