import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/infrastructure/repositories/local_ocr.repository.dart';
import 'package:immich_mobile/providers/infrastructure/db.provider.dart';
import 'package:immich_mobile/services/local_ocr.service.dart';
import 'package:immich_mobile/services/placeholder.service.dart';

// ---------------------------------------------------------------------------
// Placeholder providers
// ---------------------------------------------------------------------------

/// Provides [PlaceholderService] backed by the Drift database.
final placeholderServiceProvider = Provider<PlaceholderService>(
  (ref) => PlaceholderService(ref.watch(driftProvider)),
);

// ---------------------------------------------------------------------------
// Local OCR providers
// ---------------------------------------------------------------------------

/// Provides [LocalOcrRepository] backed by the Drift database.
final localOcrRepositoryProvider = Provider<LocalOcrRepository>(
  (ref) => LocalOcrRepository(ref.watch(driftProvider)),
);

/// Provides [LocalOcrService].
///
/// The service is kept alive for the lifetime of the app since it manages a
/// background processing queue.  Call [LocalOcrService.dispose] on sign-out.
final localOcrServiceProvider = Provider<LocalOcrService>((ref) {
  final service = LocalOcrService(
    repository: ref.watch(localOcrRepositoryProvider),
  );
  ref.onDispose(service.dispose);
  return service;
});
