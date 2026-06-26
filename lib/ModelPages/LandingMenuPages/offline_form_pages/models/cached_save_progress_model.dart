import 'package:get/get.dart';

class CachedSaveProgressModel {
  RxList<CachedSaveProgressItemModel> cachedSaveUpdateMap =
      <CachedSaveProgressItemModel>[].obs;
}

class CachedSaveProgressItemModel {
  final String axm_queueid;
  final int payloadsCount;
  final List<int> pushedAxmRecIds;
  final List<int> successAxmRecIds;
  final List<int> failedAxmRecIds;

  CachedSaveProgressItemModel(
      {required this.axm_queueid,
      required this.payloadsCount,
      required this.pushedAxmRecIds,
      this.successAxmRecIds = const [],
      this.failedAxmRecIds = const []});
}
