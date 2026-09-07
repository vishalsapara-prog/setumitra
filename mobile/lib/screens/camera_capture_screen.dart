import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:path_provider/path_provider.dart';
import '../models/camera_settings_model.dart';
import '../services/image_processing_service.dart';

/// Live in-app camera capture screen, replacing the previous
/// image_picker-based "launch the OS camera app" flow. A real in-app
/// preview is required to honor the approved Camera Settings
/// (resolution, grid overlay, flash) at capture time — none of that is
/// controllable through image_picker's simple camera launcher.
///
/// Runs the full approved workflow on capture: resolution/flash already
/// applied via the live controller -> Auto/Manual Crop -> Filter/
/// Enhancement -> returns the final processed file via Navigator.pop.
class CameraCaptureScreen extends StatefulWidget {
  const CameraCaptureScreen({Key? key}) : super(key: key);

  @override
  State<CameraCaptureScreen> createState() => _CameraCaptureScreenState();
}

class _CameraCaptureScreenState extends State<CameraCaptureScreen> {
  CameraController? _controller;
  CameraSettingsModel _settings = CameraSettingsModel();
  bool _isReady = false;
  bool _isCapturing = false;
  String? _initError;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      _settings = await CameraSettingsModel.load();
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        setState(() => _initError = 'No camera found on this device.');
        return;
      }
      final backCamera = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );
      final controller = CameraController(
        backCamera,
        _settings.resolutionPreset,
        enableAudio: false,
      );
      await controller.initialize();
      await controller.setFlashMode(_settings.flashMode);
      if (!mounted) return;
      setState(() {
        _controller = controller;
        _isReady = true;
      });
    } on CameraException catch (e) {
      setState(() => _initError = 'Camera error: ${e.description ?? e.code}');
    } catch (e) {
      setState(() => _initError = 'Camera initialization failed: $e');
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _capture() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized || controller.value.isTakingPicture) {
      return;
    }
    setState(() => _isCapturing = true);
    try {
      final XFile shot = await controller.takePicture();
      File sourceFile = File(shot.path);

      // Manual Crop takes precedence over Auto Crop when both happen to be
      // enabled, per the requirements table listing them as independent
      // toggles but the workflow ("Auto Crop/Manual Crop દ્વારા...") implying
      // one effective crop step. Manual crop opens an interactive UI;
      // if the user cancels it, falls back to the auto-crop heuristic
      // (or the untouched capture, if Auto Crop is also off).
      Uint8List? manuallyCroppedBytes;
      if (_settings.manualCrop) {
        final cropped = await ImageCropper().cropImage(
          sourcePath: sourceFile.path,
          uiSettings: [
            AndroidUiSettings(
              toolbarTitle: 'Crop Document',
              toolbarColor: const Color(0xFF1A365D),
              toolbarWidgetColor: Colors.white,
              lockAspectRatio: false,
            ),
            IOSUiSettings(title: 'Crop Document'),
          ],
        );
        if (cropped != null) {
          manuallyCroppedBytes = await File(cropped.path).readAsBytes();
        }
      }

      final processedBytes = await ImageProcessingService.processForOcr(
        sourceFile: sourceFile,
        settings: _settings,
        manuallyCroppedBytes: manuallyCroppedBytes,
      );

      final tempDir = await getTemporaryDirectory();
      final outPath = '${tempDir.path}/setumitra_capture_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final outFile = await File(outPath).writeAsBytes(processedBytes);

      if (!mounted) return;
      Navigator.pop(context, outFile);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Capture failed: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isCapturing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_initError != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Camera'), backgroundColor: const Color(0xFF1A365D)),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(_initError!, textAlign: TextAlign.center, style: const TextStyle(color: Colors.red)),
          ),
        ),
      );
    }
    if (!_isReady || _controller == null) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(child: CircularProgressIndicator(color: Colors.white)),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('Capture Document', style: TextStyle(color: Colors.white)),
        backgroundColor: const Color(0xFF1A365D),
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          CameraPreview(_controller!),
          if (_settings.showGrid) const _GridOverlay(),
          if (_isCapturing)
            Container(
              color: Colors.black45,
              child: const Center(child: CircularProgressIndicator(color: Colors.white)),
            ),
          Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 32),
              child: GestureDetector(
                onTap: _isCapturing ? null : _capture,
                child: Container(
                  width: 74,
                  height: 74,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white,
                    border: Border.all(color: const Color(0xFF2B6CB0), width: 4),
                  ),
                  child: const Icon(Icons.camera_alt, color: Color(0xFF1A365D), size: 30),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Simple 3x3 rule-of-thirds grid overlay ("Show Grid" setting), drawn over
/// the live camera preview to help the user frame the document squarely.
class _GridOverlay extends StatelessWidget {
  const _GridOverlay();

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: CustomPaint(painter: _GridPainter(), size: Size.infinite),
    );
  }
}

class _GridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withOpacity(0.55)
      ..strokeWidth = 1;
    final dx1 = size.width / 3;
    final dx2 = size.width * 2 / 3;
    final dy1 = size.height / 3;
    final dy2 = size.height * 2 / 3;
    canvas.drawLine(Offset(dx1, 0), Offset(dx1, size.height), paint);
    canvas.drawLine(Offset(dx2, 0), Offset(dx2, size.height), paint);
    canvas.drawLine(Offset(0, dy1), Offset(size.width, dy1), paint);
    canvas.drawLine(Offset(0, dy2), Offset(size.width, dy2), paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
