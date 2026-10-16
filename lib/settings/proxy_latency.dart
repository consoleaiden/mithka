//
//  proxy_latency.dart
//
//  Answers "is this proxy link usable?" before the link is saved. A link
//  arrives in a chat message and is easy to trust on sight, so the add dialog
//  runs a probe and shows what it found while the link is still in front of
//  the user, rather than letting a dead host become a saved proxy.
//
//  What is timed is the TCP handshake to the proxy's own endpoint. That is the
//  one step SOCKS5, HTTP and MTProto proxies have in common: none of them can
//  carry a byte before it accepts a connection, so a refused or unanswered
//  dial rules a link out no matter what its secret or credentials turn out to
//  be. It is also the only test available at this point — a real round trip
//  through the tunnel would mean enabling the proxy, which is the very change
//  the user has not agreed to yet.
//

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

/// How one handshake attempt against a proxy endpoint ended.
enum ProxyProbeOutcome {
  /// The endpoint accepted the connection inside the timeout.
  connected,

  /// The host name could not be resolved, so nothing was dialled.
  unresolved,

  /// Something is there but refused the connection: nothing is listening on
  /// that port, which is what a wrong port looks like.
  refused,

  /// Nothing answered before the timeout elapsed. A blocked or filtered
  /// endpoint behaves this way.
  timedOut,

  /// The dial failed for a reason none of the above describes.
  failed,
}

/// One attempt, reduced to what a result line shows.
@immutable
class ProxyProbeSample {
  const ProxyProbeSample._(this.outcome, this.millis);

  /// An attempt that reached the endpoint, timed at [millis].
  const ProxyProbeSample.connected(int millis)
    : this._(ProxyProbeOutcome.connected, millis);

  /// An attempt that did not reach the endpoint.
  const ProxyProbeSample.failed(ProxyProbeOutcome outcome)
    : this._(outcome, null);

  final ProxyProbeOutcome outcome;

  /// How long the accepted handshake took, in milliseconds; null when the
  /// attempt never got that far.
  final int? millis;

  @override
  String toString() => millis == null
      ? 'ProxyProbeSample(${outcome.name})'
      : 'ProxyProbeSample(${millis}ms)';
}

/// Every attempt of one run, reduced to what the dialog reports.
@immutable
class ProxyLatencyReport {
  const ProxyLatencyReport(this.samples);

  /// A run that has not started — what the view holds before the first sample.
  const ProxyLatencyReport.none() : samples = const [];

  final List<ProxyProbeSample> samples;

  int get attempts => samples.length;

  /// The attempts that reached the endpoint, in milliseconds.
  List<int> get latencies {
    final values = <int>[];
    for (final sample in samples) {
      final millis = sample.millis;
      if (millis != null) values.add(millis);
    }
    return values;
  }

  /// Whether the endpoint answered at least once. One success is enough to
  /// call a link usable: the failure that follows it is the network, not the
  /// link.
  bool get reached => latencies.isNotEmpty;

  int get failures => attempts - latencies.length;

  /// The fastest handshake. A single slow attempt is congestion on the way
  /// there, so the best sample is what describes the proxy itself.
  int? get best {
    int? fastest;
    for (final sample in samples) {
      final millis = sample.millis;
      if (millis == null) continue;
      if (fastest == null || millis < fastest) fastest = millis;
    }
    return fastest;
  }

  /// The mean of the attempts that connected, rounded down.
  int? get average {
    var total = 0;
    var count = 0;
    for (final sample in samples) {
      final millis = sample.millis;
      if (millis == null) continue;
      total += millis;
      count++;
    }
    return count == 0 ? null : total ~/ count;
  }

  /// Why the last attempt failed, for the line shown when nothing connected.
  ProxyProbeOutcome? get lastFailure {
    ProxyProbeOutcome? outcome;
    for (final sample in samples) {
      if (sample.millis == null) outcome = sample.outcome;
    }
    return outcome;
  }
}

/// How a latency reads to a person, so the dialog can label the number instead
/// of leaving the user to judge a millisecond count.
enum ProxyLatencyGrade { excellent, good, fair, poor }

