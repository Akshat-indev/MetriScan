import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants/rule_definitions.dart';
import '../../core/models/ocr_block.dart';
import '../../core/models/scan_stage.dart';
import '../../core/models/stage_capture.dart';
import '../../core/services/boundary_detector.dart';
import '../../core/services/image_processor.dart';
import '../../core/services/ocr_service.dart';
import '../../correction_memory/correction_memory.dart';
import '../../core/utils/permission_helper.dart';
import 'widgets/back_thumbnail_row.dart';
import 'widgets/boundary_overlay.dart';
import 'widgets/stage_guide_banner.dart';

// ---------------------------------------------------------------------------
// State
// ---------------------------------------------------------------------------

class ScannerState {
  final ScanStage currentStage;
  final List<StageCapture> completedStages;
  final List<String> backImagePaths; // in-progress back photos
  final BoundaryResult? boundary;
  final bool isProcessing;
  final String? errorMessage;
  final int stableFrameCount;

  const ScannerState({
    this.currentStage = ScanStage.front,
    this.completedStages = const [],
    this.backImagePaths = const [],
    this.boundary,
    this.isProcessing = false,
    this.errorMessage,
    this.stableFrameCount = 0,
  });

  ScannerState copyWith({
    ScanStage? currentStage,
    List<StageCapture>? completedStages,
    List<String>? backImagePaths,
    BoundaryResult? boundary,
    bool? isProcessing,
    String? errorMessage,
    int? stableFrameCount,
  }) =>
      ScannerState(
        currentStage: currentStage ?? this.currentStage,
        completedStages: completedStages ?? this.completedStages,
        backImagePaths: backImagePaths ?? this.backImagePaths,
        boundary: boundary,
        isProcessing: isProcessing ?? this.isProcessing,
        errorMessage: errorMessage,
        stableFrameCount: stableFrameCount ?? this.stableFrameCount,
      );
}

class ScannerNotifier extends StateNotifier<ScannerState> {
  ScannerNotifier() : super(const ScannerState());

  final _boundaryDetector = BoundaryDetector();
  final _imageProcessor = ImageProcessor();
  final _ocrService = OcrService();

  CameraController? _cameraController;
  bool _isAnalyzingFrame = false;

  Future<CameraController?> initCamera() async {
    final hasPermission = await PermissionHelper.requestCamera();
    if (!hasPermission) {
      state = state.copyWith(errorMessage: 'Camera permission denied.');
      return null;
    }
    final cameras = await availableCameras();
    if (cameras.isEmpty) {
      state = state.copyWith(errorMessage: 'No camera available.');
      return null;
    }
    final controller = CameraController(
      cameras.first,
      ResolutionPreset.high,
      enableAudio: false,
      imageFormatGroup: Platform.isAndroid ? ImageFormatGroup.yuv420 : ImageFormatGroup.bgra8888,
    );
    await controller.initialize();
    _cameraController = controller;

    // Start boundary detection on image stream
    controller.startImageStream(_onFrame);
    return controller;
  }

  Future<void> _onFrame(CameraImage image) async {
    if (_isAnalyzingFrame) return;
    _isAnalyzingFrame = true;
    try {
      // Convert camera image to JPEG bytes for OpenCV
      final bytes = image.planes.first.bytes;
      final result = await _boundaryDetector.detectFromBytes(
        frameBytes: bytes,
        frameWidth: image.width,
        frameHeight: image.height,
      );

      int stable = state.stableFrameCount;
      if (result != null && result.isStable) {
        stable = (stable + 1).clamp(0, kBoundaryStableFrames + 5);
      } else {
        stable = 0;
      }

      state = state.copyWith(boundary: result, stableFrameCount: stable);
    } finally {
      _isAnalyzingFrame = false;
    }
  }

