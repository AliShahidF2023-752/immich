import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:immich_mobile/infrastructure/entities/local_ocr.entity.dart';
import 'package:immich_mobile/infrastructure/repositories/db.repository.dart';
import 'package:immich_mobile/infrastructure/repositories/local_ocr.repository.dart';

/// Creates the local_ocr_entity table in an in-memory database so that the
/// repository can be tested without running the full migration path.
Future<void> _createTable(Drift db) async {
  await db.customStatement(
    "CREATE TABLE IF NOT EXISTS local_ocr_entity ("
    "  asset_id TEXT NOT NULL PRIMARY KEY,"
    "  filename TEXT NOT NULL DEFAULT '',"
    "  extracted_text TEXT NOT NULL DEFAULT '',"
    "  created_at INTEGER NOT NULL DEFAULT 0,"
    "  processed_at INTEGER,"
    "  status INTEGER NOT NULL DEFAULT 0,"
    "  failure_count INTEGER NOT NULL DEFAULT 0,"
    "  last_error TEXT"
    ")",
  );
}

void main() {
  late Drift db;
  late LocalOcrRepository repo;

  setUp(() async {
    db = Drift(DatabaseConnection(NativeDatabase.memory(), closeStreamsSynchronously: true));
    await _createTable(db);
    repo = LocalOcrRepository(db);
  });

  tearDown(() async {
    await db.close();
  });

  // ---------------------------------------------------------------------------
  // enqueue / getByAssetId
  // ---------------------------------------------------------------------------

  group('enqueue', () {
    test('creates a pending OCR record', () async {
      await repo.enqueue('asset-1', filename: 'photo.jpg');
      final result = await repo.getByAssetId('asset-1');
      expect(result, isNotNull);
      expect(result!.assetId, 'asset-1');
      expect(result.filename, 'photo.jpg');
      expect(result.status, OcrStatus.pending);
      expect(result.extractedText, '');
    });

    test('does not overwrite an existing record (INSERT OR IGNORE)', () async {
      await repo.enqueue('asset-2');
      await repo.saveResult('asset-2', 'hello world');
      // Enqueueing again must not reset the extracted text.
      await repo.enqueue('asset-2');
      final result = await repo.getByAssetId('asset-2');
      expect(result!.extractedText, 'hello world');
    });

    test('returns null for unknown asset', () async {
      final result = await repo.getByAssetId('non-existent');
      expect(result, isNull);
    });
  });

  // ---------------------------------------------------------------------------
  // markProcessing
  // ---------------------------------------------------------------------------

  group('markProcessing', () {
    test('transitions status to processing', () async {
      await repo.enqueue('asset-3');
      await repo.markProcessing('asset-3');
      final result = await repo.getByAssetId('asset-3');
      expect(result!.status, OcrStatus.processing);
    });
  });

  // ---------------------------------------------------------------------------
  // saveResult
  // ---------------------------------------------------------------------------

  group('saveResult', () {
    test('stores text and marks as completed', () async {
      await repo.enqueue('asset-4');
      await repo.saveResult('asset-4', 'extracted text');
      final result = await repo.getByAssetId('asset-4');
      expect(result!.status, OcrStatus.completed);
      expect(result.extractedText, 'extracted text');
      expect(result.processedAt, isNotNull);
      expect(result.failureCount, 0);
    });
  });

  // ---------------------------------------------------------------------------
  // markFailed / retry logic
  // ---------------------------------------------------------------------------

  group('markFailed', () {
    test('increments failure count and transitions to retrying', () async {
      await repo.enqueue('asset-5');
      await repo.markFailed('asset-5', 'timeout');
      final result = await repo.getByAssetId('asset-5');
      expect(result!.status, OcrStatus.retrying);
      expect(result.failureCount, 1);
      expect(result.lastError, 'timeout');
    });

    test('transitions to failed after 3 consecutive failures', () async {
      await repo.enqueue('asset-6');
      await repo.markFailed('asset-6', 'err1');
      await repo.markFailed('asset-6', 'err2');
      await repo.markFailed('asset-6', 'err3');
      final result = await repo.getByAssetId('asset-6');
      expect(result!.status, OcrStatus.failed);
      expect(result.failureCount, 3);
    });
  });

  // ---------------------------------------------------------------------------
  // requeueRetrying
  // ---------------------------------------------------------------------------

  group('requeueRetrying', () {
    test('resets retrying records back to pending', () async {
      await repo.enqueue('asset-7');
      await repo.markFailed('asset-7', 'oops');
      expect((await repo.getByAssetId('asset-7'))!.status, OcrStatus.retrying);

      await repo.requeueRetrying();
      expect((await repo.getByAssetId('asset-7'))!.status, OcrStatus.pending);
    });
  });

  // ---------------------------------------------------------------------------
  // getByStatus
  // ---------------------------------------------------------------------------

  group('getByStatus', () {
    test('returns only records with matching status', () async {
      await repo.enqueue('asset-8');
      await repo.enqueue('asset-9');
      await repo.saveResult('asset-9', 'done');

      final pending = await repo.getByStatus(OcrStatus.pending);
      expect(pending.map((e) => e.assetId), contains('asset-8'));
      expect(pending.map((e) => e.assetId), isNot(contains('asset-9')));
    });
  });

  // ---------------------------------------------------------------------------
  // search
  // ---------------------------------------------------------------------------

  group('search', () {
    test('finds assets by substring match in extracted text', () async {
      await repo.enqueue('asset-10');
      await repo.saveResult('asset-10', 'The quick brown fox');
      await repo.enqueue('asset-11');
      await repo.saveResult('asset-11', 'Lorem ipsum dolor');

      final results = await repo.search('quick');
      expect(results.map((e) => e.assetId), contains('asset-10'));
      expect(results.map((e) => e.assetId), isNot(contains('asset-11')));
    });

    test('returns empty list for blank query', () async {
      await repo.enqueue('asset-12');
      await repo.saveResult('asset-12', 'some text');
      final results = await repo.search('');
      expect(results, isEmpty);
    });

    test('is case-insensitive via SQLite LIKE', () async {
      await repo.enqueue('asset-13');
      await repo.saveResult('asset-13', 'Hello World');
      // SQLite LIKE is case-insensitive for ASCII characters.
      final results = await repo.search('hello');
      expect(results.map((e) => e.assetId), contains('asset-13'));
    });
  });

  // ---------------------------------------------------------------------------
  // delete / clearAll
  // ---------------------------------------------------------------------------

  group('delete', () {
    test('removes a single record', () async {
      await repo.enqueue('asset-14');
      await repo.delete('asset-14');
      expect(await repo.getByAssetId('asset-14'), isNull);
    });
  });

  group('clearAll', () {
    test('removes all records', () async {
      await repo.enqueue('asset-15');
      await repo.enqueue('asset-16');
      await repo.clearAll();
      expect(await repo.getAll(), isEmpty);
    });
  });
}
