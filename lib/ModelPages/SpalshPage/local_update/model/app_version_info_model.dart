class AppVersionInfo {
  final String appVersion;
  final String apkUrl;
  final bool forceUpdate;

  AppVersionInfo({
    required this.appVersion,
    required this.apkUrl,
    required this.forceUpdate,
  });

  factory AppVersionInfo.fromJson(Map<String, dynamic> json) {
    return AppVersionInfo(
      appVersion: json['appVersion']?.toString() ?? '',
      apkUrl: json['apk']?.toString() ?? '',
      forceUpdate: json['forceUpdate'] == true,
    );
  }

  String get versionPart => appVersion.split('+').first;
  int get buildPart {
    final parts = appVersion.split('+');
    return parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0;
  }
}
