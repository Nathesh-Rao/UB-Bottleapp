// import 'package:flutter/material.dart';
// import 'package:get/get.dart';
// import 'package:google_fonts/google_fonts.dart';
// import 'package:intl/intl.dart';
// import 'package:ubbottleapp/ModelPages/LandingMenuPages/offline_form_pages/db/offline_db_constants.dart';
// import 'package:ubbottleapp/ModelPages/LandingMenuPages/offline_form_pages/db/offline_db_module.dart';

// class AuditColors {
//   static const primary = Color(0xFF2563EB);
//   static const success = Color(0xFF16A34A);
//   static const error = Color(0xFFDC2626);

//   static const blueSoft = Color(0xFFEFF6FF);
//   static const greenSoft = Color(0xFFECFDF5);
//   static const redSoft = Color(0xFFFEF2F2);

//   static const textPrimary = Color(0xFF111827);
//   static const textSecondary = Color(0xFF6B7280);

//   static const border = Color(0xFFE5E7EB);
//   static const surface = Color(0xFFF8FAFC);
// }

// class AuditLogPage extends StatefulWidget {
//   const AuditLogPage({super.key});

//   @override
//   State<AuditLogPage> createState() => _AuditLogPageState();
// }

// class _AuditLogPageState extends State<AuditLogPage> {
//   List<Map<String, dynamic>> allLogs = [];
//   List<Map<String, dynamic>> filteredLogs = [];
//   bool isLoading = true;

//   String selectedFilter = "All";
//   String? selectedAction;

//   @override
//   void initState() {
//     super.initState();
//     _loadLogs();
//   }

//   Future<void> _loadLogs() async {
//     setState(() => isLoading = true);
//     final data = await OfflineDbModule.getAuditLogs();
//     setState(() {
//       allLogs = data;
//       _applyFilters();
//       isLoading = false;
//     });
//   }

//   void _applyFilters() {
//     filteredLogs = allLogs.where((log) {
//       bool isError = log[OfflineDBConstants.COL_IS_ERROR] == 1;

//       bool matchesStatus = true;
//       if (selectedFilter == "Success") matchesStatus = !isError;
//       if (selectedFilter == "Error") matchesStatus = isError;

//       bool matchesAction = selectedAction == null ||
//           log[OfflineDBConstants.COL_ACTION] == selectedAction;

//       return matchesStatus && matchesAction;
//     }).toList();

//     setState(() {});
//   }

//   @override
//   Widget build(BuildContext context) {
//     return Scaffold(
//       backgroundColor: Colors.white,
//       appBar: _buildAppBar(),
//       body: Column(
//         children: [
//           _buildFilterBar(),
//           Expanded(
//             child: isLoading
//                 ? const Center(child: CircularProgressIndicator())
//                 : filteredLogs.isEmpty
//                     ? _buildEmptyState()
//                     : ListView.builder(
//                         padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
//                         itemCount: filteredLogs.length,
//                         itemBuilder: (_, i) => _buildLogTile(filteredLogs[i]),
//                       ),
//           ),
//         ],
//       ),
//     );
//   }

//   PreferredSizeWidget _buildAppBar() {
//     return AppBar(
//       elevation: 0,
//       backgroundColor: Colors.white,
//       surfaceTintColor: Colors.transparent,
//       leading: IconButton(
//         icon: const Icon(Icons.arrow_back_ios_new_rounded,
//             color: AuditColors.textPrimary, size: 20),
//         onPressed: () => Get.back(),
//       ),
//       title: Text(
//         "Activity Logs",
//         style: GoogleFonts.poppins(
//           fontWeight: FontWeight.w600,
//           fontSize: 18,
//           color: AuditColors.textPrimary,
//         ),
//       ),
//       actions: [
//         Padding(
//           padding: const EdgeInsets.only(right: 12),
//           child: IconButton(
//             style: IconButton.styleFrom(
//               backgroundColor: AuditColors.redSoft,
//               side: const BorderSide(color: AuditColors.error, width: .6),
//             ),
//             onPressed: _confirmClear,
//             icon: const Icon(Icons.delete_outline_rounded,
//                 size: 20, color: AuditColors.error),
//           ),
//         )
//       ],
//     );
//   }

