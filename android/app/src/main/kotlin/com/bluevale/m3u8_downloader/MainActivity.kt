package com.bluevale.m3u8_downloader

import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    
    companion object {
        private const val TAG = "MainActivity"
        
        init {
            // ⚠️ 关键：在应用启动时立即加载 Rust 库
            // 这会执行 JNI_OnLoad 回调
            try {
                System.loadLibrary("rust_lib_m3u8_downloader")
                Log.i(TAG, "✅ Rust library loaded successfully")
            } catch (e: UnsatisfiedLinkError) {
                Log.e(TAG, "❌ Failed to load rust_lib_m3u8_downloader: ${e.message}", e)
                throw RuntimeException("Critical: Cannot load Rust library", e)
            }
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        Log.i(TAG, "✅ Flutter engine configured")
    }
}