// Copyright 2013 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:logcam/videoview.dart';
import 'package:video_player/video_player.dart';
import 'package:ffmpeg_kit_flutter_full_gpl/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_full_gpl/return_code.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:media_store_plus/media_store_plus.dart';
import 'package:wakelock/wakelock.dart';

const storagePath = 'DCIM/LogCam';
const dcimpath = '/storage/emulated/0/$storagePath';

/// Camera example home widget.
class CameraExampleHome extends StatefulWidget {
  /// Default Constructor
  const CameraExampleHome({Key? key}) : super(key: key);

  @override
  State<CameraExampleHome> createState() {
    return _CameraExampleHomeState();
  }
}

/// Returns a suitable camera icon for [direction].
IconData getCameraLensIcon(CameraLensDirection direction) {
  switch (direction) {
    case CameraLensDirection.back:
      return Icons.camera_rear;
    case CameraLensDirection.front:
      return Icons.camera_front;
    case CameraLensDirection.external:
      return Icons.camera;
  }
  // This enum is from a different package, so a new value could be added at
  // any time. The example should keep working if that happens.
  // ignore: dead_code
  return Icons.camera;
}

void _logError(String code, String? message) {
  // ignore: avoid_print
  print('Error: $code${message == null ? '' : '\nError Message: $message'}');
}

