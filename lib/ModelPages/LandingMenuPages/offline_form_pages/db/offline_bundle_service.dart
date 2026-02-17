import 'dart:convert';
import 'dart:io';
import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:ubbottleapp/Constants/AppStorage.dart';
import 'offline_db_constants.dart';
import 'offline_db_module.dart';

class OfflineBundleService {
  static const String bundleExtension = ".axbundle";
  static const String bundleAction = "DB_BUNDLE_OPERATION";
  static const String logTag = "[AX_BUNDLE_LOG]";

  // ---------------- EXPORT LOGIC ----------------

  static Future<File?> createExportBundle() async {
    try {
      debugPrint(
          "$logTag [EXPORT_START] Packaging DB and underscore-pathed assets...");
      final scope = await OfflineDbModule
          .getRawPendingRequests(); // or use your GetLastScope helper
      final String user =
          await AppStorage().retrieveValue(AppStorage.USER_NAME) ??
              "UnknownUser";

      // 2. Format Timestamp: YYYYMMDD_HHMM
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

      //   final zipEncoder = ZipEncoder();
      //   final encodedZip = zipEncoder.encode(archive);
      //   final tempDir = await getTemporaryDirectory();
      //   final bundleFile = File(
      //       '${tempDir.path}/Export_${DateTime.now().millisecondsSinceEpoch}$bundleExtension');
      //   await bundleFile.writeAsBytes(encodedZip);

      //   debugPrint(
      //       "$logTag [EXPORT_SUCCESS] Bundled $addedCount assets into ${bundleFile.path}");
      //   return bundleFile;
      // } catch (e) {
      //   debugPrint("$logTag [EXPORT_CRASH] $e");
      //   return null;
      // }

      final zipEncoder = ZipEncoder();
      final encodedZip = zipEncoder.encode(archive);
      final tempDir = await getTemporaryDirectory();

      // 3. New Descriptive Filename: Export_uidev1_20260213_1305.axbundle
      final String fileName = "Export_${user}_$timestamp$bundleExtension";
      final bundleFile = File('${tempDir.path}/$fileName');

      await bundleFile.writeAsBytes(encodedZip);

      debugPrint(
          "$logTag [EXPORT_SUCCESS] Bundled $addedCount assets into ${bundleFile.path}");
      return bundleFile;
    } catch (e) {
      debugPrint("$logTag [EXPORT_CRASH] $e");
      return null;
    }
  }

  // ---------------- IMPORT LOGIC ----------------
  static Future<void> importBundle(File bundleFile) async {
    try {
      final bytes = await bundleFile.readAsBytes();
      final archive = ZipDecoder().decodeBytes(bytes);

      final appDocDir = await getApplicationDocumentsDirectory();
      // This is exactly /data/user/0/com.agile.ub_bottleapp/app_flutter
      final String currentAppFlutterPath = appDocDir.path;
      // This is /data/user/0/com.agile.ub_bottleapp
      final String packageRoot = appDocDir.parent.path;

      String? oldPathToReplace;

      // 1. Extract Assets to the PARENT (package root)
      for (final file in archive) {
        if (file.name.startsWith('assets/')) {
          final String fileName = basename(file.name);
          // Files are saved as /data/user/0/com.agile.ub_bottleapp/app_flutter_123.jpg
          final outFile = File(join(packageRoot, fileName));
          await outFile.create(recursive: true);
          await outFile.writeAsBytes(file.content as List<int>);
          debugPrint("$logTag [EXTRACT] Physical file: ${outFile.path}");
        }
      }

      // 2. Database Remapping
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
      debugPrint("$logTag [IMPORT_CRASH] $e");
      rethrow;
    }
  }
  // ---------------- HELPERS ----------------

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
}
