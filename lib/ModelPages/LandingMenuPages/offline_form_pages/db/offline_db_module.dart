import 'dart:convert';
import 'dart:developer';
import 'dart:io';

import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:intl/intl.dart';
import 'package:ubbottleapp/Constants/AppStorage.dart';
import 'package:ubbottleapp/Constants/Const.dart';
import 'package:ubbottleapp/Constants/GlobalVariableController.dart';
import 'package:ubbottleapp/ModelPages/LandingMenuPages/offline_form_pages/auto_sync/offline_sync_task_handler.dart';
import 'package:ubbottleapp/ModelPages/LandingMenuPages/offline_form_pages/models/form_page_model.dart';
import 'package:ubbottleapp/ModelPages/LandingMenuPages/offline_form_pages/models/submitData_APIResponseModel.dart';
import 'package:ubbottleapp/ModelPages/LandingMenuPages/offline_form_pages/models/sync_progress_model.dart';
import 'package:ubbottleapp/ModelPages/LandingPage/Controller/LandingPageController.dart';
import 'package:ubbottleapp/Utils/LogServices/LogService.dart';
import 'package:ubbottleapp/Utils/ServerConnections/ExecuteApi.dart';
import 'package:ubbottleapp/Utils/ServerConnections/ServerConnections.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import 'package:http/http.dart' as http;
import 'offline_datasources.dart';
import 'offline_db_constants.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';

enum SubmitStatus { success, savedOffline, apiFailure, sqlFailure }

class OfflineDbModule {
  OfflineDbModule._();
  // static ServerConnections serverConnections = ServerConnections();
  static Database? _db;

  // INIT

  static var autoSync = false;
  static var autoSyncMaster = false;
  static Future<bool> toggleAutoSync() async {
    var appstrg = AppStorage();

    bool current = await appstrg.retrieveValue(AppStorage.AUTO_SYNC) ?? false;

    bool newValue = !current;

    await appstrg.storeValue(AppStorage.AUTO_SYNC, newValue);

    autoSync = newValue;
    await logAudit(
      action: "TOGGLE_AUTOSYNC",
      remarks: "AutoSync changed to: $newValue",
    );
    return newValue;
  }

  static Future<bool> toggleAutoSyncMaster() async {
    var appstrg = AppStorage();

    bool current =
        await appstrg.retrieveValue(AppStorage.AUTO_SYNC_MASTER) ?? false;

    bool newValue = !current;
    globalVariableController.autoSyncMasterEnabled.value = newValue;
    await appstrg.storeValue(AppStorage.AUTO_SYNC_MASTER, newValue);
    autoSyncMaster = newValue;
    await logAudit(
      action: "TOGGLE_AUTOSYNC_MASTER",
      remarks: "AutoSyncMaster changed to: $newValue",
    );
    return newValue;
  }

