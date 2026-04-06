import 'package:drift/drift.dart';
import 'package:immich_mobile/infrastructure/utils/drift_default.mixin.dart';

/// OCR processing status values stored in [LocalOcrEntity.status].
enum OcrStatus {
  pending,
  processing,
  completed,
  failed,
  retrying,
}

/// Stores on-device OCR results for each asset.
///
/// Records persist independently of whether the source asset is still present,
/// so text can still be searched even after remote or local deletion.
@TableIndex.sql(
  'CREATE INDEX IF NOT EXISTS idx_local_ocr_asset_id '
  'ON local_ocr_entity (asset_id)',
)
@TableIndex.sql(
  'CREATE INDEX IF NOT EXISTS idx_local_ocr_status '
  'ON local_ocr_entity (status)',
)
class LocalOcrEntity extends Table with DriftDefaultsMixin {
  const LocalOcrEntity();

  /// Remote UUID or local device ID of the asset.
  TextColumn get assetId => text()();

  /// Original filename of the asset (kept for display / debugging).
  TextColumn get filename => text().withDefault(const Constant(''))();

  /// Full extracted text from the image (empty when not yet processed).
  TextColumn get extractedText => text().withDefault(const Constant(''))();

  /// When the OCR record was created.
  DateTimeColumn get createdAt =>
      dateTime().withDefault(currentDateAndTime)();

  /// When OCR processing last ran for this asset.
  DateTimeColumn get processedAt => dateTime().nullable()();

  /// Current processing status.
  IntColumn get status =>
      intEnum<OcrStatus>().withDefault(const Constant(0))();

  /// Number of consecutive failures (used by the retry queue).
  IntColumn get failureCount => integer().withDefault(const Constant(0))();

  /// Optional human-readable error message from the last failure.
  TextColumn get lastError => text().nullable()();

  @override
  Set<Column> get primaryKey => {assetId};
}

/// Light domain object for OCR results.
class LocalOcrDto {
  final String assetId;
  final String filename;
  final String extractedText;
  final DateTime createdAt;
  final DateTime? processedAt;
  final OcrStatus status;
  final int failureCount;
  final String? lastError;

  const LocalOcrDto({
    required this.assetId,
    required this.filename,
    required this.extractedText,
    required this.createdAt,
    this.processedAt,
    required this.status,
    required this.failureCount,
    this.lastError,
  });
}
