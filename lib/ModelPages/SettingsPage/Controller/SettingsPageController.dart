import 'dart:developer';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:open_file/open_file.dart';
import 'package:otp_text_field/style.dart';
import 'package:ubbottleapp/Constants/AppStorage.dart';
import 'package:ubbottleapp/Constants/Const.dart';
import 'package:ubbottleapp/Constants/MyColors.dart';
import 'package:ubbottleapp/ModelPages/LandingMenuPages/offline_form_pages/db/offline_db_module.dart';
import 'package:ubbottleapp/ModelPages/LandingMenuPages/offline_form_pages/models/sync_progress_model.dart';
import 'package:ubbottleapp/ModelPages/LandingMenuPages/offline_form_pages/widgets/sync_progress_dialog.dart';
import 'package:ubbottleapp/Utils/LogServices/LogService.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:path_provider/path_provider.dart';

class SettingsPageController extends GetxController {
  var notificationOnOffValue = false.obs;
  var logOnOffValue = false.obs;
  AppStorage appStorage = AppStorage();

  SettingsPageController() {
    getNotifyStatusDetails();
    getLogStatusDetails();
  }
  getNotifyStatusDetails() async {
    notificationOnOffValue.value =
        await appStorage.retrieveValue(AppStorage.isShowNotifyEnabled) ?? false;
  }

  void getLogStatusDetails() async {
    logOnOffValue.value =
        await appStorage.retrieveValue(AppStorage.isLogEnabled) ?? false;
  }

  setNotifyValue(value) async {
    notificationOnOffValue.value = value;
    await appStorage.storeValue(AppStorage.isShowNotifyEnabled, value) ?? false;
  }

  setLogValue(value) async {
    logOnOffValue.value = value;
    await appStorage.storeValue(AppStorage.isLogEnabled, value) ?? false;
  }

  onChangeNotifyStatus() async {
    notificationOnOffValue.toggle();
    await setNotifyValue(notificationOnOffValue.value) ?? false;
  }

  void onChangeLogStatus() async {
    if (logOnOffValue.isFalse) {
      await Get.defaultDialog(
          barrierDismissible: false,
          title: "Confirm",
          middleText: "Do you want to delete the previous logs?",
          confirm: ElevatedButton(
              onPressed: () async {
                await LogService.clearLog();
                Get.back();
              },
              child: Text("Yes")),
          cancel: TextButton(
              onPressed: () {
                Get.back();
              },
              child: Text("No")));
    }
    logOnOffValue.toggle();

    await setLogValue(logOnOffValue.value);
  }

  Future<void> downloadFileSafely() async {
    // Source file (inside app)
    // final Directory appDir = await getApplicationDocumentsDirectory();
    File sourceFile = File(Const.LOG_FILE_PATH);
    try {
      if (!await sourceFile.exists()) {
        Get.snackbar("File not found", "File is not yet created or not found",
            colorText: Colors.white, backgroundColor: MyColors.maroon);

        throw Exception('File not found');
      }

      Uint8List fileBytes = await sourceFile.readAsBytes();

      final String? targetPath = await FilePicker.platform.saveFile(
        dialogTitle: 'Save file to Downloads',
        fileName:
            'AxpertMobileLog_${DateFormat('yyyyMMddHHmmss').format(DateTime.now())}.txt',
        bytes: fileBytes,
      );

      if (targetPath != null) {
        Get.snackbar(
            "File Saved", "You can share the file from your file manager",
            colorText: Colors.white, backgroundColor: MyColors.green);
      }
    } catch (e) {
      log(e.toString(), name: "DOWNLOAD LOGS");
    }
  }

  // await sourceFile.copy(targetFile.path).then((f) {
  //   Get.snackbar("File Saved", "You can find your saved file here ",
  //       colorText: Colors.white, backgroundColor: MyColors.green);
  // });

