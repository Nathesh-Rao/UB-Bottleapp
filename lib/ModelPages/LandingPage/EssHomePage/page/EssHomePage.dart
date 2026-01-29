import 'dart:developer';

import 'package:ubbottleapp/ModelPages/InApplicationWebView/page/InApplicationWebView.dart';
import 'package:ubbottleapp/ModelPages/LandingPage/Controller/LandingPageController.dart';
import 'package:ubbottleapp/ModelPages/LandingPage/EssHomePage/controller/EssController.dart';
import 'package:ubbottleapp/ModelPages/LandingPage/EssHomePage/widgets/WidgetEssAnnouncement.dart';
import 'package:ubbottleapp/ModelPages/LandingPage/EssHomePage/widgets/WidgetEssAppDrawer.dart';
import 'package:ubbottleapp/ModelPages/LandingPage/EssHomePage/widgets/WidgetEssAttendanceCard.dart';
import 'package:ubbottleapp/ModelPages/LandingPage/EssHomePage/widgets/WidgetEssBottomNavigation.dart';
import 'package:ubbottleapp/ModelPages/LandingPage/EssHomePage/widgets/WidgetEssHomeCard.dart';
import 'package:ubbottleapp/ModelPages/LandingPage/EssHomePage/widgets/WidgetEssKPICards.dart';
import 'package:ubbottleapp/ModelPages/LandingPage/EssHomePage/widgets/WidgetEssOtherServiceCard.dart';
import 'package:ubbottleapp/ModelPages/LandingPage/EssHomePage/widgets/WidgetHeaderWidget.dart';
import 'package:ubbottleapp/Utils/LogServices/LogService.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../LandingMenuPages/MenuHomePagePage/Controllers/MenuHomePageController.dart';

import '../widgets/WidgetEssAppBar.dart';
import '../widgets/WidgetEssMenuFolderWidget.dart';
import '../widgets/WidgetEssRecentActivity.dart';

class EssHomePage extends StatelessWidget {
  EssHomePage({super.key});
  final EssController controller = Get.put(EssController());
  final LandingPageController landingPageController =
      Get.put(LandingPageController());

  @override
  Widget build(BuildContext context) {
    LogService.writeLog(message: "[>] ESSHomeScreen");
    return WillPopScope(
      onWillPop: controller.onWillPop,
      child: Scaffold(
        extendBodyBehindAppBar: true,
        drawer: WidgetEssAppDrawer(),
        appBar: WidgetEssAppBar(),
        body: Obx(
          () => IndexedStack(
            index: controller.menuHomePageController.switchPage.value ? 1 : 0,
            children: [
              controller.getPage(),
              Visibility(
                  visible: controller.menuHomePageController.switchPage.value,
                  child: InApplicationWebViewer(
                      controller.menuHomePageController.webUrl))
            ],
          ),
        ),
        bottomNavigationBar: WidgetEssBottomNavigation(),
      ),
    );
  }
}
