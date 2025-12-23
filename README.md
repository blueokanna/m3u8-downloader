# Core Documentation: M3U8 Downloader & Transcoder / M3U8 下载器与转码器核心文档

[English](#english) | [中文](#chinese)

---

<a id="english"></a>

## English

### 1. Project Overview

This project is a cross-platform application designed to download M3U8 HLS (HTTP Live Streaming) videos and transcode them into MP4 format. It leverages **Flutter** for the user interface and **Rust** for high-performance networking, file handling, and media processing. The communication between Flutter and Rust is bridged using `flutter_rust_bridge`.

### 2. Architecture

The application follows a hybrid architecture:

*   **Frontend (Dart/Flutter)**: Handles user interaction, permission requests, file picking, and displays progress updates.
*   **Backend (Rust)**: Executes the core logic including playlist parsing, concurrent segment downloading, decryption (AES-128), merging, and transcoding.
*   **Bridge**: `flutter_rust_bridge` generates the FFI binding code allowing Dart to call Rust functions asynchronously and receive stream updates.

### 3. Rust Backend Core (`rust/src/api/downloader.rs`)

The Rust backend is the engine of the application. Key functionalities are encapsulated in `downloader.rs`.

#### 3.1 Main Workflow (`hls2mp4_run`)

The entry point for the download task is the `hls2mp4_run` function. Its lifecycle involves:

1.  **Initialization**: Sets up logging (Android vs. Desktop) and progress bars.
2.  **Backend Selection**: Determines whether to use FFmpeg (with hardware acceleration detection) or Android MediaCodec.
3.  **Playlist Parsing**: Downloads and parses the Master or Media playlist using `m3u8-rs`.
    *   If a Master playlist is found, it selects the variant with the highest bandwidth.
4.  **Temporary Directory**: Selects a writable temporary directory (crucial for Android).
5.  **Download & Merge**: Calls `download_and_merge` to fetch segments.
6.  **Transcoding**: Calls `convert_to_mp4` to convert the merged TS file to MP4.
7.  **Cleanup**: Removes temporary files if configured.

#### 3.2 Downloading & Merging (`download_and_merge`)

This function handles the retrieval of video segments:

*   **Concurrency**: Uses `tokio::spawn` and `futures::stream` to download segments in parallel, controlled by a semaphore.
*   **Decryption**: Detects AES-128 encryption in the playlist. If present, it fetches the key and IV, and decrypts segments on the fly using `aes::Aes128` and `block_modes`.
*   **Merging**: Downloads segments to a temporary directory and then concatenates them into a single `.ts` file in order.

#### 3.3 Transcoding (`convert_to_mp4`)

The project supports two transcoding strategies:

1.  **FFmpeg (Desktop/General)**:
    *   Checks for `ffmpeg` availability.
    *   Detects hardware acceleration (Nvidia `h264_nvenc`, AMD `h264_amf`) or falls back to CPU (`libx264`).
    *   Constructs and executes the FFmpeg command line.

2.  **Android MediaCodec (Android Only)**:
    *   Uses JNI (Java Native Interface) to invoke Java classes.
    *   Relies on a custom `AndroidMediaCodecTranscoder` struct.
    *   Calls Java methods to perform hardware-accelerated transcoding directly on the device.

#### 3.4 Android Specifics (JNI)

The Rust code includes significant JNI integration for Android:

*   **Context Management**: `init_android_context` and `get_android_context` manage the Android Application Context.
*   **Directory Resolution**: Functions like `get_app_cache_dir` and `get_external_files_dir` call Android APIs via JNI to find valid storage paths.
*   **Transcoder Registration**: `register_android_mediacodec_transcoder` caches the Java class reference for the transcoder to be used during the conversion phase.

### 4. Flutter Frontend Core (`lib/main.dart`)

The Flutter side provides the GUI and orchestrates the process.

#### 4.1 User Interface
*   **Input Fields**: URL, Output Filename, Concurrency, Retries, Bitrates.
*   **File Picker**: Uses `file_picker` to select the output directory securely.
*   **Theme**: Supports Light/Dark modes and dynamic seed colors.

#### 4.2 Logic & State
*   **Permissions**: Requests `storage` and `manageExternalStorage` permissions on Android to ensure the app can write to the selected directories.
*   **Rust Initialization**: Calls `RustLib.init()` on startup.
*   **Stream Listening**: The `_startDownload` method listens to the stream returned by `hls2Mp4Run`. It updates the UI with progress messages (`ProgressUpdate`) and handles success/failure states.

### 5. Key Features

*   **Resumable/Robust Downloads**: Configurable retries for network requests.
*   **Security**: Support for HLS AES-128 encryption.
*   **Performance**:
    *   Asynchronous I/O with Tokio.
    *   Parallel segment downloading.
    *   Hardware accelerated transcoding where available.
*   **Cross-Platform**: Specific optimizations for Android (JNI/MediaCodec) while maintaining compatibility with Windows/Linux/macOS (FFmpeg).

---

<a id="chinese"></a>

## 中文 (Chinese)

### 1. 项目概览

本项目是一个跨平台的应用程序，旨在下载 M3U8 HLS (HTTP Live Streaming) 视频并将其转码为 MP4 格式。它利用 **Flutter** 构建用户界面，利用 **Rust** 进行高性能网络通信、文件处理和媒体处理。Flutter 和 Rust 之间的通信通过 `flutter_rust_bridge` 桥接。

### 2. 架构

应用程序遵循混合架构：

*   **前端 (Dart/Flutter)**：处理用户交互、权限请求、文件选择，并显示进度更新。
*   **后端 (Rust)**：执行核心逻辑，包括播放列表解析、并发分片下载、解密 (AES-128)、合并和转码。
*   **桥接层**：`flutter_rust_bridge` 生成 FFI 绑定代码，允许 Dart 异步调用 Rust 函数并接收流更新。

### 3. Rust 后端核心 (`rust/src/api/downloader.rs`)

Rust 后端是应用程序的引擎。关键功能封装在 `downloader.rs` 中。

#### 3.1 主工作流 (`hls2mp4_run`)

下载任务的入口点是 `hls2mp4_run` 函数。其生命周期包括：

1.  **初始化**：设置日志记录（Android 与 桌面端）和进度条。
2.  **后端选择**：决定是使用 FFmpeg（带硬件加速检测）还是 Android MediaCodec。
3.  **播放列表解析**：使用 `m3u8-rs` 下载并解析 Master 或 Media 播放列表。
    *   如果发现 Master 播放列表，它会选择带宽最高的变体。
4.  **临时目录**：选择一个可写的临时目录（对 Android 至关重要）。
5.  **下载与合并**：调用 `download_and_merge` 获取分片。
6.  **转码**：调用 `convert_to_mp4` 将合并后的 TS 文件转换为 MP4。
7.  **清理**：如果配置了清理，则删除临时文件。

#### 3.2 下载与合并 (`download_and_merge`)

此函数处理视频分片的检索：

*   **并发**：使用 `tokio::spawn` 和 `futures::stream` 并行下载分片，由信号量控制。
*   **解密**：检测播放列表中的 AES-128 加密。如果存在，它会获取密钥和 IV，并使用 `aes::Aes128` 和 `block_modes` 实时解密分片。
*   **合并**：将分片下载到临时目录，然后按顺序将它们连接成单个 `.ts` 文件。

#### 3.3 转码 (`convert_to_mp4`)

项目支持两种转码策略：

1.  **FFmpeg (桌面/通用)**：
    *   检查 `ffmpeg` 可用性。
    *   检测硬件加速（Nvidia `h264_nvenc`, AMD `h264_amf`）或回退到 CPU (`libx264`)。
    *   构建并执行 FFmpeg 命令行。

2.  **Android MediaCodec (仅限 Android)**：
    *   使用 JNI (Java Native Interface) 调用 Java 类。
    *   依赖自定义的 `AndroidMediaCodecTranscoder` 结构体。
    *   调用 Java 方法直接在设备上执行硬件加速转码。

#### 3.4 Android 特性 (JNI)

Rust 代码包含用于 Android 的大量 JNI 集成：

*   **上下文管理**：`init_android_context` 和 `get_android_context` 管理 Android 应用程序上下文。
*   **目录解析**：`get_app_cache_dir` 和 `get_external_files_dir` 等函数通过 JNI 调用 Android API 以查找有效的存储路径。
*   **转码器注册**：`register_android_mediacodec_transcoder` 缓存转码器的 Java 类引用，以便在转换阶段使用。

### 4. Flutter Frontend Core (`lib/main.dart`)

Flutter 端提供 GUI 并编排流程。

#### 4.1 用户界面
*   **输入字段**：URL、输出文件名、并发数、重试次数、码率。
*   **文件选择器**：使用 `file_picker` 安全地选择输出目录。
*   **主题**：支持亮色/暗色模式和动态种子颜色。

#### 4.2 逻辑与状态
*   **权限**：在 Android 上请求 `storage` 和 `manageExternalStorage` 权限，以确保应用可以写入选定的目录。
*   **Rust 初始化**：在启动时调用 `RustLib.init()`。
*   **流监听**：`_startDownload` 方法监听 `hls2Mp4Run` 返回的流。它使用进度消息 (`ProgressUpdate`) 更新 UI 并处理成功/失败状态。

### 5. 关键特性

*   **可恢复/健壮的下载**：针对网络请求的可配置重试。
*   **安全性**：支持 HLS AES-128 加密。
*   **性能**：
    *   使用 Tokio 进行异步 I/O。
    *   并行分片下载。
    *   在可用时进行硬件加速转码。
*   **跨平台**：针对 Android (JNI/MediaCodec) 进行了特定优化，同时保持与 Windows/Linux/macOS (FFmpeg) 的兼容性。