//   Widget _buildFilterBar() {
//     List<String> actions = allLogs
//         .map((e) => e[OfflineDBConstants.COL_ACTION].toString())
//         .toSet()
//         .toList();

//     return Container(
//       margin: const EdgeInsets.fromLTRB(16, 8, 16, 12),
//       padding: const EdgeInsets.all(12),
//       decoration: BoxDecoration(
//         gradient: const LinearGradient(
//           colors: [Color(0xFFF1F5F9), Color(0xFFE2E8F0)],
//           begin: Alignment.topLeft,
//           end: Alignment.bottomRight,
//         ),
//         borderRadius: BorderRadius.circular(16),
//         border: Border.all(color: AuditColors.border),
//       ),
//       child: Row(
//         children: [
//           _filterChip("All"),
//           const SizedBox(width: 8),
//           _filterChip("Success"),
//           const SizedBox(width: 8),
//           _filterChip("Error"),
//           const Spacer(),
//           _actionDropdown(actions),
//         ],
//       ),
//     );
//   }

//   Widget _filterChip(String label) {
//     bool selected = selectedFilter == label;

//     Color bg;
//     Color border;
//     Color text;

//     if (label == "Success" && selected) {
//       bg = AuditColors.greenSoft;
//       border = AuditColors.success;
//       text = AuditColors.success;
//     } else if (label == "Error" && selected) {
//       bg = AuditColors.redSoft;
//       border = AuditColors.error;
//       text = AuditColors.error;
//     } else if (selected) {
//       bg = AuditColors.blueSoft;
//       border = AuditColors.primary;
//       text = AuditColors.primary;
//     } else {
//       bg = Colors.white;
//       border = AuditColors.border;
//       text = AuditColors.textSecondary;
//     }

//     return InkWell(
//       borderRadius: BorderRadius.circular(20),
//       onTap: () {
//         setState(() => selectedFilter = label);
//         _applyFilters();
//       },
//       child: Container(
//         padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
//         decoration: BoxDecoration(
//           color: bg,
//           borderRadius: BorderRadius.circular(20),
//           border: Border.all(color: border),
//         ),
//         child: Text(
//           label,
//           style: GoogleFonts.poppins(
//             fontSize: 12,
//             fontWeight: FontWeight.w600,
//             color: text,
//           ),
//         ),
//       ),
//     );
//   }

//   Widget _actionDropdown(List<String> actions) {
//     return Container(
//       height: 34,
//       padding: const EdgeInsets.symmetric(horizontal: 10),
//       decoration: BoxDecoration(
//         color: Colors.white,
//         borderRadius: BorderRadius.circular(10),
//         border: Border.all(color: AuditColors.border),
//       ),
//       child: DropdownButton<String>(
//         value: selectedAction,
//         hint: Text("Action",
//             style: GoogleFonts.poppins(
//                 fontSize: 12, color: AuditColors.textSecondary)),
//         underline: const SizedBox(),
//         icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 18),
//         dropdownColor: Colors.white,
//         items: [
//           const DropdownMenuItem(
//               value: null,
//               child:
//                   Text("All", style: TextStyle(fontWeight: FontWeight.w500))),
//           ...actions.map((a) => DropdownMenuItem(
//                 value: a,
//                 child: Text(a,
//                     style: const TextStyle(fontWeight: FontWeight.w500)),
//               )),
//         ],
//         onChanged: (v) {
//           setState(() => selectedAction = v);
//           _applyFilters();
//         },
//         style:
//             GoogleFonts.poppins(fontSize: 12, color: AuditColors.textPrimary),
//       ),
//     );
//   }

//   Widget _buildLogTile(Map<String, dynamic> log) {
//     bool isError = log[OfflineDBConstants.COL_IS_ERROR] == 1;
//     String dateStr = _formatDate(log[OfflineDBConstants.COL_CREATED_AT]);

//     Color statusColor = isError ? AuditColors.error : AuditColors.success;
//     Color tileSoft = isError ? AuditColors.redSoft : AuditColors.greenSoft;

