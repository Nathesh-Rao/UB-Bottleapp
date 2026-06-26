import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lottie/lottie.dart';
import 'package:ubbottleapp/ModelPages/LandingMenuPages/offline_form_pages/models/cached_save_progress_model.dart';

class CachedSaveDialog extends StatelessWidget {
  const CachedSaveDialog({super.key, required this.cachedSaveProgressModel});

  final CachedSaveProgressModel cachedSaveProgressModel;

  // Helper to check if everything is fully complete
  void _checkIfAllComplete() {
    final items = cachedSaveProgressModel.cachedSaveUpdateMap;
    if (items.isEmpty) return;

    bool allResolved = items.every((item) {
      final processedCount =
          item.successAxmRecIds.length + item.failedAxmRecIds.length;
      return processedCount >= item.payloadsCount && item.payloadsCount > 0;
    });

    if (allResolved && Get.isDialogOpen == true) {
      // Add a slight delay so the user can see the final green checks before it closes
      Future.delayed(const Duration(milliseconds: 800), () {
        if (Get.isDialogOpen == true) Get.back();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Listen to changes and auto-close when all are done
    ever(cachedSaveProgressModel.cachedSaveUpdateMap,
        (_) => _checkIfAllComplete());

    return PopScope(
      canPop: false,
      child: Dialog(
        backgroundColor: Colors.transparent,
        elevation: 0,
        insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        child: Container(
          width: double.infinity,
          constraints: const BoxConstraints(maxHeight: 550),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1E1E20) : Colors.white,
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(isDark ? 0.3 : 0.1),
                blurRadius: 20,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildHeader(context, isDark),
              _buildQueueList(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context, bool isDark) {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: isDark
                ? Colors.white.withOpacity(0.05)
                : Colors.black.withOpacity(0.05),
            width: 1,
          ),
        ),
      ),
      child: Row(
        children: [
          Container(
            height: 52,
            width: 52,
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFF2563EB).withOpacity(0.1),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Lottie.asset(
              'assets/animations/uploading.json',
              fit: BoxFit.contain,
              errorBuilder: (_, __, ___) => const Icon(
                CupertinoIcons.cloud_upload_fill,
                color: Color(0xFF2563EB),
                size: 28,
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Syncing Data',
                  style: GoogleFonts.poppins(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: isDark ? Colors.white : const Color(0xFF111827),
                    letterSpacing: -0.3,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Awaiting server confirmations...',
                  style: GoogleFonts.poppins(
                    fontSize: 13,
                    fontWeight: FontWeight.w400,
                    color: isDark ? Colors.white60 : const Color(0xFF6B7280),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQueueList() {
    return Flexible(
      child: Obx(() {
        final items = cachedSaveProgressModel.cachedSaveUpdateMap;

        if (items.isEmpty) {
          return Padding(
            padding: const EdgeInsets.all(40.0),
            child: Center(
              child: CupertinoActivityIndicator(radius: 14),
            ),
          );
        }

        return ListView.separated(
          padding: const EdgeInsets.all(20),
          shrinkWrap: true,
          itemCount: items.length,
          separatorBuilder: (_, __) => const SizedBox(height: 12),
          itemBuilder: (context, index) {
            return _QueueItemCard(item: items[index]);
          },
        );
      }),
    );
  }
}

class _QueueItemCard extends StatelessWidget {
  const _QueueItemCard({required this.item});

  final CachedSaveProgressItemModel item;

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;

    final int processedCount =
        item.successAxmRecIds.length + item.failedAxmRecIds.length;
    // If no items have been processed, we are waiting for the notification
    final bool isWaiting = processedCount == 0;
    final bool hasErrors = item.failedAxmRecIds.isNotEmpty;

    // Determine card styling based on state
    Color cardBgColor =
        isDark ? const Color(0xFF2A2A2D) : const Color(0xFFF9FAFB);
    Color borderColor = Colors.transparent;

    if (!isWaiting) {
      cardBgColor = hasErrors
          ? const Color(0xFFFEF2F2) // Light Red
          : const Color(0xFFF0FDF4); // Light Green
      borderColor =
          hasErrors ? const Color(0xFFFCA5A5) : const Color(0xFF86EFAC);

      if (isDark) {
        cardBgColor =
            hasErrors ? const Color(0xFF451A1A) : const Color(0xFF14331E);
        borderColor =
            hasErrors ? const Color(0xFF7F1D1D) : const Color(0xFF14532D);
      }
    }

    return AnimatedContainer(
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeOutCubic,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cardBgColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor, width: 1),
      ),
      child: Row(
        children: [
          _buildLeadingIcon(isWaiting, hasErrors),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Queue ID: ${item.axm_queueid}',
                  style: GoogleFonts.poppins(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                    color: isDark ? Colors.white : const Color(0xFF111827),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                _buildSubtitle(isWaiting, hasErrors, isDark),
              ],
            ),
          ),
          const SizedBox(width: 12),
          _buildStatusBadge(isWaiting, hasErrors, isDark),
        ],
      ),
    );
  }

  Widget _buildLeadingIcon(bool isWaiting, bool hasErrors) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 300),
      child: isWaiting
          ? Container(
              key: const ValueKey('waiting'),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFF3B82F6).withOpacity(0.15),
                shape: BoxShape.circle,
              ),
              child: const SizedBox(
                height: 18,
                width: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF3B82F6)),
                ),
              ),
            )
          : Container(
              key: const ValueKey('done'),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: hasErrors
                    ? const Color(0xFFEF4444)
                    : const Color(0xFF10B981),
                shape: BoxShape.circle,
              ),
              child: Icon(
                hasErrors ? Icons.warning_rounded : Icons.check_rounded,
                color: Colors.white,
                size: 18,
              ),
            ),
    );
  }

  Widget _buildSubtitle(bool isWaiting, bool hasErrors, bool isDark) {
    if (isWaiting) {
      return Text(
        'Waiting for response (${item.payloadsCount} payloads)',
        style: GoogleFonts.poppins(
          fontSize: 12,
          color: const Color(0xFF3B82F6),
          fontWeight: FontWeight.w500,
        ),
      );
    }

    if (hasErrors) {
      return Text(
        '${item.successAxmRecIds.length} Success • ${item.failedAxmRecIds.length} Failed',
        style: GoogleFonts.poppins(
          fontSize: 12,
          color: hasErrors ? const Color(0xFFDC2626) : const Color(0xFF059669),
          fontWeight: FontWeight.w500,
        ),
      );
    }

    return Text(
      'Successfully synced ${item.payloadsCount} records',
      style: GoogleFonts.poppins(
        fontSize: 12,
        color: isDark ? const Color(0xFF34D399) : const Color(0xFF059669),
        fontWeight: FontWeight.w500,
      ),
    );
  }

  Widget _buildStatusBadge(bool isWaiting, bool hasErrors, bool isDark) {
    if (isWaiting) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: isDark ? Colors.white10 : Colors.black.withOpacity(0.05),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          'PENDING',
          style: GoogleFonts.poppins(
            fontSize: 10,
            fontWeight: FontWeight.w700,
            color: isDark ? Colors.white54 : Colors.black54,
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: hasErrors
            ? const Color(0xFFEF4444).withOpacity(0.15)
            : const Color(0xFF10B981).withOpacity(0.15),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        hasErrors ? 'ISSUES' : 'DONE',
        style: GoogleFonts.poppins(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: hasErrors ? const Color(0xFFDC2626) : const Color(0xFF059669),
        ),
      ),
    );
  }
}
