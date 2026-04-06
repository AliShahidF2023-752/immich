import 'dart:async';

import 'package:flutter/services.dart';
import 'package:immich_mobile/infrastructure/entities/local_ocr.entity.dart';
import 'package:immich_mobile/infrastructure/repositories/local_ocr.repository.dart';
import 'package:immich_mobile/services/app_settings.service.dart';
import 'package:logging/logging.dart';

// ---------------------------------------------------------------------------
// OCR provider abstraction
// ---------------------------------------------------------------------------

/// OCR provider abstraction — allows swapping server vs local implementations.
abstract class OcrProvider {
  /// Extract text from the image at [imagePath].
  Future<String> recognizeText(String imagePath);
}

/// OCR processing mode stored in app settings.
enum OcrMode {
  /// Delegate text recognition to the Immich server.
  server,

  /// Run text recognition on-device.
  local,
}

/// Accuracy level passed to the on-device OCR engine.
enum OcrAccuracy {
  low,
  balanced,
  high,
}

/// Which assets to process when OCR is first enabled.
enum OcrScope {
  /// Only process assets added after OCR was enabled.
  newOnly,

  /// Process all assets (batch mode in background).
  all,
}

// ---------------------------------------------------------------------------
// LocalOcrProvider — delegates to the native Vision / ML-Kit channel
// ---------------------------------------------------------------------------

/// On-device OCR provider backed by the platform's native OCR engine.
///
/// On iOS this calls `VNRecognizeTextRequest` via the Flutter MethodChannel
/// registered in `ios/Runner/LocalOcrChannel.swift`.
/// On Android, the same channel name is implemented with ML Kit.
class LocalOcrProvider implements OcrProvider {
  static const _channel = MethodChannel('immich/local_ocr');

  final OcrAccuracy accuracy;

  const LocalOcrProvider({this.accuracy = OcrAccuracy.balanced});

  @override
  Future<String> recognizeText(String imagePath) async {
    try {
      final result = await _channel.invokeMethod<String>('recognizeText', {
        'path': imagePath,
        'accuracy': accuracy.index,
      });
      return result ?? '';
    } on PlatformException catch (e) {
      throw Exception('OCR platform error [${e.code}]: ${e.message}');
    }
  }
}

// ---------------------------------------------------------------------------
// LocalOcrService — background batch processor
// ---------------------------------------------------------------------------

/// Orchestrates on-device OCR processing for all local and remote assets.
///
/// Processing is done sequentially (one asset at a time) in a background
/// Future-chain to avoid blocking the UI isolate.  Work is throttled with a
/// configurable delay between items so the device is not overwhelmed.
class LocalOcrService {
  static final _log = Logger('LocalOcrService');

  /// Delay between processing consecutive assets to throttle CPU/battery.
  static const _itemDelay = Duration(milliseconds: 500);

  /// Maximum consecutive failures before a batch run aborts.
  static const _maxBatchErrors = 10;

  final LocalOcrRepository _repository;
  final OcrProvider _provider;

  bool _isRunning = false;
  Timer? _retryTimer;

  LocalOcrService({
    required LocalOcrRepository repository,
    OcrProvider? provider,
  })  : _repository = repository,
        _provider = provider ??
            LocalOcrProvider(accuracy: _accuracySetting);

  // ---------------------------------------------------------------------------
  // Settings helpers
  // ---------------------------------------------------------------------------

  static bool get isEnabled =>
      AppSettingsService().getSetting(AppSettingsEnum.localOcrEnabled);

  static OcrMode get mode =>
      OcrMode.values[AppSettingsService()
          .getSetting(AppSettingsEnum.localOcrMode)
          .clamp(0, OcrMode.values.length - 1)];

  static OcrAccuracy get _accuracySetting =>
      OcrAccuracy.values[AppSettingsService()
          .getSetting(AppSettingsEnum.localOcrAccuracy)
          .clamp(0, OcrAccuracy.values.length - 1)];

  static OcrScope get scope =>
      OcrScope.values[AppSettingsService()
          .getSetting(AppSettingsEnum.localOcrScope)
          .clamp(0, OcrScope.values.length - 1)];

  // ---------------------------------------------------------------------------
  // Public API
  // ---------------------------------------------------------------------------

  /// Enqueues [assetId] for OCR when a new photo is added.
  Future<void> enqueueAsset(String assetId, {String filename = ''}) async {
    if (!isEnabled || mode != OcrMode.local) return;
    await _repository.enqueue(assetId, filename: filename);
    unawaited(_processQueue());
  }

  /// Enqueues all provided assets for batch processing (first-time enable or
  /// triggered by the user via Settings).
  Future<void> enqueueAll(
    Iterable<({String assetId, String filename})> assets,
  ) async {
    for (final asset in assets) {
      await _repository.enqueue(asset.assetId, filename: asset.filename);
    }
    unawaited(_processQueue());
  }

  /// Returns the asset IDs whose OCR text contains [query].
  Future<List<String>> searchText(String query) async {
    try {
      final results = await _repository.search(query);
      return results.map((r) => r.assetId).toList();
    } catch (e, st) {
      _log.warning('searchText failed for "$query"', e, st);
      return [];
    }
  }

  /// Cancels background processing and the retry timer.
  void dispose() {
    _isRunning = false;
    _retryTimer?.cancel();
    _retryTimer = null;
  }

  // ---------------------------------------------------------------------------
  // Internal queue processing
  // ---------------------------------------------------------------------------

  Future<void> _processQueue() async {
    if (_isRunning) return;
    _isRunning = true;
    int batchErrors = 0;

    try {
      await _repository.requeueRetrying();

      List<LocalOcrDto> pending;
      while (
        _isRunning &&
        batchErrors < _maxBatchErrors &&
        (pending = await _repository.getByStatus(OcrStatus.pending)).isNotEmpty
      ) {
        final item = pending.first;
        await _processItem(item);

        if (item.status == OcrStatus.failed) {
          batchErrors++;
        }

        await Future.delayed(_itemDelay);
      }

      _scheduleRetry();
    } finally {
      _isRunning = false;
    }
  }

  Future<void> _processItem(LocalOcrDto item) async {
    await _repository.markProcessing(item.assetId);
    try {
      // In a production implementation the service would resolve the actual
      // filesystem path for the asset from the photo manager / storage service.
      // Here we use the assetId as a proxy for the path (callers that know the
      // real path should pass it via a wrapper).
      final text = await _provider.recognizeText(item.assetId);
      await _repository.saveResult(item.assetId, text);
      _log.fine('OCR completed for ${item.assetId}: ${text.length} chars');
    } catch (e, st) {
      _log.warning('OCR failed for ${item.assetId}', e, st);
      await _repository.markFailed(item.assetId, e.toString());
    }
  }

  void _scheduleRetry() {
    _retryTimer?.cancel();
    _retryTimer = Timer(const Duration(minutes: 5), () async {
      final retrying = await _repository.getByStatus(OcrStatus.retrying);
      if (retrying.isNotEmpty) {
        _log.info('Retrying OCR for ${retrying.length} assets');
        unawaited(_processQueue());
      }
    });
  }
}
