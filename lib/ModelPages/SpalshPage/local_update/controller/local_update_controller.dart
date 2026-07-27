// lib/Controllers/update_controller.dart
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:get/get.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:open_file/open_file.dart';
import 'package:restart_app/restart_app.dart';
import 'package:ubbottleapp/ModelPages/SpalshPage/local_update/model/app_version_info_model.dart';
import 'package:ubbottleapp/Utils/LogServices/LogService.dart';

enum UpdateDownloadState {
  idle,
  downloading,
  downloaded,
  installTriggered,
  error
}

class LocalUpdateController extends GetxController {
  final AppVersionInfo versionInfo;
  LocalUpdateController(this.versionInfo);

  final Rx<UpdateDownloadState> state = UpdateDownloadState.idle.obs;
  final RxDouble progress = 0.0.obs; // 0.0 - 1.0
  final RxString errorMessage = ''.obs;

  String? _downloadedFilePath;
  final Dio _dio = Dio();

  Future<void> startDownload() async {
    const tag = "[UPDATE_DOWNLOAD]";
    try {
      // Android 13+ generally doesn't need WRITE_EXTERNAL_STORAGE for
      // app-scoped dirs, but request it defensively for older OS versions.
      if (Platform.isAndroid) {
        final status = await Permission.storage.request();
        LogService.writeLog(message: "$tag storage permission status=$status");
      }

      state.value = UpdateDownloadState.downloading;
      progress.value = 0.0;
      errorMessage.value = '';

      final Directory dir = Platform.isAndroid
          ? (await getExternalStorageDirectory() ??
              await getTemporaryDirectory())
          : await getTemporaryDirectory();

      final String savePath =
          '${dir.path}/app_update_${versionInfo.buildPart}.apk';

      LogService.writeLog(
        message:
            "$tag Starting download url=${versionInfo.apkUrl} -> $savePath",
      );

      await _dio.download(
        versionInfo.apkUrl,
        savePath,
        onReceiveProgress: (received, total) {
          if (total > 0) {
            progress.value = received / total;
          }
        },
      );

      _downloadedFilePath = savePath;
      state.value = UpdateDownloadState.downloaded;
      LogService.writeLog(message: "$tag Download complete: $savePath");
    } catch (e) {
      LogService.writeLog(message: "$tag EXCEPTION: $e");
      errorMessage.value = "Download failed: $e";
      state.value = UpdateDownloadState.error;
    }
  }

  Future<void> installUpdate() async {
    const tag = "[UPDATE_INSTALL]";
    if (_downloadedFilePath == null) return;

    try {
      if (Platform.isAndroid) {
        // Android 8+ requires this permission to be granted via Settings
        // for "install from unknown sources" to succeed silently.
        final status = await Permission.requestInstallPackages.status;
        if (!status.isGranted) {
          await Permission.requestInstallPackages.request();
        }
      }

      final result = await OpenFile.open(_downloadedFilePath!);
      LogService.writeLog(
        message:
            "$tag OpenFile result: type=${result.type} message=${result.message}",
      );

      state.value = UpdateDownloadState.installTriggered;
    } catch (e) {
      LogService.writeLog(message: "$tag EXCEPTION: $e");
      errorMessage.value = "Could not open installer: $e";
    }
  }

  Future<void> restartApp() async {
    LogService.writeLog(message: "[UPDATE_RESTART] Restarting app.");
    await Restart.restartApp();
  }
}
