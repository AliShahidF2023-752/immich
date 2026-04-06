import 'package:drift/drift.dart';
import 'package:immich_mobile/infrastructure/entities/local_ocr.entity.dart';
import 'package:immich_mobile/infrastructure/repositories/db.repository.dart';
import 'package:logging/logging.dart';

/// Repository for CRUD operations on the `local_ocr_entity` table.
///
/// Uses Drift's lower-level custom SQL API so that no code-generation step is
/// required for the new table.  All business logic lives in [LocalOcrService].
class LocalOcrRepository {
  static final _log = Logger('LocalOcrRepository');

  final Drift _db;

  const LocalOcrRepository(this._db);

  // ---------------------------------------------------------------------------
  // Queries
  // ---------------------------------------------------------------------------

  /// Returns the OCR record for [assetId], or `null` if none exists.
  Future<LocalOcrDto?> getByAssetId(String assetId) async {
    try {
      final rows = await _db
          .customSelect(
            'SELECT * FROM local_ocr_entity WHERE asset_id = ?',
            variables: [Variable.withString(assetId)],
            readsFrom: {},
          )
          .get();
      return rows.isEmpty ? null : _rowToDto(rows.first);
    } catch (e, st) {
      _log.warning('getByAssetId failed for $assetId', e, st);
      return null;
    }
  }

  /// Returns all OCR records with [status].
  Future<List<LocalOcrDto>> getByStatus(OcrStatus status) async {
    try {
      final rows = await _db
          .customSelect(
            'SELECT * FROM local_ocr_entity WHERE status = ?',
            variables: [Variable.withInt(status.index)],
            readsFrom: {},
          )
          .get();
      return rows.map(_rowToDto).toList();
    } catch (e, st) {
      _log.warning('getByStatus failed', e, st);
      return [];
    }
  }

  /// Returns all OCR records.
  Future<List<LocalOcrDto>> getAll() async {
    try {
      final rows = await _db
          .customSelect('SELECT * FROM local_ocr_entity', readsFrom: {})
          .get();
      return rows.map(_rowToDto).toList();
    } catch (e, st) {
      _log.warning('getAll failed', e, st);
      return [];
    }
  }

  /// Full-text search: returns records whose [extracted_text] contains [query].
  Future<List<LocalOcrDto>> search(String query) async {
    if (query.trim().isEmpty) return [];
    try {
      final rows = await _db
          .customSelect(
            'SELECT * FROM local_ocr_entity WHERE extracted_text LIKE ?',
            variables: [Variable.withString('%$query%')],
            readsFrom: {},
          )
          .get();
      return rows.map(_rowToDto).toList();
    } catch (e, st) {
      _log.warning('search failed for "$query"', e, st);
      return [];
    }
  }

  // ---------------------------------------------------------------------------
  // Mutations
  // ---------------------------------------------------------------------------

  /// Creates a new pending OCR record for [assetId].  If a record already
  /// exists it is left unchanged (INSERT OR IGNORE).
  Future<void> enqueue(String assetId, {String filename = ''}) async {
    try {
      await _db.customStatement(
        'INSERT OR IGNORE INTO local_ocr_entity '
        '(asset_id, filename, status) VALUES (?, ?, ?)',
        [assetId, filename, OcrStatus.pending.index],
      );
    } catch (e, st) {
      _log.warning('enqueue failed for $assetId', e, st);
    }
  }

  /// Marks [assetId] as [OcrStatus.processing].
  Future<void> markProcessing(String assetId) async {
    await _setStatus(assetId, OcrStatus.processing);
  }

  /// Saves [text] and marks [assetId] as [OcrStatus.completed].
  Future<void> saveResult(String assetId, String text) async {
    try {
      final now = DateTime.now().millisecondsSinceEpoch;
      await _db.customStatement(
        'UPDATE local_ocr_entity SET extracted_text = ?, processed_at = ?, '
        'status = ?, failure_count = 0, last_error = NULL '
        'WHERE asset_id = ?',
        [text, now, OcrStatus.completed.index, assetId],
      );
    } catch (e, st) {
      _log.warning('saveResult failed for $assetId', e, st);
    }
  }

  /// Marks [assetId] as failed and increments the failure counter.
  /// Transitions to [OcrStatus.failed] after 3 consecutive failures.
  Future<void> markFailed(String assetId, String error) async {
    try {
      final existing = await getByAssetId(assetId);
      final newCount = (existing?.failureCount ?? 0) + 1;
      final newStatus = newCount < 3 ? OcrStatus.retrying : OcrStatus.failed;
      await _db.customStatement(
        'UPDATE local_ocr_entity SET status = ?, failure_count = ?, last_error = ? '
        'WHERE asset_id = ?',
        [newStatus.index, newCount, error, assetId],
      );
    } catch (e, st) {
      _log.warning('markFailed failed for $assetId', e, st);
    }
  }

  /// Resets all [OcrStatus.retrying] records back to [OcrStatus.pending].
  Future<void> requeueRetrying() async {
    try {
      await _db.customStatement(
        'UPDATE local_ocr_entity SET status = ? WHERE status = ?',
        [OcrStatus.pending.index, OcrStatus.retrying.index],
      );
    } catch (e, st) {
      _log.warning('requeueRetrying failed', e, st);
    }
  }

  /// Removes the record for [assetId].
  Future<void> delete(String assetId) async {
    try {
      await _db.customStatement(
        'DELETE FROM local_ocr_entity WHERE asset_id = ?',
        [assetId],
      );
    } catch (e, st) {
      _log.warning('delete failed for $assetId', e, st);
    }
  }

  /// Removes all OCR records.
  Future<void> clearAll() async {
    try {
      await _db.customStatement('DELETE FROM local_ocr_entity');
    } catch (e, st) {
      _log.warning('clearAll failed', e, st);
    }
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  Future<void> _setStatus(String assetId, OcrStatus status) async {
    try {
      await _db.customStatement(
        'UPDATE local_ocr_entity SET status = ? WHERE asset_id = ?',
        [status.index, assetId],
      );
    } catch (e, st) {
      _log.warning('_setStatus failed for $assetId → $status', e, st);
    }
  }

  LocalOcrDto _rowToDto(QueryRow row) {
    final processedAtMs = row.read<int?>('processed_at');
    return LocalOcrDto(
      assetId: row.read<String>('asset_id'),
      filename: row.read<String>('filename'),
      extractedText: row.read<String>('extracted_text'),
      createdAt: DateTime.fromMillisecondsSinceEpoch(row.read<int>('created_at')),
      processedAt: processedAtMs != null
          ? DateTime.fromMillisecondsSinceEpoch(processedAtMs)
          : null,
      status: OcrStatus.values[row.read<int>('status')],
      failureCount: row.read<int>('failure_count'),
      lastError: row.read<String?>('last_error'),
    );
  }
}
