import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:m3u8_downloader/src/rust/api/downloader.dart';
import 'package:m3u8_downloader/src/rust/frb_generated.dart';
import 'package:permission_handler/permission_handler.dart';

Future<void> requestStoragePermissions() async {
  if (Platform.isAndroid) {
    // Request multiple permissions for better compatibility
    Map<Permission, PermissionStatus> statuses = await [
      Permission.storage,
      Permission.manageExternalStorage,
    ].request();

    if (statuses[Permission.manageExternalStorage]?.isGranted == true) {
      debugPrint('Manage External Storage permission granted');
    } else if (statuses[Permission.storage]?.isGranted == true) {
      debugPrint('Storage permission granted');
    } else {
      debugPrint('Storage permissions denied');
    }
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  requestStoragePermissions();

  try {
    await RustLib.init();
    debugPrint('✅ RustLib initialized successfully');
  } catch (e, s) {
    debugPrint('❌ RustLib init failed: $e\n$s');
    rethrow;
  }

  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  Color _seedColor = Colors.teal;
  ThemeMode _themeMode = ThemeMode.system;

  void _updateSeedColor(Color color) {
    setState(() {
      _seedColor = color;
    });
  }

  void _updateThemeMode(ThemeMode mode) {
    setState(() {
      _themeMode = mode;
    });
  }

  @override
  Widget build(BuildContext context) {
    final lightScheme = ColorScheme.fromSeed(
      seedColor: _seedColor,
      brightness: Brightness.light,
    );
    final darkScheme = ColorScheme.fromSeed(
      seedColor: _seedColor,
      brightness: Brightness.dark,
    );

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'M3U8 Video Downloader',
      themeMode: _themeMode,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: lightScheme,
        inputDecorationTheme: const InputDecorationTheme(
          border: OutlineInputBorder(),
          filled: true,
        ),
        cardTheme: const CardThemeData(
          margin: EdgeInsets.symmetric(vertical: 8),
        ),
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        colorScheme: darkScheme,
        inputDecorationTheme: const InputDecorationTheme(
          border: OutlineInputBorder(),
          filled: true,
        ),
        cardTheme: const CardThemeData(
          margin: EdgeInsets.symmetric(vertical: 8),
        ),
      ),
      home: DownloadPage(
        seedColor: _seedColor,
        themeMode: _themeMode,
        onSeedColorChanged: _updateSeedColor,
        onThemeModeChanged: _updateThemeMode,
      ),
    );
  }
}

class DownloadPage extends StatefulWidget {
  const DownloadPage({
    super.key,
    required this.seedColor,
    required this.themeMode,
    required this.onSeedColorChanged,
    required this.onThemeModeChanged,
  });

  final Color seedColor;
  final ThemeMode themeMode;
  final ValueChanged<Color> onSeedColorChanged;
  final ValueChanged<ThemeMode> onThemeModeChanged;

  @override
  State<DownloadPage> createState() => _DownloadPageState();
}

class _DownloadPageState extends State<DownloadPage> {
  final _formKey = GlobalKey<FormState>();

  final _urlController = TextEditingController();
  final _outputController = TextEditingController(text: 'output.mp4');
  final _concurrencyController = TextEditingController(text: '8');
  final _retriesController = TextEditingController(text: '3');
  final _videoBitrateController = TextEditingController(text: '0');
  final _audioBitrateController = TextEditingController(text: '0');

  bool _keepTemp = false;
  bool _isRunning = false;
  double _progress = 0.0;

  String? _outputDirectory;
  String? _statusMessage;
  String? _errorMessage;

  @override
  void dispose() {
    _urlController.dispose();
    _outputController.dispose();
    _concurrencyController.dispose();
    _retriesController.dispose();
    _videoBitrateController.dispose();
    _audioBitrateController.dispose();
    super.dispose();
  }

