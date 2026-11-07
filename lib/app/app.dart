import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:buildstock/core/widgets/app_lifecycle_sync.dart';
import 'package:buildstock/l10n/generated/app_localizations.dart';

import 'preferences.dart';
import 'router.dart';
import 'theme/app_theme.dart';

class BuildStockApp extends ConsumerWidget {
  const BuildStockApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final preferences = ref.watch(preferencesProvider);
    return MaterialApp.router(
      title: 'BuildStock',
      debugShowCheckedModeBanner: false,
      routerConfig: ref.watch(routerProvider),
      theme: buildLightTheme(),
      darkTheme: buildDarkTheme(),
      themeMode: preferences.themeMode,
      locale: preferences.locale,
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      builder: (context, child) {
        return AppLifecycleSync(child: child ?? const SizedBox.shrink());
      },
    );
  }
}
