import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

class AppUpdateInfo {
  const AppUpdateInfo._({
    required this.version,
    required this.build,
    required this.url,
    required this.details,
    required this.mandatory,
    required this.platform,
    this.sha256,
    this.sizeBytes,
  });

  final String version;
  final int build;
  final Uri url;
  final List<String> details;
  final bool mandatory;
  final TargetPlatform platform;
  final String? sha256;
  final int? sizeBytes;

  bool matches(AppUpdateInfo? other) =>
      other != null &&
      version == other.version &&
      build == other.build &&
      platform == other.platform &&
      url == other.url &&
      mandatory == other.mandatory &&
      sha256 == other.sha256 &&
      sizeBytes == other.sizeBytes &&
      listEquals(details, other.details);

  static AppUpdateInfo? available(Map<String, dynamic> manifest,
      TargetPlatform platform, int installedBuild) {
    // Android builds and TestFlight builds have independent release numbers.
    final data = switch (platform) {
      TargetPlatform.android => manifest,
      TargetPlatform.iOS => manifest['ios'],
      _ => null,
    };
    if (data is! Map<String, dynamic>) return null;
    final build = data['build'];
    final version = data['version'];
    final url = Uri.tryParse(data['url'] is String ? data['url'] : '');
    if (build is! int ||
        build <= installedBuild ||
        version is! String ||
        version.trim().isEmpty ||
        url == null ||
        !url.isScheme('https') ||
        url.host.isEmpty) {
      return null;
    }
    if (platform == TargetPlatform.iOS &&
        (url.host != 'testflight.apple.com' ||
            !url.path.startsWith('/join/'))) {
      return null;
    }
    final items = data['details'];
    final details = items is List
        ? items
            .whereType<String>()
            .map((s) => s.trim())
            .where((s) => s.isNotEmpty)
            .toList()
        : <String>[];
    final notes = data['notes'];
    if (details.isEmpty && notes is String && notes.trim().isNotEmpty) {
      details.add(notes.trim());
    }
    final minBuild = data['minSupportedBuild'];
    return AppUpdateInfo._(
      version: version.trim(),
      build: build,
      url: url,
      platform: platform,
      details: List.unmodifiable(details),
      mandatory: data['mandatory'] == true ||
          minBuild is int && installedBuild < minBuild,
      sha256: data['sha256'] as String?,
      sizeBytes: data['sizeBytes'] as int?,
    );
  }
}

class UpdateService {
  static final _manifestUrl = Uri.parse('https://pok-pok.app/app/version.json');
  static const _cacheKey = 'update.lastPublishedManifest';

  static Future<AppUpdateInfo?> checkForUpdate() async {
    final platform = defaultTargetPlatform;
    if (kIsWeb ||
        (platform != TargetPlatform.android &&
            platform != TargetPlatform.iOS)) {
      return null;
    }
    try {
      final installed =
          int.parse((await PackageInfo.fromPlatform()).buildNumber);
      final prefs = await SharedPreferences.getInstance();
      try {
        final response =
            await http.get(_manifestUrl).timeout(const Duration(seconds: 8));
        if (response.statusCode == 200) {
          final source = utf8.decode(response.bodyBytes);
          final manifest = jsonDecode(source) as Map<String, dynamic>;
          final update = AppUpdateInfo.available(manifest, platform, installed);
          // A rollback or a withdrawn TestFlight build clears an old reminder.
          if (update != null) {
            if (prefs.getString(_cacheKey) != source) {
              await prefs.setString(_cacheKey, source);
            }
          } else if (prefs.containsKey(_cacheKey)) {
            await prefs.remove(_cacheKey);
          }
          return update;
        }
        if (response.statusCode == 404 || response.statusCode == 410) {
          await prefs.remove(_cacheKey);
          return null;
        }
      } catch (_) {
        // A store that already heard of an update can still read its details offline.
      }
      final cached = prefs.getString(_cacheKey);
      if (cached == null) return null;
      return AppUpdateInfo.available(
          jsonDecode(cached) as Map<String, dynamic>, platform, installed);
    } catch (_) {
      // Checking for updates must never prevent checkout from starting.
      return null;
    }
  }

  /// Complete the download before Android sees the APK. Verify the published
  /// size and digest when supplied (older manifests only contained a URL).
  static Future<String> downloadApk(
      AppUpdateInfo info, ValueChanged<double> onProgress,
      {Directory? directory}) async {
    final dir = directory ?? await getTemporaryDirectory();
    // A manifest correction can start a new download while the previous
    // request drains. Never write two responses into the same file.
    final attempt = await dir.createTemp('pokpok-download-');
    final file = File('${attempt.path}/download.part');
    final client = http.Client();
    try {
      final res = await client
          .send(http.Request('GET', info.url))
          .timeout(const Duration(seconds: 30));
      if (res.statusCode != 200) throw HttpException('HTTP ${res.statusCode}');
      final total = info.sizeBytes ?? res.contentLength ?? 0;
      var received = 0;
      final digest = Sha256().toSync().newHashSink();
      final sink = file.openWrite();
      try {
        await for (final chunk
            in res.stream.timeout(const Duration(seconds: 30))) {
          sink.add(chunk);
          digest.add(chunk);
          received += chunk.length;
          if (total > 0) onProgress((received / total).clamp(0.0, 1.0));
        }
      } finally {
        digest.close();
        await sink.close();
      }
      if (received == 0 || total > 0 && received != total) {
        throw const FormatException('Incomplete update');
      }
      final hash = await digest.hash();
      final hex =
          hash.bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
      if (info.sha256 != null && hex != info.sha256!.toLowerCase()) {
        throw const FormatException('Update checksum mismatch');
      }
      final apk = File('${dir.path}/pokpok-${info.build}-$hex.apk');
      await file.rename(apk.path);
      return apk.path;
    } finally {
      client.close();
      if (await file.exists()) await file.delete();
      await attempt.delete();
    }
  }

  static Future<void> install(AppUpdateInfo info, String? path) async {
    if (info.platform == TargetPlatform.iOS) {
      if (!await launchUrl(info.url, mode: LaunchMode.externalApplication)) {
        throw StateError('TestFlight unavailable');
      }
      return;
    }
    final result = await OpenFilex.open(path!,
        type: 'application/vnd.android.package-archive');
    if (result.type == ResultType.fileNotFound) {
      throw FileSystemException('Update file no longer available', path);
    }
    if (result.type != ResultType.done) throw StateError(result.type.name);
  }
}
