import 'dart:developer';
import 'dart:io';

import 'package:animate_do/animate_do.dart';
import 'package:auto_size_text/auto_size_text.dart';
import 'package:flutter/cupertino.dart';
import 'package:ubbottleapp/Constants/CommonMethods.dart';
import 'package:ubbottleapp/Constants/GlobalVariableController.dart';
import 'package:ubbottleapp/Constants/MyColors.dart';
import 'package:ubbottleapp/ModelPages/LandingMenuPages/offline_form_pages/auto_sync/offline_background_sync_service.dart';
import 'package:ubbottleapp/ModelPages/LandingMenuPages/offline_form_pages/db/offline_db_module.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../Constants/Const.dart';
import '../../LandingMenuPages/MenuHomePagePage/Controllers/MenuHomePageController.dart';
import '../../LandingPage/Controller/LandingPageController.dart';
import '../Controller/SettingsPageController.dart';

class SettingsPage extends StatelessWidget {
  SettingsPage({super.key});

  final SettingsPageController settingsPageController =
      Get.put(SettingsPageController());
  final LandingPageController landingPageController = Get.find();
  final MenuHomePageController menuHomePageController = Get.find();
  final GlobalVariableController _globalVariableController = Get.find();
  var isAutosyncLoading = false;
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // backgroundColor: Colors.black,
      // backgroundColor: Colors.grey.shade100,
      body: Stack(
        children: [
          Container(
            height: 330,
            decoration: BoxDecoration(
                gradient: MyColors.updatedUIBackgroundGradient,
                borderRadius:
                    BorderRadius.vertical(bottom: Radius.circular(0))),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.only(left: 15, right: 15),
              child: Column(
                children: [
                  Stack(
                    children: [
                      AppBar(
                        backgroundColor: Colors.transparent,
                        elevation: 0,
                        automaticallyImplyLeading: false,
                        actions: [
                          IconButton(
                              onPressed: () {
                                Get.back();
                              },
                              icon: CircleAvatar(
                                backgroundColor: Colors.white,
                                child: Icon(
                                  Icons.close,
                                  color: Colors.black,
                                ),
                              ))
                        ],
                      ),
                      Container(
                        padding: EdgeInsets.only(top: 30, left: 20),
                        child: Row(
                          children: [
                            Container(
                              height: 80,
                              width: 80,
                              child: Stack(
                                children: [
                                  CircleAvatar(
                                    minRadius: 50,
                                    backgroundColor: Colors.white,
                                    child: Image.asset(
                                      "assets/images/avator.png",
                                      scale: 1.1,
                                    ),
                                    // child: Icon(
                                    //   Icons.person,
                                    //   color: Colors.white,
                                    //   size: 80,
                                    // ),
                                  ),
                                  Align(
                                    alignment: Alignment.bottomRight,
                                    child: Container(
                                      width: 30,
                                      height: 30,
                                      decoration: BoxDecoration(
                                          color: Colors.white,
                                          borderRadius:
                                              BorderRadius.circular(50)),
                                      child: Icon(
                                        Icons.edit,
                                        color: Colors.black,
                                      ),
                                    ),
                                  )
                                ],
                              ),
                            ),
                            SizedBox(width: 20),
                            Expanded(
                              child: Obx(() => Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      AutoSizeText(
                                        CommonMethods.capitalize(
                                            menuHomePageController
                                                .user_nickName.value),
                                        maxLines: 1,
                                        style: GoogleFonts.poppins(
                                          textStyle: const TextStyle(
                                            color: Colors.white,
                                            fontSize:
                                                25, // this is the *base* font size
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                        maxFontSize: 25,
                                        minFontSize: 15,
                                        stepGranularity:
                                            0.5, // shrink smoothly instead of big jumps
                                        //overflow: TextOverflow.ellipsis,
                                      ),
                                      Visibility(
                                        visible: menuHomePageController
                                                .client_info_companyTitle
                                                .value !=
                                            "",
                                        child: Text(
                                          menuHomePageController
                                              .client_info_companyTitle.value,
                                          style: GoogleFonts.poppins(
                                              textStyle: TextStyle(
                                                  color: Colors.white,
                                                  fontSize: 15)),
                                        ),
                                      ),
                                    ],
                                  )),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  // Container(
                  //   height: AppBar().preferredSize.height,
                  //   child: Align(
                  //     alignment: Alignment.centerRight,
                  //     child: GestureDetector(
                  //       onTap: () {
                  //         Get.back();
                  //       },
                  //       child: Container(
                  //         width: 35,
                  //         height: 35,
                  //         decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(50)),
                  //         child: Icon(
                  //           Icons.close_rounded,
                  //           color: Colors.black,
                  //         ),
                  //       ),
                  //     ),
                  //   ),
                  // ),

                  SizedBox(height: 20),
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                          // image: DecorationImage(
                          //   image: AssetImage('assets/images/buzzily_flipped.png'),
                          //   alignment: Alignment.bottomRight,
                          //   opacity: 0.3,
                          // ),
                          borderRadius: BorderRadius.circular(10),
                          // color: Colors.white,
                          color: Colors.white,
                          border: Border.all(
                              color: Colors.grey.shade300, width: 1)),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        child: SingleChildScrollView(
                            child: Column(
                          mainAxisAlignment: MainAxisAlignment.start,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const SizedBox(height: 20),
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Image.asset(
                                  'assets/images/ub_logo.png',
                                  height: 70,
                                ),
                                const SizedBox(width: 10),
                                Text(
                                  "United\nBreweries\nlimited".toUpperCase(),
                                  style: GoogleFonts.poppins(
                                    color: Colors.black54,
                                    fontWeight: FontWeight.w600,
                                  ),
                                  textAlign: TextAlign.start,
                                ),
                              ],
                            ),
                            const SizedBox(height: 30),

                            // 1. Notification
                            _buildCustomTile(
                              title: "Notification",
                              iconOn: Icons.notifications_active_rounded,
                              iconOff: Icons.notifications_off_outlined,
                              iconColor: MyColors.blue1,
                              switchValue:
                                  settingsPageController.notificationOnOffValue,
                              onToggle: (val) =>
                                  settingsPageController.onChangeNotifyStatus(),
                            ),

                            // 2. Trace
                            _buildCustomTile(
                              title: "Trace",
                              iconOn: Icons.description_rounded,
                              iconOff: Icons.description_outlined,
                              iconColor: Colors.green,
                              switchValue: settingsPageController.logOnOffValue,
                              onToggle: (val) =>
                                  settingsPageController.onChangeLogStatus(),
                            ),

                            // 3. Auto Sync Records (With animate_do Spin)
                            StatefulBuilder(builder: (c, setSt) {
                              return _buildCustomTile(
                                title: "Auto Sync Records",
                                iconOn: Icons.sync_rounded,
                                iconOff: Icons.sync_disabled_rounded,
                                iconColor: Colors.teal,
                                isLoading:
                                    isAutosyncLoading, // Triggers the Spin animation
                                switchValue:
                                    _globalVariableController.autoSyncEnabled,
                                onToggle: (val) async {
                                  setSt(() =>
                                      isAutosyncLoading = !isAutosyncLoading);

                                  final bool newValue =
                                      !_globalVariableController
                                          .autoSyncEnabled.value;
                                  final bool applied =
                                      await OfflineBackgroundSyncService
                                          .instance
                                          .setAutoSync(enabled: newValue);
                                  setSt(() => isAutosyncLoading = false);
                                  if (applied) {
                                    _globalVariableController
                                        .autoSyncEnabled.value = newValue;
                                  }
                                },
                              );
                            }),

                            // 4. Auto Sync Masters
                            _buildCustomTile(
                              title: "Auto Sync Masters",
                              iconOn: Icons.cloud_sync_rounded,
                              iconOff: Icons.cloud_off_rounded,
                              iconColor: MyColors.blue10,
                              switchValue: _globalVariableController
                                  .autoSyncMasterEnabled,
                              onToggle: (val) async {
                                await OfflineDbModule.toggleAutoSyncMaster();
                              },
                            ),

                            const Padding(
                              padding: EdgeInsets.symmetric(
                                  horizontal: 20, vertical: 8),
                              child: Divider(color: Colors.black12, height: 1),
                            ),

                            // 5. Reset Password (Action Tile)
                            _buildCustomTile(
                              title: "Reset Password",
                              iconOn: Icons.lock_reset_rounded,
                              iconColor: Colors.indigo,
                              onTap: () {
                                landingPageController.showManageWindow(
                                    initialIndex: 1);
                              },
                            ),

                            // 6. Sign out (Action Tile)
                            _buildCustomTile(
                              title: "Sign out",
                              iconOn: Icons.power_settings_new_rounded,
                              iconColor: Colors.redAccent,
                              onTap: () async {
                                if (!OfflineBackgroundSyncService.instance
                                    .canProceedWithAction()) return;
                                await OfflineBackgroundSyncService.instance
                                    .stop();
                                await landingPageController.signOut();
                              },
                            ),
                            const SizedBox(height: 20),
                          ],
                        )),
                      ),
                    ),
                  ),
                  // TextButton(
                  //     onPressed: () {
                  //       Aes().encryptString(ExecuteApi.API_PrivateKey_DashBoard);
                  //       Aes().decryptString("G7H+G66Z+peBK7zJ3Rq1SA==", ExecuteApi.API_PrivateKey_DashBoard);
                  //       // Aes().encryptString(ExecuteApi.API_PrivateKey_DashBoard);
                  //     },
                  //     child: Text("Encrypt")),
                  Container(
                    padding: EdgeInsets.only(left: 5, right: 5),
                    height: 40,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.start,
                      children: [
                        Image.asset(
                          'assets/images/axpert_03.png',
                          height: MediaQuery.of(context).size.height * 0.03,
                          // width: MediaQuery.of(context).size.width * 0.075,
                          fit: BoxFit.fill,
                        ),
                        Text(" © ${DateTime.now().year} Powered by Axpert"),
                        Spacer(),
                        Text(
                          "v${Const.APP_VERSION}_${Const.APP_RELEASE_DATE}",
                          style: GoogleFonts.poppins(
                              textStyle: TextStyle(
                                  color: MyColors.buzzilyblack,
                                  fontWeight: FontWeight.w700,
                                  fontSize: MediaQuery.of(context).size.height *
                                      0.012)),
                        )
                      ],
                    ),
                  ),
                ],
              ),
            ),
          )
        ],
      ),
    );
  }

  Widget _buildCustomTile({
    required String title,
    required IconData iconOn,
    IconData? iconOff,
    required Color iconColor,
    RxBool? switchValue,
    Function(bool)? onToggle,
    VoidCallback? onTap,
    bool isLoading = false,
  }) {
    Widget buildTile(bool isOn) {
      final IconData currentIcon = isOn ? iconOn : (iconOff ?? iconOn);

      return ListTile(
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 20,
          vertical: 4,
        ),
        onTap:
            onTap ?? (switchValue != null ? () => onToggle?.call(!isOn) : null),
        leading: AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            // color: isOn
            //     ? iconColor.withValues(alpha: 0.15)
            //     : Colors.grey.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Spin(
            animate: isLoading,
            infinite: isLoading,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              transitionBuilder: (child, animation) {
                return ScaleTransition(
                  scale: animation,
                  child: FadeTransition(
                    opacity: animation,
                    child: child,
                  ),
                );
              },
              child: Icon(
                currentIcon,
                key: ValueKey<IconData>(currentIcon),
                color: isOn ? iconColor : Colors.grey.shade500,
                size: 24,
              ),
            ),
          ),
        ),
        title: Text(
          title,
          style: GoogleFonts.poppins(
            fontSize: 16,
            fontWeight: FontWeight.w500,
            color: Colors.black87,
          ),
        ),
        trailing: switchValue != null
            ? CupertinoSwitch(
                value: isOn,
                onChanged: onToggle,
                // activeThumbColor: iconColor,
                thumbColor: iconColor,
                inactiveThumbColor: MyColors.AXMGray,
                activeTrackColor: iconColor.withValues(alpha: 0.2),
              )
            : const Icon(
                Icons.chevron_right_rounded,
                color: Colors.black26,
              ),
      );
    }

    // Only create Obx when this tile actually depends on an RxBool.
    if (switchValue != null) {
      return Obx(() => buildTile(switchValue.value));
    }

    // Normal action tile — no Obx required.
    return buildTile(true);
  }
}
