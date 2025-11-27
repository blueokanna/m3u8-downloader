# Keep MediaTranscoder class for JNI access from Rust
-keep class com.bluevale.m3u8_downloader.MediaTranscoder {
    public static *;
}

# Keep the transcode method specifically
-keepclassmembers class com.bluevale.m3u8_downloader.MediaTranscoder {
    public static boolean transcode(java.lang.String, java.lang.String, int, int);
}