  /// 选择输出目录（使用 file_picker，Android 15+ 会走系统文档选择器）
  Future<void> _pickOutputDirectory() async {
    if (_isRunning) return;

    final selectedDirectory = await FilePicker.platform.getDirectoryPath(
      dialogTitle: '选择输出目录',
    );

    if (!mounted || selectedDirectory == null) return;

    setState(() {
      _outputDirectory = selectedDirectory;
    });
  }

  /// 组合最终输出路径：目录 + 文件名
  String _buildOutputPath() {
    final fileName = _outputController.text.trim();
    if (_outputDirectory == null || _outputDirectory!.isEmpty) {
      return fileName;
    }

    final sep = Platform.pathSeparator;
    if (_outputDirectory!.endsWith(sep)) {
      return '$_outputDirectory$fileName';
    }
    return '$_outputDirectory$sep$fileName';
  }

  Future<void> _startDownload() async {
    final messenger = ScaffoldMessenger.of(context);

    if (!_formKey.currentState!.validate()) {
      messenger.showSnackBar(const SnackBar(content: Text('请先修正表单中的错误')));
      return;
    }

    final url = _urlController.text.trim();
    final output = _buildOutputPath();
    final concurrency = int.parse(_concurrencyController.text.trim());
    final retries = int.parse(_retriesController.text.trim());
    final videoBitrate = int.parse(_videoBitrateController.text.trim());
    final audioBitrate = int.parse(_audioBitrateController.text.trim());

    setState(() {
      _isRunning = true;
      _statusMessage = 'Checking environment and starting download...';
      _errorMessage = null;
      _progress = 0.0;
    });

    try {
      final stream = hls2Mp4Run(
        url: url,
        concurrency: concurrency,
        output: output,
        retries: retries,
        videoBitrate: videoBitrate,
        audioBitrate: audioBitrate,
        keepTemp: _keepTemp,
      );

      await for (final event in stream) {
        if (!mounted) break;
        setState(() {
          _statusMessage = event.message;
          _progress = event.progress;
        });
      }

      if (!mounted) return;

      setState(() {
        _statusMessage = '✅ 任务完成：$output';
        _errorMessage = null;
        _progress = 1.0;
      });

      messenger.showSnackBar(
        SnackBar(
          content: Text('下载并转码完成：$output'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e, s) {
      debugPrint('下载失败: $e\n$s');
      if (!mounted) return;

      setState(() {
        _errorMessage = '❌ 任务失败：$e';
        _statusMessage = null;
      });

      messenger.showSnackBar(
        SnackBar(content: Text('任务失败：$e'), behavior: SnackBarBehavior.floating),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isRunning = false;
        });
      }
    }
  }

  String _platformHint() {
    if (Platform.isWindows) {
      return 'Example: C:\\Users\\you\\Videos\\output.mp4';
    } else if (Platform.isAndroid) {
      return 'Note: Write storage permissions (e.g., /sdcard/Downloads/) are required. Please ensure that the appropriate permissions are declared in AndroidManifest.';
    }
    return '';
  }

  void _openThemeSettings() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      useSafeArea: true,
      builder: (context) {
        final theme = Theme.of(context);
        final colorScheme = theme.colorScheme;

        final presetColors = <Color>[
          Colors.blue,
          Colors.green,
          Colors.teal,
          Colors.deepPurple,
          Colors.orange,
          Colors.pink,
          Colors.red,
          Colors.brown,
          Colors.black,
        ];

        ThemeMode selectedMode = widget.themeMode;

        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Theme settings', style: theme.textTheme.titleLarge),
              const SizedBox(height: 16),
              Text('Theme Mode', style: theme.textTheme.titleMedium),
              const SizedBox(height: 8),
              SegmentedButton<ThemeMode>(
                segments: const [
                  ButtonSegment(
                    value: ThemeMode.system,
                    icon: Icon(Icons.brightness_auto),
                    label: Text('Follow system'),
                  ),
                  ButtonSegment(
                    value: ThemeMode.light,
                    icon: Icon(Icons.light_mode),
                    label: Text('Light Mode'),
                  ),
                  ButtonSegment(
                    value: ThemeMode.dark,
                    icon: Icon(Icons.dark_mode),
                    label: Text('Dark Mode'),
                  ),
                ],
                selected: {selectedMode},
                showSelectedIcon: false,
                onSelectionChanged: (values) {
                  final mode = values.first;
                  selectedMode = mode;
                  widget.onThemeModeChanged(mode);
                },
              ),
              const SizedBox(height: 16),
              Text('Theme color', style: theme.textTheme.titleMedium),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final color in presetColors)
                    ChoiceChip(
                      label: const Text(''),
                      selectedColor: colorScheme.primaryContainer,
                      side: BorderSide(
                        color: widget.seedColor == color
                            ? colorScheme.primary
                            : Colors.transparent,
                        width: 2,
                      ),
                      shape: const StadiumBorder(),
                      avatar: CircleAvatar(backgroundColor: color),
                      selected: widget.seedColor == color,
                      onSelected: (_) {
                        widget.onSeedColorChanged(color);
                      },
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Selecting different seed colors allows for a quick preview of Material 3 dynamic color scheme effects.',
                style: theme.textTheme.bodySmall,
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('M3U8 Video Downloader'),
        centerTitle: true,
        actions: [
          IconButton(
            tooltip: 'Theme settings',
            icon: const Icon(Icons.color_lens_outlined),
            onPressed: _openThemeSettings,
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final isWide = constraints.maxWidth >= 720;

              final formContent = Form(
                key: _formKey,
                child: ListView(
                  children: [
                    // 基本信息卡片
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Basic Information',
                              style: theme.textTheme.titleLarge,
                            ),
                            const SizedBox(height: 16),
                            TextFormField(
                              controller: _urlController,
                              enabled: !_isRunning,
                              decoration: const InputDecoration(
                                labelText: 'M3U8 URL or local path',
                                hintText: 'https://example.com/index.m3u8',
                                prefixIcon: Icon(Icons.link),
                              ),
                              validator: (value) {
                                if (value == null || value.trim().isEmpty) {
                                  return 'Please enter a URL or file path.';
                                }
                                return null;
                              },
                            ),
                            const SizedBox(height: 12),
                            TextFormField(
                              controller: _outputController,
                              enabled: !_isRunning,
                              decoration: const InputDecoration(
                                labelText: 'Output file name (MP4)',
                                prefixIcon: Icon(Icons.save_alt),
                                helperText:
                                    'Filename only, without directory, for example, output.mp4',
                              ),
                              validator: (value) {
                                if (value == null || value.trim().isEmpty) {
                                  return 'Please enter the output file name.';
                                }
                                if (!value.toLowerCase().endsWith('.mp4')) {
                                  return 'The file should end with .mp4';
                                }
                                return null;
                              },
                            ),
                          ],
                        ),
                      ),
                    ),

                    // 输出位置卡片
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Output position',
                              style: theme.textTheme.titleLarge,
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    _outputDirectory == null ||
                                            _outputDirectory!.isEmpty
                                        ? 'No selection selected, use the default working directory.'
                                        : _outputDirectory!,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: theme.textTheme.bodyMedium,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                FilledButton.icon(
                                  onPressed: _isRunning
                                      ? null
                                      : () => _pickOutputDirectory(),
                                  icon: const Icon(Icons.folder_open),
                                  label: const Text('Select directory'),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),

                    // 高级参数卡片
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Advanced parameters',
                              style: theme.textTheme.titleLarge,
                            ),
                            const SizedBox(height: 16),
                            Row(
                              children: [
                                Expanded(
                                  child: TextFormField(
                                    controller: _concurrencyController,
                                    enabled: !_isRunning,
                                    keyboardType: TextInputType.number,
                                    decoration: const InputDecoration(
                                      labelText: '并发数',
                                      helperText: '建议 4 ~ 16',
                                    ),
                                    validator: (value) {
                                      final v = int.tryParse(
                                        value?.trim() ?? '',
                                      );
                                      if (v == null) return '需为整数';
                                      if (v <= 0 || v > 64) {
                                        return '范围 1-64';
                                      }
                                      return null;
                                    },
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: TextFormField(
                                    controller: _retriesController,
                                    enabled: !_isRunning,
                                    keyboardType: TextInputType.number,
                                    decoration: const InputDecoration(
                                      labelText: '重试次数',
                                    ),
                                    validator: (value) {
                                      final v = int.tryParse(
                                        value?.trim() ?? '',
                                      );
                                      if (v == null) return '需为整数';
                                      if (v < 0 || v > 10) {
                                        return '范围 0-10';
                                      }
                                      return null;
                                    },
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Expanded(
                                  child: TextFormField(
                                    controller: _videoBitrateController,
                                    enabled: !_isRunning,
                                    keyboardType: TextInputType.number,
                                    decoration: const InputDecoration(
                                      labelText: '视频码率 (kbps)',
                                      helperText: '0 = 自动',
                                    ),
                                    validator: (value) {
                                      final v = int.tryParse(
                                        value?.trim() ?? '',
                                      );
                                      return v != null && v >= 0
                                          ? null
                                          : 'Must be a non-negative integer';
                                    },
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: TextFormField(
                                    controller: _audioBitrateController,
                                    enabled: !_isRunning,
                                    keyboardType: TextInputType.number,
                                    decoration: const InputDecoration(
                                      labelText: '音频码率 (kbps)',
                                      helperText: '0 = 自动',
                                    ),
                                    validator: (value) {
                                      final v = int.tryParse(
                                        value?.trim() ?? '',
                                      );
                                      return v != null && v >= 0
                                          ? null
                                          : 'Must be a non-negative integer';
                                    },
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            SwitchListTile(
                              value: _keepTemp,
                              onChanged: _isRunning
                                  ? null
                                  : (v) {
                                      setState(() => _keepTemp = v);
                                    },
                              title: const Text(
                                'Retain temporary TS video files',
                              ),
                              subtitle: const Text(
                                'For debugging or subsequent processing',
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 16),

                    // 执行按钮 + 顶部线性进度
                    if (_isRunning)
                      LinearProgressIndicator(
                        value: _progress > 0 ? _progress : null,
                        minHeight: 4,
                      ),
                    const SizedBox(height: 8),
                    FilledButton.icon(
                      icon: _isRunning
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.play_arrow),
                      label: Text(
                        _isRunning
                            ? 'Executing...'
                            : 'Start downloading and transcoding',
                      ),
                      onPressed: _isRunning ? null : _startDownload,
                    ),
                  ],
                ),
              );

              final statusPanel = ListView(
                children: [
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Task status',
                            style: theme.textTheme.titleLarge,
                          ),
                          const SizedBox(height: 8),
                          if (_statusMessage != null)
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Icon(
                                  Icons.check_circle_outline,
                                  color: theme.colorScheme.primary,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    _statusMessage!,
                                    style: theme.textTheme.bodyMedium?.copyWith(
                                      color: theme.colorScheme.primary,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          if (_errorMessage != null)
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Icon(
                                  Icons.error_outline,
                                  color: theme.colorScheme.error,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    _errorMessage!,
                                    style: theme.textTheme.bodyMedium?.copyWith(
                                      color: theme.colorScheme.error,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          if (_statusMessage == null && _errorMessage == null)
                            Text(
                              'No tasks available. Fill out the form and click the button below to start downloading.。',
                              style: theme.textTheme.bodyMedium,
                            ),
                          const SizedBox(height: 12),
                          Text(
                            _platformHint(),
                            style: theme.textTheme.bodySmall?.copyWith(
                              color:
                                  isDark ? Colors.grey[400] : Colors.grey[700],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              );

              if (isWide) {
                return Row(
                  children: [
                    Expanded(flex: 3, child: formContent),
                    const SizedBox(width: 16),
                    Expanded(flex: 2, child: statusPanel),
                  ],
                );
              }

              // 窄屏：上下布局
              return Column(
                children: [
                  Expanded(flex: 3, child: formContent),
                  const SizedBox(height: 8),
                  SizedBox(height: 180, child: statusPanel),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
