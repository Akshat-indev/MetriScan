import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'features/capture/scanner_screen.dart';
import 'features/history/history_screen.dart';
import 'features/ocr_review/ocr_review_screen.dart';
import 'features/report/report_screen.dart';
import 'features/training_export/training_export_screen.dart';
import 'core/models/compliance_report.dart';
import 'core/models/stage_capture.dart';

final _router = GoRouter(
  initialLocation: '/',
  routes: [
    GoRoute(
      path: '/',
      builder: (context, state) => const HistoryScreen(),
    ),
    GoRoute(
      path: '/scan',
      builder: (context, state) => const ScannerScreen(),
    ),
    GoRoute(
      path: '/ocr-review',
      builder: (context, state) {
        final captures = state.extra as List<StageCapture>;
        return OcrReviewScreen(captures: captures);
      },
    ),
    GoRoute(
      path: '/report',
      builder: (context, state) {
        final report = state.extra as ComplianceReport;
        return ReportScreen(report: report);
      },
    ),
    GoRoute(
      path: '/report/:id',
      builder: (context, state) {
        final id = state.pathParameters['id']!;
        return ReportScreen.fromHistory(scanId: id);
      },
    ),
    GoRoute(
      path: '/training-export',
      builder: (context, state) => const TrainingExportScreen(),
    ),
  ],
);

class MetriScanApp extends StatelessWidget {
  const MetriScanApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'MetriScan',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF1B5E20),
          brightness: Brightness.light,
        ),
        useMaterial3: true,
        appBarTheme: const AppBarTheme(
          centerTitle: true,
          elevation: 0,
        ),
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF1B5E20),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      routerConfig: _router,
    );
  }
}
