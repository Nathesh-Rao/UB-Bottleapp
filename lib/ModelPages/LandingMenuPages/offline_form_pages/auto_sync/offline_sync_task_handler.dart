import 'dart:async';
import 'dart:developer';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:get_storage/get_storage.dart';
import 'package:ubbottleapp/ModelPages/LandingMenuPages/offline_form_pages/db/offline_db_module.dart';
import 'package:ubbottleapp/Utils/LogServices/LogService.dart';

import 'sync_alert_notifier.dart';

const String _tag = '[FG_SYNC_TASK]';

// ─── Keys shared between both isolates ───────────────────────────────────────

class SyncDataKeys {
  // payload field keys
  static const String event = 'event';
  static const String current = 'current';
  static const String total = 'total';
  static const String result = 'result';
  static const String lastSyncedAt = 'lastSyncedAt';
  static const String pendingCount = 'pendingCount';
  static const String intervalMinutes = 'intervalMinutes';
  static const String evtAuthFailed = 'auth_failed';
  // events → main isolate
  static const String evtProgress = 'progress';
  static const String evtDone = 'done';
  static const String evtNoInternet = 'no_internet';
  static const String evtError = 'error';

  // commands → task isolate
  static const String cmdTriggerNow = 'trigger_now';
  static const String cmdUpdateInterval = 'update_interval';
}

// ─── Top-level entry point ────────────────────────────────────────────────────

@pragma('vm:entry-point')
void startSyncCallback() {
  FlutterForegroundTask.setTaskHandler(OfflineSyncTaskHandler());
}

// ─── Task Handler ─────────────────────────────────────────────────────────────

class OfflineSyncTaskHandler extends TaskHandler {
  bool _dbInitialized = false;
  bool _isCycleRunning = false;
  int _intervalMinutes = 0;
  Timer? _timer;

  // ── Lifecycle ──────────────────────────────────────────────────────────────

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    print('#### FG_SYNC_TASK onStart CALLED ####');
    // WidgetsFlutterBinding.ensureInitialized();
    FlutterForegroundTask.sendDataToMain({
      SyncDataKeys.event: 'debug_ping',
      'msg': 'onStart fired in isolate',
    });
    await GetStorage.init();
    await SyncAlertNotifier.init();
    _intervalMinutes =
        await FlutterForegroundTask.getData<int>(key: 'intervalMinutes') ?? 0;
    if (_intervalMinutes == 0) {
      await LogService.writeLog(
          message: '$_tag interval=0 — sync disabled by config. Task exiting.');
      FlutterForegroundTask.stopService();
      return;
    }
    // await LogService.writeLog(
    //     message:
    //         '$_tag onStart — interval: ${_intervalMinutes}min | armUrl: $_armUrl');

    await _ensureDbInitialized();
    await Future.delayed(const Duration(seconds: 3));
    await _runSyncCycle();

