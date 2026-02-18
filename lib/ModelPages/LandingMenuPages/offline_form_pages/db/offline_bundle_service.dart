import 'dart:convert';
import 'dart:io';
import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:ubbottleapp/Constants/AppStorage.dart';
import 'package:ubbottleapp/Utils/LogServices/LogService.dart';
import 'offline_db_constants.dart';
import 'offline_db_module.dart';

class OfflineBundleService {
  static const String bundleExtension = ".axbundle";
  static const String bundleAction = "DB_BUNDLE_OPERATION";
  static const String logTag = "[AX_BUNDLE_LOG]";
  static const String _backupFileName = "last_import_backup.axbundle";
  static const String _backupMetaFileName = "last_import_backup.meta.json";

  static Future<String> _backupFilePath() async {
    final dir = await getApplicationDocumentsDirectory();
    return join(dir.path, _backupFileName);
  }

  static Future<String> _backupMetaPath() async {
    final dir = await getApplicationDocumentsDirectory();
    return join(dir.path, _backupMetaFileName);
  }

  /// Returns true if a pre-import backup exists.
  static Future<bool> hasBackup() async {
    final path = await _backupFilePath();
    return File(path).exists();
  }

  static Future<Map<String, dynamic>?> getBackupMeta() async {
    final metaPath = await _backupMetaPath();
    final metaFile = File(metaPath);
    if (!await metaFile.exists()) return null;
    try {
      final content = await metaFile.readAsString();
      return jsonDecode(content) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  static Future<void> backupCurrentDatabase() async {
    LogService.writeLog(
        message: "$logTag [BACKUP_START] Creating pre-import backup...");
    try {
      final dbFile = await OfflineDbModule.getDatabaseFile();
      final archive = Archive();
      final List<String> assetPaths = [];

      final List<Map<String, dynamic>> pendingRequests =
          await OfflineDbModule.getRawPendingRequests();

      for (var row in pendingRequests) {
        final String jsonStr = row[OfflineDBConstants.COL_REQUEST_JSON] ?? "";
        if (jsonStr.isNotEmpty) {
          _findPathsInJson(jsonDecode(jsonStr), assetPaths);
        }
      }

      archive.addFile(ArchiveFile(
          'offline_forms.db', dbFile.lengthSync(), await dbFile.readAsBytes()));

      for (String path in assetPaths.toSet()) {
        final file = File(path);
        if (await file.exists()) {
          archive.addFile(ArchiveFile('assets/${basename(path)}',
              file.lengthSync(), await file.readAsBytes()));
        }
      }

      final zipEncoder = ZipEncoder();
      final encodedZip = zipEncoder.encode(archive);
      final backupPath = await _backupFilePath();
      await File(backupPath).writeAsBytes(encodedZip);

      final user =
          await AppStorage().retrieveValue(AppStorage.USER_NAME) ?? "Unknown";
      final now = DateTime.now();
      final meta = {
        "timestamp": now.toIso8601String(),
        "user": user,
        "displayTime":
            "${now.day.toString().padLeft(2, '0')}/${now.month.toString().padLeft(2, '0')}/${now.year} "
                "${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}",
      };
      await File(await _backupMetaPath()).writeAsString(jsonEncode(meta));

      LogService.writeLog(
          message: "$logTag [BACKUP_SUCCESS] Backup saved to $backupPath");
    } catch (e) {
      LogService.writeLog(message: "$logTag [BACKUP_CRASH] $e");
      rethrow;
    }
  }

  static Future<void> restoreBackup() async {
    final path = await _backupFilePath();
    final backupFile = File(path);
    if (!await backupFile.exists()) {
      throw Exception("No backup found to restore.");
    }
    debugPrint("$logTag [RESTORE_BACKUP] Restoring from $path");
    await importBundle(backupFile);
  }

  static Future<File?> createExportBundle() async {
    try {
      LogService.writeLog(
          message:
              "$logTag [EXPORT_START] Packaging DB and underscore-pathed assets...");

      final String user =
          await AppStorage().retrieveValue(AppStorage.USER_NAME) ??
              "UnknownUser";

      final now = DateTime.now();
      final String timestamp =
          "${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}_"
          "${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}";

      final dbFile = await OfflineDbModule.getDatabaseFile();
      final archive = Archive();
      final List<String> assetPaths = [];

      final List<Map<String, dynamic>> pendingRequests =
          await OfflineDbModule.getRawPendingRequests();

      for (var row in pendingRequests) {
        final String jsonStr = row[OfflineDBConstants.COL_REQUEST_JSON] ?? "";
        if (jsonStr.isNotEmpty) {
          _findPathsInJson(jsonDecode(jsonStr), assetPaths);
        }
      }

      final uniqueAssets = assetPaths.toSet().toList();
      archive.addFile(ArchiveFile(
          'offline_forms.db', dbFile.lengthSync(), await dbFile.readAsBytes()));

      int addedCount = 0;
      for (String path in uniqueAssets) {
        final file = File(path);
        if (await file.exists()) {
          archive.addFile(ArchiveFile('assets/${basename(path)}',
              file.lengthSync(), await file.readAsBytes()));
          addedCount++;
        } else {
          debugPrint("$logTag [EXPORT_WARN] File not found: $path");
        }
      }

      final zipEncoder = ZipEncoder();
      final encodedZip = zipEncoder.encode(archive);
      final tempDir = await getTemporaryDirectory();
      final String fileName = "Export_${user}_$timestamp$bundleExtension";
      final bundleFile = File('${tempDir.path}/$fileName');
      await bundleFile.writeAsBytes(encodedZip);

      LogService.writeLog(
          message:
              "$logTag [EXPORT_SUCCESS] Bundled $addedCount assets into ${bundleFile.path}");
      return bundleFile;
    } catch (e) {
      LogService.writeLog(message: "$logTag [EXPORT_CRASH] $e");
      return null;
    }
  }

  static Future<void> importBundle(File bundleFile) async {
    try {
      final bytes = await bundleFile.readAsBytes();
      final archive = ZipDecoder().decodeBytes(bytes);

      final appDocDir = await getApplicationDocumentsDirectory();
      final String currentAppFlutterPath = appDocDir.path;
      final String packageRoot = appDocDir.parent.path;

      String? oldPathToReplace;

      for (final file in archive) {
        if (file.name.startsWith('assets/')) {
          final String fileName = basename(file.name);
          final outFile = File(join(packageRoot, fileName));
          await outFile.create(recursive: true);
          await outFile.writeAsBytes(file.content as List<int>);
          LogService.writeLog(
              message: "$logTag [EXTRACT] Physical file: ${outFile.path}");
        }
      }

      for (final file in archive) {
        if (file.name == 'offline_forms.db') {
          final tempDbPath =
              join((await getTemporaryDirectory()).path, 'temp_import.db');
          await File(tempDbPath).writeAsBytes(file.content as List<int>);
          Database tempDb = await openDatabase(tempDbPath);

          final allRecords =
              await tempDb.query(OfflineDBConstants.TABLE_PENDING_REQUESTS);
          for (var row in allRecords) {
            final String? jsonStr =
                row[OfflineDBConstants.COL_REQUEST_JSON] as String?;
            if (oldPathToReplace == null &&
                jsonStr != null &&
                jsonStr.contains('app_flutter_')) {
              oldPathToReplace = _extractRootPath(jsonStr);
              if (oldPathToReplace != null) break;
            }
          }

          if (oldPathToReplace != null) {
            debugPrint(
                "$logTag [REMAP] Replacing: $oldPathToReplace WITH: $currentAppFlutterPath");
            await _remapDatabasePaths(
                tempDb, oldPathToReplace, currentAppFlutterPath);
          }

          await tempDb.close();
          final finalDbPath =
              join(await getDatabasesPath(), 'offline_forms.db');
          await File(tempDbPath).copy(finalDbPath);
          await File(tempDbPath).delete();
        }
      }
    } catch (e) {
      LogService.writeLog(message: "$logTag [IMPORT_CRASH] $e");
      rethrow;
    }
  }

  static void _findPathsInJson(dynamic data, List<String> paths) {
    if (data is Map) {
      data.forEach((key, value) => _findPathsInJson(value, paths));
    } else if (data is List) {
      for (var item in data) {
        _findPathsInJson(item, paths);
      }
    } else if (data is String && data.startsWith('/')) {
      paths.add(data);
    }
  }

  static String? _extractRootPath(String jsonStr) {
    final match = RegExp(r'(/[^\s]+)/app_flutter(?=_)').firstMatch(jsonStr);
    return match?.group(0);
  }

  static Future<void> _remapDatabasePaths(
      Database db, String oldRoot, String newRoot) async {
    await db.execute('''
      UPDATE ${OfflineDBConstants.TABLE_PENDING_REQUESTS} 
      SET ${OfflineDBConstants.COL_REQUEST_JSON} = REPLACE(${OfflineDBConstants.COL_REQUEST_JSON}, ?, ?)
    ''', [oldRoot, newRoot]);
  }

  static Future<void> deleteBackup() async {
    try {
      final backupPath = await _backupFilePath();
      final metaPath = await _backupMetaPath();

      final backupFile = File(backupPath);
      final metaFile = File(metaPath);

      if (await backupFile.exists()) {
        await backupFile.delete();
        debugPrint("$logTag [BACKUP_DELETE] Deleted backup: $backupPath");
      }

      if (await metaFile.exists()) {
        await metaFile.delete();
        LogService.writeLog(
            message: "$logTag [BACKUP_DELETE] Deleted metadata: $metaPath");
      }
    } catch (e) {
      LogService.writeLog(
          message: "$logTag [BACKUP_DELETE_WARN] Failed to delete backup: $e");
    }
  }
}
