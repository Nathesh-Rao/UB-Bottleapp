import 'package:ubbottleapp/ModelPages/InApplicationWebView/controller/webview_controller.dart';
import 'package:ubbottleapp/ModelPages/LandingMenuPages/MenuDashboardPage/Controllers/MenuDashboaardController.dart';
import 'package:ubbottleapp/ModelPages/LandingMenuPages/offline_form_pages/controller/offline_form_controller.dart';
import 'package:ubbottleapp/ModelPages/LandingMenuPages/offline_form_pages/inward_entry/inward_entry_dynamic_controller.dart';
import 'package:ubbottleapp/ModelPages/LandingPage/Controller/LandingPageController.dart';
import 'package:ubbottleapp/ModelPages/LandingPage/EssHomePage/controller/EssController.dart';
import 'package:get/get.dart';

class LandingPageBinding extends Bindings {
  @override
  void dependencies() {
    // TODO: implement dependencies
    Get.lazyPut(() => LandingPageController());
    Get.lazyPut(() => WebViewController());
    Get.lazyPut(() => MenuDashboardController());

    // Get.lazyPut(() => OfflineFormController());
  }
}
