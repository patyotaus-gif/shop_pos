import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

/// One available app update, parsed from the hosted manifest.
class AppUpdateInfo {
  const AppUpdateInfo({
    required this.version,
    required this.build,
    required this.url,
    required this.notes,
    required this.mandatory,
  });

  final String version;
  final int build;
  final String url;
  final String notes;
  final bool mandatory;
}

/// Self-hosted Android updates for the closed distribution (the app isn't on
/// Google Play, so there's no store auto-update). On launch the app reads a
/// version manifest; if a newer build is published it offers to download the
/// APK and hand it to the system installer. iOS is updated via TestFlight, so
/// every entry point here is a no-op off Android.
class UpdateService {
  static const _manifestUrl = 'https://pok-pok.app/app/version.json';

  /// Returns update info when a newer build is published, else null. Never
  /// throws — a network/parse hiccup must not block app startup.
  static Future<AppUpdateInfo?> checkForUpdate() async {
    if (!Platform.isAndroid) return null;
    try {
      final res = await http
          .get(Uri.parse(_manifestUrl))
          .timeout(const Duration(seconds: 8));
      if (res.statusCode != 200) return null;
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final remoteBuild = (data['build'] as num?)?.toInt() ?? 0;

      final info = await PackageInfo.fromPlatform();
      final currentBuild = int.tryParse(info.buildNumber) ?? 0;
      if (remoteBuild <= currentBuild) return null;

      final url = data['url']?.toString() ?? '';
      if (url.isEmpty) return null;
      return AppUpdateInfo(
        version: data['version']?.toString() ?? '',
        build: remoteBuild,
        url: url,
        notes: data['notes']?.toString() ?? '',
        mandatory: data['mandatory'] == true,
      );
    } catch (_) {
      return null;
    }
  }

  /// Stream the APK to a temp file, reporting progress 0..1. Returns the path.
  static Future<String> downloadApk(
    String url, {
    void Function(double progress)? onProgress,
  }) async {
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/pokpok-update.apk');
    final client = http.Client();
    try {
      final res = await client.send(http.Request('GET', Uri.parse(url)));
      if (res.statusCode != 200) {
        throw HttpException('โหลดไม่สำเร็จ (${res.statusCode})');
      }
      final total = res.contentLength ?? 0;
      var received = 0;
      final sink = file.openWrite();
      try {
        await for (final chunk in res.stream) {
          sink.add(chunk);
          received += chunk.length;
          if (total > 0) onProgress?.call(received / total);
        }
      } finally {
        await sink.close();
      }
      return file.path;
    } finally {
      client.close();
    }
  }

  /// Hand the downloaded APK to the system installer. The user must have
  /// granted "install unknown apps" for Pokpok (Android prompts on first use).
  static Future<void> install(String path) async {
    await OpenFilex.open(
      path,
      type: 'application/vnd.android.package-archive',
    );
  }
}