  static Future<void> init() async {
    autoSync = await AppStorage().retrieveValue(AppStorage.AUTO_SYNC) ?? false;

    autoSyncMaster =
        await AppStorage().retrieveValue(AppStorage.AUTO_SYNC_MASTER) ?? true;
    // globalVariableController.autoSyncMasterEnabled.value = autoSyncMaster;
    final dbPath = join(await getDatabasesPath(), 'offline_forms.db');

    _db = await openDatabase(
      dbPath,
      version: 7, // ← bumped from 5 → 6
      onCreate: (db, _) async {
        await _createTables(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        const tag = "[OFFLINE_DB_UPGRADE_006]";
        if (oldVersion < 7) {
          await db.execute(
            'ALTER TABLE ${OfflineDBConstants.TABLE_PENDING_REQUESTS} RENAME TO ${OfflineDBConstants.TABLE_PENDING_REQUESTS}_backup',
          );

          await db.execute(OfflineDBConstants.CREATE_PENDING_REQUESTS_TABLE);

          await db.execute('''
    INSERT OR IGNORE INTO ${OfflineDBConstants.TABLE_PENDING_REQUESTS} (
      ${OfflineDBConstants.COL_ID},
      ${OfflineDBConstants.COL_USERNAME},
      ${OfflineDBConstants.COL_PROJECT_NAME},
      ${OfflineDBConstants.COL_REQUEST_JSON},
      ${OfflineDBConstants.COL_STATUS},
      ${OfflineDBConstants.COL_CREATED_AT}
    )
    SELECT 
      ${OfflineDBConstants.COL_ID},
      ${OfflineDBConstants.COL_USERNAME},
      ${OfflineDBConstants.COL_PROJECT_NAME},
      ${OfflineDBConstants.COL_REQUEST_JSON},
      ${OfflineDBConstants.COL_STATUS},
      ${OfflineDBConstants.COL_CREATED_AT}
    FROM ${OfflineDBConstants.TABLE_PENDING_REQUESTS}_backup
  ''');

          await db.execute(
            'DROP TABLE IF EXISTS ${OfflineDBConstants.TABLE_PENDING_REQUESTS}_backup',
          );

          LogService.writeLog(
            message:
                "$tag[V7] Added UNIQUE constraint on '${OfflineDBConstants.COL_REQUEST_JSON}' in ${OfflineDBConstants.TABLE_PENDING_REQUESTS}.",
          );
        }
        // if (oldVersion < 5) {
        //   await db.execute(OfflineDBConstants.CREATE_AUDIT_LOGS_TABLE);
        //   LogService.writeLog(message: "$tag[V5] Audit logs table ensured.");
        // }

        // if (oldVersion < 6) {
        // try {
        //   await db.execute(
        //     'ALTER TABLE ${OfflineDBConstants.TABLE_AUDIT_LOGS} '
        //     'ADD COLUMN ${OfflineDBConstants.COL_IS_SYNCED} INTEGER NOT NULL DEFAULT 0',
        //   );
        //   LogService.writeLog(
        //     message:
        //         "$tag[V6] Added '${OfflineDBConstants.COL_IS_SYNCED}' to audit_logs.",
        //   );
        // } catch (e) {
        //   LogService.writeLog(
        //     message: "$tag[V6][SKIP] is_synced already present: $e",
        //   );
        // }

        //   try {
        //     await db.execute(
        //       'ALTER TABLE ${OfflineDBConstants.TABLE_OFFLINE_USER} '
        //       'ADD COLUMN ${OfflineDBConstants.COL_LAST_SYNCED} TEXT',
        //     );
        //     LogService.writeLog(
        //       message:
        //           "$tag[V6] Added '${OfflineDBConstants.COL_LAST_SYNCED}' to offline_user.",
        //     );
        //   } catch (e) {
        //     LogService.writeLog(
        //       message: "$tag[V6][SKIP] last_synced already present: $e",
        //     );
        //   }
        // }

        // Audit the upgrade itself
        // try {
        //   await db.insert(OfflineDBConstants.TABLE_AUDIT_LOGS, {
        //     OfflineDBConstants.COL_USERNAME: 'system',
        //     OfflineDBConstants.COL_PROJECT_NAME: 'system',
        //     OfflineDBConstants.COL_ACTION: 'DB_UPGRADE',
        //     OfflineDBConstants.COL_REMARKS:
        //         'Upgraded from $oldVersion to $newVersion.',
        //     OfflineDBConstants.COL_CREATED_AT: DateTime.now().toIso8601String(),
        //     OfflineDBConstants.COL_IS_ERROR: 0,
        //     OfflineDBConstants.COL_IS_SYNCED: 0, // new column — default 0
        //   });
        // } catch (_) {}

        LogService.writeLog(
          message: "$tag[SUCCESS] Migration complete. Data preserved.",
        );
      },
    );
    await maintenanceDeleteOldLogs();
  }

  static Database get _database {
    if (_db == null) {
      throw Exception('OfflineDbModule not initialized');
    }
    return _db!;
  }

  static Future<void> _createTables(Database db) async {
    await db.execute(OfflineDBConstants.CREATE_OFFLINE_PAGES_TABLE);
    await db.execute(OfflineDBConstants.CREATE_DATASOURCES_TABLE);
    await db.execute(OfflineDBConstants.CREATE_DATASOURCE_DATA_TABLE);
    await db.execute(OfflineDBConstants.CREATE_PENDING_REQUESTS_TABLE);
    await db.execute(OfflineDBConstants.CREATE_OFFLINE_USER_TABLE);
    await db.execute(OfflineDBConstants.CREATE_AUDIT_LOGS_TABLE);
  }

  static Future<void> maintenanceDeleteOldLogs() async {
    final thirtyDaysAgo =
        DateTime.now().subtract(const Duration(days: 30)).toIso8601String();

    int deletedCount = await _database.delete(
      OfflineDBConstants.TABLE_AUDIT_LOGS,
      where: '${OfflineDBConstants.COL_CREATED_AT} < ?',
      whereArgs: [thirtyDaysAgo],
    );

    if (deletedCount > 0) {
      debugPrint("Audit Maintenance: Deleted $deletedCount old logs.");
    }
  }

  static Future<void> handlePostLogin({
    required bool isInternetAvailable,
  }) async {
    final scope = await _getLastOfflineUserScope();
    if (scope == null) return;

    await _handlePostLoginInternal(
      isInternetAvailable: isInternetAvailable,
      username: scope['username']!,
      projectName: scope['projectName']!,
    );
  }

  static Future<void> _handlePostLoginInternal({
    required bool isInternetAvailable,
    required String username,
    required String projectName,
  }) async {
    const tag = "[OFFLINE_HANDLE_POST_LOGIN_001]";

    LogService.writeLog(
      message:
          "$tag[START] user=$username project=$projectName internet=$isInternetAvailable",
    );
    log("Is autoSync => $autoSync", name: "_handlePostLoginInternal");
    if (autoSync) {
      await _syncPendingBeforeLogin(
        username: username,
        projectName: projectName,
        isInternetAvailable: isInternetAvailable,
      );
    }

    final pages = await fetchAndStoreOfflinePages();
    log("pages => ${pages.length}", name: "_handlePostLoginInternal");
    if (pages.isEmpty) {
      LogService.writeLog(message: "$tag[INFO] No offline pages received");
      return;
    }

    await fetchAndStoreAllDatasourcesForAllForms(pages,
        isRefetching: autoSyncMaster);

    LogService.writeLog(
      message: "$tag[SUCCESS] Offline bootstrap done. pages=${pages.length}",
    );
  }

  static Future<void> fetchAndStoreAllDatasourcesForAllForms(
      List<Map<String, dynamic>> pages,
      {bool isRefetching = false}) async {
    final scope = await _getLastOfflineUserScope();
    if (scope == null) return;

    final username = scope['username']!;
    final projectName = scope['projectName']!;
    final sessionId = AppStorage().retrieveValue(AppStorage.SESSIONID) ?? "";

    for (final page in pages) {
      final transId = page['transid']?.toString();
      if (transId == null || transId.isEmpty) continue;

      final Set<String> dsSet = _getAllUniqueDatasourcesInPage(page);
      log("dsSet => ${dsSet}", name: "_handlePostLoginInternal");
      if (dsSet.isEmpty) continue;
      LandingPageController.to.totalDsCountOnStart.value = dsSet.length;
      // LandingPageController.to.completedDsCountOnStart.value = 1;
      for (final ds in dsSet) {
        LandingPageController.to.completedDsCountOnStart.value += 1;
        final exists = await _database.query(
          OfflineDBConstants.TABLE_DATASOURCE_DATA,
          columns: [OfflineDBConstants.COL_ID], // Optimization: Select ID only
          where: '''
          ${OfflineDBConstants.COL_USERNAME} = ? AND
          ${OfflineDBConstants.COL_PROJECT_NAME} = ? AND
          ${OfflineDBConstants.COL_TRANS_ID} = ? AND
          ${OfflineDBConstants.COL_DATASOURCE_NAME} = ?
        ''',
          whereArgs: [username, projectName, transId, ds],
          limit: 1,
        );

        if (exists.isNotEmpty && !isRefetching) {
          log("isRefetching => ${isRefetching} Skipping the fetch",
              name: "_handlePostLoginInternal");

          continue;
        }
        log("isRefetching => ${isRefetching} Fetching All datasource",
            name: "_handlePostLoginInternal");
        final res = await OfflineDatasources.fetchDatasource(
          datasourceName: ds,
          sessionId: sessionId,
          username: username,
          appName: projectName,
          sqlParams: {"username": username},
        );

        if (res == null || res.isEmpty) {
          LogService.writeLog(message: "[DS_FAIL] Empty response for $ds");
          continue;
        }

        await _database.insert(
          OfflineDBConstants.TABLE_DATASOURCE_DATA,
          {
            OfflineDBConstants.COL_USERNAME: username,
            OfflineDBConstants.COL_PROJECT_NAME: projectName,
            OfflineDBConstants.COL_TRANS_ID: transId,
            OfflineDBConstants.COL_DATASOURCE_NAME: ds,
            OfflineDBConstants.COL_RESPONSE_JSON: res,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    }
  }

  static Future<List<Map<String, dynamic>>> fetchAndStoreOfflinePages() async {
    final scope = await _getLastOfflineUserScope();
    if (scope == null) return [];

    return _fetchAndStoreOfflinePagesInternal(
      username: scope['username']!,
      projectName: scope['projectName']!,
    );
  }

  static Future<List<Map<String, dynamic>>> _fetchAndStoreOfflinePagesInternal({
    required String username,
    required String projectName,
  }) async {
    const String tag = "[OFFLINE_PAGES_FETCH_001]";

    try {
      LogService.writeLog(message: "$tag[START] Fetching offline pages...");

      final res =
          await http.get(Uri.parse(OfflineDBConstants.OFFLINE_PAGES_URL()));

      LogService.writeLog(
          message:
              "$tag[URL] Offline pages URL => ${Uri.parse(OfflineDBConstants.OFFLINE_PAGES_URL())} \n[URI] => ${OfflineDBConstants.OFFLINE_PAGES_URL()} ");

      log(res.body, name: tag);
      if (res.statusCode != 200) {
        if (Get.isRegistered<GlobalVariableController>()) {
          globalVariableController.OFFLINE_FORMS_COUNT.value = 0;
          return [];
        }
      }
      final decoded = jsonDecode(utf8.decode(res.bodyBytes)) as List<dynamic>;
      final pages = decoded.map((e) => e as Map<String, dynamic>).toList();
      await logAudit(
        action: "FETCH_OFFLINE_FORMS",
        response: res.toString(),
        remarks:
            "Tried fetching offline pages from server :Res Forms: ${pages.length} forms",
      );
      if (pages.isEmpty) {
        try {
          if (Get.isRegistered<GlobalVariableController>()) {
            globalVariableController.OFFLINE_FORMS_COUNT.value = 0;
            return [];
          }
        } catch (_) {
          return [];
        }
      }

      try {
        if (Get.isRegistered<GlobalVariableController>()) {
          globalVariableController.OFFLINE_FORMS_COUNT.value = pages.length;
        }
      } catch (_) {}
      log("OFFLINE_FORMS_COUNT = ${pages.length}", name: tag);
      final batchDelete = _database.batch();
      batchDelete.delete(
        OfflineDBConstants.TABLE_OFFLINE_PAGES,
        where:
            '${OfflineDBConstants.COL_USERNAME} = ? AND ${OfflineDBConstants.COL_PROJECT_NAME} = ?',
        whereArgs: [username, projectName],
      );
      batchDelete.delete(
        OfflineDBConstants.TABLE_DATASOURCES,
        where:
            '${OfflineDBConstants.COL_USERNAME} = ? AND ${OfflineDBConstants.COL_PROJECT_NAME} = ?',
        whereArgs: [username, projectName],
      );
      await batchDelete.commit(noResult: true);

      final batchInsert = _database.batch();

      for (final page in pages) {
        final String transId = page['transid'] ?? "";

        batchInsert.insert(
          OfflineDBConstants.TABLE_OFFLINE_PAGES,
          {
            OfflineDBConstants.COL_USERNAME: username,
            OfflineDBConstants.COL_PROJECT_NAME: projectName,
            OfflineDBConstants.COL_TRANS_ID: transId,
            OfflineDBConstants.COL_PAGE_JSON: jsonEncode(page),
            OfflineDBConstants.COL_FETCHED_AT: DateTime.now().toIso8601String(),
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );

        final Set<String> dsSet = _getAllUniqueDatasourcesInPage(page);
        if (dsSet.isNotEmpty) {
          final String dsString = dsSet.join(',');

          batchInsert.insert(
            OfflineDBConstants.TABLE_DATASOURCES,
            {
              OfflineDBConstants.COL_USERNAME: username,
              OfflineDBConstants.COL_PROJECT_NAME: projectName,
              OfflineDBConstants.COL_TRANS_ID: transId,
              OfflineDBConstants.COL_DATASOURCE_NAMES: dsString,
            },
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }
      }

      await batchInsert.commit(noResult: true);
      await logAudit(
        action: "FETCH_OFFLINE_FORMS",
        remarks: "Successfully downloaded and stored ${pages.length} forms",
      );
      return pages;
    } catch (e) {
      LogService.writeLog(message: "$tag[FAILED] $e");
      return [];
    }
  }

  static Future<int> getOfflinePagesCount() async {
    final scope = await _getLastOfflineUserScope();
    if (scope == null) return 0;
    return _getOfflinePagesCountInternal(
      username: scope['username']!,
      projectName: scope['projectName']!,
    );
  }

  static Future<int> _getOfflinePagesCountInternal({
    required String username,
    required String projectName,
  }) async {
    final res = await _database.rawQuery(
      '''
    SELECT COUNT(*) as cnt 
    FROM ${OfflineDBConstants.TABLE_OFFLINE_PAGES}
    WHERE ${OfflineDBConstants.COL_USERNAME} = ?
      AND ${OfflineDBConstants.COL_PROJECT_NAME} = ?
    ''',
      [username, projectName],
    );

    return Sqflite.firstIntValue(res) ?? 0;
  }

  static Future<List<Map<String, dynamic>>> getOfflinePages() async {
    final scope = await _getLastOfflineUserScope();
    if (scope == null) return [];

    return _getOfflinePagesInternal(
      username: scope['username']!,
      projectName: scope['projectName']!,
    );
  }

  static Future<List<Map<String, dynamic>>> _getOfflinePagesInternal({
    required String username,
    required String projectName,
  }) async {
    final result = await _database.query(
      OfflineDBConstants.TABLE_OFFLINE_PAGES,
      where: '''
      ${OfflineDBConstants.COL_USERNAME} = ? AND
      ${OfflineDBConstants.COL_PROJECT_NAME} = ?
    ''',
      whereArgs: [username, projectName],
      orderBy: OfflineDBConstants.COL_FETCHED_AT + ' ASC',
    );

    return result
        .map(
          (e) => jsonDecode(e[OfflineDBConstants.COL_PAGE_JSON] as String)
              as Map<String, dynamic>,
        )
        .toList();
  }

  static Future<List<String>> _getDatasourceList({
    required String username,
    required String projectName,
    required String transId,
  }) async {
    final result = await _database.query(
      OfflineDBConstants.TABLE_DATASOURCES,
      columns: [OfflineDBConstants.COL_DATASOURCE_NAMES],
      where: '''
      ${OfflineDBConstants.COL_USERNAME} = ? AND 
      ${OfflineDBConstants.COL_PROJECT_NAME} = ? AND 
      ${OfflineDBConstants.COL_TRANS_ID} = ? 
    ''',
      whereArgs: [username, projectName, transId], // <--- FILTER BY ID
      limit: 1,
    );

    if (result.isEmpty) return [];

    final raw =
        result.first[OfflineDBConstants.COL_DATASOURCE_NAMES] as String? ?? '';

    return raw
        .split(',')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
  }

  static Future<void> fetchAndStoreAllDatasources({
    required String transId,
    SyncProgressModel? progress,
    bool isrefetching = false,
  }) async {
    final scope = await _getLastOfflineUserScope();
    if (scope == null) return;
    log("fetchAndStoreAllDatasources scope => ${scope} transID => $transId",
        name: "datasourcerefetch");

    await _fetchAndStoreAllDatasourcesInternal(
      username: scope['username']!,
      projectName: scope['projectName']!,
      transId: transId,
      progress: progress,
      isrefetching: isrefetching,
    );
  }

  static Future<void> _fetchAndStoreAllDatasourcesInternal({
    required String username,
    required String projectName,
    required String transId,
    SyncProgressModel? progress,
    bool isrefetching = false,
  }) async {
    try {
      final datasources = await _getDatasourceList(
        username: username,
        projectName: projectName,
        transId: transId,
      );
      log("fetchAndStoreAllDatasources datasources => ${datasources} transID => $transId",
          name: "datasourcerefetch");
      if (datasources.isEmpty) {
        debugPrint("No datasources found inside page: $transId");
        return;
      }

      progress?.totalItems.value = datasources.length;

      for (final ds in datasources) {
        progress?.updateMessage("Fetching: $ds\n(Form: $transId)");

        final exists = await _database.query(
          OfflineDBConstants.TABLE_DATASOURCE_DATA,
          columns: [OfflineDBConstants.COL_ID],
          where: '''
            ${OfflineDBConstants.COL_USERNAME} = ? AND
            ${OfflineDBConstants.COL_PROJECT_NAME} = ? AND
            ${OfflineDBConstants.COL_TRANS_ID} = ? AND
            ${OfflineDBConstants.COL_DATASOURCE_NAME} = ?
          ''',
          whereArgs: [username, projectName, transId, ds],
          limit: 1,
        );

        log("fetchAndStoreAllDatasources exists => ${exists} transID => $transId",
            name: "datasourcerefetch");
        if (exists.isNotEmpty && !isrefetching) {
          log("exists => ${exists.isNotEmpty} skipping refetch",
              name: "datasourcerefetch");
          progress?.increment();
          continue;
        }
        log("isrefetching => ${isrefetching}  refetching",
            name: "datasourcerefetch");
        final scope = await _getLastOfflineUserScope();
        if (scope == null) continue;

        final session = AppStorage().retrieveValue(AppStorage.SESSIONID) ?? "";

        final res = await OfflineDatasources.fetchDatasource(
          datasourceName: ds,
          sessionId: session,
          username: scope['username']!,
          appName: scope['projectName']!,
          sqlParams: {
            "username": scope['username']!,
          },
        ).timeout(const Duration(seconds: 15));

        if (res == null || res.isEmpty) {
          debugPrint("Empty response for DS: $ds");
          progress?.increment(isSuccess: false);
          continue;
        }

        await _database.insert(
          OfflineDBConstants.TABLE_DATASOURCE_DATA,
          {
            OfflineDBConstants.COL_USERNAME: username,
            OfflineDBConstants.COL_PROJECT_NAME: projectName,
            OfflineDBConstants.COL_TRANS_ID: transId,
            OfflineDBConstants.COL_DATASOURCE_NAME: ds,
            OfflineDBConstants.COL_RESPONSE_JSON: res,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );

        progress?.increment();
        // After commit
        await logAudit(
          action: "FETCH_ALL_DATA_SOURCES",
          remarks:
              "Successfully downloaded and stored ${datasources.length} datasources",
        );
      }
    } catch (e) {
      await logAudit(
        action: "FETCH_ALL_DATA_SOURCES",
        isError: true,
        response: e.toString(),
        remarks: "_fetchAndStoreAllDatasourcesInternal catch block",
      );
      debugPrint("Error fetching datasources for $transId: $e");
      progress?.increment(isSuccess: false);
    }
  }

  static Set<String> _getAllUniqueDatasourcesInPage(Map<String, dynamic> page) {
    final Set<String> dsSet = {};

    if (page.containsKey('fields') && page['fields'] is List) {
      for (var field in page['fields']) {
        _addDatasourceFromField(field, dsSet);
      }
    }

    if (page.containsKey('fillgrids')) {
      final fillgrids = page['fillgrids'];

      if (fillgrids is Map) {
        if (fillgrids.containsKey('fields') && fillgrids['fields'] is List) {
          for (var field in fillgrids['fields']) {
            _addDatasourceFromField(field, dsSet);
          }
        }
      } else if (fillgrids is List) {
        for (var grid in fillgrids) {
          if (grid is Map &&
              grid.containsKey('fields') &&
              grid['fields'] is List) {
            for (var field in grid['fields']) {
              _addDatasourceFromField(field, dsSet);
            }
          }
        }
      }
    }

    return dsSet;
  }

  static void _addDatasourceFromField(dynamic field, Set<String> dsSet) {
    if (field is Map &&
        field['datasource'] != null &&
        field['datasource'].toString().trim().isNotEmpty) {
      dsSet.add(field['datasource'].toString().trim());
    }
  }

  static Future<List<Map<String, dynamic>>> getDatasourceOptions({
    required String transId,
    required String datasource,
  }) async {
    final scope = await _getLastOfflineUserScope();
    if (scope == null) return [];

    return _getDatasourceOptionsInternal(
      username: scope['username']!,
      projectName: scope['projectName']!,
      transId: transId,
      datasource: datasource,
    );
  }

  static Future<List<Map<String, dynamic>>> _getDatasourceOptionsInternal({
    required String username,
    required String projectName,
    required String transId,
    required String datasource,
  }) async {
    final result = await _database.query(
      OfflineDBConstants.TABLE_DATASOURCE_DATA,
      where: '''
      ${OfflineDBConstants.COL_USERNAME} = ? AND
      ${OfflineDBConstants.COL_PROJECT_NAME} = ? AND
      ${OfflineDBConstants.COL_TRANS_ID} = ? AND
      ${OfflineDBConstants.COL_DATASOURCE_NAME} = ?
    ''',
      whereArgs: [username, projectName, transId, datasource],
      limit: 1,
    );

    if (result.isEmpty) return [];

    try {
      final jsonStr =
          result.first[OfflineDBConstants.COL_RESPONSE_JSON] as String;
      final decoded = jsonDecode(jsonStr);

      debugPrint("fetchDatasource : getDatasourceOptions => $decoded");

      // 1. Extract the List
      List<dynamic> rawList = [];
      if (decoded is Map<String, dynamic> && decoded.containsKey('result')) {
        rawList = decoded['result']['data'] ?? [];
      } else if (decoded is List) {
        rawList = decoded;
      }

      // 2. CONVERT List<dynamic> -> List<Map<String, dynamic>> (THE FIX)
      return rawList.map((e) => Map<String, dynamic>.from(e)).toList();
    } catch (e) {
      LogService.writeLog(message: "[DS_PARSE_ERROR] $datasource: $e");
      return [];
    }
  }

  // MAP OPTIONS INTO FIELD MODELS
  static Future<List<OfflineFormPageModel>> mapDatasourceOptionsIntoPages({
    required List<OfflineFormPageModel> pages,
  }) async {
    for (final page in pages) {
      for (final field in page.fields) {
        if (field.datasource == null || field.datasource!.isEmpty) continue;

        final options = await getDatasourceOptions(
          transId: page.transId,
          datasource: field.datasource!,
        );

        debugPrint(
            "fetchDatasource: mapDatasourceOptionsIntoPages : options => ${options.toString()}");

        field.options = options;
      }
    }

    return pages;
  }

  // =================================================
  // SMART SUBMIT
  // =================================================
  static Future<SubmitStatus> submitFormSmart(
      {required Map<String, dynamic> submitBody,
      required bool isInternetAvailable,
      required bool forceOffline}) async {
    final scope = await _getLastOfflineUserScope();
    if (scope == null) return SubmitStatus.apiFailure;

    return _submitFormSmartInternal(
      username: scope['username']!,
      projectName: scope['projectName']!,
      submitBody: submitBody,
      isInternetAvailable: isInternetAvailable,
      force_offline: forceOffline,
    );
  }

  static Future<SubmitStatus> _submitFormSmartInternal({
    required String username,
    required String projectName,
    required Map<String, dynamic> submitBody,
    required bool isInternetAvailable,
    required bool force_offline,
  }) async {
    if (isInternetAvailable && !force_offline) {
      try {
        final ServerConnections serverConnections = ServerConnections();

        final String url =
            Const.getFullARMUrl(ExecuteApi.API_ARM_EXECUTE_PUBLISHED);
        final Map<String, dynamic> uploadPayload =
            await _convertPayloadPathsToBase64(submitBody);
        final dynamic responseStr = await serverConnections.postToServer(
          url: url,
          body: jsonEncode(uploadPayload),
          isBearer: true,
        );
        log(jsonEncode(submitBody), name: "SUBMIT_RESPONSE_BODY");
        log(responseStr, name: "SUBMIT_RESPONSE_RES");

        if (responseStr != null && responseStr.isNotEmpty) {
          final decoded = jsonDecode(responseStr);

          if (decoded is Map<String, dynamic>) {
            if (decoded['success'] == true) {
              // await logAudit(
              //   action: "API_SUBMIT_FORM",
              //   response: responseStr,
              //   remarks: "Form: ${submitBody['publickey'] ?? "NO_PUBLIC_KEY"}",
              // );
              await _deletePayloadFiles(submitBody);
              return SubmitStatus.success;
            } else {
              final msg = decoded['message'] ?? "Unknown Error";
              LogService.writeLog(
                  message: "[API_FAIL] Server returned false: $msg");
              await logAudit(
                action: "OFFLINE_SUBMIT_FORM",
                isError: true,
                response: responseStr,
                remarks: "Form: ${submitBody['publickey'] ?? "NO_PUBLIC_KEY"}",
              );
              return SubmitStatus.apiFailure;
            }
          }
        }
      } catch (e) {
        await logAudit(
            action: "API_SUBMIT_FORM",
            isError: true,
            response: e.toString(),
            remarks: "Form: ${submitBody['publickey'] ?? "NO_PUBLIC_KEY"}");
        LogService.writeLog(message: "[API_EXCEPTION] $e");
      }

      return SubmitStatus.apiFailure;
    }
//-----------------------OFFLINE--------------------------------------->
    try {
      final int rowId = await _database.insert(
        OfflineDBConstants.TABLE_PENDING_REQUESTS,
        {
          OfflineDBConstants.COL_USERNAME: username,
          OfflineDBConstants.COL_PROJECT_NAME: projectName,
          OfflineDBConstants.COL_REQUEST_JSON: jsonEncode(submitBody),
          OfflineDBConstants.COL_STATUS: OfflineDBConstants.STATUS_PENDING,
          OfflineDBConstants.COL_CREATED_AT: DateTime.now().toIso8601String(),
        },
      );
      // await logAudit(
      //   action: "OFFLINE_SUBMIT_FORM",
      //   remarks:
      //       "Record ID: $rowId | Form: ${submitBody['publickey'] ?? "NO_PUBLIC_KEY"}",
      //   response:
      //       "Saved locally due to ${force_offline ? 'Force Offline' : 'No Internet'}",
      // );
      return SubmitStatus.savedOffline;
    } catch (e) {
      return SubmitStatus.sqlFailure;
    }
  }

  static var processPendingQueTag = "PROCESS_PENDING_QUE";

  static Future<void> debugPrintPendingRequests() async {
    try {
      final List<Map<String, dynamic>> rows = await _database.query(
        OfflineDBConstants.TABLE_PENDING_REQUESTS,
        columns: [
          OfflineDBConstants.COL_USERNAME,
          OfflineDBConstants.COL_PROJECT_NAME,
          OfflineDBConstants.COL_STATUS,
        ],
      );

      if (rows.isEmpty) {
        log("No records found in ${OfflineDBConstants.TABLE_PENDING_REQUESTS}",
            name: "DB_CHECK");
        return;
      }

      log("--- Pending Requests Log ---", name: "DB_CHECK");
      for (var row in rows) {
        final user = row[OfflineDBConstants.COL_USERNAME];
        final project = row[OfflineDBConstants.COL_PROJECT_NAME];
        final status = row[OfflineDBConstants.COL_STATUS];

        log("User: $user | Project: $project | Status: $status",
            name: "DB_CHECK");
      }
      log("Total Records: ${rows.length}", name: "DB_CHECK");
    } catch (e) {
      log("Error printing requests: $e", name: "DB_CHECK");
    }
  }

  static Future<String> processPendingQueue({
    required bool isInternetAvailable,
    SyncProgressModel? progress,
  }) async {
    if (progress?.isLoading.value ?? true) return "Sync already running...";
    progress?.isSessionError.value = false;
    log("processpendingque started", name: processPendingQueTag);
    if (!isInternetAvailable) return "No internet connection";

    final scope = await _getLastOfflineUserScope();
    if (scope == null) return "No user session found";

    final username = scope['username']!;
    final projectName = scope['projectName']!;
    log("processpendingque scope Username $username",
        name: processPendingQueTag);
    // await logAudit(
    //   action: processPendingQueTag,
    //   remarks: "Started background sync for user: $username",
    // );
    final String currentSessionId =
        AppStorage().retrieveValue(AppStorage.SESSIONID) ?? "";
    if (currentSessionId.isEmpty) return "No active session to sync";

    progress?.updateMessage("Checking pending queue...");

    // await debugPrintPendingRequests();
    final idRows = await _database.query(
      OfflineDBConstants.TABLE_PENDING_REQUESTS,
      columns: [OfflineDBConstants.COL_ID],
      where: '''
      ${OfflineDBConstants.COL_STATUS} IN (${OfflineDBConstants.STATUS_PENDING}, ${OfflineDBConstants.STATUS_ERROR})
      AND ${OfflineDBConstants.COL_USERNAME} = ?
      AND ${OfflineDBConstants.COL_PROJECT_NAME} = ?
    ''',
      whereArgs: [username, projectName],
      orderBy: OfflineDBConstants.COL_CREATED_AT,
    );

    log("processpendingque idRows.isEmpty ${idRows.isEmpty}",
        name: processPendingQueTag);

    if (idRows.isEmpty) {
      log("progress complete called here 3");

      progress?.complete();
      await logAudit(
          action: processPendingQueTag,
          response: "SYNC_QUEUE_EMPTY",
          remarks: "No pending records found to sync");
      return "Queue is empty";
    }
///////////////////PUSH start/////////////////////////
    int successCount = 0;
    int failCount = 0;
    List<int> successIds = [];
    List<int> failedIds = [];
    int total = idRows.length;
    final ServerConnections serverConnections = ServerConnections();
    final String url =
        Const.getFullARMUrl(ExecuteApi.API_ARM_EXECUTE_PUBLISHED);
    var isTraceOn =
        await AppStorage().retrieveValue(AppStorage.isLogEnabled) ?? false;
    bool isAuthFailed = false;
    String authFailedMessage = "";
    int authFailedCode = 0;

    progress?.clearFailedRecords();
    progress?.init(
        total: total, msg: "Found $total records. Starting upload...");

    for (int i = 0; i < total; i++) {
      final id = idRows[i][OfflineDBConstants.COL_ID] as int;

      try {
        progress?.updateMessage("Reading record ${i + 1} of $total...");

        final bodyStr = await _readLargeString(
          table: OfflineDBConstants.TABLE_PENDING_REQUESTS,
          column: OfflineDBConstants.COL_REQUEST_JSON,
          where: '${OfflineDBConstants.COL_ID} = ?',
          whereArgs: [id],
        );

        if (bodyStr == null || bodyStr.isEmpty) {
          await _markAsError(id);
          failedIds.add(id);
          failCount++;
          progress?.addFailedRecord(id, "Empty payload");
          progress?.increment(isSuccess: false);
          await logAudit(
            action: processPendingQueTag,
            isError: true,
            remarks: "(ID: $id) Empty payload found in local DB",
          );
          continue;
        }

        Map<String, dynamic> originalPayload = jsonDecode(bodyStr);

        // if (id == 6267) {
        //   originalPayload = update6267UploadJson();
        // }

        originalPayload['ARMSessionId'] = currentSessionId;
        originalPayload['submitdata']['trace'] = isTraceOn ? "true" : "false";
        originalPayload['submitdata']['username'] =
            (originalPayload['submitdata']['username'] ?? "").isEmpty
                ? await AppStorage().retrieveValue(AppStorage.USER_NAME)
                : originalPayload['submitdata']['username'];
        // TODO DEBUG_ONLY: Hardcoded username and project name for imported DB testing.
        // imported db push will fail without this 2 lines
        // Remove before production build.
        // originalPayload['submitdata']['username'] =
        //     await AppStorage().retrieveValue(AppStorage.USER_NAME);
        // originalPayload['project'] =
        //     await AppStorage().retrieveValue(AppStorage.PROJECT_NAME);

        Map<String, dynamic> uploadPayload = originalPayload;
        if (_isAsset(uploadPayload)) {
          try {
            uploadPayload = await _convertPayloadPathsToBase64(originalPayload);
            log("processpendingque uploadPayload.length ${uploadPayload.length}",
                name: processPendingQueTag);
            progress?.updateMessage(
                "Uploading${_isAssetHelper(uploadPayload)}record ${i + 1} of $total...");

            var data = uploadPayload["submitdata"]["dataarray"]["data"];
            var fileMap =
                data["dc1"]["row1"]["axpfile_file"] as Map<String, dynamic>;
            fileMap.forEach((key, value) {
              if (value is Map && value.containsKey("filename")) {
                value["filename"] =
                    value["filename"].toString().replaceAll("/", "_");

                log(value["filename"], name: "file_name_change");
              }
            });

            log("Payload filenames changed for offline upload",
                name: processPendingQueTag);
          } catch (e) {
            log("Error changing asset payload: $e", name: "file_name_change");
          }
        }

        final SubmitdataApiresponsemodel res =
            await serverConnections.postQueueToServer(
          url: url,
          body: jsonEncode(uploadPayload),
          isBearer: true,
        );

        LogService.writeLog(
            message:
                "[API ERROR]||[API SUCCESS]  ${res.rawBody} ||  ${_isAssetHelper(uploadPayload)}");
        String displayMessage = res.message;

        /// =========================================================
        /// SUCCESS
        /// =========================================================

        if (res.success) {
          await _deletePayloadFiles(uploadPayload);

          await _markAsSuccess(id);

          successIds.add(id);

          successCount++;

          log(
            "counting success failure => isSuccess => true",
          );

          progress?.increment(isSuccess: true);

          continue;
        }

        /// =========================================================
        /// FAILURE FLOW
        /// =========================================================
        ///
        await _markAsError(id);
        failedIds.add(id);
        failCount++;
        progress?.increment(isSuccess: false);
        progress?.addErrors(title: "Error", errorText: "${res.message}");
        progress?.addFailedRecord(id, displayMessage);
        await logAudit(
          action: processPendingQueTag,
          isError: true,
          response: res.rawBody.isEmpty ? "-- Empty Response --" : res.rawBody,
          remarks: "[ID: $id] ${res.statusCode} — $displayMessage",
        );

        /// =========================================================
        /// 400 -> CHECK AUTH ERROR
        /// =========================================================

        if (res.statusCode == 400) {
          final bool isSessionIssue = _isAuthenticationError(displayMessage);
          if (displayMessage.toLowerCase().contains("session")) {
            progress?.isSessionError.value = true;
          }

          /// AUTH FAILURE -> BREAK
          if (isSessionIssue) {
            // failedIds.add(id);
            // failCount++;
            authFailedCode = res.statusCode;
            isAuthFailed = true;
            authFailedMessage = displayMessage;

            break;
          }

          /// NORMAL VALIDATION ERROR -> CONTINUE
          // await _markAsError(id);

          // failedIds.add(id);

          // failCount++;

          // progress?.addErrors(
          //   title: "ID : $id",
          //   errorText: displayMessage,
          // );

          log(
            "counting success failure => isSuccess => false",
          );

          // progress?.increment(isSuccess: false);

          continue;
        }

        /// =========================================================
        /// ALL OTHER FAILURES -> BREAK
        /// =========================================================

        if (displayMessage.toLowerCase().contains("session")) {
          progress?.isSessionError.value = true;
        }

        // await _markAsError(id);

        // failedIds.add(id);

        // failCount++;

        authFailedCode = res.statusCode;

        isAuthFailed = true;

        authFailedMessage = displayMessage;

        // progress?.addErrors(
        //   title: "ID : $id",
        //   errorText: displayMessage,
        // );

        log(
          "counting success failure => isSuccess => false",
        );

        // progress?.increment(isSuccess: false);

        break;

      } catch (e) {
        await logAudit(
          action: processPendingQueTag,
          isError: true,
          response: e.toString(),
          remarks: "Exception processing record ID: $id",
        );
        failedIds.add(id);
        await _markAsError(id);
        progress?.addFailedRecord(id, e.toString());
        progress?.increment(isSuccess: false);
        progress?.addErrors(title: "Error", errorText: e.toString());
        failCount++;
      }
    }
    // -----------------------------
    if (successIds.isNotEmpty) {
      var updateSuccessCount = await _batchUpdateStatus(
          successIds, OfflineDBConstants.STATUS_SUCCESS);

      logAudit(
          action: processPendingQueTag,
          response:
              "Batch update [Success] complete via IN clause. Status: ${OfflineDBConstants.STATUS_SUCCESS}, Ids: ${successIds.toString()} : updateSuccessCount : $updateSuccessCount",
          remarks: " Total count of success list updated");
    }
    if (failedIds.isNotEmpty) {
      var updateFailureCount =
          await _batchUpdateStatus(failedIds, OfflineDBConstants.STATUS_ERROR);

      logAudit(
          action: processPendingQueTag,
          response:
              "Batch update [Failure] complete via IN clause. Status: ${OfflineDBConstants.STATUS_ERROR}, Ids: ${failedIds.toString()} : updateFailureCount : $updateFailureCount",
          remarks: " Total count of failure list updated");
    }
    if (isAuthFailed) {
      log("progress complete called here 1");
      // progress?.updateMessage(authFailedMessage);

      progress?.completeWithError(
          errorMsg: authFailedMessage, statuscode: authFailedCode.toString());
    } else {
      log("progress complete called here 2");
      progress?.updateMessage("Completed");
      progress?.complete();
      progress?.showSyncAuditLogsButton.value = true;
      // await pushAuditLogsToServer(
      //   isInternetAvailable: true,
      //   progress: progress,
      // );
    }

    return "Processed: $successCount success, $failCount failed";
  }

  static Map<String, dynamic> update6267UploadJson() {
    return {
      "ARMSessionId": "ARM-genie-03dfef00-a2af-4776-bf64-bb2a67cdae65",
      "project": "genie",
      "publickey": "InwardEntry",
      "submitdata": {
        "dataarray": {
          "data": {
            "dc1": {
              "row1": {
                "bags_sample": "19",
                "billed_qty_bags_crates": "940",
                "bottle_capacity": "650",
                "bottle_type_n": "Amber",
                "btlper_bag_crate": "12",
                "empty_truck": "4080",
                "entry_date": "",
                "entry_time": "",
                "exit_date": "",
                "exit_time": "",
                "loaded_truck": "10080",
                "netweight": "6000",
                "packing": "Crates",
                "receipt_date_time": "19/05/2026 12:02:51 PM",
                "received_bags_crates": "940",
                "s1_dc": "4565",
                "s1_name": "MURTHY AND CO H O ",
                "s2_district": "Mysuru",
                "s2_name": "",
                "short_bags": "19",
                "state": "Karnataka",
                "ub_ge_no": "6744/2689",
                "unit_name": "3200-NANJANGUD",
                "vehicle_no": "KA05D7877"
              }
            },
            "dc2": {
              "row1": {
                "broken": "1",
                "extra_dirty": "0",
                "fillrows": "1",
                "mfgstate": "Karnataka",
                "mng_year": "2025",
                "neck_chip": "0",
                "other_brand": "0",
                "other_kf": "0",
                "short": "0",
                "tat_mfg_date": "21/02/2026",
                "torn_bags": "0"
              },
              "row10": {
                "broken": "0",
                "extra_dirty": "0",
                "fillrows": "10",
                "mfgstate": "Karnataka",
                "mng_year": "2025",
                "neck_chip": "1",
                "other_brand": "0",
                "other_kf": "0",
                "short": "0",
                "tat_mfg_date": "06/03/2026",
                "torn_bags": "0"
              },
              "row11": {
                "broken": "0",
                "extra_dirty": "0",
                "fillrows": "11",
                "mfgstate": "Karnataka",
                "mng_year": "2025",
                "neck_chip": "0",
                "other_brand": "0",
                "other_kf": "0",
                "short": "0",
                "tat_mfg_date": "09/04/2026",
                "torn_bags": "0"
              },
              "row12": {
                "broken": "0",
                "extra_dirty": "0",
                "fillrows": "12",
                "mfgstate": "Karnataka",
                "mng_year": "2025",
                "neck_chip": "0",
                "other_brand": "0",
                "other_kf": "0",
                "short": "0",
                "tat_mfg_date": "23/01/2026",
                "torn_bags": "0"
              },
              "row13": {
                "broken": "1",
                "extra_dirty": "0",
                "fillrows": "13",
                "mfgstate": "Karnataka",
                "mng_year": "2025",
                "neck_chip": "0",
                "other_brand": "0",
                "other_kf": "0",
                "short": "0",
                "tat_mfg_date": "27/04/2026",
                "torn_bags": "0"
              },
              "row14": {
                "broken": "0",
                "extra_dirty": "0",
                "fillrows": "14",
                "mfgstate": "Karnataka",
                "mng_year": "2025",
                "neck_chip": "0",
                "other_brand": "1",
                "other_kf": "0",
                "short": "0",
                "tat_mfg_date": "11/02/2026",
                "torn_bags": "0"
              },
              "row15": {
                "broken": "0",
                "extra_dirty": "0",
                "fillrows": "15",
                "mfgstate": "Jharkhand",
                "mng_year": "2025",
                "neck_chip": "0",
                "other_brand": "0",
                "other_kf": "0",
                "short": "0",
                "tat_mfg_date": "05/04/2026",
                "torn_bags": "0"
              },
              "row16": {
                "broken": "0",
                "extra_dirty": "1",
                "fillrows": "16",
                "mfgstate": "Karnataka",
                "mng_year": "2025",
                "neck_chip": "0",
                "other_brand": "0",
                "other_kf": "0",
                "short": "0",
                "tat_mfg_date": "17/12/2025",
                "torn_bags": "0"
              },
              "row17": {
                "broken": "0",
                "extra_dirty": "0",
                "fillrows": "17",
                "mfgstate": "Karnataka",
                "mng_year": "2025",
                "neck_chip": "0",
                "other_brand": "0",
                "other_kf": "0",
                "short": "0",
                "tat_mfg_date": "20/04/2026",
                "torn_bags": "0"
              },
              "row18": {
                "broken": "0",
                "extra_dirty": "0",
                "fillrows": "18",
                "mfgstate": "Karnataka",
                "mng_year": "2025",
                "neck_chip": "0",
                "other_brand": "0",
                "other_kf": "0",
                "short": "0",
                "tat_mfg_date": "13/01/2026",
                "torn_bags": "0"
              },
              "row19": {
                "broken": "0",
                "extra_dirty": "0",
                "fillrows": "19",
                "mfgstate": "Jharkhand",
                "mng_year": "2025",
                "neck_chip": "0",
                "other_brand": "0",
                "other_kf": "0",
                "short": "0",
                "tat_mfg_date": "12/03/2026",
                "torn_bags": "0"
              },
              "row2": {
                "broken": "0",
                "extra_dirty": "0",
                "fillrows": "2",
                "mfgstate": "Karnataka",
                "mng_year": "2025",
                "neck_chip": "0",
                "other_brand": "0",
                "other_kf": "0",
                "short": "0",
                "tat_mfg_date": "18/01/2026",
                "torn_bags": "0"
              },
              "row3": {
                "broken": "0",
                "extra_dirty": "0",
                "fillrows": "3",
                "mfgstate": "Karnataka",
                "mng_year": "2025",
                "neck_chip": "0",
                "other_brand": "0",
                "other_kf": "0",
                "short": "0",
                "tat_mfg_date": "25/03/2026",
                "torn_bags": "0"
              },
              "row4": {
                "broken": "0",
                "extra_dirty": "1",
                "fillrows": "4",
                "mfgstate": "Karnataka",
                "mng_year": "2025",
                "neck_chip": "0",
                "other_brand": "0",
                "other_kf": "0",
                "short": "0",
                "tat_mfg_date": "07/02/2026",
                "torn_bags": "0"
              },
              "row5": {
                "broken": "0",
                "extra_dirty": "0",
                "fillrows": "5",
                "mfgstate": "Karnataka",
                "mng_year": "2025",
                "neck_chip": "0",
                "other_brand": "0",
                "other_kf": "0",
                "short": "0",
                "tat_mfg_date": "15/04/2026",
                "torn_bags": "0"
              },
              "row6": {
                "broken": "0",
                "extra_dirty": "0",
                "fillrows": "6",
                "mfgstate": "Karnataka",
                "mng_year": "2025",
                "neck_chip": "0",
                "other_brand": "0",
                "other_kf": "0",
                "short": "0",
                "tat_mfg_date": "18/02/2026",
                "torn_bags": "0"
              },
              "row7": {
                "broken": "1",
                "extra_dirty": "0",
                "fillrows": "7",
                "mfgstate": "Karnataka",
                "mng_year": "2025",
                "neck_chip": "0",
                "other_brand": "0",
                "other_kf": "0",
                "short": "0",
                "tat_mfg_date": "30/01/2026",
                "torn_bags": "0"
              },
              "row8": {
                "broken": "0",
                "extra_dirty": "0",
                "fillrows": "8",
                "mfgstate": "Karnataka",
                "mng_year": "2025",
                "neck_chip": "0",
                "other_brand": "0",
                "other_kf": "0",
                "short": "0",
                "tat_mfg_date": "11/12/2025",
                "torn_bags": "0"
              },
              "row9": {
                "broken": "0",
                "extra_dirty": "0",
                "fillrows": "9",
                "mfgstate": "Karnataka",
                "mng_year": "2025",
                "neck_chip": "0",
                "other_brand": "0",
                "other_kf": "0",
                "short": "0",
                "tat_mfg_date": "24/01/2026",
                "torn_bags": "0"
              }
            },
            "dc3": {
              "row1": {
                "tot_broken": "3",
                "tot_extradirty": "2",
                "tot_neckchip": "1",
                "tot_otherbrand": "1",
                "tot_otherkf": "0",
                "tot_short": "0",
                "tot_tornbags": "0"
              }
            },
            "keyvalue": "",
            "mode": "new",
            "recordid": "0"
          }
        },
        "keyfield": "",
        "trace": "false",
        "username": "kantha"
      }
    };
  }

  static bool _isAuthenticationError(String message) {
    final lowerMessage = message.toLowerCase();

    const authKeywords = [
      "session",
      "authentication",
      "token",
      "unexpected"
          "authentication failed",
      "session expired",
      "invalid session",
      "session not valid",
      "invalid token",
      "token expired",
      "unauthorized",
      "access denied",
      "login expired",
      "jwt expired",
    ];

    return authKeywords.any((keyword) {
      return lowerMessage.contains(keyword);
    });
  }

  static Future<int> _batchUpdateStatus(List<int> ids, int status) async {
    if (ids.isEmpty) return 0;

    final String placeholders = List.filled(ids.length, '?').join(',');
    try {
      var updatecount = await _database.rawUpdate(
        '''
        UPDATE ${OfflineDBConstants.TABLE_PENDING_REQUESTS}
        SET ${OfflineDBConstants.COL_STATUS} = ?
        WHERE ${OfflineDBConstants.COL_ID} IN ($placeholders)
        ''',
        [status, ...ids],
      );

      LogService.writeLog(
          message:
              "Batch update complete via IN clause. Status: ${(status == 2) ? "Error" : "Success"}, IDS: ${ids.toString()} : updatecount : $updatecount");

      return updatecount;
    } catch (e) {
      log("Error in batch update: $e", name: "DB_ERROR");
      return -1;
    }
  }

  static bool _isAsset(Map<String, dynamic> pl) {
    String publicKey = (pl["publickey"] ?? '').toString().toLowerCase();
    return publicKey == "inwardattach";
  }

  static Future<void> _markAsError(int id) async {
    await _database.update(
      OfflineDBConstants.TABLE_PENDING_REQUESTS,
      {OfflineDBConstants.COL_STATUS: OfflineDBConstants.STATUS_ERROR},
      where: '${OfflineDBConstants.COL_ID} = ?',
      whereArgs: [id],
    );
  }

  static Future<void> _markAsSuccess(int id) async {
    await _database.update(
      OfflineDBConstants.TABLE_PENDING_REQUESTS,
      {OfflineDBConstants.COL_STATUS: OfflineDBConstants.STATUS_SUCCESS},
      where: '${OfflineDBConstants.COL_ID} = ?',
      whereArgs: [id],
    );
  }

  static String _isAssetHelper(Map<String, dynamic> pl) {
    String publicKey = pl["publickey"] ?? '';

    if (publicKey.toLowerCase() == "inwardentry") {
      var ubge = pl["submitdata"]["dataarray"]["data"]["dc1"]["row1"]
              ["ub_ge_no"] ??
          "";
      return ubge.isEmpty ? " Master " : " UBGE: $ubge ";
    } else if (publicKey.toLowerCase() == "inwardattach") {
      var ubge = pl["submitdata"]["dataarray"]["data"]["dc1"]["row1"]
              ["ub_gen_no"] ??
          "";
      return ubge.isEmpty ? " Asset " : " UBGE: $ubge ";
    }
    return ' ';
  }

  static Future<void> forcePushFailedRecords({
    required bool isInternetAvailable,
    required SyncProgressModel progress,
  }) async {
    const String forcePushAction = "FORCE_PUSH_RECORDS";
    if (!isInternetAvailable) {
      Get.snackbar("Error", "No internet connection");
      return;
    }

    if (progress.failedRecords.isEmpty) {
      progress.updateMessage("No failed records to force push.");
      return;
    }

    final int total = progress.failedRecords.length;
    progress.init(total: total, msg: "Preparing Force Push...");

    final ServerConnections serverConnections = ServerConnections();
    final String forceUrl =
        Const.getFullARMUrl(ExecuteApi.API_ARM_EXECUTE_PUBLISHED);

    int successCount = 0;
    int failCount = 0;
    var isTraceOn =
        await AppStorage().retrieveValue(AppStorage.isLogEnabled) ?? false;

    log(isTraceOn.toString(), name: "trace");

    for (int i = 0; i < total; i++) {
      final record = progress.failedRecords[i];
      final int id = record['id'];
      final String prevError = record['error'];
      final String errt = record['timestamp'];

      try {
        progress.updateMessage("Force pushing record ${i + 1} of $total...");

        final bodyStr = await _readLargeString(
          table: OfflineDBConstants.TABLE_PENDING_REQUESTS,
          column: OfflineDBConstants.COL_REQUEST_JSON,
          where: '${OfflineDBConstants.COL_ID} = ?',
          whereArgs: [id],
        );

        if (bodyStr == null || bodyStr.isEmpty) {
          progress.increment(isSuccess: false);
          await logAudit(
            action: forcePushAction,
            isError: true,
            remarks: "Record $id: Skipped (Payload empty)",
          );
          continue;
        }

        final Map<String, dynamic> originalPayload = jsonDecode(bodyStr);
        originalPayload['ARMSessionId'] =
            AppStorage().retrieveValue(AppStorage.SESSIONID);

        final Map<String, dynamic> payloadWithBase64 =
            await _convertPayloadPathsToBase64(originalPayload);

        final String payloadStringToSend = jsonEncode(payloadWithBase64);

        final Map<String, dynamic> wrapperPayload = {
          "ARMSessionId":
              await AppStorage().retrieveValue(AppStorage.SESSIONID),
          "publickey": "axofflinemobilelog",
          "project": await AppStorage().retrieveValue(AppStorage.PROJECT_NAME),
          "submitdata": {
            "username": await AppStorage().retrieveValue(AppStorage.USER_NAME),
            "trace": isTraceOn ? "true" : "false",
            "keyfield": "",
            "dataarray": {
              "data": {
                "mode": "new",
                "keyvalue": "",
                "recordid": "0",
                "dc1": {
                  "row1": {
                    "errordt": errt,
                    "username":
                        await AppStorage().retrieveValue(AppStorage.USER_NAME),
                    "errorresponse": prevError,
                    "payload": payloadStringToSend
                  }
                }
              }
            }
          }
        };

        final dynamic res = await serverConnections.postToServer(
          url: forceUrl,
          body: jsonEncode(wrapperPayload),
          isBearer: true,
        );

        bool isSuccess = false;
        if (res != null && res.isNotEmpty) {
          final decoded = jsonDecode(res);
          if (decoded is Map && decoded['success'] == true) {
            isSuccess = true;
          }
        }

        if (isSuccess) {
          successCount++;

          await _deletePayloadFiles(payloadWithBase64);

          await _database.update(
            OfflineDBConstants.TABLE_PENDING_REQUESTS,
            {
              OfflineDBConstants.COL_STATUS:
                  OfflineDBConstants.STATUS_FORCE_PUSHED
            },
            where: '${OfflineDBConstants.COL_ID} = ?',
            whereArgs: [id],
          );
        } else {
          failCount++;
          LogService.writeLog(message: "[FORCE_FAIL] ID: $id - $res");
        }
        await logAudit(
          action: forcePushAction,
          isError: !isSuccess,
          response: res?.toString() ?? "Empty Response",
          remarks:
              "Record $id: ${isSuccess ? 'SUCCESS' : 'FAILED'} | Previous Error: $prevError",
        );
        progress.increment(isSuccess: isSuccess);
      } catch (e) {
        failCount++;
        await logAudit(
          action: forcePushAction,
          isError: true,
          response: e.toString(),
          remarks: "Exception on Record $id force push",
        );
        progress.increment(isSuccess: false);
        LogService.writeLog(message: "[FORCE_FAIL] ID: $id - $e");
      }
    }

    progress.complete();
    await logAudit(
      action: forcePushAction,
      response: "COMPLETED",
      remarks:
          "COMPLETED: $successCount Success, $failCount Failed out of $total total.",
    );
    if (successCount > 0 && failCount == 0) {
      progress.updateMessage(
          "Force Push Successful! \nOffloaded all $successCount records.");
    } else if (successCount == 0 && failCount > 0) {
      progress.updateMessage(
          "Force Push Failed. \nCould not offload any of the $failCount records.");
    } else if (successCount > 0 && failCount > 0) {
      progress.updateMessage(
          "Force Push Completed with Issues.\nSuccess: $successCount \nFailed: $failCount");
    } else {
      progress.updateMessage("Operation completed. No records processed.");
    }
  }

  static Future<Map<String, dynamic>> _convertPayloadPathsToBase64(
      Map<String, dynamic> originalBody) async {
    Map<String, dynamic> payload = jsonDecode(jsonEncode(originalBody));

    try {
      await _recursivePathProcessor(payload, _convertAction);

      return payload;
    } catch (e) {
      log("_convertPayloadPathsToBase64", name: processPendingQueTag);
      return {};
    }
  }

  static Future<void> savePayloadForPostman(
      Map<String, dynamic> payload, String name) async {
    final directory = await getApplicationDocumentsDirectory();
    final file = File('${directory.path}/${name}_payload.json');

    await file.writeAsString(jsonEncode(payload));

    print("✅ FILE SAVED AT SPEED: ${file.path}");
    Get.snackbar("Saved", "File ready for extraction");
  }

  static Future<void> uploadTraceFile({
    required bool isInternetAvailable,
    SyncProgressModel? progress,
  }) async {
    const String uploadAction = "UPLOAD_TRACE_FILE";
    if (!isInternetAvailable) {
      progress?.updateMessage("Error: No internet connection");
      progress?.increment(isSuccess: false);
      return;
    }

    final File traceFile = File(Const.LOG_FILE_PATH);
    if (!await traceFile.exists()) {
      progress?.updateMessage("No trace file found to upload.");
      progress?.increment(isSuccess: false);
      await logAudit(
        action: uploadAction,
        isError: true,
        remarks: "Trace file not found at path: ${Const.LOG_FILE_PATH}",
      );
      return;
    }
    var isTraceOn =
        await AppStorage().retrieveValue(AppStorage.isLogEnabled) ?? false;
    try {
      progress?.updateMessage("Reading trace file...");
      progress?.updateMessage("Uploading to server...");
      LogService.writeLog(message: "[TRACE_UPLOAD] Preparing upload...");

      List<int> fileBytes = await traceFile.readAsBytes();
      String base64Trace = base64Encode(fileBytes);

      final String currentSessionId =
          await AppStorage().retrieveValue(AppStorage.SESSIONID) ?? "";
      final String currentUser =
          await AppStorage().retrieveValue(AppStorage.USER_NAME) ?? "";
      final String project =
          await AppStorage().retrieveValue(AppStorage.PROJECT_NAME) ?? "";

      final Map<String, dynamic> payload = {
        "ARMSessionId": currentSessionId,
        "publickey": "axofflinemobilelog",
        "project": project,
        "submitdata": {
          "username": currentUser,
          "trace": isTraceOn ? "true" : "false",
          "keyfield": "",
          "dataarray": {
            "data": {
              "mode": "new",
              "keyvalue": "",
              "recordid": "0",
              "dc1": {
                "row1": {
                  "errordt": DateTime.now().toIso8601String(),
                  "username": currentUser,
                  "errorresponse": "Trace Log Upload",
                  "payload": "",
                  "axpfile_file": {
                    "file1": {
                      "filename": "${Const.LOG_FILE_PATH.split("/").last}",
                      "fileasbase64": base64Trace
                    }
                  }
                }
              }
            }
          }
        }
      };

      final ServerConnections serverConnections = ServerConnections();
      final String url =
          Const.getFullARMUrl(ExecuteApi.API_ARM_EXECUTE_PUBLISHED);

      final dynamic res = await serverConnections.postToServer(
        url: url,
        body: jsonEncode(payload),
        isBearer: true,
      );

      if (res != null && res.isNotEmpty) {
        final decoded = jsonDecode(res);
        if (decoded is Map && decoded['success'] == true) {
          progress?.updateMessage("Upload Successful!");

          await logAudit(
              action: uploadAction,
              response: res?.toString() ?? "Empty Response",
              remarks:
                  "Successfully uploaded trace file: ${Const.LOG_FILE_PATH.split("/").last}");

          LogService.writeLog(message: "[TRACE_UPLOAD] Success");
        } else {
          await logAudit(
            action: uploadAction,
            isError: true,
            response: res?.toString() ?? "Empty Response",
            remarks:
                "Failed to upload trace file: ${Const.LOG_FILE_PATH.split("/").last}",
          );
          progress?.increment(isSuccess: false);
          progress?.updateMessage("Upload Failed.");
          LogService.writeLog(message: "[TRACE_UPLOAD] Server Failed: $res");
        }
      }
    } catch (e) {
      await logAudit(
        action: uploadAction,
        isError: true,
        response: e.toString(),
        remarks: "Exception occurred during trace file upload",
      );
      progress?.increment(isSuccess: false);
      progress?.updateMessage("Upload Failed.");
      LogService.writeLog(message: "[TRACE_UPLOAD] Exception: $e");
    }
  }

  static Future<dynamic> _convertAction(dynamic value) async {
    if (value is String && value.startsWith('/')) {
      final file = File(value);
      if (await file.exists()) {
        log("File found at $value, converting to base64",
            name: "AX_BUNDLE_LOG");
        var b64 = await fileToBase64Correct(file);

        return b64;
      } else {
        log("CRITICAL: File MISSING at $value during conversion!",
            name: "AX_BUNDLE_LOG");
        //remove before build
        // return "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII=";
        return "";
      }
    }
  }

  static Future<String> fileToBase64Correct(File file) async {
    final output = StringBuffer();

    final encoder = Base64Encoder();
    final stream = file.openRead().transform(encoder);

    await for (final chunk in stream) {
      output.write(chunk);
    }

    return output.toString();
  }

  static Future<String> compressAndBase64Large(File file) async {
    final tempDir = await getTemporaryDirectory();
    final targetPath =
        '${tempDir.path}/${DateTime.now().millisecondsSinceEpoch}.jpg';

    final compressedFile = await FlutterImageCompress.compressAndGetFile(
      file.path,
      targetPath,
      quality: 60,
      minWidth: 1280,
      minHeight: 1280,
    );

    if (compressedFile == null) {
      throw Exception('Compression failed');
    }

    final result = await streamFileToBase64(compressedFile);
    await File(targetPath).delete();
    return result;
  }

  static Future<String> streamFileToBase64(XFile file) async {
    final inputStream = file.openRead();
    final base64Sink = StringBuffer();

    await for (var chunk in inputStream) {
      base64Sink.write(base64.encode(chunk));
    }

    return base64Sink.toString();
  }

  static Future<String> compressImageToBase64(File imageFile) async {
    final Uint8List? compressedBytes =
        await FlutterImageCompress.compressWithFile(
      imageFile.absolute.path,
      quality: 65,
      minWidth: 1280,
      minHeight: 1280,
      format: CompressFormat.jpeg,
    );

    if (compressedBytes == null) {
      throw Exception("Compression failed");
    }

    return base64Encode(compressedBytes);
  }

  static Future<Uint8List?> compressFile(File file) async {
    var result = await FlutterImageCompress.compressWithFile(
      file.absolute.path,
      quality: 70,
    );
    print(file.lengthSync());
    print(result?.length);
    return result;
  }

  static Future<void> _deletePayloadFiles(Map<String, dynamic> body) async {
    await _recursivePathProcessor(body, _deleteAction);
  }

  static Future<void> _recursivePathProcessor(
    dynamic data,
    Future<dynamic> Function(dynamic) action,
  ) async {
    if (data is Map<String, dynamic>) {
      for (var key in data.keys) {
        if (key == 'fileasbase64') {
          var value = data[key];

          if (value is String) {
            data[key] = await action(value);
          } else if (value is List) {
            for (int i = 0; i < value.length; i++) {
              value[i] = await action(value[i]);
            }
          }
        } else {
          await _recursivePathProcessor(data[key], action);
        }
      }
    } else if (data is List) {
      for (var item in data) {
        await _recursivePathProcessor(item, action);
      }
    }
  }

  // Helper action: Delete File
  static Future<dynamic> _deleteAction(dynamic value) async {
    if (value is String && value.startsWith('/')) {
      final file = File(value);
      try {
        if (await file.exists()) {
          await file.delete();
          print("Deleted local image: $value");
        }
      } catch (e) {
        print("Error deleting file: $e");
      }
    }
    return value;
  }

  static Future<String?> _readLargeString({
    required String table,
    required String column,
    required String where,
    required List<Object?> whereArgs,
  }) async {
    final lengthResult = await _database.rawQuery(
      'SELECT length($column) as len FROM $table WHERE $where',
      whereArgs,
    );

    if (lengthResult.isEmpty) return null;
    int totalLength = (lengthResult.first['len'] as int?) ?? 0;

    if (totalLength == 0) return "";

    const int chunkSize = 1000000;
    StringBuffer finalString = StringBuffer();

    for (int offset = 1; offset <= totalLength; offset += chunkSize) {
      final chunkResult = await _database.rawQuery(
        'SELECT substr($column, ?, ?) as chunk FROM $table WHERE $where',
        [offset, chunkSize, ...whereArgs],
      );

      if (chunkResult.isNotEmpty) {
        finalString.write(chunkResult.first['chunk'] as String);
      }
    }

    return finalString.toString();
  }

  static Future<void> _syncPendingBeforeLogin({
    required String username,
    required String projectName,
    required bool isInternetAvailable,
  }) async {
    const String syncAction = "SYNC_BEFORE_LOGIN";
    if (!isInternetAvailable) return;

    final String currentSessionId =
        AppStorage().retrieveValue(AppStorage.SESSIONID) ?? "";
    if (currentSessionId.isEmpty) {
      LogService.writeLog(
          message: "[SYNC_SKIP] No active session ID found for sync");
      return;
    }

    final rows = await _database.query(
      OfflineDBConstants.TABLE_PENDING_REQUESTS,
      where: '''
      ${OfflineDBConstants.COL_STATUS} IN (${OfflineDBConstants.STATUS_PENDING}, ${OfflineDBConstants.STATUS_ERROR})
      AND ${OfflineDBConstants.COL_USERNAME} = ?
      AND ${OfflineDBConstants.COL_PROJECT_NAME} = ?
    ''',
      whereArgs: [username, projectName],
      orderBy: OfflineDBConstants.COL_CREATED_AT,
    );

    if (rows.isEmpty) return;

    final ServerConnections serverConnections = ServerConnections();
    final String url =
        Const.getFullARMUrl(ExecuteApi.API_ARM_EXECUTE_PUBLISHED);
    await logAudit(
      action: syncAction,
      remarks: "Found ${rows.length} pending records to sync during login.",
    );
    for (final row in rows) {
      final id = row[OfflineDBConstants.COL_ID] as int;
      try {
        final Map<String, dynamic> payload =
            jsonDecode(row[OfflineDBConstants.COL_REQUEST_JSON] as String);

        // 2. OVERRIDE with Fresh Session ID
        payload['ARMSessionId'] = currentSessionId;

        final res = await serverConnections.postToServer(
          url: url,
          body: jsonEncode(payload),
          isBearer: true,
        );

        bool isSuccess = false;
        if (res != null && res.isNotEmpty) {
          try {
            final decoded = jsonDecode(res);
            if (decoded is Map<String, dynamic> && decoded['success'] == true) {
              isSuccess = true;
            }
          } catch (_) {}
        }

        await _database.update(
          OfflineDBConstants.TABLE_PENDING_REQUESTS,
          {
            OfflineDBConstants.COL_STATUS: isSuccess
                ? OfflineDBConstants.STATUS_SUCCESS
                : OfflineDBConstants.STATUS_ERROR,
          },
          where: '${OfflineDBConstants.COL_ID} = ?',
          whereArgs: [id],
        );

        await logAudit(
          action: syncAction,
          isError: !isSuccess,
          response: res?.toString() ?? "Empty Response",
          remarks:
              "Auto-Sync Record ID: $id | Result: ${isSuccess ? 'SUCCESS' : 'FAILED'}",
        );
      } catch (e) {
        LogService.writeLog(message: "[SYNC_LOGIN_ERR] $e");
        await logAudit(
          action: syncAction,
          isError: true,
          response: e.toString(),
          remarks: "Exception during auto-sync of record ID: $id",
        );
      }
    }
  }

  // =================================================
  // SYNC ALL DATA (BUTTON)
  // =================================================

  static Future<void> syncAllData({
    required bool isInternetAvailable,
  }) async {
    final scope = await _getLastOfflineUserScope();
    if (scope == null) return;

    await _syncAllDataInternal(
      username: scope['username']!,
      projectName: scope['projectName']!,
      isInternetAvailable: isInternetAvailable,
    );
  }

  static Future<void> _syncAllDataInternal({
    required String username,
    required String projectName,
    required bool isInternetAvailable,
  }) async {
    const String syncAction = "SYNC_ALL_DATA";
    try {
      if (!isInternetAvailable) return;
      await logAudit(
        action: syncAction,
        remarks: "Full sync initiated: clearing cache and refetching all data.",
      );
      await _syncPendingBeforeLogin(
        username: username,
        projectName: projectName,
        isInternetAvailable: true,
      );

      int deletedPages = await _database.delete(
        OfflineDBConstants.TABLE_OFFLINE_PAGES,
        where: 'username = ? AND project_name = ?',
        whereArgs: [username, projectName],
      );

      await _database.delete(
        OfflineDBConstants.TABLE_DATASOURCES,
        where: 'username = ? AND project_name = ?',
        whereArgs: [username, projectName],
      );

      await _database.delete(
        OfflineDBConstants.TABLE_DATASOURCE_DATA,
        where: 'username = ? AND project_name = ?',
        whereArgs: [username, projectName],
      );
      await logAudit(
        action: syncAction,
        remarks:
            "Cache cleared for user $username. Previous pages removed: $deletedPages",
      );
      final pages = await fetchAndStoreOfflinePages();
      await logAudit(
        action: syncAction,
        isError: pages.isEmpty,
        remarks: pages.isNotEmpty
            ? "Full sync completed successfully. Fetched ${pages.length} forms."
            : "Full sync completed but no forms were found on the server.",
      );
      if (pages.isNotEmpty) {
        // datasources will be fetched lazily per form
      }
    } catch (e) {
      await logAudit(
        action: syncAction,
        isError: true,
        response: e.toString(),
        remarks: "Critical error during full sync process.",
      );
    }
  }

  // =================================================
  // CLEAR METHODS
  // =================================================
  static Future<void> clearPendingRequests({
    required String username,
    required String projectName,
  }) async {
    await _database.delete(
      OfflineDBConstants.TABLE_PENDING_REQUESTS,
      where: 'username = ? AND project_name = ?',
      whereArgs: [username, projectName],
    );
    await logAudit(
        action: "CLEAR_PENDING_QUEUE",
        remarks: "User manually cleared all pending uploads.");
  }

  static Future<void> clearOfflineCache({
    required String username,
    required String projectName,
  }) async {
    await _database.delete(
      OfflineDBConstants.TABLE_OFFLINE_PAGES,
      where: 'username = ? AND project_name = ?',
      whereArgs: [username, projectName],
    );

    await _database.delete(
      OfflineDBConstants.TABLE_DATASOURCES,
      where: 'username = ? AND project_name = ?',
      whereArgs: [username, projectName],
    );

    await _database.delete(
      OfflineDBConstants.TABLE_DATASOURCE_DATA,
      where: 'username = ? AND project_name = ?',
      whereArgs: [username, projectName],
    );

    await logAudit(
        action: "CLEAR_LOCAL_CACHE",
        remarks: "All offline forms and datasources cleared.");
  }

  static Future<void> clearAllData({
    required String username,
    required String projectName,
  }) async {
    await clearOfflineCache(username: username, projectName: projectName);
    await clearPendingRequests(username: username, projectName: projectName);
  }

  static Future<int> getPendingCount() async {
    final scope = await _getLastOfflineUserScope();
    if (scope == null) return 0;

    return _getPendingCountInternal(
      username: scope['username']!,
      projectName: scope['projectName']!,
    );
  }

  static Future<int> _getPendingCountInternal({
    required String username,
    required String projectName,
  }) async {
    final result = await _database.rawQuery(
      '''
    SELECT COUNT(*) as cnt 
    FROM ${OfflineDBConstants.TABLE_PENDING_REQUESTS} 
    WHERE ${OfflineDBConstants.COL_STATUS} IN (${OfflineDBConstants.STATUS_PENDING}, ${OfflineDBConstants.STATUS_ERROR})
    AND ${OfflineDBConstants.COL_USERNAME} = ?
    AND ${OfflineDBConstants.COL_PROJECT_NAME} = ?
    ''',
      [username, projectName],
    );

    return Sqflite.firstIntValue(result) ?? 0;
  }

  static Future<void> refetchAll({
    required bool isOnline,
  }) async {
    await syncAllData(
      isInternetAvailable: isOnline,
    );
  }

  static Future<void> refetchOnlyForms() async {
    String username =
        await AppStorage().retrieveValue(AppStorage.USER_NAME) ?? '';
    String projectName =
        await AppStorage().retrieveValue(AppStorage.PROJECT_NAME) ?? '';

    await _database.delete(
      OfflineDBConstants.TABLE_OFFLINE_PAGES,
      where: 'username = ? AND project_name = ?',
      whereArgs: [username, projectName],
    );

    await fetchAndStoreOfflinePages();
  }

  static Future<void> refetchOnlyDatasources({
    required String username,
    required String projectName,
  }) async {
    await _database.delete(
      OfflineDBConstants.TABLE_DATASOURCE_DATA,
      where: 'username = ? AND project_name = ?',
      whereArgs: [username, projectName],
    );
  }

  static Future<void> clearOfflinePages() async {
    final scope = await _getLastOfflineUserScope();
    if (scope == null) return;

    await _database.delete(
      OfflineDBConstants.TABLE_OFFLINE_PAGES,
      where: 'username = ? AND project_name = ?',
      whereArgs: [scope['username'], scope['projectName']],
    );
  }

  static Future<void> clearDatasources() async {
    final scope = await _getLastOfflineUserScope();
    if (scope == null) return;

    await _database.delete(
      OfflineDBConstants.TABLE_DATASOURCES,
      where: 'username = ? AND project_name = ?',
      whereArgs: [scope['username'], scope['projectName']],
    );

    await _database.delete(
      OfflineDBConstants.TABLE_DATASOURCE_DATA,
      where: 'username = ? AND project_name = ?',
      whereArgs: [scope['username'], scope['projectName']],
    );
  }

  static Future<void> clearPendingQueue() async {
    final scope = await _getLastOfflineUserScope();
    if (scope == null) return;

    await clearPendingRequests(
      username: scope['username']!,
      projectName: scope['projectName']!,
    );
  }

  static Future<void> clearAllExceptUser() async {
    final scope = await _getLastOfflineUserScope();
    if (scope == null) return;

    await clearOfflineCache(
      username: scope['username']!,
      projectName: scope['projectName']!,
    );

    await clearPendingRequests(
      username: scope['username']!,
      projectName: scope['projectName']!,
    );
  }

  static Future<void> syncAll({
    required bool isInternetAvailable,
  }) async {
    final scope = await _getLastOfflineUserScope();
    if (scope == null) return;

    await syncAllData(
      isInternetAvailable: isInternetAvailable,
    );
  }

  static Future<void> refetchAllData({
    required bool isOnline,
  }) async {
    final scope = await _getLastOfflineUserScope();
    if (scope == null) return;

    await refetchAll(
      isOnline: isOnline,
    );
  }

  static Future<void> clearOnlyForms() async {
    final scope = await _getLastOfflineUserScope();
    if (scope == null) return;

    await _database.delete(
      OfflineDBConstants.TABLE_OFFLINE_PAGES,
      where: 'username = ? AND project_name = ?',
      whereArgs: [scope['username'], scope['projectName']],
    );
  }

  static Future<void> clearOnlyDatasources() async {
    final scope = await _getLastOfflineUserScope();
    if (scope == null) return;

    await _database.delete(
      OfflineDBConstants.TABLE_DATASOURCE_DATA,
      where: 'username = ? AND project_name = ?',
      whereArgs: [scope['username'], scope['projectName']],
    );
  }

  static Future<bool> hasOfflineUser({
    required String projectName,
    required String username,
  }) async {
    final res = await _database.query(
      OfflineDBConstants.TABLE_OFFLINE_USER,
      where:
          '${OfflineDBConstants.COL_PROJECT_NAME} = ? AND ${OfflineDBConstants.COL_USERNAME} = ?',
      whereArgs: [projectName, username],
      limit: 1,
    );
    return res.isNotEmpty;
  }

  static Future<bool> validateOfflineLogin({
    required String projectName,
    required String username,
    required String passwordHash,
  }) async {
    final res = await _database.query(
      OfflineDBConstants.TABLE_OFFLINE_USER,
      where: '''
      ${OfflineDBConstants.COL_PROJECT_NAME} = ? AND
      ${OfflineDBConstants.COL_USERNAME} = ? AND
      ${OfflineDBConstants.COL_PASSWORD_HASH} = ?
    ''',
      whereArgs: [projectName, username, passwordHash],
      limit: 1,
    );
    await logAudit(
        action: "OFFLINE_LOGIN_VALIDATION",
        response: res.toString(),
        isError: res.isEmpty,
        remarks: res.isNotEmpty ? "VALIDATED" : "NOT_VALIDATED");
    return res.isNotEmpty;
  }

  static Future<void> saveUser({
    required String projectName,
    required String username,
    required String passwordHash,
    required Map<String, dynamic> loginResult,
  }) async {
    const tag = "[OFFLINE_USER_SAVE_002]";
    try {
      final result = loginResult['result'] ?? loginResult;
      final data = {
        OfflineDBConstants.COL_PROJECT_NAME: projectName,
        OfflineDBConstants.COL_USERNAME: username,
        OfflineDBConstants.COL_PASSWORD_HASH: passwordHash,
        OfflineDBConstants.COL_DISPLAY_NAME:
            result['nickname']?.toString() ?? username,
        OfflineDBConstants.COL_SESSION_ID:
            result['ARMSessionId']?.toString() ?? '',
        OfflineDBConstants.COL_RAW_JSON: jsonEncode(result),
        OfflineDBConstants.COL_LAST_LOGIN_AT: DateTime.now().toIso8601String(),
      };

      // ── Upsert: update if (projectName + username) already exists ─────────
      final List<Map<String, dynamic>> existing = await _database.query(
        OfflineDBConstants.TABLE_OFFLINE_USER,
        where:
            '${OfflineDBConstants.COL_PROJECT_NAME} = ? AND ${OfflineDBConstants.COL_USERNAME} = ?',
        whereArgs: [projectName, username],
        limit: 1,
      );

      if (existing.isNotEmpty) {
        await _database.update(
          OfflineDBConstants.TABLE_OFFLINE_USER,
          data,
          where:
              '${OfflineDBConstants.COL_PROJECT_NAME} = ? AND ${OfflineDBConstants.COL_USERNAME} = ?',
          whereArgs: [projectName, username],
        );
      } else {
        await _database.insert(
          OfflineDBConstants.TABLE_OFFLINE_USER,
          data,
        );
      }

      LogService.writeLog(
          message:
              "$tag[SUCCESS] User saved for offline login [${existing.isNotEmpty ? "Updated" : "Created"}]");
    } catch (e, st) {
      await logAudit(
        action: "SAVE_USER",
        response: st.toString(),
        isError: true,
        remarks:
            "[${OfflineDBConstants.TABLE_OFFLINE_USER}] User $username saving failed for offline login",
      );
      LogService.writeLog(message: "$tag[FAILED] $e");
      LogService.writeLog(message: "$tag[STACK] $st");
    }
  }

  static Future<Map<String, String>?> _getLastOfflineUserScope() async {
    final res = await _database.query(
      OfflineDBConstants.TABLE_OFFLINE_USER,
      orderBy: OfflineDBConstants.COL_LAST_LOGIN_AT + ' DESC',
      limit: 1,
    );

    if (res.isEmpty) return null;

    return {
      'username': res.first[OfflineDBConstants.COL_USERNAME] as String,
      'projectName': res.first[OfflineDBConstants.COL_PROJECT_NAME] as String,
    };
  }

  static Future<void> refreshAllDatasourcesFromDownloadedPages({
    SyncProgressModel? progressModel,
    bool isrefetching = false,
  }) async {
    var pages = await OfflineDbModule.getOfflinePages();
    log("getOfflinePages length => ${pages.length}", name: "datasourcerefetch");
    if (pages.isEmpty) return;
    progressModel?.init(total: pages.length, msg: "Analyzing forms...");
    for (final p in pages) {
      final transId = p['transid'];
      if (transId != null) {
        await fetchAndStoreAllDatasources(
            transId: transId,
            progress: progressModel,
            isrefetching: isrefetching);
      }
    }
  }

  static Future<void> logAudit({
    required String action,
    bool isError = false,
    String? response,
    String? remarks,
  }) async {
    try {
      final scope = await _getLastOfflineUserScope();
      final String? username = scope?['username'] ??
          await AppStorage().retrieveValue(AppStorage.USER_NAME);
      final String? projectName = scope?['projectName'] ??
          await AppStorage().retrieveValue(AppStorage.PROJECT_NAME);

      await _database.insert(
        OfflineDBConstants.TABLE_AUDIT_LOGS,
        {
          OfflineDBConstants.COL_USERNAME: username ?? 'Unknown',
          OfflineDBConstants.COL_PROJECT_NAME: projectName ?? 'Unknown',
          OfflineDBConstants.COL_ACTION: action,
          OfflineDBConstants.COL_CREATED_AT: DateTime.now().toIso8601String(),
          OfflineDBConstants.COL_IS_ERROR: isError ? 1 : 0,
          OfflineDBConstants.COL_RESPONSE: response ?? '',
          OfflineDBConstants.COL_REMARKS: remarks ?? '',
          OfflineDBConstants.COL_IS_SYNCED: 0,
        },
      );
    } catch (e) {
      debugPrint("Audit Log failed: $e");
    }
  }

  static Future<List<Map<String, dynamic>>> getAuditLogs() async {
    final res = await _database.query(
      OfflineDBConstants.TABLE_AUDIT_LOGS,
      orderBy: '${OfflineDBConstants.COL_ID} DESC',
      limit: 100,
    );
    return res;
  }

  static Future<void> clearAuditLogs() async {
    await _database.delete(OfflineDBConstants.TABLE_AUDIT_LOGS);
  }

  static Future<File> getDatabaseFile() async {
    final dbPath = join(await getDatabasesPath(), 'offline_forms.db');
    return File(dbPath);
  }

  static Future<void> importDatabaseFile(File sourceFile) async {
    final dbPath = join(await getDatabasesPath(), 'offline_forms.db');

    await _db?.close();

    await sourceFile.copy(dbPath);

    await init();
  }

  static Future<List<Map<String, dynamic>>> getRawPendingRequests() async {
    return await _database.query(OfflineDBConstants.TABLE_PENDING_REQUESTS);
  }

  static Future<void> updateLastSyncedTimestamp() async {
    try {
      final scope = await _getLastOfflineUserScope();
      if (scope == null) return;

      final now = DateTime.now().toIso8601String();

      await _database.update(
        OfflineDBConstants.TABLE_OFFLINE_USER,
        {OfflineDBConstants.COL_LAST_SYNCED: now},
        where: '${OfflineDBConstants.COL_USERNAME} = ? AND '
            '${OfflineDBConstants.COL_PROJECT_NAME} = ?',
        whereArgs: [scope['username'], scope['projectName']],
      );

      debugPrint("[OFFLINE_DB] last_synced updated → $now");
    } catch (e) {
      debugPrint("[OFFLINE_DB] updateLastSyncedTimestamp failed: $e");
    }
  }

  static Future<String?> getLastSyncedTimestamp() async {
    try {
      final scope = await _getLastOfflineUserScope();
      if (scope == null) return null;

      final res = await _database.query(
        OfflineDBConstants.TABLE_OFFLINE_USER,
        columns: [OfflineDBConstants.COL_LAST_SYNCED],
        where: '${OfflineDBConstants.COL_USERNAME} = ? AND '
            '${OfflineDBConstants.COL_PROJECT_NAME} = ?',
        whereArgs: [scope['username'], scope['projectName']],
        limit: 1,
      );

      if (res.isEmpty) return null;
      return res.first[OfflineDBConstants.COL_LAST_SYNCED] as String?;
    } catch (e) {
      return null;
    }
  }

  static Future<int> markAuditLogsAsSynced(List<int> ids) async {
    if (ids.isEmpty) return 0;

    final placeholders = ids.map((_) => '?').join(',');
    return await _database.rawUpdate(
      'UPDATE ${OfflineDBConstants.TABLE_AUDIT_LOGS} '
      'SET ${OfflineDBConstants.COL_IS_SYNCED} = 1 '
      'WHERE ${OfflineDBConstants.COL_ID} IN ($placeholders)',
      ids,
    );
  }

  static Future<List<Map<String, dynamic>>> getUnsyncedAuditLogs({
    int? limit = 200,
  }) async {
    return await _database.query(
      OfflineDBConstants.TABLE_AUDIT_LOGS,
      where: '${OfflineDBConstants.COL_IS_SYNCED} = 0',
      orderBy: '${OfflineDBConstants.COL_ID} ASC',
      limit: (limit != null && limit > 0) ? limit : null,
    );
  }

  static const String _bgPushTag = 'BG_PUSH_QUEUE_TAG';

  // static Future<String> backgroundPushPendingQueue({
  //   required String armUrl,
  //   void Function(int current, int total)? onProgress,
  // }) async {
  //   final scope = await _getLastOfflineUserScope();
  //   if (scope == null) {
  //     await LogService.writeLog(message: '[$_bgPushTag] No user scope found.');
  //     return 'No user session found';
  //   }

  //   final String username = scope['username']!;
  //   final String projectName = scope['projectName']!;

  //   final String sessionId =
  //       await AppStorage().retrieveValue(AppStorage.SESSIONID) ?? '';
  //   final String token =
  //       await AppStorage().retrieveValue(AppStorage.TOKEN) ?? '';
  //   final bool isTrace =
  //       await AppStorage().retrieveValue(AppStorage.isLogEnabled) ?? false;
  //   await LogService.writeLog(
  //     message:
  //         '[BG_PUSH_QUEUE] Session: "${sessionId.isEmpty ? "EMPTY" : sessionId.substring(0, sessionId.length.clamp(0, 20))}..." | User: $username',
  //   );
  //   // Inside the for loop, just before httpClient.post()

  //   if (sessionId.isEmpty) {
  //     await LogService.writeLog(
  //         message: '[$_bgPushTag] No active session. Aborting.');
  //     return 'No active session';
  //   }

  //   final idRows = await _database.query(
  //     OfflineDBConstants.TABLE_PENDING_REQUESTS,
  //     columns: [OfflineDBConstants.COL_ID],
  //     where: '''
  //     ${OfflineDBConstants.COL_STATUS} IN (
  //       ${OfflineDBConstants.STATUS_PENDING},
  //       ${OfflineDBConstants.STATUS_ERROR}
  //     )
  //     AND ${OfflineDBConstants.COL_USERNAME}     = ?
  //     AND ${OfflineDBConstants.COL_PROJECT_NAME} = ?
  //   ''',
  //     whereArgs: [username, projectName],
  //     orderBy: OfflineDBConstants.COL_CREATED_AT,
  //   );

  //   if (idRows.isEmpty) {
  //     await LogService.writeLog(message: '[$_bgPushTag] Queue is empty.');
  //     return 'Queue is empty';
  //   }

  //   final http.Client httpClient = http.Client();
  //   final String url = armUrl;
  //   final Map<String, String> headers = {
  //     'Content-Type': 'application/json',
  //     'Authorization': 'Bearer $token',
  //   };

  //   int successCount = 0;
  //   int failCount = 0;
  //   final int total = idRows.length;
  //   final List<int> successIds = [];
  //   final List<int> failedIds = [];
  //   await LogService.writeLog(
  //     message: '[$_bgPushTag] Starting push. Total: $total | User: $username',
  //   );

  //   for (int i = 0; i < total; i++) {
  //     final int id = idRows[i][OfflineDBConstants.COL_ID] as int;

  //     try {
  //       final String? bodyStr = await _readLargeString(
  //         table: OfflineDBConstants.TABLE_PENDING_REQUESTS,
  //         column: OfflineDBConstants.COL_REQUEST_JSON,
  //         where: '${OfflineDBConstants.COL_ID} = ?',
  //         whereArgs: [id],
  //       );

  //       if (bodyStr == null || bodyStr.isEmpty) {
  //         await _markAsError(id);
  //         await logAudit(
  //           action: _bgPushTag,
  //           isError: true,
  //           remarks: '[ID: $id] Empty payload — skipping.',
  //         );
  //         failCount++;
  //         continue;
  //       }

  //       final Map<String, dynamic> payload = jsonDecode(bodyStr);
  //       payload['ARMSessionId'] = sessionId.trim();
  //       payload['submitdata']['trace'] = isTrace ? 'true' : 'false';

  //       final String? storedUsername = payload['submitdata']['username'];
  //       if (storedUsername == null || storedUsername.isEmpty) {
  //         payload['submitdata']['username'] =
  //             AppStorage().retrieveValue(AppStorage.USER_NAME) ?? username;
  //       }
  //       await LogService.writeLog(
  //         message:
  //             '[$_bgPushTag] [ID: $id] Sending sessionId: "${payload['ARMSessionId'].toString()}"',
  //       );
  //       final Map<String, dynamic> uploadPayload =
  //           await _convertPayloadPathsToBase64(payload);
  //       if (uploadPayload.isEmpty) {
  //         failedIds.add(id);
  //         await _markAsError(id);
  //         await logAudit(
  //           action: _bgPushTag,
  //           isError: true,
  //           remarks: '[ID: $id] base64 conversion returned empty map.',
  //         );
  //         failCount++;
  //         continue;
  //       }

  //       if (_isAsset(uploadPayload)) {
  //         try {
  //           final fileMap = uploadPayload['submitdata']['dataarray']['data']
  //               ['dc1']['row1']['axpfile_file'] as Map<String, dynamic>;
  //           fileMap.forEach((key, value) {
  //             if (value is Map && value.containsKey('filename')) {
  //               value['filename'] =
  //                   value['filename'].toString().replaceAll('/', '_');
  //             }
  //           });
  //         } catch (e) {
  //           await LogService.writeLog(
  //               message: '[$_bgPushTag] [ID: $id] Filename fix failed: $e');
  //         }
  //       }

  //       // TODO DEBUG_ONLY: Hardcoded username and project name for imported DB testing.
  //       // imported db push will fail without this 2 lines
  //       // Remove before production build.
  //       // uploadPayload['submitdata']['username'] =
  //       //     await AppStorage().retrieveValue(AppStorage.USER_NAME);
  //       // uploadPayload['project'] =
  //       //     await AppStorage().retrieveValue(AppStorage.PROJECT_NAME);

  //       final http.Response response = await httpClient
  //           .post(
  //             Uri.parse(url),
  //             headers: headers,
  //             body: jsonEncode(uploadPayload),
  //           )
  //           .timeout(const Duration(seconds: 60));

  //       bool isSuccess = false;
  //       String errorMsg = 'Unknown error';

  //       // if (response.statusCode == 200 && response.body.isNotEmpty) {
  //       //   try {
  //       //     final decoded = jsonDecode(response.body);
  //       //     if (decoded is Map<String, dynamic> && decoded['success'] == true) {
  //       //       isSuccess = true;
  //       //     } else {
  //       //       errorMsg =
  //       //           decoded['message']?.toString() ?? 'Server returned false';
  //       //     }
  //       //   } catch (e) {
  //       //     errorMsg = 'Response parse error: $e';
  //       //   }
  //       // } else {
  //       //   await LogService.writeLog(
  //       //       message: "[$_bgPushTag] ${uploadPayload.toString()}");
  //       //   await LogService.writeLog(
  //       //       message:
  //       //           '[$_bgPushTag] HTTP ${response.statusCode}: ${response.body.isEmpty ? "-- Empty Response Body -- ${response.toString()}" : response.body}');
  //       //   await LogService.writeLog(
  //       //     message:
  //       //         '[$_bgPushTag] Unauthorized — session expired. Stopping cycle.',
  //       //   );

  //       //   await _markAsError(id);

  //       //   failedIds.add(id);
  //       //   failCount++;

  //       //   await logAudit(
  //       //     action: _bgPushTag,
  //       //     isError: true,
  //       //     response:
  //       //         'HTTP ${response.statusCode}: ${response.body.isEmpty ? "-- Empty Response Body -- ${response.toString()}" : response.body}',
  //       //     remarks: '[ID: $id] 401 Unauthorized. Stopping background push. '
  //       //         '| Progress: ${i + 1}/$total processed '
  //       //         '| Success count: ${successIds.length} — IDs: ${successIds.isEmpty ? 'none' : successIds.join(', ')} '
  //       //         '| Failed count: ${failedIds.length} — IDs: ${failedIds.isEmpty ? 'none' : failedIds.join(', ')} '
  //       //         '| Unprocessed count: ${total - (i + 1)} — IDs: ${idRows.sublist(i + 1).map((r) => r[OfflineDBConstants.COL_ID]).join(', ')}',
  //       //   );

  //       //   FlutterForegroundTask.sendDataToMain({
  //       //     SyncDataKeys.event: SyncDataKeys.evtAuthFailed,
  //       //     'statusCode': response.statusCode,
  //       //     'body':
  //       //         response.body.isEmpty ? '-- Empty Response --' : response.body,
  //       //   });
  //       //   errorMsg = 'HTTP ${response.statusCode}: ${response.body}';
  //       //   break;
  //       // }

  //       if (response.statusCode == 200 && response.body.isNotEmpty) {
  //         try {
  //           final decoded = jsonDecode(response.body);

  //           if (decoded is Map<String, dynamic> && decoded['success'] == true) {
  //             isSuccess = true;
  //           } else {
  //             errorMsg =
  //                 decoded['message']?.toString() ?? 'Server returned false';
  //           }
  //         } catch (e) {
  //           errorMsg = 'Response parse error: $e';
  //         }
  //       } else {
  //         final responseBody = response.body.isEmpty
  //             ? "-- Empty Response Body -- ${response.toString()}"
  //             : response.body;

  //         String displayMessage = responseBody;

  //         try {
  //           final decoded = jsonDecode(response.body);

  //           if (decoded is Map<String, dynamic>) {
  //             displayMessage = decoded['message']?.toString() ?? responseBody;
  //           }
  //         } catch (_) {}

  //         final bool isSessionIssue = _isAuthenticationError(displayMessage);

  //         await LogService.writeLog(
  //           message: "[$_bgPushTag] ${uploadPayload.toString()}",
  //         );

  //         await LogService.writeLog(
  //           message: '[$_bgPushTag] HTTP ${response.statusCode}: $responseBody',
  //         );

  //         await LogService.writeLog(
  //           message: isSessionIssue
  //               ? '[$_bgPushTag] Authentication/session issue detected. Stopping cycle.'
  //               : '[$_bgPushTag] Non-auth failure detected. Continuing sync.',
  //         );

  //         errorMsg = 'HTTP ${response.statusCode}: $displayMessage';
  //         await logAudit(
  //           action: _bgPushTag,
  //           isError: true,
  //           response: 'HTTP ${response.statusCode}: $responseBody',
  //           remarks: '[ID: $id] ${response.statusCode} — $displayMessage '
  //               '| Progress: ${i + 1}/$total processed '
  //               '| Success count: ${successIds.length} — IDs: ${successIds.isEmpty ? 'none' : successIds.join(', ')} '
  //               '| Failed count: ${failedIds.length} — IDs: ${failedIds.isEmpty ? 'none' : failedIds.join(', ')} '
  //               '| Unprocessed count: ${total - (i + 1)} — IDs: ${idRows.sublist(i + 1).map((r) => r[OfflineDBConstants.COL_ID]).join(', ')}',
  //         );
  //         if (isSessionIssue) {
  //           await _markAsError(id);

  //           failedIds.add(id);
  //           failCount++;

  //           FlutterForegroundTask.sendDataToMain({
  //             SyncDataKeys.event: SyncDataKeys.evtAuthFailed,
  //             'statusCode': response.statusCode,
  //             'body': displayMessage,
  //           });

  //           break;
  //         }
  //       }

  //       if (isSuccess) {
  //         successIds.add(id);
  //         await _deletePayloadFiles(uploadPayload);
  //         await _markAsSuccess(id);
  //         successCount++;
  //       } else {
  //         failedIds.add(id);
  //         await _markAsError(id);
  //         failCount++;
  //         await logAudit(
  //           action: _bgPushTag,
  //           isError: true,
  //           response: response.body,
  //           remarks:
  //               '[ID: $id] ${isSuccess ? "SUCCESS" : "FAILED"} | Key: ${uploadPayload['publickey']}',
  //         );
  //       }
  //       onProgress?.call(i + 1, total);
  //       await LogService.writeLog(
  //         message:
  //             '[$_bgPushTag] [ID: $id] ${isSuccess ? "SUCCESS" : "FAILED: $errorMsg"}',
  //       );
  //     } catch (e) {
  //       await _markAsError(id);
  //       failCount++;
  //       failedIds.add(id);
  //       await LogService.writeLog(
  //           message: '[$_bgPushTag] [ID: $id] Exception: $e');
  //       await logAudit(
  //         action: _bgPushTag,
  //         isError: true,
  //         response: e.toString(),
  //         remarks: '[ID: $id] Exception during background push.',
  //       );
  //     }
  //   }

  //   httpClient.close();
  //   if (successIds.isNotEmpty) {
  //     await _database.rawUpdate(
  //       '''UPDATE ${OfflineDBConstants.TABLE_PENDING_REQUESTS}
  //        SET ${OfflineDBConstants.COL_STATUS} = ${OfflineDBConstants.STATUS_SUCCESS}
  //        WHERE ${OfflineDBConstants.COL_ID} IN (${successIds.join(',')})''',
  //     );
  //     await LogService.writeLog(
  //         message:
  //             '[$_bgPushTag] Batch SUCCESS update: ${successIds.length} rows — IDs: $successIds');
  //   }

  //   if (failedIds.isNotEmpty) {
  //     await _database.rawUpdate(
  //       '''UPDATE ${OfflineDBConstants.TABLE_PENDING_REQUESTS}
  //        SET ${OfflineDBConstants.COL_STATUS} = ${OfflineDBConstants.STATUS_ERROR}
  //        WHERE ${OfflineDBConstants.COL_ID} IN (${failedIds.join(',')})''',
  //     );
  //     await LogService.writeLog(
  //         message:
  //             '[$_bgPushTag] Batch ERROR update: ${failedIds.length} rows — IDs: $failedIds');
  //   }
  //   final String result = 'Processed: $successCount success, $failCount failed';
  //   await LogService.writeLog(message: '[$_bgPushTag] Done. $result');
  //   await backgroundPushAuditLogs(
  //     armUrl: armUrl,
  //     onStatusUpdate: (msg) => onProgress?.call(-1, -1),
  //   );
  //   return result;
  // }

  // static Future<Set<String>> getExistingUbgeNos() async {
  //   final scope = await _getLastOfflineUserScope();
  //   if (scope == null) return {};

  //   final rows = await _database.query(
  //     OfflineDBConstants.TABLE_PENDING_REQUESTS,
  //     columns: [OfflineDBConstants.COL_ID, OfflineDBConstants.COL_REQUEST_JSON],
  //     where: '''
  //     ${OfflineDBConstants.COL_STATUS} IN (
  //       ${OfflineDBConstants.STATUS_PENDING},
  //       ${OfflineDBConstants.STATUS_ERROR},
  //       ${OfflineDBConstants.STATUS_SUCCESS}
  //     )
  //     AND ${OfflineDBConstants.COL_USERNAME} = ?
  //     AND ${OfflineDBConstants.COL_PROJECT_NAME} = ?
  //   ''',
  //     whereArgs: [scope['username'], scope['projectName']],
  //   );

  //   final Set<String> result = {};

  //   for (final row in rows) {
  //     try {
  //       final bodyStr = await _readLargeString(
  //         table: OfflineDBConstants.TABLE_PENDING_REQUESTS,
  //         column: OfflineDBConstants.COL_REQUEST_JSON,
  //         where: '${OfflineDBConstants.COL_ID} = ?',
  //         whereArgs: [row[OfflineDBConstants.COL_ID]],
  //       );

  //       if (bodyStr == null || bodyStr.isEmpty) continue;

  //       final Map<String, dynamic> payload = jsonDecode(bodyStr);

  //       final String publicKey =
  //           (payload['publickey'] ?? '').toString().toLowerCase();
  //       if (publicKey != 'inwardentry') continue;

  //       final String? ubgeNo = payload['submitdata']?['dataarray']?['data']
  //               ?['dc1']?['row1']?['ub_ge_no']
  //           ?.toString();

  //       if (ubgeNo != null && ubgeNo.trim().isNotEmpty) {
  //         result.add(ubgeNo.trim().toUpperCase());
  //       }
  //     } catch (e) {
  //       debugPrint("[UBGE_CHECK] Error parsing record: $e");
  //     }
  //   }

  //   return result;
  // }

  static Future<String> backgroundPushPendingQueue({
    required String armUrl,
    void Function(int current, int total)? onProgress,
  }) async {
    final scope = await _getLastOfflineUserScope();
    if (scope == null) {
      await LogService.writeLog(message: '[$_bgPushTag] No user scope found.');
      return 'No user session found';
    }

    final String username = scope['username']!;
    final String projectName = scope['projectName']!;

    final String sessionId =
        await AppStorage().retrieveValue(AppStorage.SESSIONID) ?? '';
    final String token =
        await AppStorage().retrieveValue(AppStorage.TOKEN) ?? '';
    final bool isTrace =
        await AppStorage().retrieveValue(AppStorage.isLogEnabled) ?? false;

    await LogService.writeLog(
      message:
          '[BG_PUSH_QUEUE] Session: "${sessionId.isEmpty ? "EMPTY" : sessionId.substring(0, sessionId.length.clamp(0, 20))}..." | User: $username',
    );

    if (sessionId.isEmpty) {
      await LogService.writeLog(
          message: '[$_bgPushTag] No active session. Aborting.');
      return 'No active session';
    }

    final idRows = await _database.query(
      OfflineDBConstants.TABLE_PENDING_REQUESTS,
      columns: [OfflineDBConstants.COL_ID],
      where: '''
      ${OfflineDBConstants.COL_STATUS} IN (
        ${OfflineDBConstants.STATUS_PENDING},
        ${OfflineDBConstants.STATUS_ERROR}
      )
      AND ${OfflineDBConstants.COL_USERNAME}     = ?
      AND ${OfflineDBConstants.COL_PROJECT_NAME} = ?
    ''',
      whereArgs: [username, projectName],
      orderBy: OfflineDBConstants.COL_CREATED_AT,
    );

    if (idRows.isEmpty) {
      await LogService.writeLog(message: '[$_bgPushTag] Queue is empty.');
      return 'Queue is empty';
    }

    final ServerConnections serverConnections = ServerConnections();
    final String url = armUrl;

    int successCount = 0;
    int failCount = 0;
    final int total = idRows.length;
    final List<int> successIds = [];
    final List<int> failedIds = [];

    await LogService.writeLog(
      message: '[$_bgPushTag] Starting push. Total: $total | User: $username',
    );

    for (int i = 0; i < total; i++) {
      final int id = idRows[i][OfflineDBConstants.COL_ID] as int;

      try {
        final String? bodyStr = await _readLargeString(
          table: OfflineDBConstants.TABLE_PENDING_REQUESTS,
          column: OfflineDBConstants.COL_REQUEST_JSON,
          where: '${OfflineDBConstants.COL_ID} = ?',
          whereArgs: [id],
        );

        if (bodyStr == null || bodyStr.isEmpty) {
          await _markAsError(id);
          await logAudit(
            action: _bgPushTag,
            isError: true,
            remarks: '[ID: $id] Empty payload — skipping.',
          );
          failCount++;
          continue;
        }

        final Map<String, dynamic> payload = jsonDecode(bodyStr);
        payload['ARMSessionId'] = sessionId.trim();
        payload['submitdata']['trace'] = isTrace ? 'true' : 'false';

        final String? storedUsername = payload['submitdata']['username'];
        if (storedUsername == null || storedUsername.isEmpty) {
          payload['submitdata']['username'] =
              AppStorage().retrieveValue(AppStorage.USER_NAME) ?? username;
        }

        await LogService.writeLog(
          message:
              '[$_bgPushTag] [ID: $id] Sending sessionId: "${payload['ARMSessionId'].toString()}"',
        );

        final Map<String, dynamic> uploadPayload =
            await _convertPayloadPathsToBase64(payload);

        if (uploadPayload.isEmpty) {
          failedIds.add(id);
          await _markAsError(id);
          await logAudit(
            action: _bgPushTag,
            isError: true,
            remarks: '[ID: $id] base64 conversion returned empty map.',
          );
          failCount++;
          continue;
        }

        if (_isAsset(uploadPayload)) {
          try {
            final fileMap = uploadPayload['submitdata']['dataarray']['data']
                ['dc1']['row1']['axpfile_file'] as Map<String, dynamic>;
            fileMap.forEach((key, value) {
              if (value is Map && value.containsKey('filename')) {
                value['filename'] =
                    value['filename'].toString().replaceAll('/', '_');
              }
            });
          } catch (e) {
            await LogService.writeLog(
                message: '[$_bgPushTag] [ID: $id] Filename fix failed: $e');
          }
        }

        final SubmitdataApiresponsemodel res =
            await serverConnections.postQueueToServer(
          url: url,
          body: jsonEncode(uploadPayload),
          isBearer: true,
        );

        String displayMessage = res.message;

        await LogService.writeLog(
          message:
              "[$_bgPushTag] [API RESULT] ${res.rawBody} || ${_isAssetHelper(uploadPayload)}",
        );

        // if (res.statusCode != 200) {
        //   await logAudit(
        //     action: _bgPushTag,
        //     isError: true,
        //     response:
        //         res.rawBody.isEmpty ? "-- Empty Response --" : res.rawBody,
        //     remarks: "[ID: $id] ${res.statusCode} — $displayMessage "
        //         "| Progress: ${i + 1}/$total processed "
        //         "| Success count: ${successIds.length} — IDs: ${successIds.isEmpty ? 'none' : successIds.join(', ')} "
        //         "| Failed count: ${failedIds.length} — IDs: ${failedIds.isEmpty ? 'none' : failedIds.join(', ')}",
        //   );

        //   /// =====================================================
        //   /// DIRECT BREAK (Auth failure / Server crash)
        //   /// =====================================================
        //   if (res.statusCode == 401 || res.statusCode == 500) {
        //     await _markAsError(id);
        //     failedIds.add(id);
        //     failCount++;

        //     FlutterForegroundTask.sendDataToMain({
        //       SyncDataKeys.event: SyncDataKeys.evtAuthFailed,
        //       'statusCode': res.statusCode,
        //       'body': displayMessage,
        //     });
        //     break;
        //   }

        //   /// =====================================================
        //   /// 400 -> CHECK AUTH MESSAGE
        //   /// =====================================================
        //   if (res.statusCode == 400) {
        //     final bool isSessionIssue = _isAuthenticationError(displayMessage);

        //     if (isSessionIssue) {
        //       await _markAsError(id);
        //       failedIds.add(id);
        //       failCount++;

        //       FlutterForegroundTask.sendDataToMain({
        //         SyncDataKeys.event: SyncDataKeys.evtAuthFailed,
        //         'statusCode': res.statusCode,
        //         'body': displayMessage,
        //       });
        //       break;
        //     }

        //     // Normal validation error
        //     await _markAsError(id);
        //     failedIds.add(id);
        //     failCount++;
        //     continue;
        //   }

        //   /// =====================================================
        //   /// OTHER NON-200 ERRORS
        //   /// =====================================================
        //   await _markAsError(id);
        //   failedIds.add(id);
        //   failCount++;
        //   continue;
        // }

        // // =====================================================
        // // SUCCESS HANDLING (Status 200)
        // // =====================================================

        // String displayMessage = res.message;

        /// =====================================================
        /// SUCCESS
        /// =====================================================

        if (res.success) {
          await _deletePayloadFiles(uploadPayload);

          await _markAsSuccess(id);

          successIds.add(id);

          successCount++;
        } else {
          await logAudit(
            action: _bgPushTag,
            isError: true,
            response:
                res.rawBody.isEmpty ? "-- Empty Response --" : res.rawBody,
            remarks: "[ID: $id] ${res.statusCode} — $displayMessage "
                "| Progress: ${i + 1}/$total processed "
                "| Success count: ${successIds.length} — IDs: ${successIds.isEmpty ? 'none' : successIds.join(', ')} "
                "| Failed count: ${failedIds.length} — IDs: ${failedIds.isEmpty ? 'none' : failedIds.join(', ')}",
          );

          /// =====================================================
          /// 400 -> AUTH CHECK
          /// =====================================================

          if (res.statusCode == 400) {
            final bool isSessionIssue = _isAuthenticationError(displayMessage);

            /// AUTH FAILURE -> BREAK
            if (isSessionIssue) {
              await _markAsError(id);

              failedIds.add(id);

              failCount++;

              FlutterForegroundTask.sendDataToMain({
                SyncDataKeys.event: SyncDataKeys.evtAuthFailed,
                'statusCode': res.statusCode,
                'body': displayMessage,
              });

              break;
            }

            /// NORMAL VALIDATION ERROR -> CONTINUE
            await _markAsError(id);

            failedIds.add(id);

            failCount++;

            continue;
          }

          /// =====================================================
          /// ALL OTHER FAILURES -> BREAK
          /// =====================================================

          await _markAsError(id);

          failedIds.add(id);

          failCount++;

          FlutterForegroundTask.sendDataToMain({
            SyncDataKeys.event: SyncDataKeys.evtAuthFailed,
            'statusCode': res.statusCode,
            'body': displayMessage,
          });

          break;
        }
        // if (res.success) {
        //   await _deletePayloadFiles(uploadPayload);
        //   await _markAsSuccess(id);
        //   successIds.add(id);
        //   successCount++;
        // } else {
        //   await _markAsError(id);
        //   failedIds.add(id);
        //   failCount++;
        //   await logAudit(
        //     action: _bgPushTag,
        //     isError: true,
        //     response: res.rawBody,
        //     remarks:
        //         '[ID: $id] Status: ${res.success ? 'SUCCESS' : 'FAILED'} | Key: ${uploadPayload['publickey']}',
        //   );
        // }

        onProgress?.call(i + 1, total);
        await LogService.writeLog(
          message:
              '[$_bgPushTag] [ID: $id] ${res.success ? "SUCCESS" : "FAILED: $displayMessage"}',
        );
      } catch (e) {
        await _markAsError(id);
        failCount++;
        failedIds.add(id);
        await LogService.writeLog(
            message: '[$_bgPushTag] [ID: $id] Exception: $e');
        await logAudit(
          action: _bgPushTag,
          isError: true,
          response: e.toString(),
          remarks: '[ID: $id] Exception during background push.',
        );
      }
    }

    if (successIds.isNotEmpty) {
      var updateSuccessCount = await _batchUpdateStatus(
          successIds, OfflineDBConstants.STATUS_SUCCESS);
      await LogService.writeLog(
          message:
              '[$_bgPushTag] Batch SUCCESS update: $updateSuccessCount rows — IDs: $successIds');
    }

    if (failedIds.isNotEmpty) {
      var updateFailureCount =
          await _batchUpdateStatus(failedIds, OfflineDBConstants.STATUS_ERROR);
      await LogService.writeLog(
          message:
              '[$_bgPushTag] Batch ERROR update: $updateFailureCount rows — IDs: $failedIds');
    }

    final String result = 'Processed: $successCount success, $failCount failed';
    await LogService.writeLog(message: '[$_bgPushTag] Done. $result');
    await backgroundPushAuditLogs(
      armUrl: armUrl,
      onStatusUpdate: (msg) => onProgress?.call(-1, -1),
    );
    return result;
  }

  static Future<bool> isUbgeNoExists(String typed) async {
    final scope = await _getLastOfflineUserScope();
    if (scope == null) return false;

    final rows = await _database.query(
      OfflineDBConstants.TABLE_PENDING_REQUESTS,
      columns: [OfflineDBConstants.COL_ID, OfflineDBConstants.COL_REQUEST_JSON],
      where: '''
      ${OfflineDBConstants.COL_STATUS} IN (
        ${OfflineDBConstants.STATUS_PENDING},
        ${OfflineDBConstants.STATUS_ERROR},
        ${OfflineDBConstants.STATUS_SUCCESS}
      )
      AND ${OfflineDBConstants.COL_USERNAME} = ?
      AND ${OfflineDBConstants.COL_PROJECT_NAME} = ?
    ''',
      whereArgs: [scope['username'], scope['projectName']],
    );

    final typedUpper = typed.trim().toUpperCase();

    for (final row in rows) {
      try {
        final bodyStr = await _readLargeString(
          table: OfflineDBConstants.TABLE_PENDING_REQUESTS,
          column: OfflineDBConstants.COL_REQUEST_JSON,
          where: '${OfflineDBConstants.COL_ID} = ?',
          whereArgs: [row[OfflineDBConstants.COL_ID]],
        );

        if (bodyStr == null || bodyStr.isEmpty) continue;

        final Map<String, dynamic> payload = jsonDecode(bodyStr);

        final String publicKey =
            (payload['publickey'] ?? '').toString().toLowerCase();
        if (publicKey != 'inwardentry') continue;

        final String? ubgeNo = payload['submitdata']?['dataarray']?['data']
                ?['dc1']?['row1']?['ub_ge_no']
            ?.toString();

        // Check if the current row matches the typed value
        if (ubgeNo != null && ubgeNo.trim().toUpperCase() == typedUpper) {
          return true;
        }
      } catch (e) {
        debugPrint("[UBGE_CHECK] Error parsing record: $e");
      }
    }
    return false; // No match found after checking all rows
  }

  // ─────────────────────────────────────────────────────────────────────────────
// AUDIT LOG PUSH
// ─────────────────────────────────────────────────────────────────────────────

  static const String _auditPushTag = 'PUSH_AUDIT_LOGS';
  static Future<void> pushAuditLogsToServer({
    required bool isInternetAvailable,
    SyncProgressModel? progress,
  }) async {
    if (!isInternetAvailable) {
      LogService.writeLog(message: '[$_auditPushTag] Skipped — no internet.');
      return;
    }

    final scope = await _getLastOfflineUserScope();
    if (scope == null) {
      LogService.writeLog(message: '[$_auditPushTag] Skipped — no user scope.');
      return;
    }

    final String sessionId =
        AppStorage().retrieveValue(AppStorage.SESSIONID) ?? '';
    final String username = scope['username']!;
    final String projectName = scope['projectName']!;
    final bool isTrace =
        await AppStorage().retrieveValue(AppStorage.isLogEnabled) ?? false;

    if (sessionId.isEmpty) {
      LogService.writeLog(
          message: '[$_auditPushTag] Skipped — empty session ID.');
      return;
    }

    final List<Map<String, dynamic>> rows =
        await getUnsyncedAuditLogs(limit: 200);

    if (rows.isEmpty) {
      progress?.startAuditPhase(0);
      progress?.completeAuditPhase();
      LogService.writeLog(
          message: '[$_auditPushTag] No unsynced audit logs found.');

      return;
    }

    // ── STARTED ───────────────────────────────────────────────────────────────
    await logAudit(
      action: _auditPushTag,
      remarks: 'Audit log push started — ${rows.length} unsynced rows queued.',
    );
    progress?.startAuditPhase(rows.length);

    LogService.writeLog(
      message: '[$_auditPushTag] Starting push — ${rows.length} unsynced rows.',
    );
    final ServerConnections serverConnections = ServerConnections();
    final String url =
        Const.getFullARMUrl(ExecuteApi.API_ARM_EXECUTE_PUBLISHED);
    final List<int> syncedIds = [];

    for (final row in rows) {
      final int id = row[OfflineDBConstants.COL_ID] as int;

      try {
        final String rawCreatedAt =
            row[OfflineDBConstants.COL_CREATED_AT] as String? ?? '';
        String formattedDate = rawCreatedAt;
        try {
          final dt = DateTime.parse(rawCreatedAt);
          formattedDate = DateFormat('dd/MM/yyyy hh:mm:ss a').format(dt);
        } catch (_) {}

        final Map<String, dynamic> payload = {
          'ARMSessionId': sessionId,
          'publickey': 'api_axm_audit',
          'project': projectName,
          'submitdata': {
            'username': username,
            'trace': isTrace ? 'true' : 'false',
            'keyfield': '',
            'dataarray': {
              'data': {
                'mode': 'new',
                'keyvalue': '',
                'recordid': '0',
                'dc1': {
                  'row1': {
                    'username':
                        row[OfflineDBConstants.COL_USERNAME] ?? username,
                    'project_name':
                        row[OfflineDBConstants.COL_PROJECT_NAME] ?? projectName,
                    'action': row[OfflineDBConstants.COL_ACTION] ?? '',
                    'created_at': formattedDate,
                    'is_error':
                        ((row[OfflineDBConstants.COL_IS_ERROR] ?? 0) == 1)
                            ? 'true'
                            : 'false',
                    'response': row[OfflineDBConstants.COL_RESPONSE] ?? '',
                    'remarks': row[OfflineDBConstants.COL_REMARKS] ?? '',
                  },
                },
              },
            },
          },
        };

        final SubmitdataApiresponsemodel res =
            await serverConnections.postQueueToServer(
          url: url,
          body: jsonEncode(payload),
          isBearer: true,
        );

        if (res.rawBody.isEmpty) {
          LogService.writeLog(
            message: '[$_auditPushTag] [ID: $id] Empty response — skipping.',
          );
          await logAudit(
            action: _auditPushTag,
            isError: true,
            remarks: '[ID: $id] Empty response from server — skipped.',
          );
          continue;
        }
        String displayMessage = res.message;

        /// =====================================================
        /// SUCCESS
        /// =====================================================

        if (res.success) {
          syncedIds.add(id);

          progress?.incrementAudit(isSuccess: true);

          LogService.writeLog(
            message: '[$_auditPushTag] [ID: $id] Pushed successfully.',
          );
        } else {
          progress?.incrementAudit(isSuccess: false);

          LogService.writeLog(
            message: '[$_auditPushTag] [ID: $id] FAILED: $displayMessage',
          );

          await logAudit(
            action: _auditPushTag,
            isError: true,
            response: res.rawBody,
            remarks: '[ID: $id] Server rejected audit row — continuing. '
                'Reason: $displayMessage',
          );

          /// =====================================================
          /// 400 -> AUTH CHECK
          /// =====================================================

          if (res.statusCode == 400) {
            final bool isAuthIssue = _isAuthenticationError(displayMessage);

            if (isAuthIssue) {
              LogService.writeLog(
                message: '[$_auditPushTag] [ID: $id] Auth error — stopping. '
                    'Reason: $displayMessage',
              );

              progress?.completeAuditPhase();

              break;
            }

            /// NORMAL VALIDATION ERROR
            continue;
          }

          /// =====================================================
          /// ALL OTHER FAILURES -> BREAK
          /// =====================================================

          progress?.completeAuditPhase();

          break;
        }
      } catch (e) {
        final String err = e.toString();
        LogService.writeLog(
            message: '[$_auditPushTag] [ID: $id] Exception: $err');
        await logAudit(
          action: _auditPushTag,
          isError: true,
          response: err,
          remarks:
              '[ID: $id] Exception during audit push — ${_isAuthenticationError(err) ? "loop stopped (auth)" : "continuing"}.',
        );

        if (_isAuthenticationError(err)) {
          break;
        }
        continue;
      }
    }

    if (syncedIds.isNotEmpty) {
      final int updated = await markAuditLogsAsSynced(syncedIds);
      LogService.writeLog(
        message:
            '[$_auditPushTag] Marked $updated rows as synced. IDs: $syncedIds',
      );
    }

    // ── ENDED ────────────────────────────────────────────────────────────────
    await logAudit(
      action: _auditPushTag,
      remarks:
          'Audit log push ended — ${syncedIds.length}/${rows.length} rows synced successfully.',
    );
    progress?.completeAuditPhase();
    LogService.writeLog(
      message:
          '[$_auditPushTag] Done. ${syncedIds.length}/${rows.length} pushed.',
    );
  }

  static const String _bgAuditPushTag = 'BG_PUSH_AUDIT_LOGS';

  static Future<String> backgroundPushAuditLogs({
    required String armUrl,
    void Function(String message)? onStatusUpdate,
  }) async {
    // ── Scope + session guards ──────────────────────────────────────────────
    final scope = await _getLastOfflineUserScope();
    if (scope == null) {
      await LogService.writeLog(
        message: '[$_bgAuditPushTag] No user scope found.',
      );
      return 'No user session found';
    }

    final String username = scope['username']!;
    final String projectName = scope['projectName']!;

    final String sessionId =
        await AppStorage().retrieveValue(AppStorage.SESSIONID) ?? '';
    final String token =
        await AppStorage().retrieveValue(AppStorage.TOKEN) ?? '';
    final bool isTrace =
        await AppStorage().retrieveValue(AppStorage.isLogEnabled) ?? false;

    if (sessionId.isEmpty) {
      await LogService.writeLog(
        message: '[$_bgAuditPushTag] No active session. Aborting.',
      );
      return 'No active session';
    }

    // ── Fetch unsynced rows ─────────────────────────────────────────────────
    final List<Map<String, dynamic>> rows =
        await getUnsyncedAuditLogs(limit: 200);

    if (rows.isEmpty) {
      await LogService.writeLog(
        message: '[$_bgAuditPushTag] No unsynced audit logs. Skipping.',
      );
      return 'No audit logs to push';
    }

    // ── STARTED ────────────────────────────────────────────────────────────
    await logAudit(
      action: _bgAuditPushTag,
      remarks:
          'Background audit push started — ${rows.length} unsynced rows queued.',
    );

    await LogService.writeLog(
      message:
          '[$_bgAuditPushTag] Starting. Total: ${rows.length} | User: $username',
    );

    onStatusUpdate?.call('Uploading audit logs (0 / ${rows.length})...');

    final http.Client httpClient = http.Client();
    final Map<String, String> headers = {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $token',
    };

    final int total = rows.length;
    final List<int> syncedIds = [];
    int failCount = 0;

    for (int i = 0; i < total; i++) {
      final int id = rows[i][OfflineDBConstants.COL_ID] as int;

      try {
        // ── Format the timestamp ──────────────────────────────────────────
        final String rawCreatedAt =
            rows[i][OfflineDBConstants.COL_CREATED_AT] as String? ?? '';
        String formattedDate = rawCreatedAt;
        try {
          final dt = DateTime.parse(rawCreatedAt);
          formattedDate = DateFormat('dd/MM/yyyy hh:mm:ss a').format(dt);
        } catch (_) {}

        // ── Build payload ─────────────────────────────────────────────────
        final Map<String, dynamic> payload = {
          'ARMSessionId': sessionId.trim(),
          'publickey': 'api_axm_audit',
          'project': projectName,
          'submitdata': {
            'username': username,
            'trace': isTrace ? 'true' : 'false',
            'keyfield': '',
            'dataarray': {
              'data': {
                'mode': 'new',
                'keyvalue': '',
                'recordid': '0',
                'dc1': {
                  'row1': {
                    'username':
                        rows[i][OfflineDBConstants.COL_USERNAME] ?? username,
                    'project_name': rows[i]
                            [OfflineDBConstants.COL_PROJECT_NAME] ??
                        projectName,
                    'action': rows[i][OfflineDBConstants.COL_ACTION] ?? '',
                    'created_at': formattedDate,
                    'is_error':
                        ((rows[i][OfflineDBConstants.COL_IS_ERROR] ?? 0) == 1)
                            ? 'true'
                            : 'false',
                    'response': rows[i][OfflineDBConstants.COL_RESPONSE] ?? '',
                    'remarks': rows[i][OfflineDBConstants.COL_REMARKS] ?? '',
                  },
                },
              },
            },
          },
        };

        // ── POST ──────────────────────────────────────────────────────────
        final http.Response response = await httpClient
            .post(
              Uri.parse(armUrl),
              headers: headers,
              body: jsonEncode(payload),
            )
            .timeout(const Duration(seconds: 30));

        // ── Evaluate ──────────────────────────────────────────────────────
        final SubmitdataApiresponsemodel res =
            SubmitdataApiresponsemodel.fromHttpResponse(response);
        String displayMessage = res.message;

        /// =====================================================
        /// SUCCESS
        /// =====================================================

        if (res.success) {
          syncedIds.add(id);

          await LogService.writeLog(
            message: '[$_bgAuditPushTag] [ID: $id] SUCCESS.',
          );
        } else {
          await LogService.writeLog(
            message: '[$_bgAuditPushTag] [ID: $id] FAILED: $displayMessage',
          );

          await logAudit(
            action: _bgAuditPushTag,
            isError: true,
            response: res.rawBody,
            remarks: '[ID: $id] Server rejected audit row — $displayMessage',
          );

          /// =====================================================
          /// 400 -> AUTH CHECK
          /// =====================================================

          if (res.statusCode == 400) {
            final bool isAuthIssue = _isAuthenticationError(displayMessage);

            if (isAuthIssue) {
              await LogService.writeLog(
                message:
                    '[$_bgAuditPushTag] Auth error detected — stopping loop.',
              );

              await logAudit(
                action: _bgAuditPushTag,
                isError: true,
                remarks:
                    '[ID: $id] Auth error during background audit push — loop stopped.',
              );

              break;
            }

            /// normal validation failure
            failCount++;

            onStatusUpdate?.call(
              'Audit logs: ${syncedIds.length + failCount} / $total processed...',
            );

            continue;
          }

          /// =====================================================
          /// ALL OTHER FAILURES -> BREAK
          /// =====================================================

          failCount++;

          await LogService.writeLog(
            message: '[$_bgAuditPushTag] Critical failure — stopping loop.',
          );

          break;
        }
      } catch (e) {
        final String err = e.toString();
        failCount++;
        await LogService.writeLog(
          message: '[$_bgAuditPushTag] [ID: $id] Exception: $err',
        );
        await logAudit(
          action: _bgAuditPushTag,
          isError: true,
          response: err,
          remarks:
              '[ID: $id] Exception — ${_isAuthenticationError(err) ? "loop stopped (auth)" : "continuing"}.',
        );

        if (_isAuthenticationError(err)) {
          break;
        }
        continue;
      }
    }

    httpClient.close();

    // ── Batch-mark synced rows ──────────────────────────────────────────────
    if (syncedIds.isNotEmpty) {
      final int updated = await markAuditLogsAsSynced(syncedIds);
      await LogService.writeLog(
        message:
            '[$_bgAuditPushTag] Marked $updated rows as synced. IDs: $syncedIds',
      );
    }

    final String result =
        'Audit logs: ${syncedIds.length} synced, $failCount failed';

    // ── ENDED ──────────────────────────────────────────────────────────────
    await logAudit(
      action: _bgAuditPushTag,
      remarks:
          'Background audit push ended — ${syncedIds.length}/$total synced successfully.',
    );

    await LogService.writeLog(
      message: '[$_bgAuditPushTag] Done. $result',
    );

    onStatusUpdate?.call(result);

    return result;
  }
}
