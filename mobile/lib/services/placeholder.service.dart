import 'dart:io';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:immich_mobile/infrastructure/repositories/db.repository.dart';
import 'package:immich_mobile/services/app_settings.service.dart';
import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Resolution bucket used in the placeholder settings.
enum PlaceholderResolution {
  /// Longest side capped at 240 px.
  p240(240),

  /// Longest side capped at 480 px.
  p480(480),

  /// Longest side capped at 720 px.
  p720(720);

  final int maxSide;
  const PlaceholderResolution(this.maxSide);
}

/// Light DTO returned by [PlaceholderService] queries.
class PlaceholderImageDto {
  final String assetId;
  final String filePath;
  final int width;
  final int height;
  final int quality;
  final int fileSize;
  final DateTime createdAt;

  const PlaceholderImageDto({
    required this.assetId,
    required this.filePath,
    required this.width,
    required this.height,
    required this.quality,
    required this.fileSize,
    required this.createdAt,
  });
}

/// Manages generation, storage and retrieval of low-resolution placeholder
/// images for the offline-first image display pipeline.
///
/// Placeholders are PNG-encoded bytes (Flutter's built-in encoder) written to
/// the app's cache directory.  Their paths are persisted in the
/// `placeholder_image_entity` table via Drift's custom SQL API so that no
/// code-generation step is required.
class PlaceholderService {
  static final _log = Logger('PlaceholderService');

  final Drift _db;

  PlaceholderService(this._db);

  // ---------------------------------------------------------------------------
  // Settings helpers
  // ---------------------------------------------------------------------------

  static PlaceholderResolution get _resolution {
    final idx = AppSettingsService()
        .getSetting(AppSettingsEnum.placeholderMaxResolution);
    return PlaceholderResolution
        .values[idx.clamp(0, PlaceholderResolution.values.length - 1)];
  }

  static int get _quality =>
      AppSettingsService()
          .getSetting(AppSettingsEnum.placeholderCompression)
          .clamp(1, 100);

  static bool get isEnabled =>
      AppSettingsService().getSetting(AppSettingsEnum.placeholderImagesEnabled);

  // ---------------------------------------------------------------------------
  // Placeholder directory
  // ---------------------------------------------------------------------------