    _startTimer();
  }

  @override
  Future<void> onRepeatEvent(DateTime timestamp) async {}

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {
    _timer?.cancel();
    _timer = null;
    await LogService.writeLog(message: '$_tag onDestroy. isTimeout=$isTimeout');
  }

  @override
  void onReceiveData(Object data) {
    if (data is! Map) return;
    final String event = data[SyncDataKeys.event] as String? ?? '';

    switch (event) {
      case SyncDataKeys.cmdTriggerNow:
        log('$_tag Manual trigger received.', name: _tag);
        if (!_isCycleRunning) _runSyncCycle();
        break;

      case SyncDataKeys.cmdUpdateInterval:
        final int newInterval =
            data[SyncDataKeys.intervalMinutes] as int? ?? _intervalMinutes;
        if (newInterval != _intervalMinutes) {
          _intervalMinutes = newInterval;
          _startTimer(); // restart timer immediately with new interval
          LogService.writeLog(
              message:
                  '$_tag Interval updated to ${_intervalMinutes}min — timer restarted.');
        }
        break;
    }
  }

  // ── Timer ─────────────────────────────────────────────────────────────────

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(Duration(minutes: _intervalMinutes), (_) async {
      if (!_isCycleRunning) {
        await LogService.writeLog(
            message: '$_tag Timer fired — running sync cycle.');
        await _runSyncCycle();
      } else {
        await LogService.writeLog(
            message: '$_tag Timer fired — cycle already running, skipping.');
      }
    });
    log('$_tag Timer started. Interval: ${_intervalMinutes}min.', name: _tag);
  }

  Future<void> _runSyncCycle() async {
    _isCycleRunning = true;

    try {
      if (!await _checkInternet()) {
        await LogService.writeLog(
            message: '$_tag No internet — skipping cycle.');
        _updateNotification(
          title: '📡 Sync Waiting',
          text: 'No connection — will retry in ${_intervalMinutes}min',
        );
        FlutterForegroundTask.sendDataToMain(
            {SyncDataKeys.event: SyncDataKeys.evtNoInternet});
        return;
      }

      final int pending = await OfflineDbModule.getPendingCount();
      final List<Map<String, dynamic>> leftoverQueues =
          await OfflineDbModule.getPendigQueuesToRefresh();

      if (pending == 0 && leftoverQueues.isEmpty) {
        await LogService.writeLog(
          message:
              '$_tag Nothing pending and no leftover queues — skipping cycle.',
        );
        _updateNotification(
          title: '🔵 Sync Service Active',
          text: 'No pending records — next check in ${_intervalMinutes}min',
        );
        return;
      }

      final acquired =
          await OfflineDbModule.tryAcquireCachedSaveLock(owner: 'background');
      if (!acquired) {
        await LogService.writeLog(
          message:
              '$_tag Cached save is already running elsewhere. Skipping this cycle.',
        );
        _updateNotification(
          title: '🔵 Sync Service Active',
          text: 'Another sync is currently in progress.',
        );
        return;
      }

      final bool sessionOk = await OfflineDbModule.ensureValidSession();
      if (!sessionOk) {
        await LogService.writeLog(
          message:
              '$_tag Session invalid and silent relogin failed — skipping cycle.',
        );
        _updateNotification(
            title: '🔴 Session Expired',
            text: 'Please log in again to continue syncing.');
        await SyncAlertNotifier.show(
          id: 2,
          title: '🔴 Session Expired',
          body: 'Please log in again to continue syncing your offline data.',
        );
        FlutterForegroundTask.sendDataToMain(
            {SyncDataKeys.event: SyncDataKeys.evtAuthFailed});
        return;
      }

      _updateNotification(
          title: '🔄 Syncing', text: 'Checking previous sync queues...');

      final leftoverResults = await OfflineDbModule
          .resolvePendingCachedSaveQueueBatchesBackgroundSafe(
        onProgress: (msg) {
          log('$_tag [RESOLVE] $msg');
          FlutterForegroundTask.updateService(notificationText: msg);
        },
      );

      await LogService.writeLog(
        message: '$_tag Resolved ${leftoverResults.length} leftover queue(s). '
            'results=${leftoverResults.map((r) => '${r.queueId}:${r.statusLabel}').toList()}',
      );

      // Re-check AFTER resolving — this is the real number that matters now.
      final int pendingAfterResolve = await OfflineDbModule.getPendingCount();
      if (pendingAfterResolve == 0) {
        await LogService.writeLog(
            message: '$_tag Nothing left to push after resolving.');
        _updateNotification(
          title: '✅ Sync Complete',
          text: 'All records synced — next check in ${_intervalMinutes}min',
        );
        return;
      }

      _updateNotification(
        title: '🔄 Syncing',
        text: 'Found $pendingAfterResolve records — starting upload...',
      );
      await SyncAlertNotifier.show(
        id: 1,
        title: '🔄 Sync Started',
        body: 'Uploading $pendingAfterResolve pending record(s)...',
      );

      final result = await OfflineDbModule.runCachedSave(
        onProgress: (message) {
          log('$_tag $message');
          FlutterForegroundTask.updateService(notificationText: message);
        },
      );

      await LogService.writeLog(message: '$_tag Push done. Result: $result');

      switch (result.status) {
        case CachedSaveStatus.success:
          _sendData({
            SyncDataKeys.event: SyncDataKeys.evtDone,
            SyncDataKeys.result: result.message,
            SyncDataKeys.lastSyncedAt:
                await OfflineDbModule.getLastSyncedTimestamp(),
            SyncDataKeys.pendingCount: await OfflineDbModule.getPendingCount(),
          });
          await SyncAlertNotifier.show(
            id: 3,
            title: '✅ Sync Complete',
            body: result.message,
          );
          break;

        case CachedSaveStatus.queueEmpty:
          _sendData({
            SyncDataKeys.event: SyncDataKeys.evtDone,
            SyncDataKeys.result: "Queue is empty",
            SyncDataKeys.pendingCount: 0,
          });
          break;

        case CachedSaveStatus.noSession:
        case CachedSaveStatus.authFailed:
          _sendData({
            SyncDataKeys.event: SyncDataKeys.evtAuthFailed,
            SyncDataKeys.result: result.message,
          });
          await SyncAlertNotifier.show(
            id: 2,
            title: '🔴 Session Expired',
            body: 'Please log in again to continue syncing your offline data.',
          );
          break;

        case CachedSaveStatus.failed:
          _sendData({
            SyncDataKeys.event: SyncDataKeys.evtError,
            SyncDataKeys.result: result.message,
          });
          await SyncAlertNotifier.show(
            id: 4,
            title: '⚠️ Sync Failed',
            body: result.message,
          );
          break;
      }
      final int remaining = await OfflineDbModule.getPendingCount();
      final String? lastTs = await OfflineDbModule.getLastSyncedTimestamp();

      _updateNotification(
        title: remaining == 0 ? '✅ Sync Complete' : '⚠️ Sync Partial',
        text: remaining == 0
            ? 'Last sync: ${_formatTime(DateTime.parse(lastTs ?? DateTime.now().toIso8601String()).toLocal())} — next check in ${_intervalMinutes}min'
            : '$remaining records pending — retrying in ${_intervalMinutes}min',
      );

      FlutterForegroundTask.sendDataToMain({
        SyncDataKeys.event: SyncDataKeys.evtDone,
        SyncDataKeys.result: result.message,
        SyncDataKeys.pendingCount: remaining,
        SyncDataKeys.lastSyncedAt: lastTs ?? '',
      });
    } catch (e) {
      await LogService.writeLog(message: '$_tag Cycle FAILED: $e');
      _updateNotification(
        title: '🔴 Sync Error',
        text: 'Sync failed — retrying in ${_intervalMinutes}min',
      );
      FlutterForegroundTask.sendDataToMain({
        SyncDataKeys.event: SyncDataKeys.evtError,
        SyncDataKeys.result: e.toString(),
      });
    } finally {
      _isCycleRunning = false;
      await OfflineDbModule.releaseCachedSaveLock(owner: 'background');
    }
  }
  // ── Helpers ────────────────────────────────────────────────────────────────

  Future<void> _ensureDbInitialized() async {
    if (_dbInitialized) return;
    await OfflineDbModule.init();
    _dbInitialized = true;
    await LogService.writeLog(message: '$_tag DB initialized in isolate.');
  }

  Future<bool> _checkInternet() async {
    try {
      final result = await Connectivity().checkConnectivity();
      return result.contains(ConnectivityResult.mobile) ||
          result.contains(ConnectivityResult.wifi);
    } catch (_) {
      return false;
    }
  }

  void _updateNotification({required String title, required String text}) {
    FlutterForegroundTask.updateService(
      notificationTitle: title,
      notificationText: text,
    );
  }

  String _formatTime(DateTime dt) {
    final now = DateTime.now();
    final time =
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    if (dt.year == now.year && dt.month == now.month && dt.day == now.day) {
      return 'Today $time';
    }
    return '${dt.day}/${dt.month} $time';
  }

  void _sendData(Map<String, dynamic> data) {
    FlutterForegroundTask.sendDataToMain(data);
  }
}
