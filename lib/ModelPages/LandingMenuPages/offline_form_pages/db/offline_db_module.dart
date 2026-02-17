import 'dart:convert';
import 'dart:developer';
import 'dart:io';

import 'package:ubbottleapp/Constants/AppStorage.dart';
import 'package:ubbottleapp/Constants/Const.dart';
import 'package:ubbottleapp/ModelPages/LandingMenuPages/offline_form_pages/models/data_source_model.dart';
import 'package:ubbottleapp/ModelPages/LandingMenuPages/offline_form_pages/models/form_page_model.dart';
import 'package:ubbottleapp/ModelPages/LandingMenuPages/offline_form_pages/models/sync_progress_model.dart';
import 'package:ubbottleapp/ModelPages/LandingMenuPages/offline_form_pages/widgets/sync_progress_dialog.dart';
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

enum SubmitStatus { success, savedOffline, apiFailure }

//TODO check role and save to globalvar and show the audit manage screen
//( (role == admin ) = all data)
class OfflineDbModule {
  OfflineDbModule._();
  // static ServerConnections serverConnections = ServerConnections();
  static Database? _db;

  // INIT

  static var autoSync = false;

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

  static Future<void> init() async {
    autoSync = await AppStorage().retrieveValue(AppStorage.AUTO_SYNC) ?? false;
    final dbPath = join(await getDatabasesPath(), 'offline_forms.db');

    _db = await openDatabase(
      dbPath,
      version: 5,
      onCreate: (db, _) async {
        await _createTables(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        const tag = "[OFFLINE_DB_UPGRADE_005]";
        LogService.writeLog(
            message: "$tag[START] Upgrading DB $oldVersion → $newVersion");

        await db.execute(OfflineDBConstants.CREATE_AUDIT_LOGS_TABLE);

        await db.insert(OfflineDBConstants.TABLE_AUDIT_LOGS, {
          OfflineDBConstants.COL_ACTION: "DB_UPGRADE",
          OfflineDBConstants.COL_REMARKS:
              "Upgraded from $oldVersion to $newVersion successfully.",
          OfflineDBConstants.COL_CREATED_AT: DateTime.now().toIso8601String(),
          OfflineDBConstants.COL_IS_ERROR: 0,
        });

        LogService.writeLog(
            message: "$tag[SUCCESS] Audit table added, data preserved.");
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

    if (autoSync) {
      await _syncPendingBeforeLogin(
        username: username,
        projectName: projectName,
        isInternetAvailable: isInternetAvailable,
      );
    }

    final pages = await fetchAndStoreOfflinePages();

    if (pages.isEmpty) {
      LogService.writeLog(message: "$tag[INFO] No offline pages received");
      return;
    }

    await fetchAndStoreAllDatasourcesForAllForms(pages);

    LogService.writeLog(
      message: "$tag[SUCCESS] Offline bootstrap done. pages=${pages.length}",
    );
  }

  static Future<void> fetchAndStoreAllDatasourcesForAllForms(
    List<Map<String, dynamic>> pages,
  ) async {
    final scope = await _getLastOfflineUserScope();
    if (scope == null) return;

    final username = scope['username']!;
    final projectName = scope['projectName']!;
    final sessionId = AppStorage().retrieveValue(AppStorage.SESSIONID) ?? "";

    for (final page in pages) {
      final transId = page['transid']?.toString();
      if (transId == null || transId.isEmpty) continue;

      final Set<String> dsSet = _getAllUniqueDatasourcesInPage(page);

      if (dsSet.isEmpty) continue;

      for (final ds in dsSet) {
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

        if (exists.isNotEmpty) {
          continue;
        }

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
              "$tag[URL] Offline pages URL => ${Uri.parse(OfflineDBConstants.OFFLINE_PAGES_URL())} \n[URI] => ");

      log(res.body, name: tag);
      if (res.statusCode != 200) return [];

      final decoded = jsonDecode(utf8.decode(res.bodyBytes)) as List<dynamic>;
      final pages = decoded.map((e) => e as Map<String, dynamic>).toList();
      await logAudit(
        action: "FETCH_OFFLINE_FORMS",
        response: res.toString(),
        remarks:
            "Tried fetching offline pages from server :Res Forms: ${pages.length} forms",
      );
      if (pages.isEmpty) return [];

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
  }) async {
    final scope = await _getLastOfflineUserScope();
    if (scope == null) return;

    await _fetchAndStoreAllDatasourcesInternal(
      username: scope['username']!,
      projectName: scope['projectName']!,
      transId: transId,
      progress: progress,
    );
  }

  static Future<void> _fetchAndStoreAllDatasourcesInternal({
    required String username,
    required String projectName,
    required String transId,
    SyncProgressModel? progress,
  }) async {
    try {
      final datasources = await _getDatasourceList(
        username: username,
        projectName: projectName,
        transId: transId,
      );

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

        if (exists.isNotEmpty) {
          progress?.increment();
          continue;
        }

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
              await logAudit(
                action: "API_SUBMIT_FORM",
                response: responseStr,
                remarks: "Form: ${submitBody['publickey'] ?? "NO_PUBLIC_KEY"}",
              );
              await _deletePayloadFiles(submitBody);
              return SubmitStatus.success;
            } else {
              final msg = decoded['message'] ?? "Unknown Error";
              LogService.writeLog(
                  message: "[API_FAIL] Server returned false: $msg");
              await logAudit(
                action: "API_SUBMIT_FORM",
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
    await logAudit(
      action: "OFFLINE_SUBMIT_FORM",
      remarks:
          "Record ID: $rowId | Form: ${submitBody['publickey'] ?? "NO_PUBLIC_KEY"}",
      response:
          "Saved locally due to ${force_offline ? 'Force Offline' : 'No Internet'}",
    );
    return SubmitStatus.savedOffline;
  }

  static var processPendingQueTag = "PROCESS_PENDING_QUE";
  static Future<String> processPendingQueue({
    required bool isInternetAvailable,
    SyncProgressModel? progress,
  }) async {
    log("processpendingque started", name: processPendingQueTag);
    if (!isInternetAvailable) return "No internet connection";

    final scope = await _getLastOfflineUserScope();
    if (scope == null) return "No user session found";

    final username = scope['username']!;
    final projectName = scope['projectName']!;
    log("processpendingque scope Username $username",
        name: processPendingQueTag);
    await logAudit(
      action: processPendingQueTag,
      remarks: "Started background sync for user: $username",
    );
    final String currentSessionId =
        AppStorage().retrieveValue(AppStorage.SESSIONID) ?? "";
    if (currentSessionId.isEmpty) return "No active session to sync";

    progress?.updateMessage("Checking pending queue...");

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
      progress?.complete();
      await logAudit(
          action: processPendingQueTag,
          response: "SYNC_QUEUE_EMPTY",
          remarks: "No pending records found to sync");
      return "Queue is empty";
    }

    int successCount = 0;
    int failCount = 0;
    int total = idRows.length;

    progress?.clearFailedRecords();
    progress?.init(
        total: total, msg: "Found $total records. Starting upload...");

    final ServerConnections serverConnections = ServerConnections();
    final String url =
        Const.getFullARMUrl(ExecuteApi.API_ARM_EXECUTE_PUBLISHED);
    var isTraceOn =
        await AppStorage().retrieveValue(AppStorage.isLogEnabled) ?? false;
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
          progress?.addFailedRecord(id, "Empty payload");
          progress?.increment(isSuccess: false);
          await logAudit(
            action: processPendingQueTag,
            isError: true,
            remarks: "(ID: $id) Empty payload found in local DB",
          );
          continue;
        }

        final Map<String, dynamic> originalPayload = jsonDecode(bodyStr);
        originalPayload['ARMSessionId'] = currentSessionId;

        originalPayload['ARMSessionId'] = currentSessionId;
        originalPayload['submitdata']['trace'] = isTraceOn ? "true" : "false";
        originalPayload['submitdata']['username'] =
            (originalPayload['submitdata']['username'] ?? "").isEmpty
                ? await AppStorage().retrieveValue(AppStorage.USER_NAME)
                : originalPayload['submitdata']['username'];

        final Map<String, dynamic> uploadPayload =
            await _convertPayloadPathsToBase64(originalPayload);
        log("processpendingque uploadPayload.length ${uploadPayload.length}",
            name: processPendingQueTag);
        progress?.updateMessage(
            "Uploading${_isAssetHelper(uploadPayload)}record ${i + 1} of $total...");

        if (_isAsset(uploadPayload)) {
          try {
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

        final dynamic res = await serverConnections.postToServer(
          url: url,
          body: jsonEncode(uploadPayload),
          isBearer: true,
        );

        bool isSuccess = false;
        String? errorMsg;

        if (res != null && res.isNotEmpty) {
          LogService.writeLog(message: "[API ERROR]||[API SUCCESS] $res");
          try {
            final decoded = jsonDecode(res);
            if (decoded is Map<String, dynamic> && decoded['success'] == true) {
              isSuccess = true;
            } else {
              errorMsg = decoded['message'] ?? "Unknown server error";
            }
          } catch (e) {
            errorMsg = "Response parse error: $e";
          }
        } else {
          errorMsg = "Empty response from server";
        }

        if (isSuccess) {
          await _deletePayloadFiles(uploadPayload);
          await _markAsSuccess(id);
          successCount++;
        } else {
          await _markAsError(id);
          progress?.addFailedRecord(id, errorMsg ?? "Unknown error");
          failCount++;
        }
        await logAudit(
          action: processPendingQueTag,
          isError: !isSuccess,
          response: res?.toString() ?? "Empty Response",
          remarks:
              "[ID: $id] Status: ${isSuccess ? 'SUCCESS' : 'FAILED'} | Key: ${uploadPayload['publickey']}",
        );
        progress?.increment(isSuccess: isSuccess);
      } catch (e) {
        await logAudit(
          action: processPendingQueTag,
          isError: true,
          response: e.toString(),
          remarks: "Exception processing record ID: $id",
        );
        await _markAsError(id);
        progress?.addFailedRecord(id, e.toString());
        progress?.increment(isSuccess: false);
        failCount++;
      }
    }

    progress?.complete();
    progress?.updateMessage("Completed ");

    return "Processed: $successCount success, $failCount failed ";
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

      final int rowId = await _database.insert(
        OfflineDBConstants.TABLE_OFFLINE_USER,
        data,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

      await logAudit(
        action: "SAVE_USER",
        response: "Success",
        remarks:
            "[${OfflineDBConstants.TABLE_OFFLINE_USER}] (ID: $rowId) User $username saved for offline login",
      );

      LogService.writeLog(
          message: "$tag[SUCCESS] User saved for offline login");
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

  static Future<void> refreshAllDatasourcesFromDownloadedPages(
      {SyncProgressModel? progressModel}) async {
    var pages = await OfflineDbModule.getOfflinePages();
    if (pages.isEmpty) return;
    progressModel?.init(total: pages.length, msg: "Analyzing forms...");
    for (final p in pages) {
      final transId = p['transid'];
      if (transId != null) {
        await fetchAndStoreAllDatasources(
            transId: transId, progress: progressModel);
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
}