//     return Container(
//       margin: const EdgeInsets.only(bottom: 10),
//       padding: const EdgeInsets.all(14),
//       decoration: BoxDecoration(
//         color: Colors.white,
//         borderRadius: BorderRadius.circular(14),
//         border: Border.all(color: AuditColors.border),
//         boxShadow: [
//           BoxShadow(
//             color: Colors.black.withOpacity(.03),
//             blurRadius: 6,
//             offset: const Offset(0, 2),
//           )
//         ],
//       ),
//       child: Column(
//         crossAxisAlignment: CrossAxisAlignment.start,
//         children: [
//           Row(
//             children: [
//               Expanded(
//                 child: Column(
//                   crossAxisAlignment: CrossAxisAlignment.start,
//                   children: [
//                     Text(
//                       log[OfflineDBConstants.COL_ACTION] ?? "SYSTEM",
//                       style: GoogleFonts.poppins(
//                         fontWeight: FontWeight.w600,
//                         fontSize: 14,
//                         color: AuditColors.textPrimary,
//                       ),
//                     ),
//                     const SizedBox(height: 2),
//                     Text(
//                       dateStr,
//                       style: GoogleFonts.poppins(
//                         fontSize: 11,
//                         color: AuditColors.textSecondary,
//                       ),
//                     ),
//                   ],
//                 ),
//               ),
//               Container(
//                 padding:
//                     const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
//                 decoration: BoxDecoration(
//                   color: tileSoft,
//                   borderRadius: BorderRadius.circular(20),
//                   border: Border.all(color: statusColor),
//                 ),
//                 child: Text(
//                   isError ? "ERROR" : "SUCCESS",
//                   style: GoogleFonts.poppins(
//                     fontSize: 10,
//                     fontWeight: FontWeight.w700,
//                     color: statusColor,
//                     letterSpacing: .3,
//                   ),
//                 ),
//               ),
//             ],
//           ),
//           const SizedBox(height: 10),
//           Text(
//             log[OfflineDBConstants.COL_REMARKS] ?? "No remarks provided",
//             style: GoogleFonts.poppins(
//               fontSize: 13,
//               color: AuditColors.textPrimary,
//             ),
//           ),
//           if (log[OfflineDBConstants.COL_RESPONSE] != null &&
//               log[OfflineDBConstants.COL_RESPONSE].isNotEmpty)
//             Container(
//               width: double.infinity,
//               margin: const EdgeInsets.only(top: 10),
//               padding: const EdgeInsets.all(10),
//               decoration: BoxDecoration(
//                 color: AuditColors.surface,
//                 borderRadius: BorderRadius.circular(10),
//                 border: Border.all(color: AuditColors.border),
//               ),
//               child: Text(
//                 log[OfflineDBConstants.COL_RESPONSE],
//                 style: GoogleFonts.firaCode(
//                   fontSize: 11,
//                   color: AuditColors.textSecondary,
//                 ),
//               ),
//             ),
//         ],
//       ),
//     );
//   }

//   String _formatDate(String date) {
//     try {
//       DateTime dt = DateTime.parse(date);
//       return DateFormat('EEE, dd MMM • hh:mm a').format(dt);
//     } catch (_) {
//       return date;
//     }
//   }

//   Widget _buildEmptyState() {
//     return Center(
//       child: Column(
//         mainAxisAlignment: MainAxisAlignment.center,
//         children: [
//           Container(
//             padding: const EdgeInsets.all(18),
//             decoration: const BoxDecoration(
//               color: AuditColors.surface,
//               shape: BoxShape.circle,
//             ),
//             child: const Icon(Icons.history_rounded,
//                 size: 36, color: AuditColors.textSecondary),
//           ),
//           const SizedBox(height: 12),
//           Text(
//             "No activity logs found",
//             style: GoogleFonts.poppins(
//               color: AuditColors.textSecondary,
//               fontWeight: FontWeight.w500,
//             ),
//           ),
//         ],
//       ),
//     );
//   }

