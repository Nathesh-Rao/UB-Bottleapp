// import 'dart:developer';

// import 'package:flutter/widgets.dart';
// import 'package:get/get.dart';
// import 'package:ubbottleapp/Constants/AppStorage.dart';
// import 'package:ubbottleapp/ModelPages/LandingMenuPages/offline_form_pages/db/offline_db_module.dart';
// import 'package:ubbottleapp/Utils/LogServices/LogService.dart';
// import 'package:workmanager/workmanager.dart';

// // ─────────────────────────────────────────────────────────────────────────────
// // HOW TO USE
// // ─────────────────────────────────────────────────────────────────────────────
// //
// // main.dart — before runApp:
// //   await OfflineBackgroundSyncService.instance.initWorkManager();
// //   AppLifecycleObserver.instance.register();
// //
// // After every login:
// //   await OfflineBackgroundSyncService.instance.start();
// //
// // On logout:
// //   await OfflineBackgroundSyncService.instance.stop();
// //
// // Settings — change interval for current user+project:
// //   await OfflineBackgroundSyncService.instance.setIntervalMinutes(60);
// //
// // Sync Now button:
// //   await OfflineBackgroundSyncService.instance.triggerImmediateSync();
// //
// // UI — bind these anywhere with Obx():
// //   OfflineBackgroundSyncService.instance.statusMessage   → "Last sync: Today 14:32"
// //   OfflineBackgroundSyncService.instance.isSyncing       → true during triggerImmediateSync
// //   OfflineBackgroundSyncService.instance.lastSyncedAt    → ISO-8601 string or null
// //   OfflineBackgroundSyncService.instance.intervalMinutes → current WM interval
// // ─────────────────────────────────────────────────────────────────────────────

// const int _kDefaultIntervalMinutes = 30;

// const int _kMinIntervalMinutes = 15;

// const String _kWmTaskName = 'offline_bg_sync_task';
// const String _kWmTaskTag = 'offline_bg_sync';
// const String _tag = '[BG_SYNC]';

// String _intervalKey(String username, String projectName) =>
//     'sync_interval_${username}_$projectName';

// @pragma('vm:entry-point')
// void offlineSyncWorkManagerDispatcher() {
//   Workmanager().executeTask((taskName, inputData) async {
//     log('$_tag WM fired: $taskName', name: _tag);
//     try {
//       WidgetsFlutterBinding.ensureInitialized();
//       await OfflineDbModule.init();
//       await _executeSyncCycle(source: taskName ?? 'WorkManager');
//       return true;
//     } catch (e, st) {
//       log('$_tag WM FAILED: $e\n$st', name: _tag);
//       return true;
//     }
//   });
// }

// Future<void> _executeSyncCycle({String source = 'WorkManager'}) async {
//   await LogService.writeLog(message: '$_tag [$source] Cycle started.');

//   try {
//     final String result = await OfflineDbModule.processPendingQueue(
//       isInternetAvailable: true,
//     );
//     log('$_tag [$source] Push: $result', name: _tag);
//   } catch (e) {
//     await LogService.writeLog(message: '$_tag [$source] Push FAILED: $e');
//   }

//   List<Map<String, dynamic>> pages = [];
//   try {
//     pages = await OfflineDbModule.fetchAndStoreOfflinePages();
//     log('$_tag [$source] Forms: ${pages.length}', name: _tag);
//   } catch (e) {
//     await LogService.writeLog(message: '$_tag [$source] Form fetch FAILED: $e');
//   }

//   try {
//     await OfflineDbModule.refreshAllDatasourcesFromDownloadedPages();
//   } catch (e) {
//     await LogService.writeLog(message: '$_tag [$source] DS refresh FAILED: $e');
//   }

//   await OfflineDbModule.updateLastSyncedTimestamp();

//   await OfflineDbModule.logAudit(
//     action: 'BG_SYNC_CYCLE',
//     remarks: '[$source] Cycle complete. Forms: ${pages.length}',
//   );

