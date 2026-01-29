import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lottie/lottie.dart';
import 'package:ubbottleapp/ModelPages/LandingMenuPages/offline_form_pages/models/sync_progress_model.dart';

class SyncProgressDialog extends StatelessWidget {
  final SyncProgressModel progressModel;

  const SyncProgressDialog({Key? key, required this.progressModel})
      : super(key: key);

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        elevation: 0,
        backgroundColor: Colors.white,
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildIcon(),
              const SizedBox(height: 20),
              _buildTitle(),
              const SizedBox(height: 8),
              _buildMessage(),
              const SizedBox(height: 20),
              _buildProgress(),
              const SizedBox(height: 16),
              _buildStats(),
              _buildBottomAction(),
            ],
          ),
        ),
      ),
    );
  }

  // ---------------- ICON ----------------

  Widget _buildIcon() {
    return Obx(() {
      final done = progressModel.isCompleted.value;

      return AnimatedSwitcher(
        duration: const Duration(milliseconds: 300),
        child: Container(
          key: ValueKey(done),
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            color: done
                ? const Color(0xFFDCFCE7)
                : const Color(0xFF2563EB).withValues(alpha: 0.1),
            shape: BoxShape.circle,
          ),
          child: done
              ? const Icon(Icons.check_rounded,
                  size: 28, color: Color(0xFF16A34A))
              : Lottie.asset("assets/lotties/upload.json", repeat: true),
        ),
      );
    });
  }

  // ---------------- TITLE ----------------

  Widget _buildTitle() {
    return Obx(() => Text(
          progressModel.title.value,
          textAlign: TextAlign.center,
          style: GoogleFonts.poppins(
            fontSize: 17,
            fontWeight: FontWeight.w600,
            color: Colors.black87,
          ),
        ));
  }

  // ---------------- MESSAGE ----------------

  Widget _buildMessage() {
    return SizedBox(
      height: 36,
      child: Obx(() {
        final text = progressModel.message.value;
        return AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          child: Text(
            text,
            key: ValueKey(text),
            textAlign: TextAlign.center,
            style: GoogleFonts.poppins(
              fontSize: 13,
              color: Colors.grey[600],
              height: 1.4,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        );
      }),
    );
  }

  // ---------------- PROGRESS ----------------

  Widget _buildProgress() {
    return Obx(() {
      return Column(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: LinearProgressIndicator(
              value: progressModel.progressValue,
              minHeight: 5,
              backgroundColor: Colors.grey.shade200,
              valueColor: const AlwaysStoppedAnimation(Color(0xFF2563EB)),
            ),
          ),
          const SizedBox(height: 6),
          Align(
            alignment: Alignment.centerRight,
            child: Text(
              "${progressModel.processedItems.value} / ${progressModel.totalItems.value}",
              style: GoogleFonts.poppins(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: Colors.grey.shade500,
              ),
            ),
          ),
        ],
      );
    });
  }

  // ---------------- STATS ----------------

  Widget _buildStats() {
    return Obx(
      () => (progressModel.successCount != 0 || progressModel.failureCount != 0)
          ? Container(
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 14),
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _statItem(progressModel.successCount, "Success",
                      const Color(0xFF16A34A)),
                  _statItem(progressModel.failureCount, "Failed",
                      const Color(0xFFDC2626)),
                ],
              ),
            )
          : SizedBox.shrink(),
    );
  }

  Widget _statItem(RxInt count, String label, Color color) {
    return Obx(() => Row(
          children: [
            Text(
              count.value.toString(),
              style: GoogleFonts.poppins(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: GoogleFonts.poppins(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: Colors.grey[600],
              ),
            ),
          ],
        ));
  }

  // ---------------- BUTTON ----------------

  Widget _buildBottomAction() {
    return Obx(() {
      if (!progressModel.isCompleted.value) return const SizedBox.shrink();

      return Padding(
        padding: const EdgeInsets.only(top: 20),
        child: SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: Get.back,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF2563EB),
              elevation: 0,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: Text(
              "Close",
              style: GoogleFonts.poppins(
                fontWeight: FontWeight.w600,
                fontSize: 14,
              ),
            ),
          ),
        ),
      );
    });
  }
}
