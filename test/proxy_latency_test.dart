import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/settings/proxy_latency.dart';

/// A connector that fails every dial with a [SocketException] carrying
/// [message], standing in for a port that refuses or a host that will not
/// resolve.
ProxySocketConnect _refusing(String message) =>
    (host, port, {timeout}) => Future<Socket>.error(SocketException(message));

/// A connector whose dials never complete inside the probe's timeout.
ProxySocketConnect _timingOut(String message) =>
    (host, port, {timeout}) => Future<Socket>.error(TimeoutException(message));

void main() {
  test('grades a latency by the band it falls into', () {
    expect(proxyLatencyGrade(0), ProxyLatencyGrade.excellent);
    expect(proxyLatencyGrade(120), ProxyLatencyGrade.excellent);
    expect(proxyLatencyGrade(121), ProxyLatencyGrade.good);
    expect(proxyLatencyGrade(300), ProxyLatencyGrade.good);
    expect(proxyLatencyGrade(301), ProxyLatencyGrade.fair);
    expect(proxyLatencyGrade(800), ProxyLatencyGrade.fair);
    expect(proxyLatencyGrade(801), ProxyLatencyGrade.poor);
  });

  test('reports the fastest attempt and counts the rest as failures', () {
    const report = ProxyLatencyReport([
      ProxyProbeSample.connected(240),
      ProxyProbeSample.failed(ProxyProbeOutcome.timedOut),
      ProxyProbeSample.connected(90),
    ]);

    expect(report.attempts, 3);
    expect(report.reached, isTrue);
    expect(report.latencies, [240, 90]);
    expect(report.best, 90);
    expect(report.average, 165);
    expect(report.failures, 1);
    expect(report.lastFailure, ProxyProbeOutcome.timedOut);
  });

  test('an untouched report claims nothing', () {
    const report = ProxyLatencyReport.none();

    expect(report.attempts, 0);
    expect(report.reached, isFalse);
    expect(report.best, isNull);
    expect(report.average, isNull);
    expect(report.lastFailure, isNull);
    expect(report.failures, 0);
  });

  test('times a real dial to an endpoint that is listening', () async {
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(server.close);
    final progress = <int>[];

    final report = await ProxyLatencyProbe(attempts: 2).run(
      InternetAddress.loopbackIPv4.address,
      server.port,
      onProgress: (soFar) => progress.add(soFar.attempts),
    );

    expect(report.attempts, 2);
    expect(report.reached, isTrue);
    expect(report.best, isNotNull);
    expect(report.failures, 0);
    // One report per attempt, so a caller can show a result before the last
    // one lands.
    expect(progress, [1, 2]);
  });

  test('a refused port is reported as refused on every attempt', () async {
    final report = await ProxyLatencyProbe(
      attempts: 2,
      connect: _refusing('Connection refused'),
    ).run('proxy.example', 443);

    expect(report.attempts, 2);
    expect(report.reached, isFalse);
    expect(report.best, isNull);
    expect(report.failures, 2);
    expect(report.lastFailure, ProxyProbeOutcome.refused);
  });

  test('an unresolvable host is reported as such', () async {
    final report = await ProxyLatencyProbe(
      attempts: 1,
      connect: _refusing('Failed host lookup: proxy.example'),
    ).run('proxy.example', 443);

    expect(report.lastFailure, ProxyProbeOutcome.unresolved);
  });

  test('a dial that runs out its timeout is reported as a timeout', () async {
    final report = await ProxyLatencyProbe(
      attempts: 1,
      connect: _timingOut('dial timed out'),
    ).run('proxy.example', 443);

    expect(report.lastFailure, ProxyProbeOutcome.timedOut);
  });

  test('a dial that fails for another reason stays generic', () async {
    final report = await ProxyLatencyProbe(
      attempts: 1,
      connect: _refusing('Something else went wrong'),
    ).run('proxy.example', 443);

    expect(report.lastFailure, ProxyProbeOutcome.failed);
  });

  test('a run always dials at least once', () async {
    final report = await ProxyLatencyProbe(
      attempts: 0,
      connect: _refusing('Connection refused'),
    ).run('proxy.example', 443);

    expect(report.attempts, 1);
  });
}