  static Future<Directory> _placeholderDir() async {
    final cache = await getApplicationCacheDirectory();
    final dir = Directory(p.join(cache.path, 'immich_placeholders'));
    if (!dir.existsSync()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  // ---------------------------------------------------------------------------
  // Public API
  // ---------------------------------------------------------------------------

  /// Returns the bytes of an already-generated placeholder for [assetId],
  /// or `null` when no placeholder exists yet.
  Future<Uint8List?> getPlaceholderBytes(String assetId) async {
    try {
      final rows = await _db
          .customSelect(
            'SELECT * FROM placeholder_image_entity WHERE asset_id = ?',
            variables: [Variable.withString(assetId)],
            readsFrom: {},
          )
          .get();
      if (rows.isEmpty) return null;

      final filePath = rows.first.read<String>('file_path');
      final file = File(filePath);
      if (!file.existsSync()) {
        await _db.customStatement(
          'DELETE FROM placeholder_image_entity WHERE asset_id = ?',
          [assetId],
        );
        return null;
      }

      return file.readAsBytes();
    } catch (e, st) {
      _log.warning('Failed to read placeholder for $assetId', e, st);
      return null;
    }
  }

  /// Retrieves the [PlaceholderImageDto] for [assetId], or `null`.
  Future<PlaceholderImageDto?> getDto(String assetId) async {
    try {
      final rows = await _db
          .customSelect(
            'SELECT * FROM placeholder_image_entity WHERE asset_id = ?',
            variables: [Variable.withString(assetId)],
            readsFrom: {},
          )
          .get();
      return rows.isEmpty ? null : _rowToDto(rows.first);
    } catch (e, st) {
      _log.warning('getDto failed for $assetId', e, st);
      return null;
    }
  }

  /// Stores a placeholder derived from [imageBytes] for [assetId].
  ///
  /// The image is downscaled to the user-configured maximum resolution and
  /// re-encoded before being written to disk.  If a record already exists for
  /// [assetId] the old file is replaced.
  Future<void> storePlaceholder(
    String assetId,
    Uint8List imageBytes, {
    String? filename,
  }) async {
    if (!isEnabled) return;

    try {
      final maxSide = _resolution.maxSide;
      final quality = _quality;

      // Resize on a background isolate to keep the UI thread free.
      final resized = await compute(
        _resizeAndEncodeImage,
        _ResizeRequest(bytes: imageBytes, maxSide: maxSide, quality: quality),
      );

      if (resized == null) return;

      final dir = await _placeholderDir();
      final filePath = p.join(dir.path, '$assetId.png');
      final file = File(filePath);
      await file.writeAsBytes(resized.bytes, flush: true);

      final now = DateTime.now().millisecondsSinceEpoch;
      await _db.customStatement(
        'INSERT OR REPLACE INTO placeholder_image_entity '
        '(asset_id, file_path, width, height, quality, file_size, created_at) '
        'VALUES (?, ?, ?, ?, ?, ?, ?)',
        [assetId, filePath, resized.width, resized.height, quality, resized.bytes.length, now],
      );

      _log.fine(
        'Stored placeholder for $assetId: ${resized.width}×${resized.height} '
        '${(resized.bytes.length / 1024).toStringAsFixed(1)} KiB',
      );
    } catch (e, st) {
      _log.warning('Failed to store placeholder for $assetId', e, st);
    }
  }

  /// Deletes the placeholder file and DB record for [assetId].
  Future<void> deletePlaceholder(String assetId) async {
    try {
      final dto = await getDto(assetId);
      if (dto != null) {
        final file = File(dto.filePath);
        if (file.existsSync()) await file.delete();
        await _db.customStatement(
          'DELETE FROM placeholder_image_entity WHERE asset_id = ?',
          [assetId],
        );
      }
    } catch (e, st) {
      _log.warning('Failed to delete placeholder for $assetId', e, st);
    }
  }

  /// Returns the total storage used by all placeholder files in bytes.
  Future<int> getTotalStorageUsed() async {
    try {
      final rows = await _db
          .customSelect(
            'SELECT SUM(file_size) AS total FROM placeholder_image_entity',
            readsFrom: {},
          )
          .get();
      return rows.first.read<int?>('total') ?? 0;
    } catch (_) {
      return 0;
    }
  }

  /// Removes all placeholder files and DB records.
  Future<void> clearAll() async {
    try {
      final rows = await _db
          .customSelect(
            'SELECT file_path FROM placeholder_image_entity',
            readsFrom: {},
          )
          .get();
      for (final row in rows) {
        final file = File(row.read<String>('file_path'));
        if (file.existsSync()) await file.delete();
      }
      await _db.customStatement('DELETE FROM placeholder_image_entity');
    } catch (e, st) {
      _log.warning('Failed to clear placeholders', e, st);
    }
  }

  /// Removes DB records whose backing file no longer exists on disk.
  Future<void> pruneStaleRecords() async {
    try {
      final rows = await _db
          .customSelect(
            'SELECT asset_id, file_path FROM placeholder_image_entity',
            readsFrom: {},
          )
          .get();
      for (final row in rows) {
        if (!File(row.read<String>('file_path')).existsSync()) {
          await _db.customStatement(
            'DELETE FROM placeholder_image_entity WHERE asset_id = ?',
            [row.read<String>('asset_id')],
          );
        }
      }
    } catch (e, st) {
      _log.warning('Failed to prune stale placeholder records', e, st);
    }
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  PlaceholderImageDto _rowToDto(QueryRow row) {
    return PlaceholderImageDto(
      assetId: row.read<String>('asset_id'),
      filePath: row.read<String>('file_path'),
      width: row.read<int>('width'),
      height: row.read<int>('height'),
      quality: row.read<int>('quality'),
      fileSize: row.read<int>('file_size'),
      createdAt: DateTime.fromMillisecondsSinceEpoch(row.read<int>('created_at')),
    );
  }
}

// ---------------------------------------------------------------------------
// Isolate helpers
// ---------------------------------------------------------------------------

class _ResizeRequest {
  final Uint8List bytes;
  final int maxSide;
  final int quality;
  const _ResizeRequest({
    required this.bytes,
    required this.maxSide,
    required this.quality,
  });
}

class _ResizeResult {
  final Uint8List bytes;
  final int width;
  final int height;
  const _ResizeResult({
    required this.bytes,
    required this.width,
    required this.height,
  });
}

/// Top-level function usable with [compute].
Future<_ResizeResult?> _resizeAndEncodeImage(_ResizeRequest req) async {
  try {
    // Decode to get natural dimensions.
    final codec = await ui.instantiateImageCodecFromBuffer(
      await ui.ImmutableBuffer.fromUint8List(req.bytes),
    );
    final frame = await codec.getNextFrame();
    final src = frame.image;
    final srcW = src.width;
    final srcH = src.height;
    src.dispose();
    codec.dispose();

    final scale = req.maxSide / max(srcW, srcH);
    final int dstW;
    final int dstH;
    if (scale < 1.0) {
      dstW = (srcW * scale).round();
      dstH = (srcH * scale).round();
    } else {
      dstW = srcW;
      dstH = srcH;
    }

    // Re-decode at the target resolution.
    final resizedCodec = await ui.instantiateImageCodecFromBuffer(
      await ui.ImmutableBuffer.fromUint8List(req.bytes),
      targetWidth: dstW,
      targetHeight: dstH,
    );
    final resizedFrame = await resizedCodec.getNextFrame();
    final resizedImage = resizedFrame.image;

    // Encode as PNG (Flutter's built-in encoder).
    final byteData =
        await resizedImage.toByteData(format: ui.ImageByteFormat.png);
    resizedImage.dispose();
    resizedCodec.dispose();

    if (byteData == null) return null;

    return _ResizeResult(
      bytes: byteData.buffer.asUint8List(),
      width: dstW,
      height: dstH,
    );
  } catch (e) {
    return null;
  }
}
