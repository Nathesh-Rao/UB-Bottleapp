import 'dart:async';
import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:ubbottleapp/Constants/AppStorage.dart';
import 'package:ubbottleapp/Constants/Routes.dart';
import 'package:ubbottleapp/Constants/VersionUpdateClearOldData.dart';
import 'package:ubbottleapp/Constants/Const.dart';
import 'package:ubbottleapp/ModelPages/ProjectListing/Model/ProjectModel.dart';
import 'package:ubbottleapp/ModelPages/location_permission.dart';
import 'package:ubbottleapp/Utils/LogServices/LogService.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:get/get.dart';
import 'package:local_auth/local_auth.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:ubbottleapp/ModelPages/SpalshPage/upgrade_page.dart';
import 'package:upgrader/upgrader.dart';
import 'package:version/version.dart';

class SplashPage extends StatefulWidget {
  const SplashPage({super.key});

  @override
  State<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends State<SplashPage>
    with SingleTickerProviderStateMixin {
  var _animationController;
  AppStorage appStorage = AppStorage();
  ProjectModel? projectModel;

  @override
  void initState() {
    LogService.writeLog(message: "[>] SplashPage");
    // LogService.writeOnConsole(message: "[>] SplashPage");
    super.initState();
    // SystemChrome.setEnabledSystemUIMode(SystemUiMode.manual);
    // SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle(statusBarColor: Colors.transparent));
    _animationController =
        AnimationController(vsync: this, duration: Duration(milliseconds: 800));
    _animationController.forward();
    VersionUpdateClearOldData.clearAllOldData();
    checkIfDeviceSupportBiometric();
    //

//
    // Future.delayed(Duration(milliseconds: 1800), () {
    //   _animationController.stop();

    //   var cached = appStorage.retrieveValue(AppStorage.CACHED);

    //   try {
    //     if (cached == null)
    //       Get.offAllNamed(Routes.ProjectListingPage);
    //     else {
    //       var jsonProject = appStorage.retrieveValue(cached);
    //       projectModel = ProjectModel.fromJson(jsonProject);
    //       globalVariableController.PROJECT_NAME.value = projectModel!.projectname;
    //       globalVariableController.WEB_URL.value = projectModel!.web_url;
    //       globalVariableController.ARM_URL.value = projectModel!.arm_url;
    //       LogService.writeOnConsole(message: " splash-page projectModel => $jsonProject");
    //       Get.offAllNamed(Routes.Login);
    //     }
    //   } catch (e) {
    //     LogService.writeLog(message: "[ERROR] \nPage: SplashPage\nScope: initState()\nError: $e");
    //     LogService.writeOnConsole(message: "[ERROR] \nPage: SplashPage\nScope: initState()\nError: $e");
    //     Get.offAllNamed(Routes.ProjectListingPage);
    //   }
    // });

    Future.delayed(const Duration(milliseconds: 1800), () async {
      _animationController.stop();

      const String tag = "[SPLASH_STARTUP_001]";

      try {
        checkVersionAndNavigate();
      } catch (e, st) {
        LogService.writeLog(
            message: "$tag[FAILED] Splash routing failed => $e");
        LogService.writeLog(message: "$tag[STACK] $st");
        Get.offAllNamed(Routes.ProjectListingPage);
      }
    });
  }

  // _askLocationPermission() async {
  //   if (Platform.isAndroid) {
  //     var permission = await Permission.locationAlways.request();

  //     // print("Location Permission: ${permission}");
  //     LogService.writeLog(
  //         message:
  //             "[i] SplashPage \nScope: askLocationPermission() : $permission ");
  //     if (permission != PermissionStatus.granted) {
  //       Get.to(RequestLocationPage());
  //     }
  //   }
  //   if (Platform.isIOS) {
  //     await Geolocator.requestPermission();
  //   }
  // }
  void checkVersionAndNavigate() async {
    final appcastURL =
        'https://raw.githubusercontent.com/amrith4agile/update_xml_ub_bottleapp/main/appcast.xml';

    final deviceInfo = DeviceInfoPlugin();
    final androidInfo = await deviceInfo.androidInfo;

    final upgrader = Upgrader(
      debugLogging: true,
      storeController: UpgraderStoreController(
        onAndroid: () {
          String release = androidInfo.version.release;

          List<String> parts = release.split('.');
          while (parts.length < 3) {
            parts.add('0');
          }
          String formattedVersion = parts.join('.');

          return UpgraderAppcastStore(
              appcastURL: appcastURL,
              osVersion: Version.parse(formattedVersion));
        },
        // oniOS: () => UpgraderAppcastStore(appcastURL: appcastURL),
      ),
    );
    await upgrader.initialize();

    if (upgrader.shouldDisplayUpgrade()) {
      Get.offAll(() => UpdateRequiredPage(
            upgrader: upgrader,
          ));
    } else {
      var cached = appStorage.retrieveValue(AppStorage.CACHED);

      if (cached == null) {
        await setupDefaultProject();
      } else {
        var jsonProject = appStorage.retrieveValue(cached);
        projectModel = ProjectModel.fromJson(jsonProject);
        globalVariableController.PROJECT_NAME.value = projectModel!.projectname;
        globalVariableController.WEB_URL.value = projectModel!.web_url;
        globalVariableController.ARM_URL.value = projectModel!.arm_url;
        LogService.writeOnConsole(
            message: " splash-page projectModel => $jsonProject");
        Get.offAllNamed(Routes.Login);
      }
    }
  }

  setupDefaultProject() async {
    ProjectModel ubProject = ProjectModel(
        DateTime.now().toString(),
        "genie",
        "https://app.ublnet.in/genie",
        "https://app.ublnet.in/arm114",
        "Bottle Sampling");
    List<ProjectModel> projects = [ubProject];

    String? storedData = appStorage.retrieveValue("projects");

    if (storedData == null) {
      String encodedData = ProjectModel.encode(projects);
      await appStorage.storeValue("projects", encodedData);
      await appStorage.storeValue(ubProject.projectCaption, ubProject);
      await appStorage.storeValue(AppStorage.CACHED, ubProject.projectCaption);
      globalVariableController.PROJECT_NAME.value = ubProject.projectname;
      globalVariableController.WEB_URL.value = ubProject.web_url;
      globalVariableController.ARM_URL.value = ubProject.arm_url;
      await appStorage.storeValue(
          AppStorage.PROJECT_NAME, ubProject.projectname);
      await appStorage.storeValue(AppStorage.PROJECT_URL, ubProject.web_url);
      await appStorage.storeValue(AppStorage.ARM_URL, ubProject.arm_url);
      Get.offAllNamed(Routes.Login);
    }
  }

  @override
  void dispose() {
    // TODO: implement dispose
    // SystemChrome.setEnabledSystemUIMode(SystemUiMode.manual, overlays: SystemUiOverlay.values);
    // SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle.dark);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      // _askLocationPermission();
      // await ensureLocalNetworkPermission();
    });

