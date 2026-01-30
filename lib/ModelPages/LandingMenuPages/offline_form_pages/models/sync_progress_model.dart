import 'package:get/get.dart';
import 'package:intl/intl.dart';

class SyncProgressModel {
  RxInt totalItems = 0.obs;
  RxInt processedItems = 0.obs;
  RxInt successCount = 0.obs;
  RxInt failureCount = 0.obs;

  RxString message = "Initializing...".obs;
  RxString title = "Processing".obs;
  RxBool isLoading = true.obs;
  RxBool isCompleted = false.obs;
  List<Map<String, dynamic>> failedRecords = [];
  SyncProgressModel({String initialTitle = "Processing"}) {
    title.value = initialTitle;
  }

  void init({required int total, String msg = "Starting..."}) {
    totalItems.value = total;
    processedItems.value = 0;
    successCount.value = 0;
    failureCount.value = 0;
    message.value = msg;
    isLoading.value = true;
    isCompleted.value = false;
  }

  void addFailedRecord(int id, String error) {
    failedRecords.add({
      "id": id,
      "error": error,
      "timestamp": DateFormat('yyyy-MM-dd h:mm a').format(DateTime.now()),
    });
  }

  void clearFailedRecords() {
    failedRecords.clear();
  }

  void complete() {
    isLoading.value = false;
    isCompleted.value = true;
    processedItems.value = totalItems.value;
    message.value = "Process Completed";
  }

  void updateMessage(String msg) {
    message.value = msg;
  }

  void increment({bool isSuccess = true}) {
    processedItems.value++;
    if (isSuccess) {
      successCount.value++;
    } else {
      failureCount.value++;
    }
  }

  double get progressValue {
    if (totalItems.value == 0) return 0.0;
    if (processedItems.value > totalItems.value) return 1.0;
    return processedItems.value / totalItems.value;
  }
}