//   Future<void> _confirmClear() async {
//     bool? ok = await Get.dialog<bool>(
//       AlertDialog(
//         shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
//         title: Text("Clear History?",
//             style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
//         content: Text("This will wipe all audit logs permanently.",
//             style: GoogleFonts.poppins()),
//         actions: [
//           TextButton(
//               onPressed: () => Get.back(result: false),
//               child: const Text("Cancel")),
//           ElevatedButton(
//             style: ElevatedButton.styleFrom(
//                 backgroundColor: AuditColors.error, elevation: 0),
//             onPressed: () => Get.back(result: true),
//             child:
//                 const Text("Clear All", style: TextStyle(color: Colors.white)),
//           ),
//         ],
//       ),
//     );

//     if (ok == true) {
//       await OfflineDbModule.clearAuditLogs();
//       _loadLogs();
//     }
//   }
// }
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart' as intl;
import 'package:ubbottleapp/ModelPages/LandingMenuPages/offline_form_pages/db/offline_db_constants.dart';
import 'package:ubbottleapp/ModelPages/LandingMenuPages/offline_form_pages/db/offline_db_module.dart';

class AuditColors {
  static const primary = Color(0xFF2563EB);
  static const success = Color(0xFF16A34A);
  static const error = Color(0xFFDC2626);

  static const blueSoft = Color(0xFFEFF6FF);
  static const greenSoft = Color(0xFFECFDF5);
  static const redSoft = Color(0xFFFEF2F2);

  static const textPrimary = Color(0xFF111827);
  static const textSecondary = Color(0xFF6B7280);

  static const border = Color(0xFFE5E7EB);
  static const surface = Color(0xFFF8FAFC);
}

class AuditLogPage extends StatefulWidget {
  const AuditLogPage({super.key});

  @override
  State<AuditLogPage> createState() => _AuditLogPageState();
}

class _AuditLogPageState extends State<AuditLogPage> {
  List<Map<String, dynamic>> allLogs = [];
  List<Map<String, dynamic>> filteredLogs = [];
  bool isLoading = true;

  String selectedFilter = "All";
  String? selectedAction;

  @override
  void initState() {
    super.initState();
    _loadLogs();
  }

  Future<void> _loadLogs() async {
    setState(() => isLoading = true);
    final data = await OfflineDbModule.getAuditLogs();
    setState(() {
      allLogs = data;
      _applyFilters();
      isLoading = false;
    });
  }