    return Scaffold(
      // color: Colors.red,
      body: Stack(
        children: [
          Center(
            child: RotationTransition(
              turns: Tween(begin: 0.0, end: 1.0).animate(_animationController),
              child: Container(
                height: 90,
                width: 90,
                child: Image.asset(
                  'assets/images/ub_logo.png',
                  height: 80,
                  fit: BoxFit.contain,
                ),
              ),
            ),
          ),
          // Align(
          //   alignment: Alignment.bottomRight,
          //   child: Padding(
          //     padding: EdgeInsets.only(right: 20, bottom: 20),
          //     child: Text("Version: "),
          //   ),
          // )
        ],
      ),
    );
  }

  void checkIfDeviceSupportBiometric() async {
    final LocalAuthentication auth = LocalAuthentication();
    final bool canAuthenticateWithBiometrics = await auth.canCheckBiometrics;
    final bool canAuthenticate =
        canAuthenticateWithBiometrics || await auth.isDeviceSupported();
    LogService.writeOnConsole(message: "canAuthenticate: $canAuthenticate");
    LogService.writeLog(
        message:
            "[i] SplashPage\nScope:checkIfDeviceSupportBiometric()\nCanAuthenticate: $canAuthenticate");
    if (canAuthenticate) {
      final List<BiometricType> availableBiometrics =
          await auth.getAvailableBiometrics();
      LogService.writeOnConsole(message: "List: $availableBiometrics");
      LogService.writeLog(
          message:
              "[i] SplashPage\nScope:checkIfDeviceSupportBiometric()\nAvailable Biometrics: $availableBiometrics");

      // if (availableBiometrics.contains (BiometricType.fingerprint) ||
      //     availableBiometrics.contains(BiometricType.weak) ||
      //     availableBiometrics.contains(BiometricType.strong))
      if (availableBiometrics.isNotEmpty) {
        AppStorage().storeValue(AppStorage.CAN_AUTHENTICATE, canAuthenticate);
      } else {
        AppStorage().remove(AppStorage.CAN_AUTHENTICATE);
      }
    }
  }
}
