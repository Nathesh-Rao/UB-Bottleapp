import 'dart:async';
import 'dart:developer';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import 'package:get/route_manager.dart';
import 'package:ubbottleapp/Constants/AppStorage.dart';
import 'package:ubbottleapp/Constants/Enums.dart';
import 'package:ubbottleapp/Constants/Const.dart';
import 'package:intl/intl.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:ubbottleapp/Constants/GlobalVariableController.dart';

class LogService {
  static GlobalVariableController gvcontroller = Get.find();

  static File? localFile;

  static Future<String> _localPath() async {
    var directory = await getExternalStorageDirectory();
    directory ??= await getApplicationDocumentsDirectory();
    return directory.path;
  }

  static Future<File> _localFile() async {
    final path = await _localPath();
    debugPrint(" log_path : $path");
    var fullPath = '$path/AxpertLog.txt';
    debugPrint(" log_fullPath : $fullPath");
    Const.LOG_FILE_PATH = fullPath;
    // gvcontroller.LOG_PATH.value = fullPath;
    debugPrint(" const_log_fullPath : ${Const.LOG_FILE_PATH}");
    return File(fullPath);
  }

  static getVersion() async {
    PackageInfo packageInfo = await PackageInfo.fromPlatform();
    var version = packageInfo.version;
    Const.APP_VERSION = version;
  }

  static initLogs() async {
    localFile = await _localFile();
    try {
      var isTraceOn =
          await AppStorage().retrieveValue(AppStorage.isLogEnabled) ?? false;
      Const.isLogEnabled = isTraceOn;

      var isExists = await localFile!.exists();
      if (!isExists) {
        if (Const.APP_VERSION == "") {
          await getVersion();
        }
        await localFile?.writeAsString('Axpert Android Log File\n',
            mode: FileMode.write, flush: true);
        await localFile?.writeAsString('App Version: ${Const.APP_VERSION}\n',
            mode: FileMode.append, flush: true);
        await localFile?.writeAsString(
            'File Creation Date: ${DateFormat("dd-MMM-yyyy HH:mm:ss").format(DateTime.now())}\n',
            mode: FileMode.append,
            flush: true);
        await localFile?.writeAsString(
            '------------------------------------------------------------------- \n\n',
            mode: FileMode.append,
            flush: true);
      }
    } catch (e) {}
  }

  static writeOnConsole({String message = ""}) async {
    return;

    _logWithColor("console-log: $message", skyBlue);
  }

  static writeLog({String message = ""}) async {
    _logWithColor(message, yellow);
    if (Const.isLogEnabled) {
      // final file = await _localFile();
      var formatedDateTime =
          DateFormat("dd-MMM-yyyy HH:mm:ss:SSS").format(DateTime.now());
      try {
        await localFile?.writeAsString('$formatedDateTime: $message\n',
            mode: FileMode.append);
      } catch (e) {}
    }
  }

  static const String yellow = '\u001B[33m';
  static const String skyBlue = '\u001B[38;5;39m';

  static clearLog() async {
    try {
      var isExists = await localFile?.exists() ?? false;
      if (isExists) {
        localFile?.delete();
        initLogs();
      }
    } catch (e) {}
  }

  // Experimental------------->
  static writeLogAdv({
    LogType logType = LogType.REGULAR,
    String message = '',
  }) async {
    if (Const.isLogEnabled) {
      var formatedDateTime =
          DateFormat("dd-MMM-yyyy HH:mm:ss:SSS").format(DateTime.now());
      try {
        await localFile?.writeAsString('$formatedDateTime: $log\n',
            mode: FileMode.append);
      } catch (e) {}
    }

    _logWithColor(message, yellow);
  }

  static void _logWithColor(String message, String colorCode) {
    print('$colorCode$message\u001B[0m');
  }

  String formatApiLog({
    required String method,
    required String url,
    required String apiName,
    required Map<String, dynamic> requestBody,
    required int statusCode,
    required Map<String, dynamic> responseBody,
  }) {
    String line = '═' * 70;
    String boxLine = '─' * 70;

    return '''
╔$line╗
║${'API CALL'.padLeft(36).padRight(70)}║
╟$boxLine╢
║ [${method.toUpperCase()}] URL: $url
║ API Name: $apiName
║ Request Body:
║ ${requestBody.toString().split('\n').join('\n║ ')}
║ Status Code: $statusCode
║ Response:
║ ${responseBody.toString().split('\n').join('\n║ ')}
╚$line╝
  ''';
  }
}
