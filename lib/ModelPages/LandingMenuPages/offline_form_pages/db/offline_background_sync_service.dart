import 'dart:developer';

import 'package:flutter/widgets.dart';
import 'package:get/get.dart';
import 'package:ubbottleapp/Constants/AppStorage.dart';
import 'package:ubbottleapp/ModelPages/LandingMenuPages/offline_form_pages/db/offline_db_module.dart';
import 'package:ubbottleapp/Utils/LogServices/LogService.dart';
import 'package:workmanager/workmanager.dart';

const int _kDefaultIntervalMinutes = 15;
const int _kMinIntervalMinutes = 15;
const String _kWmTaskName = 'offline_bg_sync_task';
const String _kWmTaskTag = 'offline_bg_sync';
const String _tag = '[BG_SYNC]';

String _intervalKey(String username, String projectName) =>
    'sync_interval_${username}_$projectName';
@pragma('vm:entry-point')
void offlineSyncWorkManagerDispatcher() {
  Workmanager().executeTask((taskName, inputData) async {
    // 1. Initialize Bindings first
    WidgetsFlutterBinding.ensureInitialized();

    try {
      await OfflineDbModule.init();
      await LogService.writeLog(message: '$_tag WM INITIALIZED');
      await _executeSyncCycle(source: "WM_$taskName");

      return Future.value(true);
    } catch (e) {
      await LogService.writeLog(message: '$_tag CRITICAL WM FAIL: $e');
      return Future.value(false);
    }
  });
}

// Future<void> _executeSyncCycle({String source = 'WorkManager'}) async {
//   await LogService.writeLog(message: '$_tag [$source] Push cycle started.');

//   try {
//     final String result = await OfflineDbModule.processPendingQueue(
//       isInternetAvailable: true,
//     );

//     await OfflineDbModule.updateLastSyncedTimestamp();
//     await OfflineDbModule.logAudit(
//       action: 'BG_PUSH_ONLY',
//       remarks: '[$source] Push complete. Result: $result',
//     );

//     await LogService.writeLog(message: '$_tag [$source] Push Success: $result');
//   } catch (e) {
//     await LogService.writeLog(message: '$_tag [$source] Push FAILED: $e');
//   }
// }
Future<void> _executeSyncCycle({String source = 'WorkManager'}) async {
  await LogService.writeLog(message: '$_tag [$source] Push cycle started.');

  try {
    final String result = await OfflineDbModule.backgroundPushPendingQueue();

    await OfflineDbModule.updateLastSyncedTimestamp();
    await OfflineDbModule.logAudit(
      action: 'BG_PUSH_ONLY',
      remarks: '[$source] Push complete. Result: $result',
    );

    await LogService.writeLog(message: '$_tag [$source] Push Success: $result');
  } catch (e) {
    await LogService.writeLog(message: '$_tag [$source] Push FAILED: $e');
  }
}

class OfflineBackgroundSyncService {
  //TODO initial do the 3 part cycle => push => fetch form => datasource
// TODO after initial => only push pending records
  OfflineBackgroundSyncService._();
  static final OfflineBackgroundSyncService instance =
      OfflineBackgroundSyncService._();

  final RxString statusMessage = 'Idle'.obs;

  final RxBool isSyncing = false.obs;

  final Rxn<String> lastSyncedAt = Rxn<String>();

  final RxInt intervalMinutes = _kDefaultIntervalMinutes.obs;

  bool _wmInitialized = false;
  bool _isRunning = false;

  Future<void> initWorkManager() async {
    if (_wmInitialized) return;
    await Workmanager().initialize(
      offlineSyncWorkManagerDispatcher,
      isInDebugMode: false,
    );
    _wmInitialized = true;
    log('$_tag WorkManager initialized.', name: _tag);
  }

  Future<void> start() async {
    var pages = await OfflineDbModule.getOfflinePages();
    final bool hasOfflineForms = pages.isNotEmpty;
    if (!hasOfflineForms) {
      log('$_tag No offline forms found. Skipping WM registration.',
          name: _tag);
      await _cancelWmTask();
      _isRunning = false;
      return;
    }

    _isRunning = true;
    final int minutes = await getIntervalMinutes();
    intervalMinutes.value = minutes;

    await _registerWmTask(
        minutes: minutes, policy: ExistingPeriodicWorkPolicy.replace);
    await OfflineDbModule.fetchAndStoreOfflinePages();
    await OfflineDbModule.refreshAllDatasourcesFromDownloadedPages();
    await _refreshStatusFromDb();
    log('$_tag Background Sync Started. Interval: $minutes min.', name: _tag);
  }

  Future<void> stop() async {
    await _cancelWmTask();

    _isRunning = false;
    isSyncing.value = false;
    lastSyncedAt.value = null;
    intervalMinutes.value = _kDefaultIntervalMinutes;
    statusMessage.value = 'Idle';

    log('$_tag Stopped.', name: _tag);
    await LogService.writeLog(message: '$_tag Stopped (logout).');
  }

  bool get isRunning => _isRunning;

  Future<void> onAppResumed() async {
    if (!_isRunning) return;
    await _refreshStatusFromDb();
    log('$_tag App resumed — status refreshed from DB.', name: _tag);
  }

