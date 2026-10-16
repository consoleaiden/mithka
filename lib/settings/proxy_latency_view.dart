//
//  proxy_latency_view.dart
//
//  The body of the add-proxy confirmation: what a probe measured against the
//  link the user just tapped, and a way to measure it again.
//

import 'dart:async';

import 'package:flutter/material.dart';

import '../components/app_interactive_surface.dart';
import '../l10n/app_localizations.dart';
import '../theme/app_theme.dart';
import 'proxy_latency.dart';

/// Times [host]:[port] and renders the result, so the user can tell whether a
/// proxy link is worth saving before they confirm it.
///
/// The first probe starts on its own. The user has already asked for this link
/// to be added, and reachability is the one thing about it they cannot see from
/// the address — the reason the dialog exists at all.
class ProxyLatencyView extends StatefulWidget {
  const ProxyLatencyView({
    super.key,
    required this.host,
    required this.port,
    this.probe,
  });

  final String host;
  final int port;

  /// Drives the measurements. Injected by tests; production dials for real.
  final ProxyLatencyProbe? probe;

  @override
  State<ProxyLatencyView> createState() => _ProxyLatencyViewState();
}

class _ProxyLatencyViewState extends State<ProxyLatencyView> {
  late final ProxyLatencyProbe _probe = widget.probe ?? ProxyLatencyProbe();

  ProxyLatencyReport _report = const ProxyLatencyReport.none();
  bool _running = false;

  /// Identifies the current run, so a sample that lands after the user asked
  /// for a re-test cannot repaint the view with the old endpoint's numbers.
  int _runId = 0;

  @override
  void initState() {
    super.initState();
    // Deferred by a frame: the probe reports through setState, and this view is
    // built as part of the dialog's own build.
    WidgetsBinding.instance.addPostFrameCallback((_) => _startRun());
  }

  void _startRun() {
    if (!mounted || _running) return;
    unawaited(_run());
  }

  Future<void> _run() async {
    final runId = ++_runId;
    setState(() {
      _report = const ProxyLatencyReport.none();
      _running = true;
    });
    final report = await _probe.run(
      widget.host,
      widget.port,
      onProgress: (soFar) {
        if (!mounted || runId != _runId) return;
        setState(() => _report = soFar);
      },
    );
    if (!mounted || runId != _runId) return;
    setState(() {
      _report = report;
      _running = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        _panel(context),
        const SizedBox(height: AppSpacing.xs),
        _retest(context),
      ],
    );
  }

  Widget _panel(BuildContext context) {
    final c = context.colors;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: c.searchFill,
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.lg,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: _lines(context),
        ),
      ),
    );
  }

  List<Widget> _lines(BuildContext context) {
    final c = context.colors;
    final report = _report;
    final best = report.best;

    if (best != null) {
      final grade = proxyLatencyGrade(best);
      final colour = _gradeColour(c, grade);
      return [
        _measurement(
          context,
          value: AppStrings.t(AppStringKeys.proxyLatencyValue, {'ms': best}),
          colour: colour,
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          AppStrings.t(_gradeKey(grade)),
          style: AppTextStyle.footnote(colour, weight: AppTextWeight.semibold),
        ),
        // Only worth saying when something failed: an endpoint that answered
        // every time has nothing to explain.
        if (report.failures > 0) ...[
          const SizedBox(height: AppSpacing.xxs),
          Text(
            AppStrings.t(AppStringKeys.proxyLatencyAttempts, {
              'ok': report.latencies.length,
              'total': report.attempts,
            }),
            style: AppTextStyle.footnote(c.textSecondary),
          ),
        ],
      ];
    }

    if (_running) {
      return [
        Row(
          children: [
            SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(c.textSecondary),
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Text(
              AppStrings.t(AppStringKeys.proxyLatencyTesting),
              style: AppTextStyle.footnote(c.textSecondary),
            ),
          ],
        ),
      ];
    }

    return [
      _measurement(
        context,
        value: AppStrings.t(AppStringKeys.proxyLatencyUnreachable),
        colour: AppTheme.tagRed,
      ),
      const SizedBox(height: AppSpacing.xs),
      Text(
        AppStrings.t(_failureKey(report.lastFailure)),
        style: AppTextStyle.footnote(c.textSecondary),
      ),
    ];
  }

  Widget _measurement(
    BuildContext context, {
    required String value,
    required Color colour,
  }) {
    final c = context.colors;
    return Row(
      children: [
        Expanded(
          child: Text(
            AppStrings.t(AppStringKeys.proxyLatencyLabel),
            style: AppTextStyle.footnote(c.textSecondary),
          ),
        ),
        const SizedBox(width: AppSpacing.md),
        Text(
          value,
          style: AppTextStyle.bodyLarge(
            colour,
            weight: AppTextWeight.semibold,
          ),
        ),
      ],
    );
  }

  Widget _retest(BuildContext context) {
    final c = context.colors;
    final label = AppStrings.t(AppStringKeys.proxyLatencyRetest);
    return AppInteractiveSurface(
      semanticLabel: label,
      enabled: !_running,
      borderRadius: BorderRadius.circular(AppRadius.control),
      onTap: _running ? null : _startRun,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 34),
        child: Center(
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: AppTextStyle.footnote(
              _running ? c.textTertiary : c.linkBlue,
              weight: AppTextWeight.semibold,
            ),
          ),
        ),
      ),
    );
  }

  /// A fast hop is the accent, a slow one the same red the app uses for a
  /// failed state, and the band between them stays neutral: colour is the
  /// glanceable half of the answer, the word is the precise half.
  Color _gradeColour(AppColors c, ProxyLatencyGrade grade) {
    if (grade == ProxyLatencyGrade.poor) return AppTheme.tagRed;
    if (grade == ProxyLatencyGrade.fair) return c.textSecondary;
    return AppTheme.cloverGreen;
  }

  String _gradeKey(ProxyLatencyGrade grade) => switch (grade) {
    ProxyLatencyGrade.excellent => AppStringKeys.proxyLatencyGradeExcellent,
    ProxyLatencyGrade.good => AppStringKeys.proxyLatencyGradeGood,
    ProxyLatencyGrade.fair => AppStringKeys.proxyLatencyGradeFair,
    ProxyLatencyGrade.poor => AppStringKeys.proxyLatencyGradePoor,
  };

  String _failureKey(ProxyProbeOutcome? outcome) {
    if (outcome == ProxyProbeOutcome.unresolved) {
      return AppStringKeys.proxyLatencyReasonUnresolved;
    }
    if (outcome == ProxyProbeOutcome.refused) {
      return AppStringKeys.proxyLatencyReasonRefused;
    }
    if (outcome == ProxyProbeOutcome.timedOut) {
      return AppStringKeys.proxyLatencyReasonTimedOut;
    }
    return AppStringKeys.proxyLatencyReasonFailed;
  }
}