  Future<void> capture() async {
    if (_cameraController == null || state.isProcessing) return;
    state = state.copyWith(isProcessing: true, errorMessage: null);

    try {
      await _cameraController!.stopImageStream();
      
      if (Platform.isAndroid) {
        // Allow Mediatek/CameraX HAL to recover from stream teardown
        await Future.delayed(const Duration(milliseconds: 600));
      }

      // Burst capture: take kBurstFrameCount shots, pick sharpest
      final files = <File>[];
      for (var i = 0; i < kBurstFrameCount; i++) {
        try {
          final xFile = await _cameraController!.takePicture();
          files.add(File(xFile.path));
          if (Platform.isAndroid && i < kBurstFrameCount - 1) {
            await Future.delayed(const Duration(milliseconds: 200));
          }
        } catch (e) {
          debugPrint('Capture error: $e');
          if (files.isNotEmpty) break; // Proceed if we got at least one frame
          rethrow;
        }
      }

      File best = files.first;
      double bestScore = -1;
      for (final f in files) {
        final score = await _imageProcessor.sharpnessScore(f);
        if (score > bestScore) {
          bestScore = score;
          best = f;
        }
      }

      // Detect boundary from the best captured frame
      final corners = await _boundaryDetector.detectFromFile(best);

      // Image processing pipeline
      final processedPath = await _imageProcessor.process(
        inputFile: best,
        corners: corners,
        detectClipping: state.currentStage.enforcesBoundaryClipping,
      );

      await _onImageReady(processedPath, corners);
    } catch (e) {
      state = state.copyWith(
        isProcessing: false,
        errorMessage: 'Capture failed: $e',
      );
    } finally {
      // Restart stream only if we haven't finished all stages
      if (state.completedStages.length < 3 && _cameraController != null) {
        try {
          _cameraController!.startImageStream(_onFrame);
        } catch (_) {}
      }
    }
  }

  Future<void> _onImageReady(String processedPath, List? corners) async {
    final stage = state.currentStage;

    if (stage == ScanStage.back) {
      // Accumulate back photos
      final paths = [...state.backImagePaths, processedPath];
      state = state.copyWith(
        backImagePaths: paths,
        isProcessing: false,
        boundary: null,
      );
    } else {
      // Single-capture stages: run OCR and complete stage
      await _completeStage(stage, [processedPath]);
    }
  }

  Future<void> finishBackStage() async {
    if (state.backImagePaths.isEmpty) return;
    state = state.copyWith(isProcessing: true);
    await _completeStage(ScanStage.back, state.backImagePaths);
  }

  Future<void> _completeStage(ScanStage stage, List<String> imagePaths) async {
    state = state.copyWith(isProcessing: true);

    // Run OCR on all images for this stage
    final files = imagePaths.map((p) => File(p)).toList();
    List<OcrBlock> blocks;
    if (files.length == 1) {
      blocks = await _ocrService.recognise(
        imageFile: files.first,
        stage: stage.id,
      );
    } else {
      blocks = await _ocrService.recogniseMultiple(
        imageFiles: files,
        stage: stage.id,
      );
    }
    // TEMPORARY: correction-memory stand-in, remove when trained model replaces this (see /correction_memory/README.md)
    blocks = [
      for (final block in blocks)
        block.copyWith(
          text: await CorrectionMemory().preprocessOcrText(block.text),
        ),
    ];

    // Build raw text for training JSON
    final rawText = blocks.map((b) => b.text).join('\n');

    int imgW = 0;
    int imgH = 0;
    if (files.isNotEmpty) {
      final decoded = await decodeImageFromList(await files.first.readAsBytes());
      imgW = decoded.width;
      imgH = decoded.height;
    }

    // Clipping detection: check if any block is within kClippingMarginPx of image edge
    final hasClipping = stage.enforcesBoundaryClipping &&
        blocks.any((b) =>
            b.boundingBox.left < kClippingMarginPx ||
            b.boundingBox.top < kClippingMarginPx ||
            b.boundingBox.right > imgW - kClippingMarginPx ||
            b.boundingBox.bottom > imgH - kClippingMarginPx);

    final capture = StageCapture(
      stage: stage,
      imagePaths: imagePaths,
      ocrBlocks: blocks,
      hasClipping: hasClipping,
      allRawText: rawText,
      imageWidth: imgW,
      imageHeight: imgH,
    );

    final completed = [...state.completedStages, capture];
    final nextStage = _nextStage(stage);

    if (nextStage == null) {
      // All stages done — navigate to OCR review
      state = state.copyWith(
        completedStages: completed,
        backImagePaths: [],
        isProcessing: false,
        currentStage: ScanStage.front,
      );
      _navigateToReview(completed);
    } else {
      state = state.copyWith(
        completedStages: completed,
        backImagePaths: [],
        currentStage: nextStage,
        isProcessing: false,
        boundary: null,
      );
      _boundaryDetector.reset();
    }
  }

  ScanStage? _nextStage(ScanStage current) {
    switch (current) {
      case ScanStage.front:
        return ScanStage.back;
      case ScanStage.back:
        return ScanStage.detail;
      case ScanStage.detail:
        return null;
    }
  }

  void _navigateToReview(List<StageCapture> stages) {
    // Navigation happens in the widget using a callback; expose via state change.
    // We use a ref-based approach — see ScannerScreen.
  }