//   await LogService.writeLog(
//     message: '$_tag [$source] Done. Forms: ${pages.length}',
//   );
// }

// class OfflineBackgroundSyncService {
//   OfflineBackgroundSyncService._();
//   static final OfflineBackgroundSyncService instance =
//       OfflineBackgroundSyncService._();

//   final RxString statusMessage = 'Idle'.obs;

//   final RxBool isSyncing = false.obs;

//   final Rxn<String> lastSyncedAt = Rxn<String>();

//   final RxInt intervalMinutes = _kDefaultIntervalMinutes.obs;

//   bool _wmInitialized = false;
//   bool _isRunning = false;

//   Future<void> initWorkManager() async {
//     if (_wmInitialized) return;
//     await Workmanager().initialize(
//       offlineSyncWorkManagerDispatcher,

//     );
//     _wmInitialized = true;
//     log('$_tag WorkManager initialized.', name: _tag);
//   }

//   Future<void> start() async {
//     _isRunning = true;

//     final int minutes = await getIntervalMinutes();
//     intervalMinutes.value = minutes;

//     await _registerWmTask(
//         minutes: minutes, policy: ExistingPeriodicWorkPolicy.keep);
//     await _refreshStatusFromDb();

//     log('$_tag Started. Interval: $minutes min.', name: _tag);
//     await LogService.writeLog(
//         message: '$_tag Started. Interval: $minutes min.');
//   }

//   Future<void> stop() async {
//     _isRunning = false;
//     isSyncing.value = false;
//     lastSyncedAt.value = null;
//     intervalMinutes.value = _kDefaultIntervalMinutes;
//     statusMessage.value = 'Idle';

//     await _cancelWmTask();

//     log('$_tag Stopped.', name: _tag);
//     await LogService.writeLog(message: '$_tag Stopped (logout).');
//   }

//   bool get isRunning => _isRunning;

//   Future<void> onAppResumed() async {
//     if (!_isRunning) return;
//     await _refreshStatusFromDb();
//     log('$_tag App resumed — status refreshed.', name: _tag);
//   }

//   Future<int> getIntervalMinutes() async {
//     try {
//       final String? username =
//           await AppStorage().retrieveValue(AppStorage.USER_NAME);
//       final String? projectName =
//           await AppStorage().retrieveValue(AppStorage.PROJECT_NAME);

//       if (username == null || projectName == null)
//         return _kDefaultIntervalMinutes;

//       final dynamic stored =
//           await AppStorage().retrieveValue(_intervalKey(username, projectName));

//       if (stored == null) return _kDefaultIntervalMinutes;

//       return (int.tryParse(stored.toString()) ?? _kDefaultIntervalMinutes)
//           .clamp(_kMinIntervalMinutes, 1440);
//     } catch (_) {
//       return _kDefaultIntervalMinutes;
//     }
//   }

//   Future<void> setIntervalMinutes(int minutes) async {
//     final int clamped = minutes.clamp(_kMinIntervalMinutes, 1440);

//     final String? username =
//         await AppStorage().retrieveValue(AppStorage.USER_NAME);
//     final String? projectName =
//         await AppStorage().retrieveValue(AppStorage.PROJECT_NAME);

//     if (username != null && projectName != null) {
//       await AppStorage()
//           .storeValue(_intervalKey(username, projectName), clamped.toString());
//     }

//     intervalMinutes.value = clamped;

//     if (_isRunning) {
//       await _registerWmTask(
//           minutes: clamped, policy: ExistingPeriodicWorkPolicy.replace);
//       _updateStatus('Background sync active (every ${_labelFor(clamped)})');
//     }

//     await LogService.writeLog(
//       message:
//           '$_tag Interval updated to $clamped min for $username / $projectName.',
//     );
//   }

//   Future<void> triggerImmediateSync() async {
//     if (isSyncing.value) return;

//     isSyncing.value = true;
//     _updateStatus('Syncing…');

