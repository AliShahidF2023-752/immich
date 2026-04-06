import 'package:drift/drift.dart';
import 'package:immich_mobile/infrastructure/utils/drift_default.mixin.dart';

/// Stores a mapping from [assetId] (remote or local asset identifier)
/// to the on-device path of its low-resolution placeholder image.
///
/// Placeholder files are stored as PNG-encoded images.
/// Records are keyed by [assetId] so that placeholder generation is idempotent —
/// re-running the generation for the same asset simply updates the existing row.
@TableIndex.sql(
  'CREATE INDEX IF NOT EXISTS idx_placeholder_asset_id '
  'ON placeholder_image_entity (asset_id)',
)
class PlaceholderImageEntity extends Table with DriftDefaultsMixin {
  const PlaceholderImageEntity();

  /// The asset's remote UUID (or local device ID when no remote asset exists).
  TextColumn get assetId => text()();

  /// Absolute filesystem path to the stored WebP/JPEG placeholder file.
  TextColumn get filePath => text()();

  /// Width of the generated placeholder in pixels.
  IntColumn get width => integer()();

  /// Height of the generated placeholder in pixels.
  IntColumn get height => integer()();

  /// JPEG quality used when writing the file (1–100).
  ///
  /// Stored for future use when a JPEG encoder is available.
  /// The current PNG implementation uses lossless encoding;
  /// this value is preserved for settings persistence and UI display.
  IntColumn get quality => integer()();

  /// Approximate size of the placeholder file in bytes.
  IntColumn get fileSize => integer().withDefault(const Constant(0))();

  /// When this placeholder was created / last refreshed.
  DateTimeColumn get createdAt =>
      dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {assetId};
}

/// Light domain object returned by repository queries.
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
