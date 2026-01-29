import 'package:ubbottleapp/Constants/AppStorage.dart';
import 'package:ubbottleapp/Constants/Const.dart';
import 'package:ubbottleapp/ModelPages/InApplicationWebView/page/InApplicationWebView.dart';
import 'package:flutter/material.dart';

class WebViewFromBottomBar extends StatelessWidget {
  final String url;

  const WebViewFromBottomBar({super.key, required this.url});

  @override
  Widget build(BuildContext context) {
    final String weburl = Const.getFullWebUrl(url) +
        AppStorage().retrieveValue(AppStorage.SESSIONID);

    print(weburl);
    return InApplicationWebViewer(weburl);
  }
}