//     try {
//       await _executeSyncCycle(source: 'Manual');
//       await _refreshStatusFromDb();
//     } catch (e) {
//       _updateStatus('Sync error — retrying on next cycle');
//       await LogService.writeLog(message: '$_tag Manual sync FAILED: $e');
//       await OfflineDbModule.logAudit(
//         action: 'BG_SYNC_CYCLE',
//         isError: true,
//         response: e.toString(),
//         remarks: 'triggerImmediateSync threw an exception.',
//       );
//     } finally {
//       isSyncing.value = false;
//     }
//   }

//   Future<void> _registerWmTask({
//     required int minutes,
//     required ExistingPeriodicWorkPolicy policy,
//   }) async {
//     if (!_wmInitialized) return;

//     await Workmanager().registerPeriodicTask(
//       _kWmTaskName,
//       _kWmTaskName,
//       tag: _kWmTaskTag,
//       frequency: Duration(minutes: minutes),
//       existingWorkPolicy: policy,
//       constraints: Constraints(
//         networkType: NetworkType.connected,
//         requiresBatteryNotLow: false,
//         requiresCharging: false,
//         requiresDeviceIdle: false,
//       ),
//       backoffPolicy: BackoffPolicy.linear,
//       backoffPolicyDelay: const Duration(seconds: 10),
//     );

//     log('$_tag WM task registered. Interval: ${minutes}min.', name: _tag);
//   }

//   Future<void> _cancelWmTask() async {
//     if (!_wmInitialized) return;
//     await Workmanager().cancelByUniqueName(_kWmTaskName);
//     log('$_tag WM task cancelled.', name: _tag);
//   }

//   Future<void> _refreshStatusFromDb() async {
//     try {
//       final String? ts = await OfflineDbModule.getLastSyncedTimestamp();

//       if (ts == null || ts.isEmpty) {
//         _updateStatus('Not yet synced');
//         return;
//       }

//       lastSyncedAt.value = ts;
//       final DateTime dt = DateTime.parse(ts).toLocal();
//       _updateStatus('Last sync: ${_formatDateTime(dt)}');
//     } catch (_) {
//       _updateStatus('Background sync active');
//     }
//   }

//   void _updateStatus(String msg) => statusMessage.value = msg;

//   String _formatDateTime(DateTime dt) {
//     final now = DateTime.now();
//     final time =
//         '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';

//     final isToday =
//         dt.year == now.year && dt.month == now.month && dt.day == now.day;
//     if (isToday) return 'Today $time';

//     final yesterday = now.subtract(const Duration(days: 1));
//     final isYesterday = dt.year == yesterday.year &&
//         dt.month == yesterday.month &&
//         dt.day == yesterday.day;
//     if (isYesterday) return 'Yesterday $time';

//     return '${dt.day}/${dt.month}/${dt.year} $time';
//   }

//   String _labelFor(int minutes) {
//     if (minutes < 60) return '$minutes min';
//     if (minutes == 60) return '1 hour';
//     if (minutes < 1440) return '${minutes ~/ 60} hours';
//     return '24 hours';
//   }
// }

// class AppLifecycleObserver extends WidgetsBindingObserver {
//   AppLifecycleObserver._();
//   static final AppLifecycleObserver instance = AppLifecycleObserver._();

//   void register() => WidgetsBinding.instance.addObserver(this);
//   void unregister() => WidgetsBinding.instance.removeObserver(this);

//   @override
//   void didChangeAppLifecycleState(AppLifecycleState state) {
//     if (state == AppLifecycleState.resumed) {
//       OfflineBackgroundSyncService.instance.onAppResumed();
//     }
//   }
// }
import 'dart:developer';

import 'package:flutter/widgets.dart';
import 'package:get/get.dart';
import 'package:ubbottleapp/Constants/AppStorage.dart';
import 'package:ubbottleapp/ModelPages/LandingMenuPages/offline_form_pages/db/offline_db_module.dart';
import 'package:ubbottleapp/Utils/LogServices/LogService.dart';
import 'package:workmanager/workmanager.dart';

