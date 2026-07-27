import 'package:animate_do/animate_do.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:get/state_manager.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lottie/lottie.dart';
import 'package:ubbottleapp/Constants/MyColors.dart';
import 'package:ubbottleapp/ModelPages/LandingMenuPages/offline_form_pages/controller/offline_form_controller.dart';
import 'package:ubbottleapp/ModelPages/LandingMenuPages/offline_form_pages/models/cached_save_item_model.dart';

class CachedSaveDialogWidget extends GetView<OfflineFormController> {
  const CachedSaveDialogWidget({
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    controller.cachedSaveQueItems.clear();
    return PopScope(
      canPop: false,
      child: Dialog(
        backgroundColor: Colors.white,
        elevation: 0,
        insetPadding: const EdgeInsets.symmetric(horizontal: 24),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 15, 20, 5),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      "Uploading pending data",
                      style: GoogleFonts.inter(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: Colors.black87,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Divider(),
            _getQueueUploadWidget(),
            const SizedBox(height: 14),
            Obx(() => !controller.isCachedSaveActive.value
                ? Container(
                    margin: const EdgeInsets.fromLTRB(20, 5, 20, 18),
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton(
                      onPressed: () {
                        Get.back();
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xff212529),
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      child: Text(
                        "Close",
                        style: GoogleFonts.inter(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  )
                : SizedBox.shrink())
          ],
        ),
      ),
    );
  }

  Column _getQueueUploadWidget() {
    return Column(
      children: [
        Padding(
          padding: EdgeInsets.symmetric(horizontal: 20),
          child: Obx(() {
            final queueCount = controller.cachedSaveQueItems.length;

            final totalItems = controller.cachedSaveQueItems.fold<int>(
              0,
              (sum, item) => sum + item.value.totalItems,
            );

            final successItems = controller.cachedSaveQueItems.fold<int>(
              0,
              (sum, item) => sum + item.value.successItems,
            );
            final failedItems = controller.cachedSaveQueItems.fold<int>(
              0,
              (sum, item) => sum + item.value.failedItems,
            );
            return Row(
              spacing: 10,
              // runSpacing: 10,
              // alignment: WrapAlignment.end,
              children: [
                Expanded(
                  child: _summaryChip(
                    hideChip: queueCount == 0,
                    icon: Icons.layers_outlined,
                    label: "$queueCount",
                    color: const Color(0xFF6366F1),
                  ),
                ),
                Expanded(
                  child: _summaryChip(
                    hideChip: totalItems == 0,
                    icon: Icons.inventory_2_outlined,
                    label: "$totalItems",
                    color: const Color(0xFF0EA5E9),
                  ),
                ),
                Expanded(
                  child: _summaryChip(
                    hideChip: successItems == 0,
                    icon: Icons.check_circle_outline,
                    label: "$successItems",
                    color: Colors.green,
                  ),
                ),
                Expanded(
                  child: _summaryChip(
                    hideChip: failedItems == 0,
                    icon: Icons.cancel_outlined,
                    label: "$failedItems",
                    color: Colors.red,
                  ),
                ),
              ],
            );
          }),
        ),
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 18),
            Obx(() {
              if (controller.cachedSaveQueItems.isEmpty) {
                return SizedBox(
                  height: 200,
                  child: Center(
                    child: Lottie.asset(
                      "assets/lotties/loading.json",
                    ),
                  ),
                );
              }

              return ConstrainedBox(
                constraints: const BoxConstraints(
                  maxHeight: 380,
                ),
                child: ListView.separated(
                  // reverse: true,
                  padding: const EdgeInsets.fromLTRB(20, 5, 20, 18),
                  physics: BouncingScrollPhysics(),
                  itemCount: controller.cachedSaveQueItems.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (_, i) {
                    return _InfoTile2(
                      key: ValueKey(
                        controller.cachedSaveQueItems[i].value.qId,
                      ),
                      model: controller.cachedSaveQueItems[i],
                    );
                  },
                ),
              );
            }),
            Container(
              height: 80,
              padding: EdgeInsets.symmetric(horizontal: 20),
              decoration: BoxDecoration(
                  borderRadius: BorderRadius.only(
                      topLeft: Radius.circular(50),
                      topRight: Radius.circular(50)),
                  border: Border(
                      top: BorderSide(
                          color: MyColors.AXMGray.withValues(alpha: 0.1),
                          width: 3))),
              child: Center(
                child: Obx(
                  () => AnimatedSwitcher(
                    duration: const Duration(milliseconds: 300),
                    transitionBuilder: (child, animation) => FadeTransition(
                      opacity: animation,
                      child: child,
                    ),
                    child: Text(
                      controller.cachedSaveUpdateMessage.value,
                      key: ValueKey(controller.cachedSaveUpdateMessage.value),
                      textAlign: TextAlign.center,
                      maxLines: 4,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        )
      ],
    );
  }

  Widget _summaryChip({
    required IconData icon,
    required String label,
    required Color color,
    bool hideChip = false,
  }) {
    if (hideChip) return SizedBox();
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 12,
        vertical: 7,
      ),
      decoration: BoxDecoration(
        color: color.withOpacity(.10),
        borderRadius: BorderRadius.circular(100),
        border: Border.all(
          color: color.withOpacity(.18),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 15,
            color: color,
          ),
          // const SizedBox(width: 6),
          Expanded(
            child: Center(
              child: Text(
                label,
                style: GoogleFonts.inter(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: color,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoTile2 extends StatelessWidget {
  const _InfoTile2({
    super.key,
    required this.model,
  });

  final Rx<CachedSaveItemModel> model;

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      var item = model.value;
      return Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          // color: Colors.grey.shade50,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  /// Top row
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Image.asset(
                        getStatusImage(item.submissionStatus),
                        width: 15,
                        height: 15,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          item.qId,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.inter(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      _statusChip(),
                    ],
                  ),
                  const SizedBox(height: 3),

                  // Text(
                  //   item.smallStatusMessage,
                  //   maxLines: 1,
                  //   overflow: TextOverflow.ellipsis,
                  //   style: GoogleFonts.inter(
                  //     fontSize: 12,
                  //     color: Colors.grey.shade600,
                  //   ),
                  // ),
                  _miniChip(
                    Icons.info,
                    "${item.smallStatusMessage}",
                    Colors.grey,
                  ),

                  const SizedBox(height: 3),

                  Align(
                    alignment: Alignment.centerRight,
                    child: Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      alignment: WrapAlignment.end,
                      children: [
                        _miniChip(
                          Icons.check_circle,
                          "${item.successItems}",
                          Colors.green,
                        ),
                        _miniChip(
                          Icons.cancel,
                          "${item.failedItems}",
                          Colors.red,
                        ),
                        _miniChip(
                          item.fcmRecived
                              ? Icons.cloud_done
                              : Icons.cloud_upload_outlined,
                          item.fcmRecived ? "FCM" : "Waiting",
                          item.fcmRecived ? Colors.teal : Colors.orange,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    });
  }

  Widget _miniChip(
    IconData icon,
    String text,
    Color color,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 8,
        vertical: 4,
      ),
      decoration: BoxDecoration(
        color: color.withOpacity(.1),
        borderRadius: BorderRadius.circular(50),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 12,
            color: color,
          ),
          const SizedBox(width: 4),
          Text(
            text,
            style: GoogleFonts.inter(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _statusChip() {
    Color bg;
    Color fg;
    String text;
    var item = model.value;
    switch (item.submissionStatus) {
      case QueueSubmissionStatus.success:
        bg = Colors.green.withOpacity(.12);
        fg = Colors.green;
        text = "SUCCESS";
        break;

      case QueueSubmissionStatus.error:
        bg = Colors.red.withOpacity(.12);
        fg = Colors.red;
        text = "ERROR";
        break;

      case QueueSubmissionStatus.pending:
        bg = Colors.orange.withOpacity(.12);
        fg = Colors.orange;
        text = "PENDING";
        break;

      case QueueSubmissionStatus.partial:
        bg = Colors.blue.withOpacity(.12);
        fg = Colors.blue;
        text = "PARTIAL";
        break;

      case QueueSubmissionStatus.refetch:
        bg = Colors.purple.withOpacity(.12);
        fg = Colors.purple;
        text = "REFETCH";
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 10,
        vertical: 5,
      ),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        text,
        style: GoogleFonts.inter(
          fontSize: 8,
          fontWeight: FontWeight.w700,
          color: fg,
        ),
      ),
    );
  }

  String getStatusImage(QueueSubmissionStatus status) {
    switch (status) {
      case QueueSubmissionStatus.success:
        return 'assets/images/q-success2.png';
      case QueueSubmissionStatus.error:
        return 'assets/images/q-error2.png';
      case QueueSubmissionStatus.pending:
        return 'assets/images/q-pending2.png';
      case QueueSubmissionStatus.partial:
        return 'assets/images/q-partial2.png';
      case QueueSubmissionStatus.refetch:
        return 'assets/images/q-refetch2.png';
    }
  }
}


// class _InfoTile2 extends StatelessWidget {
//   const _InfoTile2({
//     required this.item,
//   });

//   final CachedSaveItemModel item;

//   @override
//   Widget build(BuildContext context) {
//     return Container(
//       margin: const EdgeInsets.only(bottom: 10),
//       padding: const EdgeInsets.symmetric(
//         horizontal: 12,
//         vertical: 10,
//       ),
//       decoration: BoxDecoration(
//         color: Colors.grey.shade50,
//         borderRadius: BorderRadius.circular(14),
//         border: Border.all(
//           color: Colors.grey.shade200,
//         ),
//       ),
//       child: Row(
//         crossAxisAlignment: CrossAxisAlignment.center,
//         children: [
//           /// Status Icon
//           SizedBox(
//             width: 36,
//             child: Center(
//               child: Image.asset(
//                 getStatusImage(item.submissionStatus),
//                 width: 28,
//                 height: 28,
//               ),
//             ),
//           ),

//           const SizedBox(width: 12),

//           /// Content
//           Expanded(
//             child: Column(
//               crossAxisAlignment: CrossAxisAlignment.start,
//               children: [
//                 /// Header
//                 Row(
//                   children: [
//                     Expanded(
//                       child: Text(
//                         "ID : ${item.qId}",
//                         overflow: TextOverflow.ellipsis,
//                         style: GoogleFonts.inter(
//                           fontSize: 13,
//                           fontWeight: FontWeight.w700,
//                         ),
//                       ),
//                     ),

//                     const SizedBox(width: 8),

//                     _statusChip(),
//                   ],
//                 ),

//                 const SizedBox(height: 6),

//                 /// Message + Chips
//                 Row(
//                   crossAxisAlignment: CrossAxisAlignment.start,
//                   children: [
//                     Expanded(
//                       child: Text(
//                         item.smallStatusMessage,
//                         style: GoogleFonts.inter(
//                           fontSize: 12,
//                           height: 1.3,
//                           color: Colors.grey.shade600,
//                         ),
//                       ),
//                     ),

//                     const SizedBox(width: 8),

//                     Flexible(
//                       child: Wrap(
//                         alignment: WrapAlignment.end,
//                         spacing: 5,
//                         runSpacing: 5,
//                         children: [
//                           _miniChip(
//                             Icons.check_circle_rounded,
//                             "${item.successItems}",
//                             Colors.green,
//                           ),
//                           _miniChip(
//                             Icons.cancel_rounded,
//                             "${item.failedItems}",
//                             Colors.red,
//                           ),
//                           _miniChip(
//                             item.fcmRecived
//                                 ? Icons.cloud_done_rounded
//                                 : Icons.cloud_upload_rounded,
//                             item.fcmRecived ? "FCM" : "Wait",
//                             item.fcmRecived
//                                 ? Colors.teal
//                                 : Colors.orange,
//                           ),
//                         ],
//                       ),
//                     ),
//                   ],
//                 ),
//               ],
//             ),
//           ),
//         ],
//       ),
//     );
//   }

//   Widget _miniChip(
//     IconData icon,
//     String text,
//     Color color,
//   ) {
//     return Container(
//       padding: const EdgeInsets.symmetric(
//         horizontal: 8,
//         vertical: 4,
//       ),
//       decoration: BoxDecoration(
//         color: color.withOpacity(.1),
//         borderRadius: BorderRadius.circular(100),
//       ),
//       child: Row(
//         mainAxisSize: MainAxisSize.min,
//         children: [
//           Icon(
//             icon,
//             size: 12,
//             color: color,
//           ),
//           const SizedBox(width: 4),
//           Text(
//             text,
//             style: GoogleFonts.inter(
//               fontSize: 10,
//               fontWeight: FontWeight.w600,
//               color: color,
//             ),
//           ),
//         ],
//       ),
//     );
//   }

//   Widget _statusChip() {
//     late final Color bg;
//     late final Color fg;
//     late final String text;

//     switch (item.submissionStatus) {
//       case QueueSubmissionStatus.success:
//         bg = Colors.green.withOpacity(.1);
//         fg = Colors.green;
//         text = "SUCCESS";
//         break;

//       case QueueSubmissionStatus.error:
//         bg = Colors.red.withOpacity(.1);
//         fg = Colors.red;
//         text = "ERROR";
//         break;

//       case QueueSubmissionStatus.pending:
//         bg = Colors.orange.withOpacity(.1);
//         fg = Colors.orange;
//         text = "PENDING";
//         break;

//       case QueueSubmissionStatus.partial:
//         bg = Colors.blue.withOpacity(.1);
//         fg = Colors.blue;
//         text = "PARTIAL";
//         break;

//       case QueueSubmissionStatus.refetch:
//         bg = Colors.purple.withOpacity(.1);
//         fg = Colors.purple;
//         text = "REFETCH";
//         break;
//     }

//     return Container(
//       padding: const EdgeInsets.symmetric(
//         horizontal: 9,
//         vertical: 4,
//       ),
//       decoration: BoxDecoration(
//         color: bg,
//         borderRadius: BorderRadius.circular(100),
//       ),
//       child: Text(
//         text,
//         style: GoogleFonts.inter(
//           fontSize: 10,
//           fontWeight: FontWeight.w700,
//           color: fg,
//         ),
//       ),
//     );
//   }

//   String getStatusImage(QueueSubmissionStatus status) {
//     switch (status) {
//       case QueueSubmissionStatus.success:
//         return 'assets/images/q-success2.png';
//       case QueueSubmissionStatus.error:
//         return 'assets/images/q-error2.png';
//       case QueueSubmissionStatus.pending:
//         return 'assets/images/q-pending2.png';
//       case QueueSubmissionStatus.partial:
//         return 'assets/images/q-partial2.png';
//       case QueueSubmissionStatus.refetch:
//         return 'assets/images/q-refetch2.png';
//     }
//   }
// }