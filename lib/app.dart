import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'core/constants/app_constants.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'features/home/data/repositories/home_repository.dart';
import 'features/auth/auth_screen.dart';
import 'core/widgets/phone_frame.dart';
import 'features/home/presentation/providers/home_provider.dart';
import 'features/shell/presentation/providers/bottom_nav_provider.dart';

class AnubhavApp extends StatelessWidget {
  const AnubhavApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        Provider<HomeRepository>(
          create: (_) => HomeRepository(),
          dispose: (_, repository) => repository.dispose(),
        ),
        ChangeNotifierProvider<HomeProvider>(
          create: (context) => HomeProvider(context.read<HomeRepository>()),
        ),
        ChangeNotifierProvider<BottomNavProvider>(
          create: (_) => BottomNavProvider(),
        ),
      ],
      child: MaterialApp.router(
        title: AppConstants.appName,
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        routerConfig: appRouter,
        builder: (context, child) {
          final home = context.watch<HomeProvider>();
          if (home.loading) {
            return const Scaffold(
              body: PhoneFrame(
                child: Center(child: CircularProgressIndicator()),
              ),
            );
          }
          if (home.user == null) return const AuthScreen();
          return child ?? const SizedBox.shrink();
        },
      ),
    );
  }
}
