// lib/Services/version_check_service.dart
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:ubbottleapp/ModelPages/LandingMenuPages/offline_form_pages/db/offline_db_constants.dart';
// import 'package:ubbottleapp/Constants/AppStorage.dart';
import 'package:ubbottleapp/ModelPages/SpalshPage/local_update/model/app_version_info_model.dart';
import 'package:ubbottleapp/Utils/LogServices/LogService.dart';

class VersionCheckService {
  static const String _tag = "[VERSION_CHECK]";
//TODO check for internetavailability
//TODO check
  // static const String versionInfoUrl =
  //     'https://raw.githubusercontent.com/amrith4agile/offline_sample_pages/refs/heads/main/appVersionInfo.json';

  static Future<AppVersionInfo?> fetchRemoteVersionInfo() async {
    try {
      final response = await http
          .get(Uri.parse(OfflineDBConstants.VERSION_INFO_URL()))
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        if (decoded is Map<String, dynamic>) {
          final info = AppVersionInfo.fromJson(decoded);
          LogService.writeLog(
            message: "$_tag Fetched remote version info: "
                "version=${info.versionPart} build=${info.buildPart} "
                "forceUpdate=${info.forceUpdate}",
          );
          return info;
        }
      }
      LogService.writeLog(
        message:
            "$_tag Non-200 or bad shape — statusCode=${response.statusCode}",
      );
    } catch (e) {
      LogService.writeLog(message: "$_tag EXCEPTION fetching version info: $e");
    }
    return null;
  }

  static Future<bool> isUpdateAvailable(AppVersionInfo remote) async {
    final packageInfo = await PackageInfo.fromPlatform();
    final String localVersion = packageInfo.version;
    final int localBuild = int.tryParse(packageInfo.buildNumber) ?? 0;

    final int versionCompare =
        _compareVersionStrings(remote.versionPart, localVersion);

    LogService.writeLog(
      message:
          "$_tag local=$localVersion+$localBuild remote=${remote.versionPart}+${remote.buildPart} "
          "versionCompare=$versionCompare",
    );

    if (versionCompare > 0) return true;
    if (versionCompare == 0 && remote.buildPart > localBuild) return true;
    return false;
  }

  static int _compareVersionStrings(String a, String b) {
    final aParts = a.split('.').map((e) => int.tryParse(e) ?? 0).toList();
    final bParts = b.split('.').map((e) => int.tryParse(e) ?? 0).toList();
    final maxLen =
        aParts.length > bParts.length ? aParts.length : bParts.length;

    for (int i = 0; i < maxLen; i++) {
      final av = i < aParts.length ? aParts[i] : 0;
      final bv = i < bParts.length ? bParts[i] : 0;
      if (av != bv) return av.compareTo(bv);
    }
    return 0;
  }
}
