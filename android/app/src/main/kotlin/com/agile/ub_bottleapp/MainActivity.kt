package com.agile.ub_bottleapp

import android.media.MediaScannerConnection
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterFragmentActivity() {
    private val CHANNEL = "com.agile.ub_bottleapp/media_scanner"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                if (call.method == "scanFile") {
                    val path = call.argument<String>("path")
                    MediaScannerConnection.scanFile(
                        this, arrayOf(path), null
                    ) { _, _ -> result.success(true) }
                } else {
                    result.notImplemented()
                }
            }
    }
}