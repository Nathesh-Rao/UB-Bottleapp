import 'dart:convert';
import 'dart:developer';

import 'package:http/http.dart' as http;
import 'package:ubbottleapp/Constants/AppStorage.dart';
import 'package:ubbottleapp/ModelPages/LandingMenuPages/offline_form_pages/db/offline_db_constants.dart';
import 'package:ubbottleapp/Utils/LogServices/LogService.dart';

const String _tag = '[OFFLINE_CONFIG]';

const String kOfflineSyncIntervalKey = 'offline_sync_interval_minutes';

const int kDefaultSyncInterval = 15;

class OfflineConfigService {
  OfflineConfigService._();
  static String _configUrl = OfflineDBConstants.OFFLINE_CONFIG_URL();
  static Future<int> fetchAndStore() async {
    try {
      final response = await http
          .get(Uri.parse(_configUrl))
          .timeout(const Duration(seconds: 10));

      if (response.statusCode != 200 || response.body.isEmpty) {
        await LogService.writeLog(
            message:
                '$_tag Fetch failed — HTTP ${response.statusCode}. Using fallback: ${kDefaultSyncInterval}min.');
        return _useFallback();
      }

      final Map<String, dynamic> json = jsonDecode(response.body);
      final int interval = (json['sync_interval_minutes'] as num?)?.toInt() ??
          kDefaultSyncInterval;

      AppStorage().storeValue(kOfflineSyncIntervalKey, interval);

      await LogService.writeLog(
          message:
              '$_tag Config loaded. sync_interval_minutes=$interval${interval == 0 ? " → sync disabled" : ""}');

      log('$_tag interval=${interval}min.', name: _tag);
      return interval;
    } catch (e) {
      await LogService.writeLog(
          message:
              '$_tag Fetch error: $e. Using fallback: ${kDefaultSyncInterval}min.');
      return _useFallback();
    }
  }

  static int getCachedInterval() {
    final dynamic stored = AppStorage().retrieveValue(kOfflineSyncIntervalKey);
    if (stored == null) return kDefaultSyncInterval;
    return int.tryParse(stored.toString()) ?? kDefaultSyncInterval;
  }

  static int _useFallback() {
    final int cached = getCachedInterval();
    AppStorage().storeValue(kOfflineSyncIntervalKey, cached);
    return cached;
  }
}
