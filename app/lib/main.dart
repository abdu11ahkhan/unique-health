import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'core/i18n.dart';
import 'package:provider/provider.dart';
import 'screens/auth_screen.dart';
import 'screens/home_screen.dart';
import 'state/app_state.dart';
import 'widgets/ui.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(ChangeNotifierProvider(create: (_) => AppState()..init(), child: const UniqueCloneApp()));
}

class UniqueCloneApp extends StatelessWidget {
  const UniqueCloneApp({super.key});

  ThemeData _theme(Brightness b) {
    final dark = b == Brightness.dark;
    final scheme = ColorScheme.fromSeed(seedColor: brandBlue, brightness: b).copyWith(primary: brandBlue);
    final fg = dark ? const Color(0xFFE8EAF6) : inkColor;
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: Colors.transparent,
      appBarTheme: AppBarTheme(backgroundColor: Colors.transparent, elevation: 0, scrolledUnderElevation: 0, centerTitle: true, foregroundColor: fg, titleTextStyle: TextStyle(color: fg, fontSize: 18, fontWeight: FontWeight.w700)),
      cardTheme: CardThemeData(elevation: 0, color: dark ? const Color(0xFF1D2136) : Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18))),
      filledButtonTheme: FilledButtonThemeData(style: FilledButton.styleFrom(minimumSize: const Size(64, 48), shape: const StadiumBorder(), backgroundColor: brandBlue)),
      outlinedButtonTheme: OutlinedButtonThemeData(style: OutlinedButton.styleFrom(minimumSize: const Size(64, 48), shape: const StadiumBorder())),
      inputDecorationTheme: InputDecorationTheme(border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)), filled: true, fillColor: dark ? const Color(0xFF1D2136) : Colors.white),
      chipTheme: ChipThemeData(shape: const StadiumBorder(), side: BorderSide.none, backgroundColor: dark ? const Color(0xFF262B45) : const Color(0xFFEEF0FB)),
      dialogTheme: DialogThemeData(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20))),
      listTileTheme: const ListTileThemeData(iconColor: brandBlue),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    return MaterialApp(
      navigatorKey: navKey,
      scaffoldMessengerKey: messengerKey,
      title: 'Unique Health (clone)',
      debugShowCheckedModeBanner: false,
      theme: _theme(Brightness.light),
      darkTheme: _theme(Brightness.dark),
      themeMode: s.themeMode,
      locale: s.ready ? Locale(s.lang) : null,
      supportedLocales: [for (final c in I18n.languages.keys) Locale(c)],
      localizationsDelegates: const [GlobalMaterialLocalizations.delegate, GlobalWidgetsLocalizations.delegate, GlobalCupertinoLocalizations.delegate],
      home: !s.ready
          ? const Scaffold(body: Center(child: CircularProgressIndicator()))
          : (s.user == null ? const AuthScreen() : const HomeScreen()),
    );
  }
}