  Future<int> getIntervalMinutes() async {
    try {
      final String? username =
          await AppStorage().retrieveValue(AppStorage.USER_NAME);
      final String? projectName =
          await AppStorage().retrieveValue(AppStorage.PROJECT_NAME);

      if (username == null || projectName == null)
        return _kDefaultIntervalMinutes;

      final dynamic stored =
          await AppStorage().retrieveValue(_intervalKey(username, projectName));

      if (stored == null) return _kDefaultIntervalMinutes;

      return (int.tryParse(stored.toString()) ?? _kDefaultIntervalMinutes)
          .clamp(_kMinIntervalMinutes, 1440);
    } catch (_) {
      return _kDefaultIntervalMinutes;
    }
  }

  Future<void> setIntervalMinutes(int minutes) async {
    final int clamped = minutes.clamp(_kMinIntervalMinutes, 1440);

    final String? username =
        await AppStorage().retrieveValue(AppStorage.USER_NAME);
    final String? projectName =
        await AppStorage().retrieveValue(AppStorage.PROJECT_NAME);

    if (username != null && projectName != null) {
      await AppStorage().storeValue(
        _intervalKey(username, projectName),
        clamped.toString(),
      );
    }

    intervalMinutes.value = clamped;

    if (_isRunning) {
      await _registerWmTask(
        minutes: clamped,
        policy: ExistingPeriodicWorkPolicy.replace,
      );
      _updateStatus('Background sync active (every ${_labelFor(clamped)})');
    }

    await LogService.writeLog(
      message:
          '$_tag Interval set to $clamped min for $username / $projectName.',
    );
  }

  Future<void> triggerImmediateSync() async {
    if (isSyncing.value) return;

    isSyncing.value = true;
    _updateStatus('Syncing…');

    try {
      await _executeSyncCycle(source: 'Manual');
      await _refreshStatusFromDb();
    } catch (e) {
      _updateStatus('Sync error — retrying on next cycle');
      await LogService.writeLog(message: '$_tag Manual sync FAILED: $e');
      await OfflineDbModule.logAudit(
        action: 'BG_SYNC_CYCLE',
        isError: true,
        response: e.toString(),
        remarks: 'triggerImmediateSync threw an exception.',
      );
    } finally {
      isSyncing.value = false;
    }
  }

  Future<void> _registerWmTask({
    required int minutes,
    required ExistingPeriodicWorkPolicy policy,
  }) async {
    if (!_wmInitialized) return;

    await Workmanager().registerPeriodicTask(
      _kWmTaskName,
      _kWmTaskName,
      tag: _kWmTaskTag,
      frequency: Duration(minutes: minutes),
      existingWorkPolicy: policy,
      constraints: Constraints(
        networkType: NetworkType.connected,
        requiresBatteryNotLow: false,
        requiresCharging: false,
        requiresDeviceIdle: false,
      ),
      backoffPolicy: BackoffPolicy.linear,
      backoffPolicyDelay: const Duration(seconds: 10),
    );

    log('$_tag WM task registered. Interval: ${minutes}min.', name: _tag);
  }

  Future<void> _cancelWmTask() async {
    if (!_wmInitialized) return;
    await Workmanager().cancelByUniqueName(_kWmTaskName);
    log('$_tag WM task cancelled.', name: _tag);
  }

  Future<void> _refreshStatusFromDb() async {
    try {
      final String? ts = await OfflineDbModule.getLastSyncedTimestamp();

      if (ts == null || ts.isEmpty) {
        _updateStatus('Not yet synced');
        return;
      }

      lastSyncedAt.value = ts;
      final DateTime dt = DateTime.parse(ts).toLocal();
      _updateStatus('Last sync: ${_formatDateTime(dt)}');
    } catch (_) {
      _updateStatus('Background sync active');
    }
  }

  void _updateStatus(String msg) => statusMessage.value = msg;

  String _formatDateTime(DateTime dt) {
    final now = DateTime.now();
    final time =
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';

    final isToday =
        dt.year == now.year && dt.month == now.month && dt.day == now.day;
    if (isToday) return 'Today $time';

    final yesterday = now.subtract(const Duration(days: 1));
    final isYesterday = dt.year == yesterday.year &&
        dt.month == yesterday.month &&
        dt.day == yesterday.day;
    if (isYesterday) return 'Yesterday $time';

    return '${dt.day}/${dt.month}/${dt.year} $time';
  }

  String _labelFor(int minutes) {
    if (minutes < 60) return '$minutes min';
    if (minutes == 60) return '1 hour';
    if (minutes < 1440) return '${minutes ~/ 60} hours';
    return '24 hours';
  }
}

class AppLifecycleObserver extends WidgetsBindingObserver {
  AppLifecycleObserver._();
  static final AppLifecycleObserver instance = AppLifecycleObserver._();

  void register() => WidgetsBinding.instance.addObserver(this);
  void unregister() => WidgetsBinding.instance.removeObserver(this);

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      OfflineBackgroundSyncService.instance.onAppResumed();
    }
  }
}