  void _applyFilters() {
    filteredLogs = allLogs.where((log) {
      bool isError = log[OfflineDBConstants.COL_IS_ERROR] == 1;

      bool matchesStatus = true;
      if (selectedFilter == "Success") matchesStatus = !isError;
      if (selectedFilter == "Error") matchesStatus = isError;

      bool matchesAction = selectedAction == null ||
          log[OfflineDBConstants.COL_ACTION] == selectedAction;

      return matchesStatus && matchesAction;
    }).toList();

    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: _buildAppBar(),
      body: Column(
        children: [
          _buildFilterBar(),
          Expanded(
            child: isLoading
                ? const Center(child: CircularProgressIndicator())
                : filteredLogs.isEmpty
                    ? _buildEmptyState()
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                        itemCount: filteredLogs.length,
                        itemBuilder: (_, i) => _buildLogTile(filteredLogs[i]),
                      ),
          ),
        ],
      ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      elevation: 0,
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_ios_new_rounded,
            color: AuditColors.textPrimary, size: 20),
        onPressed: () => Get.back(),
      ),
      title: Text(
        "Activity Logs",
        style: GoogleFonts.poppins(
          fontWeight: FontWeight.w600,
          fontSize: 18,
          color: AuditColors.textPrimary,
        ),
      ),
      actions: [
        Padding(
          padding: const EdgeInsets.only(right: 12),
          child: IconButton(
            style: IconButton.styleFrom(
              backgroundColor: AuditColors.redSoft,
              side: const BorderSide(color: AuditColors.error, width: .6),
            ),
            onPressed: _confirmClear,
            icon: const Icon(Icons.delete_outline_rounded,
                size: 20, color: AuditColors.error),
          ),
        )
      ],
    );
  }

  Widget _buildFilterBar() {
    List<String> actions = allLogs
        .map((e) => e[OfflineDBConstants.COL_ACTION].toString())
        .toSet()
        .toList();

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFF1F5F9), Color(0xFFE2E8F0)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AuditColors.border),
      ),
      child: Row(
        children: [
          _filterChip("All"),
          const SizedBox(width: 8),
          _filterChip("Success"),
          const SizedBox(width: 8),
          _filterChip("Error"),
          const Spacer(),
          _actionDropdown(actions),
        ],
      ),
    );
  }

  Widget _filterChip(String label) {
    bool selected = selectedFilter == label;

    Color bg;
    Color border;
    Color text;

    if (label == "Success" && selected) {
      bg = AuditColors.greenSoft;
      border = AuditColors.success;
      text = AuditColors.success;
    } else if (label == "Error" && selected) {
      bg = AuditColors.redSoft;
      border = AuditColors.error;
      text = AuditColors.error;
    } else if (selected) {
      bg = AuditColors.blueSoft;
      border = AuditColors.primary;
      text = AuditColors.primary;
    } else {
      bg = Colors.white;
      border = AuditColors.border;
      text = AuditColors.textSecondary;
    }

    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: () {
        setState(() => selectedFilter = label);
        _applyFilters();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: border),
        ),
        child: Text(
          label,
          style: GoogleFonts.poppins(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: text,
          ),
        ),
      ),
    );
  }

  Widget _actionDropdown(List<String> actions) {
    return Container(
      height: 34,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AuditColors.border),
      ),
      child: DropdownButton<String>(
        value: selectedAction,
        hint: Text("Action",
            style: GoogleFonts.poppins(
                fontSize: 12, color: AuditColors.textSecondary)),
        underline: const SizedBox(),
        icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 18),
        dropdownColor: Colors.white,
        items: [
          const DropdownMenuItem(
              value: null,
              child:
                  Text("All", style: TextStyle(fontWeight: FontWeight.w500))),
          ...actions.map((a) => DropdownMenuItem(
                value: a,
                child: Text(a,
                    style: const TextStyle(fontWeight: FontWeight.w500)),
              )),
        ],
        onChanged: (v) {
          setState(() => selectedAction = v);
          _applyFilters();
        },
        style:
            GoogleFonts.poppins(fontSize: 12, color: AuditColors.textPrimary),
      ),
    );
  }

  // Widget _buildLogTile(Map<String, dynamic> log) {
  //   bool isError = log[OfflineDBConstants.COL_IS_ERROR] == 1;
  //   String dateStr = _formatDate(log[OfflineDBConstants.COL_CREATED_AT]);

  //   Color statusColor = isError ? AuditColors.error : AuditColors.success;
  //   Color tileSoft = isError ? AuditColors.redSoft : AuditColors.greenSoft;

  //   return Container(
  //     margin: const EdgeInsets.only(bottom: 10),
  //     padding: const EdgeInsets.all(14),
  //     decoration: BoxDecoration(
  //       color: Colors.white,
  //       borderRadius: BorderRadius.circular(14),
  //       border: Border.all(color: AuditColors.border),
  //       boxShadow: [
  //         BoxShadow(
  //           color: Colors.black.withOpacity(.03),
  //           blurRadius: 6,
  //           offset: const Offset(0, 2),
  //         )
  //       ],
  //     ),
  //     child: Column(
  //       crossAxisAlignment: CrossAxisAlignment.start,
  //       children: [
  //         Row(
  //           children: [
  //             Expanded(
  //               child: Column(
  //                 crossAxisAlignment: CrossAxisAlignment.start,
  //                 children: [
  //                   Text(
  //                     log[OfflineDBConstants.COL_ACTION] ?? "SYSTEM",
  //                     style: GoogleFonts.poppins(
  //                       fontWeight: FontWeight.w600,
  //                       fontSize: 14,
  //                       color: AuditColors.textPrimary,
  //                     ),
  //                   ),
  //                   const SizedBox(height: 2),
  //                   Text(
  //                     dateStr,
  //                     style: GoogleFonts.poppins(
  //                       fontSize: 11,
  //                       color: AuditColors.textSecondary,
  //                     ),
  //                   ),
  //                 ],
  //               ),
  //             ),
  //             Container(
  //               padding:
  //                   const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
  //               decoration: BoxDecoration(
  //                 color: tileSoft,
  //                 borderRadius: BorderRadius.circular(20),
  //                 border: Border.all(color: statusColor),
  //               ),
  //               child: Text(
  //                 isError ? "ERROR" : "SUCCESS",
  //                 style: GoogleFonts.poppins(
  //                   fontSize: 10,
  //                   fontWeight: FontWeight.w700,
  //                   color: statusColor,
  //                   letterSpacing: .3,
  //                 ),
  //               ),
  //             ),
  //           ],
  //         ),
  //         const SizedBox(height: 10),
  //         Text(
  //           log[OfflineDBConstants.COL_REMARKS] ?? "No remarks provided",
  //           style: GoogleFonts.poppins(
  //             fontSize: 13,
  //             color: AuditColors.textPrimary,
  //           ),
  //         ),
  //         if (log[OfflineDBConstants.COL_RESPONSE] != null &&
  //             log[OfflineDBConstants.COL_RESPONSE].isNotEmpty)
  //           Container(
  //             width: double.infinity,
  //             margin: const EdgeInsets.only(top: 10),
  //             padding: const EdgeInsets.all(10),
  //             decoration: BoxDecoration(
  //               color: AuditColors.surface,
  //               borderRadius: BorderRadius.circular(10),
  //               border: Border.all(color: AuditColors.border),
  //             ),
  //             child: Text(
  //               log[OfflineDBConstants.COL_RESPONSE],
  //               style: GoogleFonts.firaCode(
  //                 fontSize: 11,
  //                 color: AuditColors.textSecondary,
  //               ),
  //             ),
  //           ),
  //       ],
  //     ),
  //   );
  // }

  Widget _buildLogTile(Map<String, dynamic> log) {
    bool isError = log[OfflineDBConstants.COL_IS_ERROR] == 1;
    String dateStr = _formatDate(log[OfflineDBConstants.COL_CREATED_AT]);

    Color statusColor = isError ? AuditColors.error : AuditColors.success;
    Color tileSoft = isError ? AuditColors.redSoft : AuditColors.greenSoft;

    final String response = log[OfflineDBConstants.COL_RESPONSE] ?? "";

    return StatefulBuilder(
      builder: (context, setState) {
        bool expanded = false;

        return Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AuditColors.border),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(.03),
                blurRadius: 6,
                offset: const Offset(0, 2),
              )
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              /// HEADER
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          log[OfflineDBConstants.COL_ACTION] ?? "SYSTEM",
                          style: GoogleFonts.poppins(
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                            color: AuditColors.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          dateStr,
                          style: GoogleFonts.poppins(
                            fontSize: 11,
                            color: AuditColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: tileSoft,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: statusColor),
                    ),
                    child: Text(
                      isError ? "ERROR" : "SUCCESS",
                      style: GoogleFonts.poppins(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: statusColor,
                        letterSpacing: .3,
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 10),

              /// REMARKS
              Text(
                log[OfflineDBConstants.COL_REMARKS] ?? "No remarks provided",
                style: GoogleFonts.poppins(
                  fontSize: 13,
                  color: AuditColors.textPrimary,
                ),
              ),

              /// RESPONSE BLOCK
              // if (response.isNotEmpty) ...[
              //   const SizedBox(height: 10),
              //   Container(
              //     width: double.infinity,
              //     decoration: BoxDecoration(
              //       color: const Color(0xFF0F172A), // IDE dark bg
              //       borderRadius: BorderRadius.circular(10),
              //       border: Border.all(color: const Color(0xFF1E293B)),
              //     ),
              //     padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
              //     child: Column(
              //       crossAxisAlignment: CrossAxisAlignment.start,
              //       children: [
              //         AnimatedSize(
              //           duration: const Duration(milliseconds: 200),
              //           curve: Curves.easeInOut,
              //           child: Text(
              //             _prettyJson(response),
              //             maxLines: expanded ? null : 4,
              //             overflow: TextOverflow.fade,
              //             style: GoogleFonts.firaCode(
              //               fontSize: 11.5,
              //               height: 1.45,
              //               color: const Color(0xFFE2E8F0),
              //             ),
              //           ),
              //         ),
              //         if (_isOverflowing(response))
              //           GestureDetector(
              //             onTap: () => setState(() => expanded = !expanded),
              //             child: Padding(
              //               padding: const EdgeInsets.only(top: 6),
              //               child: Text(
              //                 expanded ? "Collapse ▲" : "Expand ▼",
              //                 style: GoogleFonts.poppins(
              //                   fontSize: 10,
              //                   fontWeight: FontWeight.w600,
              //                   color: const Color(0xFF38BDF8),
              //                 ),
              //               ),
              //             ),
              //           ),
              //       ],
              //     ),
              //   ),
              // ],
              if (response.isNotEmpty) ...[
                const SizedBox(height: 10),
                _JsonResponseViewer(response: response),
              ],
            ],
          ),
        );
      },
    );
  }

  String _prettyJson(String input) {
    try {
      final decoded = jsonDecode(input);
      const encoder = JsonEncoder.withIndent('  ');
      return encoder.convert(decoded);
    } catch (_) {
      return input;
    }
  }

  bool _isOverflowing(String text) {
    return '\n'.allMatches(_prettyJson(text)).length >= 4;
  }

  String _formatDate(String date) {
    try {
      DateTime dt = DateTime.parse(date);
      return intl.DateFormat('EEE, dd MMM • hh:mm a').format(dt);
    } catch (_) {
      return date;
    }
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: const BoxDecoration(
              color: AuditColors.surface,
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.history_rounded,
                size: 36, color: AuditColors.textSecondary),
          ),
          const SizedBox(height: 12),
          Text(
            "No activity logs found",
            style: GoogleFonts.poppins(
              color: AuditColors.textSecondary,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmClear() async {
    bool? ok = await Get.dialog<bool>(
      AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text("Clear History?",
            style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
        content: Text("This will wipe all audit logs permanently.",
            style: GoogleFonts.poppins()),
        actions: [
          TextButton(
              onPressed: () => Get.back(result: false),
              child: const Text("Cancel")),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: AuditColors.error, elevation: 0),
            onPressed: () => Get.back(result: true),
            child:
                const Text("Clear All", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (ok == true) {
      await OfflineDbModule.clearAuditLogs();
      _loadLogs();
    }
  }
}

class _JsonResponseViewer extends StatefulWidget {
  final String response;
  const _JsonResponseViewer({required this.response});

  @override
  State<_JsonResponseViewer> createState() => _JsonResponseViewerState();
}

class _JsonResponseViewerState extends State<_JsonResponseViewer>
    with TickerProviderStateMixin {
  bool expanded = false;
  bool overflow = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _checkOverflow();
  }

  void _checkOverflow() {
    final span = TextSpan(
      text: _prettyJson(widget.response),
      style: GoogleFonts.firaCode(fontSize: 11.5, height: 1.45),
    );

    final tp = TextPainter(
      text: span,
      maxLines: 4,
      textDirection: TextDirection.ltr,
    );

    tp.layout(maxWidth: MediaQuery.of(context).size.width - 80);

    overflow = tp.didExceedMaxLines;
  }

  @override
  Widget build(BuildContext context) {
    final formatted = _prettyJson(widget.response);

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF1E293B)),
      ),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Stack(
            children: [
              AnimatedSize(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeInOut,
                child: Text(
                  formatted,
                  maxLines: expanded ? null : 4,
                  overflow: TextOverflow.clip,
                  style: GoogleFonts.firaCode(
                    fontSize: 11.5,
                    height: 1.45,
                    color: const Color(0xFFE2E8F0),
                  ),
                ),
              ),

              /// fade hint when collapsed
              if (!expanded && overflow)
                Positioned.fill(
                  child: Align(
                    alignment: Alignment.bottomCenter,
                    child: Container(
                      height: 28,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(8),
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            const Color(0xFF0F172A).withOpacity(0),
                            const Color(0xFF0F172A),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
          if (overflow)
            GestureDetector(
              onTap: () => setState(() => expanded = !expanded),
              child: Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  expanded ? "Collapse ▲" : "Expand ▼",
                  style: GoogleFonts.poppins(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFF38BDF8),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  String _prettyJson(String input) {
    try {
      final decoded = jsonDecode(input);
      const encoder = JsonEncoder.withIndent('  ');
      return encoder.convert(decoded);
    } catch (_) {
      return input;
    }
  }
}