class _CameraExampleHomeState extends State<CameraExampleHome>
    with WidgetsBindingObserver, TickerProviderStateMixin {
  int? selectCam;
  CameraController? controller;
  XFile? imageFile;
  XFile? videoFile;
  VideoPlayerController? videoController;
  VoidCallback? videoPlayerListener;
  bool enableAudio = true;
  bool isProcessing = false;
  late AnimationController _flashModeControlRowAnimationController;
  late AnimationController _exposureModeControlRowAnimationController;
  double _minAvailableZoom = 1.0;
  double _maxAvailableZoom = 1.0;
  double _currentScale = 1.0;
  double _baseScale = 1.0;

  // Counting pointers (number of user fingers on screen)
  int _pointers = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);

    _flashModeControlRowAnimationController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _exposureModeControlRowAnimationController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _flashModeControlRowAnimationController.dispose();
    _exposureModeControlRowAnimationController.dispose();
    super.dispose();
  }

  // #docregion AppLifecycle
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final CameraController? cameraController = controller;

    // App state changed before we got the chance to initialize.
    if (cameraController == null || !cameraController.value.isInitialized) {
      return;
    }

    if (state == AppLifecycleState.inactive) {
      cameraController.dispose();
    } else if (state == AppLifecycleState.resumed) {
      onNewCameraSelected(cameraController.description);
    }
  }
  // #enddocregion AppLifecycle

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // appBar: AppBar(
      //   title: const Text('Camera example'),
      // ),
      body: Row(
        children: <Widget>[
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: Colors.black,
                border: Border.all(
                  color:
                      controller != null && controller!.value.isRecordingVideo
                          ? Colors.redAccent
                          : isProcessing
                              ? Colors.green
                              : Colors.grey,
                  width: 3.0,
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.all(1.0),
                child: Center(
                  child: _cameraPreviewWidget(),
                ),
              ),
            ),
          ),
          _captureControlRowWidget(),
        ],
      ),
    );
  }

  /// Display the preview from the camera (or a message if the preview is not available).
  Widget _cameraPreviewWidget() {
    final CameraController? cameraController = controller;

    if (cameraController == null || !cameraController.value.isInitialized) {
      return const Text(
        '切换你的摄像头(在右上角!)',
        style: TextStyle(
          color: Colors.white,
          fontSize: 24.0,
          fontWeight: FontWeight.w900,
        ),
      );
    } else {
      return Listener(
        onPointerDown: (_) => _pointers++,
        onPointerUp: (_) => _pointers--,
        child: CameraPreview(
          controller!,
          child: LayoutBuilder(
              builder: (BuildContext context, BoxConstraints constraints) {
            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onScaleStart: _handleScaleStart,
              onScaleUpdate: _handleScaleUpdate,
              onTapDown: (TapDownDetails details) =>
                  onViewFinderTap(details, constraints),
            );
          }),
        ),
      );
    }
  }

  void _handleScaleStart(ScaleStartDetails details) {
    _baseScale = _currentScale;
  }

  Future<void> _handleScaleUpdate(ScaleUpdateDetails details) async {
    // When there are not exactly two fingers on screen don't scale
    if (controller == null || _pointers != 2) {
      return;
    }

    _currentScale = (_baseScale * details.scale)
        .clamp(_minAvailableZoom, _maxAvailableZoom);

    await controller!.setZoomLevel(_currentScale);
  }

  /// Display the control bar with buttons to take pictures and record videos.
  Widget _captureControlRowWidget() {
    final CameraController? cameraController = controller;

    return Column(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: <Widget>[
        IconButton(
          icon: const Icon(Icons.cameraswitch),
          color: Colors.blue,
          tooltip: '切换摄像头',
          onPressed: _cameras.isNotEmpty ? onSwitchCameraButtonPressed : null,
        ),
        IconButton(
          icon: const Icon(Icons.camera_alt),
          color: Colors.blue,
          tooltip: '拍照',
          onPressed: cameraController != null &&
                  cameraController.value.isInitialized &&
                  !cameraController.value.isRecordingVideo
              ? onTakePictureButtonPressed
              : null,
        ),
        IconButton(
          tooltip: '录像',
          icon: Icon(cameraController != null &&
                  cameraController.value.isRecordingVideo
              ? Icons.stop
              : Icons.videocam),
          color: cameraController != null &&
                  cameraController.value.isRecordingVideo
              ? Colors.red
              : Colors.blue,
          onPressed:
              cameraController != null && cameraController.value.isInitialized
                  ? !cameraController.value.isRecordingVideo
                      ? onVideoRecordButtonPressed
                      : onStopButtonPressed
                  : null,
        ),
        const SizedBox(
          height: 1,
          width: 25,
          child: Divider(
            thickness: 0.5,
            color: Colors.black,
          ),
        ),
        IconButton(
            tooltip: '库',
            icon: const Icon(Icons.video_file),
            color: Colors.blue.shade900,
            onPressed: (() => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: ((context) => const VideoViewPage()))))),
      ],
    );
  }

  String timestamp() => DateTime.now().millisecondsSinceEpoch.toString();
  double timestampInt() => DateTime.now().millisecondsSinceEpoch / 1000;

  void showInSnackBar(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  void onViewFinderTap(TapDownDetails details, BoxConstraints constraints) {
    if (controller == null) {
      return;
    }

    final CameraController cameraController = controller!;

    final Offset offset = Offset(
      details.localPosition.dx / constraints.maxWidth,
      details.localPosition.dy / constraints.maxHeight,
    );
    cameraController.setExposurePoint(offset);
    cameraController.setFocusPoint(offset);
  }

  Future<void> onNewCameraSelected(CameraDescription cameraDescription) async {
    final CameraController? oldController = controller;
    if (oldController != null) {
      // `controller` needs to be set to null before getting disposed,
      // to avoid a race condition when we use the controller that is being
      // disposed. This happens when camera permission dialog shows up,
      // which triggers `didChangeAppLifecycleState`, which disposes and
      // re-creates the controller.
      controller = null;
      await oldController.dispose();
    }

    final CameraController cameraController = CameraController(
      cameraDescription,
      kIsWeb ? ResolutionPreset.max : ResolutionPreset.low,
      enableAudio: enableAudio,
      imageFormatGroup: ImageFormatGroup.jpeg,
    );

    controller = cameraController;

    // If the controller is updated then update the UI.
    cameraController.addListener(() {
      if (mounted) {
        setState(() {});
      }
      if (cameraController.value.hasError) {
        showInSnackBar(
            'Camera error ${cameraController.value.errorDescription}');
      }
    });

    try {
      await cameraController.initialize();
      await Future.wait(<Future<Object?>>[
        // The exposure mode is currently not supported on the web.
        ...!kIsWeb ? <Future<Object?>>[] : <Future<Object?>>[],
        cameraController
            .getMaxZoomLevel()
            .then((double value) => _maxAvailableZoom = value),
        cameraController
            .getMinZoomLevel()
            .then((double value) => _minAvailableZoom = value),
      ]);
    } on CameraException catch (e) {
      switch (e.code) {
        case 'CameraAccessDenied':
          showInSnackBar('没权限我录不了视频啊崽种');
          break;
        case 'CameraAccessDeniedWithoutPrompt':
          // iOS only
          showInSnackBar('请到设置中手动开启摄像头权限');
          break;
        case 'CameraAccessRestricted':
          // iOS only
          showInSnackBar('Camera access is restricted.');
          break;
        case 'AudioAccessDenied':
          showInSnackBar('没有录音权限捏');
          break;
        case 'AudioAccessDeniedWithoutPrompt':
          // iOS only
          showInSnackBar('Please go to Settings app to enable audio access.');
          break;
        case 'AudioAccessRestricted':
          // iOS only
          showInSnackBar('Audio access is restricted.');
          break;
        default:
          _showCameraException(e);
          break;
      }
    }

    if (mounted) {
      setState(() {});
    }
  }

  void onTakePictureButtonPressed() {
    takePicture().then((XFile? file) {
      if (mounted) {
        setState(() {
          videoController?.dispose();
          videoController = null;
        });
        final DateTime now = DateTime.now().toLocal();
        startTimeStr =
            '${now.year % 100}-${now.month}-${now.day}_${now.hour};${now.minute};${now.second}';
        final processPath = '$dcimpath/$startTimeStr.jpg';
        if (file != null) {
          FFmpegKit.execute("-i ${file.path}"
                  " -movflags use_metadata_tags"
                  " -vf \"drawtext=fontfile=/system/fonts/DroidSansMono.ttf"
                  ": text='%{localtime\\:%x %X}': fontcolor=white@0.5"
                  ": x=h/50: y=(h-text_h)-h/50: fontsize=h/25"
                  ": shadowcolor=black: shadowx=1: shadowy=1\""
                  " $processPath")
              .then((session) async {
            if (ReturnCode.isSuccess(await session.getReturnCode())) {
              showInSnackBar('文件已保存至 $processPath');
            } else {
              showInSnackBar('发生了一些错误');
              final String ret = (await session.getOutput()).toString();
              showDialog(
                  context: context,
                  builder: (_) => AlertDialog(
                        title: const Text("错误信息"),
                        content: SingleChildScrollView(
                            child: ListBody(
                          children: <Widget>[Text(ret)],
                        )),
                      ));
            }
            File(file.path).delete();
          });
        }
      }
    });
  }

  void onSwitchCameraButtonPressed() {
    if (selectCam != null) {
      if (_cameras.length > 1) {
        selectCam = (selectCam! + 1) % _cameras.length;
        onNewCameraSelected(_cameras[selectCam!]);
      }
    } else {
      if (_cameras.isNotEmpty) {
        selectCam = 0;
        onNewCameraSelected(_cameras[0]);
      }
    }
  }

  late double startTime;
  late String startTimeStr;

  void onVideoRecordButtonPressed() {
    startVideoRecording().then((_) {
      if (mounted) {
        setState(() {});
      }
      startTime = timestampInt();
      final DateTime now = DateTime.now().toLocal();
      startTimeStr =
          '${now.year % 100}-${now.month}-${now.day}_${now.hour};${now.minute};${now.second}';
    });
  }

  void onStopButtonPressed() {
    final that = this;
    stopVideoRecording().then((XFile? file) {
      if (mounted) {
        setState(() {});
      }
      if (file != null) {
        final String processPath = '${file.path}-out.mp4';
        showInSnackBar('我们正在处理你的视频!请稍等...');
        that.setState(() {
          isProcessing = true;
        });
        FFmpegKit.execute("-i ${file.path}"
                " -vcodec libx264 -crf 30"
                " -movflags use_metadata_tags"
                " -vf \"drawtext=fontfile=/system/fonts/DroidSansMono.ttf"
                ": text='%{pts\\:localtime\\:$startTime\\:%x %X}': fontcolor=white@0.5"
                ": x=h/50: y=(h-text_h)-h/50: fontsize=h/25"
                ": shadowcolor=black: shadowx=1: shadowy=1\""
                " -c:a aac -b:a 8k"
                " $processPath")
            .then((session) async {
          that.setState(() {
            isProcessing = false;
          });
          if (ReturnCode.isSuccess(await session.getReturnCode())) {
            final outPath = '$dcimpath/$startTimeStr.mp4';
            File(processPath).copy(outPath);
            File(processPath).delete();
            File(file.path).delete();
            showInSnackBar('视频已保存至 $outPath');
          } else {
            showInSnackBar('视频尾处理发生了一些错误。');
            final String ret = (await session.getOutput()).toString();
            showDialog(
                context: context,
                builder: (_) => AlertDialog(
                      title: const Text("错误信息"),
                      content: SingleChildScrollView(
                          child: ListBody(
                        children: <Widget>[Text(ret)],
                      )),
                    ));
          }
        });
      }
    });
  }

  Future<void> startVideoRecording() async {
    final CameraController? cameraController = controller;

    if (cameraController == null || !cameraController.value.isInitialized) {
      showInSnackBar('Error: select a camera first.');
      return;
    }

    if (cameraController.value.isRecordingVideo) {
      // A recording is already started, do nothing.
      return;
    }

    try {
      await cameraController.startVideoRecording();
      Wakelock.enable();
    } on CameraException catch (e) {
      _showCameraException(e);
      return;
    }
  }

  Future<XFile?> takePicture() async {
    final CameraController? cameraController = controller;
    if (cameraController == null || !cameraController.value.isInitialized) {
      showInSnackBar('Error: select a camera first.');
      return null;
    }

    if (cameraController.value.isTakingPicture) {
      // A capture is already pending, do nothing.
      return null;
    }

    try {
      final XFile file = await cameraController.takePicture();
      return file;
    } on CameraException catch (e) {
      _showCameraException(e);
      return null;
    }
  }

  Future<XFile?> stopVideoRecording() async {
    final CameraController? cameraController = controller;

    if (cameraController == null || !cameraController.value.isRecordingVideo) {
      return null;
    }

    try {
      Wakelock.disable();
      return cameraController.stopVideoRecording();
    } on CameraException catch (e) {
      _showCameraException(e);
      return null;
    }
  }

  Future<void> pauseVideoRecording() async {
    final CameraController? cameraController = controller;

    if (cameraController == null || !cameraController.value.isRecordingVideo) {
      return;
    }

    try {
      await cameraController.pauseVideoRecording();
    } on CameraException catch (e) {
      _showCameraException(e);
      rethrow;
    }
  }

  Future<void> resumeVideoRecording() async {
    final CameraController? cameraController = controller;

    if (cameraController == null || !cameraController.value.isRecordingVideo) {
      return;
    }

    try {
      await cameraController.resumeVideoRecording();
    } on CameraException catch (e) {
      _showCameraException(e);
      rethrow;
    }
  }

  Future<void> setFlashMode(FlashMode mode) async {
    if (controller == null) {
      return;
    }

    try {
      await controller!.setFlashMode(mode);
    } on CameraException catch (e) {
      _showCameraException(e);
      rethrow;
    }
  }

  Future<void> setExposureMode(ExposureMode mode) async {
    if (controller == null) {
      return;
    }

    try {
      await controller!.setExposureMode(mode);
    } on CameraException catch (e) {
      _showCameraException(e);
      rethrow;
    }
  }

  void _showCameraException(CameraException e) {
    _logError(e.code, e.description);
    showInSnackBar('错误: ${e.code}\n${e.description}');
  }
}

/// CameraApp is the Main Application.
class CameraApp extends StatelessWidget {
  /// Default Constructor
  const CameraApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      home: CameraExampleHome(),
    );
  }
}

List<CameraDescription> _cameras = <CameraDescription>[];

final mediaStorePlugin = MediaStore();

Future<void> main() async {
  // Fetch the available cameras before initializing the app.
  try {
    WidgetsFlutterBinding.ensureInitialized();
    _cameras = await availableCameras();
  } on CameraException catch (e) {
    _logError(e.code, e.description);
  }
  List<Permission> permissions = [
    Permission.storage,
  ];

  if (!kIsWeb) {
    if ((await mediaStorePlugin.getPlatformSDKInt()) >= 33) {
      permissions.add(Permission.photos);
      permissions.add(Permission.audio);
      permissions.add(Permission.videos);
      permissions.add(Permission.manageExternalStorage);
    }
    await permissions.request();
  }
  final path = Directory(dcimpath);
  if (!(await path.exists())) {
    await path.create();
  }
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.leanBack);
  runApp(const CameraApp());
}