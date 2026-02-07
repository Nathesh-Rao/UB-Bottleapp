import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:lottie/lottie.dart';
import 'package:upgrader/upgrader.dart';

import '../../Constants/Routes.dart';

class UpdateRequiredPage extends StatefulWidget {
  const UpdateRequiredPage({super.key, required this.upgrader});

  final Upgrader upgrader;

  @override
  State<UpdateRequiredPage> createState() => _UpdateRequiredPageState();
}

class _UpdateRequiredPageState extends State<UpdateRequiredPage> {
  late final StreamSubscription<UpgraderState> _subscription;
  @override
  void initState() {
    super.initState();

    _subscription = widget.upgrader.stateStream.listen(onUpgradeStateChange);
  }

  void onUpgradeStateChange(UpgraderState state) {
    if (!widget.upgrader.shouldDisplayUpgrade()) {
      Get.offAllNamed(Routes.SplashScreen);
    }
  }

  @override
  void dispose() {
    _subscription.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF4A80F0), Color(0xFF1C54D4)],
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 30),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 40),
                Expanded(
                  child: Lottie.asset(
                    'assets/lotties/update_app.json',
                    height: 300,
                  ),
                ),
                const Text(
                  "New\nUpdate\nAvailable",
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 48,
                    fontWeight: FontWeight.bold,
                    height: 1.1,
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  "A newer version of Bottle Sampling is available on the Store. Update your app to enjoy access to new features and improvements.",
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.9),
                    fontSize: 16,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 40),
                SizedBox(
                  width: double.infinity,
                  height: 60,
                  child: ElevatedButton(
                    onPressed: () {
                      widget.upgrader.sendUserToAppStore();
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white.withValues(alpha: 0.2),
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text(
                      "Update App",
                      style:
                          TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
                const SizedBox(height: 40),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