  @override
  void dispose() {
    _cameraController?.stopImageStream();
    _cameraController?.dispose();
    super.dispose();
  }
}

final scannerProvider =
    StateNotifierProvider.autoDispose<ScannerNotifier, ScannerState>(
  (ref) => ScannerNotifier(),
);

// ---------------------------------------------------------------------------
// Screen
// ---------------------------------------------------------------------------

class ScannerScreen extends ConsumerStatefulWidget {
  const ScannerScreen({super.key});

  @override
  ConsumerState<ScannerScreen> createState() => _ScannerScreenState();
}

class _ScannerScreenState extends ConsumerState<ScannerScreen> {
  CameraController? _controller;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _initCamera());
  }

  Future<void> _initCamera() async {
    final notifier = ref.read(scannerProvider.notifier);
    final ctrl = await notifier.initCamera();
    if (mounted) setState(() => _controller = ctrl);
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(scannerProvider);
    final notifier = ref.read(scannerProvider.notifier);

    // Navigate when all stages complete (state has 3 completed stages and no next)
    ref.listen<ScannerState>(scannerProvider, (prev, next) {
      if (next.completedStages.length == 3 && !next.isProcessing) {
        context.replace('/ocr-review', extra: next.completedStages);
      }
    });

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Camera preview
          if (_controller != null && _controller!.value.isInitialized)
            CameraPreview(_controller!)
          else
            const Center(
                child: CircularProgressIndicator(color: Colors.white)),

          // Boundary overlay
          if (state.boundary != null)
            BoundaryOverlay(
              boundary: state.boundary!,
              isStable: state.stableFrameCount >= kBoundaryStableFrames,
            ),

          // Stage guide banner
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: StageGuideBanner(stage: state.currentStage),
          ),

          // Back thumbnail row
          if (state.currentStage == ScanStage.back)
            Positioned(
              bottom: 120,
              left: 16,
              right: 16,
              child: BackThumbnailRow(imagePaths: state.backImagePaths),
            ),

          // Processing overlay
          if (state.isProcessing)
            Container(
              color: Colors.black54,
              child: const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(color: Colors.white),
                    SizedBox(height: 12),
                    Text('Processing…',
                        style: TextStyle(color: Colors.white, fontSize: 16)),
                  ],
                ),
              ),
            ),

          // Error snackbar trigger
          if (state.errorMessage != null)
            Positioned(
              bottom: 200,
              left: 16,
              right: 16,
              child: Material(
                borderRadius: BorderRadius.circular(8),
                color: Colors.red.shade800,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(state.errorMessage!,
                      style: const TextStyle(color: Colors.white)),
                ),
              ),
            ),

          // Controls
          Positioned(
            bottom: 32,
            left: 0,
            right: 0,
            child: _buildControls(state, notifier),
          ),
        ],
      ),
    );
  }

  Widget _buildControls(ScannerState state, ScannerNotifier notifier) {
    final isBack = state.currentStage == ScanStage.back;
    final canFinishBack = isBack &&
        state.backImagePaths.length >= kMinBackPhotos &&
        !state.isProcessing;
    final canAddMore =
        isBack && state.backImagePaths.length < kMaxBackPhotos;

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        // Cancel
        IconButton(
          icon: const Icon(Icons.close, color: Colors.white, size: 28),
          onPressed: () => context.pop(),
        ),

        // Capture button
        if (!isBack || canAddMore)
          GestureDetector(
            onTap: state.isProcessing ? null : notifier.capture,
            child: Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white,
                border: Border.all(
                  color: state.boundary?.isStable == true
                      ? Colors.green.shade400
                      : Colors.white60,
                  width: 4,
                ),
              ),
              child: state.boundary?.isStable == true
                  ? const Icon(Icons.camera_alt, size: 32, color: Colors.green)
                  : const Icon(Icons.camera_alt, size: 32),
            ),
          ),

        // "Done" for back stage
        if (canFinishBack)
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green.shade600,
              foregroundColor: Colors.white,
              padding:
                  const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            ),
            onPressed: notifier.finishBackStage,
            icon: const Icon(Icons.check),
            label: const Text('Done'),
          ),

        // Stage indicator dots
        Row(
          children: ScanStage.values.map((s) {
            final done = state.completedStages.any((c) => c.stage == s);
            final current = state.currentStage == s;
            return Container(
              margin: const EdgeInsets.symmetric(horizontal: 3),
              width: current ? 12 : 8,
              height: current ? 12 : 8,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: done
                    ? Colors.green
                    : current
                        ? Colors.white
                        : Colors.white38,
              ),
            );
          }).toList(),
        ),
      ],
    );
  }
}