  showtraceDlg() async {
    // File sourceFile = File(path);

    await Get.dialog(
      Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        elevation: 0,
        backgroundColor: Colors.white,
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                "Export Trace",
                textAlign: TextAlign.center,
                style: GoogleFonts.poppins(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: Colors.black87,
                ),
              ),
              const SizedBox(height: 10),
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Text(
                  "You can downlod or open your trace file from here",
                  style: GoogleFonts.poppins(
                    fontSize: 14,
                    color: Colors.grey[600],
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: () {
                        Get.back();
                      },
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        foregroundColor: Colors.grey[700],
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: BorderSide(color: Colors.grey.shade300),
                        ),
                      ),
                      child: Text(
                        "Cancel",
                        style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () async {
                        Get.back();
                        // await downloadFileSafely();
                        await uploadTraceFile();
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: MyColors.AXMDark,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: Text(
                        "Upload",
                        style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () async {
                        Get.back();

                        await OpenFile.open(Const.LOG_FILE_PATH).then((_) {
                          Get.back();
                        });
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: MyColors.blue10,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: Text(
                        "Open Trace",
                        style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
      barrierDismissible: false,
    );
  }

  uploadTraceFile() async {
    var ok = await _confirm(
        title: "Upload Trace Log",
        message:
            "Would you like to upload your offline activity log? This helps the support team analyze and troubleshoot any issues.");

    if (!ok) return;

    final SyncProgressModel progress = SyncProgressModel();
    progress.init(total: 1, msg: "Preparing trace log...");

    Get.dialog(
      SyncProgressDialog(
          progressModel: progress,
          onComplete: downloadFileSafely,
          onCompleteTitle: "Download to device"),
      barrierDismissible: false,
    );

    await OfflineDbModule.uploadTraceFile(
      isInternetAvailable: true,
      progress: progress,
    );
    progress.complete();

    // await Future.delayed(const Duration(seconds: 1));
    // if (Get.isDialogOpen ?? false) Get.back();
  }

  Future<bool> _confirm({
    required String title,
    required String message,
    String subtitle = '',
    String okText = "Yes",
    String cancelText = "Cancel",
    IconData icon = Icons.help_outline_rounded,
    Color confirmColor = const Color(0xFF2563EB),
    TextAlign? messageTextAlign,
    Color? highLightColor,
    Color? subtitleColor,
  }) async {
    bool result = false;

    Widget _parseText(String text, TextStyle baseStyle, {TextAlign? align}) {
      if (!text.contains("**")) {
        return Text(text,
            textAlign: align ?? TextAlign.center, style: baseStyle);
      }

      final parts = text.split("**");
      return Text.rich(
        TextSpan(
          children: parts.map((part) {
            final isBold = parts.indexOf(part) % 2 != 0;
            return TextSpan(
              text: part,
              style: isBold
                  ? baseStyle.copyWith(
                      fontWeight: FontWeight.bold,
                      color: highLightColor ?? Colors.grey[600])
                  : baseStyle,
            );
          }).toList(),
        ),
        textAlign: align ?? TextAlign.center,
      );
    }

    await Get.dialog(
      Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        elevation: 0,
        backgroundColor: Colors.white,
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  color: confirmColor.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, size: 30, color: confirmColor),
              ),
              const SizedBox(height: 20),
              Text(
                title,
                textAlign: TextAlign.center,
                style: GoogleFonts.poppins(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: Colors.black87,
                ),
              ),
              const SizedBox(height: 10),
              if (subtitle.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _parseText(
                    subtitle,
                    GoogleFonts.poppins(
                      fontSize: 14,
                      color: subtitleColor ?? Colors.grey[600],
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              _parseText(
                message,
                align: messageTextAlign,
                GoogleFonts.poppins(
                  fontSize: 14,
                  color: Colors.grey[600],
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: () {
                        result = false;
                        Get.back();
                      },
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        foregroundColor: Colors.grey[700],
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: BorderSide(color: Colors.grey.shade300),
                        ),
                      ),
                      child: Text(
                        cancelText,
                        style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () {
                        result = true;
                        Get.back();
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: confirmColor,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: Text(
                        okText,
                        style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
      barrierDismissible: false,
    );

    return result;
  }
}
