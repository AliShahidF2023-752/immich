import 'package:immich_mobile/domain/models/asset/base_asset.model.dart';
import 'package:immich_mobile/domain/models/search_result.model.dart';
import 'package:immich_mobile/extensions/string_extensions.dart';
import 'package:immich_mobile/infrastructure/repositories/local_ocr.repository.dart';
import 'package:immich_mobile/infrastructure/repositories/search_api.repository.dart';
import 'package:immich_mobile/models/search/search_filter.model.dart';
import 'package:immich_mobile/services/local_ocr.service.dart';
import 'package:logging/logging.dart';
import 'package:openapi/api.dart' as api show AssetVisibility;
import 'package:openapi/api.dart' hide AssetVisibility;

class SearchService {
  final _log = Logger("SearchService");
  final SearchApiRepository _searchApiRepository;

  /// Optional local OCR repository.  When provided and local OCR is enabled,
  /// [searchLocalOcr] returns matching asset IDs from the on-device database.
  final LocalOcrRepository? _localOcrRepository;

  SearchService(this._searchApiRepository, {LocalOcrRepository? localOcrRepository})
      : _localOcrRepository = localOcrRepository;

  Future<List<String>?> getSearchSuggestions(
    SearchSuggestionType type, {
    String? country,
    String? state,
    String? make,
    String? model,
  }) async {
    try {
      return await _searchApiRepository.getSearchSuggestions(
        type,
        country: country,
        state: state,
        make: make,
        model: model,
      );
    } catch (e) {
      _log.warning("Failed to get search suggestions", e);
    }
    return [];
  }

  Future<SearchResult?> search(SearchFilter filter, int page) async {
    try {
      final response = await _searchApiRepository.search(filter, page);

      if (response == null || response.assets.items.isEmpty) {
        return null;
      }

      return SearchResult(
        assets: response.assets.items.map((e) => e.toDto()).toList(),
        nextPage: response.assets.nextPage?.toInt(),
      );
    } catch (error, stackTrace) {
      _log.severe("Failed to search for assets", error, stackTrace);
    }
    return null;
  }

  /// Searches the on-device OCR database for [query].
  ///
  /// Returns a list of asset IDs whose extracted text contains [query].
  /// Returns an empty list when local OCR is disabled or the repository is not
  /// available.
  Future<List<String>> searchLocalOcr(String query) async {
    if (!LocalOcrService.isEnabled || _localOcrRepository == null) return [];
    try {
      return await _localOcrRepository!.search(query).then(
            (results) => results.map((r) => r.assetId).toList(),
          );
    } catch (e, st) {
      _log.warning('Local OCR search failed for "$query"', e, st);
      return [];
    }
  }
}

extension on AssetResponseDto {
  RemoteAsset toDto() {
    return RemoteAsset(
      id: id,
      name: originalFileName,
      checksum: checksum,
      createdAt: fileCreatedAt,
      updatedAt: updatedAt,
      ownerId: ownerId,
      visibility: switch (visibility) {
        api.AssetVisibility.timeline => AssetVisibility.timeline,
        api.AssetVisibility.hidden => AssetVisibility.hidden,
        api.AssetVisibility.archive => AssetVisibility.archive,
        api.AssetVisibility.locked => AssetVisibility.locked,
        _ => AssetVisibility.timeline,
      },
      durationInSeconds: duration.toDuration()?.inSeconds ?? 0,
      height: height?.toInt(),
      width: width?.toInt(),
      isFavorite: isFavorite,
      livePhotoVideoId: livePhotoVideoId,
      thumbHash: thumbhash,
      localId: null,
      type: type.toAssetType(),
      stackId: stack?.id,
      isEdited: isEdited,
    );
  }
}

extension on AssetTypeEnum {
  AssetType toAssetType() => switch (this) {
    AssetTypeEnum.IMAGE => AssetType.image,
    AssetTypeEnum.VIDEO => AssetType.video,
    AssetTypeEnum.AUDIO => AssetType.audio,
    AssetTypeEnum.OTHER => AssetType.other,
    _ => throw Exception('Unknown AssetType value: $this'),
  };
}