/// The band [millis] falls into.
///
/// The thresholds are round trips a proxy hop is worth living with: under
/// 120 ms is indistinguishable from a direct connection for messaging, past
/// 800 ms every send visibly waits on the hop.
ProxyLatencyGrade proxyLatencyGrade(int millis) {
  if (millis <= 120) return ProxyLatencyGrade.excellent;
  if (millis <= 300) return ProxyLatencyGrade.good;
  if (millis <= 800) return ProxyLatencyGrade.fair;
  return ProxyLatencyGrade.poor;
}

/// Opens one TCP connection to a proxy endpoint.
///
/// Injectable so a test can drive the probe's timing and its failure handling
/// without a listening socket.
typedef ProxySocketConnect =
    Future<Socket> Function(String host, int port, {Duration? timeout});

/// Times the TCP handshake to a proxy endpoint, a few times over.
class ProxyLatencyProbe {
  ProxyLatencyProbe({
    this.attempts = 3,
    this.timeout = const Duration(seconds: 3),
    ProxySocketConnect? connect,
  }) : _connect = connect ?? _dial;

  /// Attempts per run. Repeats are what make the fastest sample meaningful, so
  /// the number is never below one.
  final int attempts;

  /// How long one attempt may take before it is called a timeout.
  final Duration timeout;

  final ProxySocketConnect _connect;

  static Future<Socket> _dial(String host, int port, {Duration? timeout}) =>
      Socket.connect(host, port, timeout: timeout);

  /// Dials [host]:[port], reporting each attempt as it lands.
  ///
  /// [onProgress] receives the samples collected so far. That matters on the
  /// path where the endpoint never answers: every attempt has to run out its
  /// timeout, and a caller that waits for the whole run shows a spinner for
  /// seconds with nothing to say.
  Future<ProxyLatencyReport> run(
    String host,
    int port, {
    void Function(ProxyLatencyReport soFar)? onProgress,
  }) async {
    final samples = <ProxyProbeSample>[];
    final rounds = attempts < 1 ? 1 : attempts;
    for (var attempt = 0; attempt < rounds; attempt++) {
      samples.add(await _attempt(host, port));
      onProgress?.call(ProxyLatencyReport(List<ProxyProbeSample>.of(samples)));
    }
    return ProxyLatencyReport(List<ProxyProbeSample>.of(samples));
  }

  Future<ProxyProbeSample> _attempt(String host, int port) async {
    final stopwatch = Stopwatch()..start();
    try {
      final socket = await _connect(host, port, timeout: timeout);
      stopwatch.stop();
      final millis = stopwatch.elapsedMilliseconds;
      // The handshake is the whole measurement — nothing is read or written —
      // so the connection is closed the moment it has been timed. A dial that
      // failed never produced a socket to close.
      socket.destroy();
      return ProxyProbeSample.connected(millis);
    } on TimeoutException {
      return const ProxyProbeSample.failed(ProxyProbeOutcome.timedOut);
    } on SocketException catch (error) {
      return ProxyProbeSample.failed(_outcomeFor(error));
    } catch (_) {
      return const ProxyProbeSample.failed(ProxyProbeOutcome.failed);
    }
  }

  /// Reads Dart's failure text, which is the only cross-platform signal there
  /// is: `SocketException.osError` codes are per-operating-system, while the
  /// wording for name resolution, refusal and timeout is stable across them.
  static ProxyProbeOutcome _outcomeFor(SocketException error) {
    final text = '${error.message} ${error.osError?.message ?? ''}'
        .toLowerCase();
    if (text.contains('failed host lookup') ||
        text.contains('nodename nor servname') ||
        text.contains('no address associated')) {
      return ProxyProbeOutcome.unresolved;
    }
    if (text.contains('timed out') || text.contains('timeout')) {
      return ProxyProbeOutcome.timedOut;
    }
    if (text.contains('refused')) {
      return ProxyProbeOutcome.refused;
    }
    return ProxyProbeOutcome.failed;
  }
}
