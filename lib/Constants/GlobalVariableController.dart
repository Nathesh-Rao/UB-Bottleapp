import 'package:get/get.dart';

class GlobalVariableController extends GetxController {
  // static GlobalVariableController to = Get.find();

  var WEB_URL = ''.obs;
  var PROJECT_NAME = ''.obs;
  var ARM_URL = ''.obs;
  var LOG_PATH = ''.obs;
  var USER_ROLE = ''.obs;
  var OFFLINE_FORMS_COUNT = 0.obs;
  final RxBool autoSyncEnabled = false.obs;
  final RxBool autoSyncMasterEnabled = false.obs;

  final USER_NAME = ''.obs;
}
