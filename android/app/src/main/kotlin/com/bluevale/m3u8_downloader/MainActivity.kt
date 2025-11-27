package com.bluevale.m3u8_downloader

import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {
    companion object {
        init {
            System.loadLibrary("rust_lib_m3u8_downloader")
        }
    }
}
