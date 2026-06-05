import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
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
            // gradient: LinearGradient(
            //   begin: Alignment.topCenter,
            //   end: Alignment.bottomCenter,
            //   colors: [Color(0xFF4A80F0), Color(0xFF1C54D4)],
            // ),
            image: DecorationImage(
                image: AssetImage("assets/images/update_bg.png"),
                fit: BoxFit.cover)),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 30),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(height: (Get.height) * 0.3),
                // Expanded(
                //   child: Lottie.asset(
                //     'assets/lotties/update_app.json',
                //     height: 300,
                //   ),
                // ),
                Text(
                  "New\nUpdate",
                  style: GoogleFonts.poppins(
                    color: Colors.deepPurple,
                    fontSize: 48,
                    fontWeight: FontWeight.w600,
                    height: 1.1,
                  ),
                ),
                Text(
                  "Available!",
                  style: GoogleFonts.poppins(
                    color: Colors.purple,
                    fontSize: 48,
                    fontWeight: FontWeight.w600,
                    height: 1.1,
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  "A newer version of Bottle Sampling is\navailable on the Store. Update your app\nto enjoy access to new features and\nimprovements.",
                  style: GoogleFonts.poppins(
                    color: Colors.black.withValues(alpha: 0.9),
                    fontSize: 16,
                    height: 1.4,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                // Expanded(
                //   child: Container(
                //     decoration: BoxDecoration(
                //       color: Colors.white,
                //     ),
                //   ),
                // ),
                Spacer(),
                UpdateHighlightsCard(),
                Spacer(),
                SizedBox(
                  width: double.infinity,
                  height: 60,
                  child: ElevatedButton(
                    onPressed: () {
                      widget.upgrader.sendUserToAppStore();
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.deepPurple.withValues(alpha: 0.2),
                      foregroundColor: Colors.deepPurple,
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

class UpdateHighlightsCard extends StatelessWidget {
  const UpdateHighlightsCard({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: EdgeInsets.symmetric(vertical: 10),
      padding: const EdgeInsets.symmetric(
        horizontal: 10,
        vertical: 15,
      ),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(.92),
        borderRadius: BorderRadius.circular(15),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(.04),
            blurRadius: 30,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Row(
        children: const [
          Expanded(
            child: _FeatureItem(
              icon: Icons.card_giftcard_rounded,
              iconColor: Color(0xFFFF7A59),
              backgroundColor: Color(0xFFFFF1EC),
              title: "New\nFeatures",
              subtitle: "Exciting new\ncapabilities",
            ),
          ),
          _VerticalDivider(),
          Expanded(
            child: _FeatureItem(
              icon: Icons.bolt_rounded,
              iconColor: Color(0xFFFFA726),
              backgroundColor: Color(0xFFFFF4E5),
              title: "Better Performance",
              subtitle: "Enhanced speed\nand stability",
            ),
          ),
          _VerticalDivider(),
          Expanded(
            child: _FeatureItem(
              icon: Icons.verified_user_rounded,
              iconColor: Color(0xFF9C6BFF),
              backgroundColor: Color(0xFFF4EDFF),
              title: "Improved Experience",
              subtitle: "Smoother and more\nintuitive",
            ),
          ),
        ],
      ),
    );
  }
}

class _VerticalDivider extends StatelessWidget {
  const _VerticalDivider();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 120,
      margin: const EdgeInsets.symmetric(horizontal: 8),
      color: const Color(0xFFEAEAF2),
    );
  }
}

class _FeatureItem extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final Color backgroundColor;
  final String title;
  final String subtitle;

  const _FeatureItem({
    required this.icon,
    required this.iconColor,
    required this.backgroundColor,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: 62,
          height: 62,
          decoration: BoxDecoration(
            color: backgroundColor,
            shape: BoxShape.circle,
          ),
          child: Icon(
            icon,
            size: 26,
            color: iconColor,
          ),
        ),
        const SizedBox(height: 15),
        Text(
          title,
          textAlign: TextAlign.center,
          style: GoogleFonts.poppins(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: Color(0xFF121826),
          ),
        ),
        const SizedBox(height: 5),
        Text(
          subtitle,
          textAlign: TextAlign.center,
          style: GoogleFonts.poppins(
            fontSize: 10,
            height: 1.5,
            color: Color(0xFF7B849A),
          ),
        ),
      ],
    );
  }
}
