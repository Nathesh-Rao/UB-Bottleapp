import 'package:animate_do/animate_do.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lottie/lottie.dart';
import 'package:ubbottleapp/ModelPages/LandingMenuPages/MenuDashboardPage/Controllers/MenuDashboaardController.dart';
import 'package:ubbottleapp/ModelPages/LandingMenuPages/offline_form_pages/controller/offline_form_controller.dart';
import 'package:ubbottleapp/ModelPages/LandingMenuPages/offline_form_pages/db/offline_db_module.dart';

enum CachedRefreshResult {
  cancelled,
  refreshed,
  sessionInvalid,
}

class CachedRefreshDialogWidget extends GetView<OfflineFormController> {
  const CachedRefreshDialogWidget({
    super.key,
    required this.refreshQueueRows,
  });

  final List<Map<String, dynamic>> refreshQueueRows;

  @override
  Widget build(BuildContext context) {
    // WidgetsBinding.instance.addPostFrameCallback((_) => onSpawn);
    return Dialog(
      backgroundColor: Colors.white,
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          /// Header
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 15, 16, 10),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    "Refresh Pending Queues",
                    style: GoogleFonts.inter(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: Colors.black87,
                    ),
                  ),
                ),
                InkWell(
                  borderRadius: BorderRadius.circular(30),
                  onTap: () {
                    Get.back(
                      result: CachedRefreshResult.cancelled,
                    );
                  },
                  child: const Padding(
                    padding: EdgeInsets.all(4),
                    child: Icon(
                      Icons.close_rounded,
                      size: 20,
                    ),
                  ),
                )
              ],
            ),
          ),

          Divider(height: 1),

          Padding(
            padding: const EdgeInsets.fromLTRB(22, 22, 22, 18),
            child: Column(
              children: [
                ConstrainedBox(
                  constraints: const BoxConstraints(
                    maxHeight: 250,
                  ),
                  child: ListView.separated(
                    physics: BouncingScrollPhysics(),
                    shrinkWrap: true,
                    itemCount: refreshQueueRows.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final queueId = refreshQueueRows[index]["queue_id"];

                      return Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 12,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: const Color(0xffE5E7EB),
                          ),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                color: const Color(0xffEEF5FF),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Icon(
                                Icons.query_builder,
                                size: 20,
                                color: Color(0xff2563EB),
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    "Queue ID",
                                    style: GoogleFonts.inter(
                                      fontSize: 11,
                                      color: Colors.grey.shade600,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    queueId.toString(),
                                    style: GoogleFonts.inter(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w700,
                                      color: Colors.black87,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 5,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xffEEF5FF),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(
                                "${index + 1}",
                                style: GoogleFonts.inter(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: const Color(0xff2563EB),
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 20),
                Obx(
                  () => FlipInX(
                    key: ValueKey(controller.isPendingQuesRefreshing.value),
                    child: controller.isPendingQuesRefreshing.value
                        ? _infoBox(
                            icon: Icons.security,
                            message: "We are refreshing your pending queues\n"
                                "Please hold on",
                            color: Color(0xffF59E0B))
                        : _infoBox(
                            icon: Icons.security,
                            message:
                                "We found ${refreshQueueRows.length} pending queues from previous push, "
                                "Please continue to refresh the status",
                            color: Color(0xffF59E0B)),
                  ),
                ),
                // const SizedBox(height: 22),

                Obx(() => FlipInX(
                      key: ValueKey(controller.isPendingQuesRefreshing.value),
                      child: controller.isPendingQuesRefreshing.value
                          ? SizedBox(
                              height: 48,
                              child: Center(
                                  child: LinearProgressIndicator(
                                borderRadius: BorderRadius.circular(100),
                                color: Color(0xff212529),
                              )),
                            )
                          : Container(
                              margin: EdgeInsets.only(top: 22),
                              width: double.infinity,
                              height: 48,
                              child: ElevatedButton.icon(
                                onPressed: () async {
                                  controller.isPendingQuesRefreshing.value =
                                      true;

                                  try {
                                    await OfflineDbModule
                                        .resolvePendingCachedSaveQueueBatches(
                                      controller: controller,
                                    );

                                    Get.back(
                                      result: CachedRefreshResult.refreshed,
                                    );
                                  } catch (_) {
                                  } finally {
                                    controller.isPendingQuesRefreshing.value =
                                        false;

                                    Get.back(
                                      result: CachedRefreshResult.refreshed,
                                    );
                                  }
                                },
                                icon: const Icon(
                                  Icons.sync_rounded,
                                  size: 18,
                                ),
                                label: Text(
                                  "Refresh and Continue",
                                  style: GoogleFonts.inter(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xff212529),
                                  foregroundColor: Colors.white,
                                  elevation: 0,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                ),
                              ),
                            ),
                    )),
                // const SizedBox(height: 10),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeaderSection() {
    return Column(
      children: [
        Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            color: const Color(0xffEEF5FF),
            borderRadius: BorderRadius.circular(16),
          ),
          child: const Icon(
            Icons.sync_rounded,
            size: 28,
            color: Color(0xff2563EB),
          ),
        ),
        const SizedBox(height: 18),
        Text(
          "Refresh Pending Queues?",
          textAlign: TextAlign.center,
          style: GoogleFonts.inter(
            fontSize: 21,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          "This will refresh all pending queues from the server.\n"
          "Your offline data will remain safe.",
          textAlign: TextAlign.center,
          style: GoogleFonts.inter(
            fontSize: 13,
            height: 1.55,
            color: Colors.grey.shade600,
          ),
        ),
      ],
    );
  }

  Widget _infoBox(
      {required IconData icon, required String message, required Color color}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: 14,
        vertical: 12,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: color.withValues(alpha: 0.5),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            icon,
            color: color,
            size: 18,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: GoogleFonts.poppins(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: Colors.grey.shade800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
