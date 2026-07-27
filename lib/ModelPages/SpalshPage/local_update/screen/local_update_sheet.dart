// lib/Screens/update_bottom_sheet.dart

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:ubbottleapp/ModelPages/SpalshPage/local_update/controller/local_update_controller.dart';
import 'package:ubbottleapp/ModelPages/SpalshPage/local_update/model/app_version_info_model.dart';
import 'package:ubbottleapp/ModelPages/SpalshPage/upgrade_page.dart';

class LocalUpdateBottomSheet extends StatelessWidget {
  final AppVersionInfo versionInfo;

  const LocalUpdateBottomSheet({
    super.key,
    required this.versionInfo,
  });

  static Future<void> show(BuildContext context, AppVersionInfo versionInfo) {
    return showModalBottomSheet(
      context: context,
      isDismissible: !versionInfo.forceUpdate,
      enableDrag: !versionInfo.forceUpdate,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => LocalUpdateBottomSheet(versionInfo: versionInfo),
    );
  }

  @override
  Widget build(BuildContext context) {
    final controller = Get.put(LocalUpdateController(versionInfo));

    return PopScope(
      canPop: !versionInfo.forceUpdate,
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: EdgeInsets.only(
              left: 30,
              right: 30,
              top: 16,
              bottom: MediaQuery.of(context).viewInsets.bottom + 24,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Drag handle — cosmetic when non-dismissible, but keeps
                // the sheet reading consistently as a sheet either way.
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 20),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: .15),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),

                Text(
                  "New Update Available!",
                  style: GoogleFonts.poppins(
                    color: Colors.deepPurple,
                    fontSize: 24,
                    fontWeight: FontWeight.w600,
                    height: 1.2,
                  ),
                ),

                const SizedBox(height: 12),

                Text(
                  "Version ${versionInfo.versionPart}+${versionInfo.buildPart} is ready to download.\n"
                  "Update now to enjoy the latest improvements,\n"
                  "bug fixes and enhanced performance.",
                  style: GoogleFonts.poppins(
                    color: Colors.black.withValues(alpha: .85),
                    fontSize: 15,
                    height: 1.45,
                    fontWeight: FontWeight.w500,
                  ),
                ),

                const SizedBox(height: 28),

                Obx(() {
                  switch (controller.state.value) {
                    case UpdateDownloadState.idle:
                      return _PrimaryButton(
                        text: "Download Update",
                        icon: Icons.download,
                        onPressed: controller.startDownload,
                      );

                    case UpdateDownloadState.downloading:
                      return Column(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(30),
                            child: LinearProgressIndicator(
                              value: controller.progress.value,
                              minHeight: 10,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            "${(controller.progress.value * 100).toStringAsFixed(0)}%",
                            style: GoogleFonts.poppins(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      );

                    case UpdateDownloadState.downloaded:
                      return _PrimaryButton(
                        text: "Install Update",
                        icon: Icons.install_mobile,
                        onPressed: controller.installUpdate,
                      );

                    case UpdateDownloadState.installTriggered:
                      return _PrimaryButton(
                        text: "Restart App",
                        icon: Icons.restart_alt,
                        onPressed: controller.restartApp,
                      );

                    case UpdateDownloadState.error:
                      return Column(
                        children: [
                          Text(
                            'SOMETHING WENT WRONG\nPLEASE CONNECT TO THE ADMIN',
                            style: GoogleFonts.poppins(
                              color: Colors.red,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 16),
                          _PrimaryButton(
                            text: "Retry Download",
                            icon: Icons.refresh,
                            onPressed: controller.startDownload,
                          ),
                        ],
                      );
                  }
                }),

                if (!versionInfo.forceUpdate) ...[
                  const SizedBox(height: 18),
                  Center(
                    child: TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: Text(
                        "Skip for now",
                        style: GoogleFonts.poppins(
                          color: Colors.deepPurple,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PrimaryButton extends StatelessWidget {
  final String text;
  final IconData icon;
  final VoidCallback onPressed;

  const _PrimaryButton({
    required this.text,
    required this.icon,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 60,
      child: ElevatedButton.icon(
        onPressed: onPressed,
        icon: Icon(icon),
        label: Text(
          text,
          style: GoogleFonts.poppins(
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.deepPurple.withValues(alpha: .18),
          foregroundColor: Colors.deepPurple,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
    );
  }
}