// ─────────────────────────────────────────────────────────────────────────────
// HOW TO USE
// ─────────────────────────────────────────────────────────────────────────────
//
// main.dart — before runApp:
//   await OfflineBackgroundSyncService.instance.initWorkManager();
//   AppLifecycleObserver.instance.register();
//
// After every login (same or different user — always restarts clean):
//   await OfflineBackgroundSyncService.instance.start();
//
// On logout:
//   await OfflineBackgroundSyncService.instance.stop();
//
// Settings screen — change interval for current user+project:
//   await OfflineBackgroundSyncService.instance.setIntervalMinutes(60);
//
// Sync Now button:
//   await OfflineBackgroundSyncService.instance.triggerImmediateSync();
//
// UI — bind with Obx(), all updated automatically:
//   .statusMessage   → "Last sync: Today 14:32" / "Syncing…" / "Not yet synced"
//   .isSyncing       → true only during triggerImmediateSync
//   .lastSyncedAt    → ISO-8601 string of last completed cycle, or null
//   .intervalMinutes → current WM interval in minutes for current user+project
// ─────────────────────────────────────────────────────────────────────────────

// ── Constants ─────────────────────────────────────────────────────────────────

const int _kDefaultIntervalMinutes = 30;
const int _kMinIntervalMinutes = 15;
const String _kWmTaskName = 'offline_bg_sync_task';
const String _kWmTaskTag = 'offline_bg_sync';
const String _tag = '[BG_SYNC]';

String _intervalKey(String username, String projectName) =>
    'sync_interval_${username}_$projectName';

@pragma('vm:entry-point')
void offlineSyncWorkManagerDispatcher() {
  Workmanager().executeTask((taskName, inputData) async {
    debugPrint('$_tag WM fired: $taskName');
    try {
      WidgetsFlutterBinding.ensureInitialized();

      await OfflineDbModule.init();

      await _executeSyncCycle(source: taskName ?? 'WorkManager');

      return true;
    } catch (e, st) {
      debugPrint('$_tag WM FAILED: $e\n$st');

      return true;
    }
  });
}

Future<void> _executeSyncCycle({String source = 'WorkManager'}) async {
  await LogService.writeLog(message: '$_tag [$source] Cycle started.');

  try {
    final String result = await OfflineDbModule.processPendingQueue(
      isInternetAvailable: true,
    );
    log('$_tag [$source] Push: $result', name: _tag);
  } catch (e) {
    await LogService.writeLog(message: '$_tag [$source] Push FAILED: $e');
  }

  List<Map<String, dynamic>> pages = [];
  try {
    pages = await OfflineDbModule.fetchAndStoreOfflinePages();
    log('$_tag [$source] Forms: ${pages.length}', name: _tag);
  } catch (e) {
    await LogService.writeLog(message: '$_tag [$source] Form fetch FAILED: $e');
  }

  try {
    await OfflineDbModule.refreshAllDatasourcesFromDownloadedPages();
  } catch (e) {
    await LogService.writeLog(message: '$_tag [$source] DS refresh FAILED: $e');
  }

  await OfflineDbModule.updateLastSyncedTimestamp();

  await OfflineDbModule.logAudit(
    action: 'BG_SYNC_CYCLE',
    remarks: '[$source] Cycle complete. Forms: ${pages.length}',
  );

  await LogService.writeLog(
    message: '$_tag [$source] Done. Forms: ${pages.length}',
  );
}

class OfflineBackgroundSyncService {
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
    await _cancelWmTask();

    _isRunning = true;

    final int minutes = await getIntervalMinutes();
    intervalMinutes.value = minutes;

    await _registerWmTask(
        minutes: minutes, policy: ExistingPeriodicWorkPolicy.replace);

    await _refreshStatusFromDb();

    log('$_tag Started for current user. Interval: $minutes min.', name: _tag);
    await LogService.writeLog(
      message: '$_tag Started. Interval: $minutes min.',
    );
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
