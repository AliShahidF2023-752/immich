import 'dart:typed_data';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/services/live_text.service.dart';

class LiveTextState {
  final bool isProcessing;
  final List<RecognizedTextBlock>? blocks;
  final bool isToggled;

  LiveTextState({
    this.isProcessing = false,
    this.blocks,
    this.isToggled = false,
  });

  LiveTextState copyWith({
    bool? isProcessing,
    List<RecognizedTextBlock>? blocks,
    bool? isToggled,
  }) {
    return LiveTextState(
      isProcessing: isProcessing ?? this.isProcessing,
      blocks: blocks ?? this.blocks,
      isToggled: isToggled ?? this.isToggled,
    );
  }
}

class LiveTextNotifier extends StateNotifier<LiveTextState> {
  LiveTextNotifier() : super(LiveTextState());

  // In-memory cache mapping assetId -> text blocks
  static final Map<String, List<RecognizedTextBlock>> _cache = {};

  void toggle() {
    state = state.copyWith(isToggled: !state.isToggled);
  }

  void hide() {
    if (state.isToggled) {
      state = state.copyWith(isToggled: false);
    }
  }

  Future<void> processImage(String assetId, Uint8List imageBytes) async {
    // If we have a cached result for this asset, use it immediately
    if (_cache.containsKey(assetId)) {
      state = state.copyWith(
        isProcessing: false,
        blocks: _cache[assetId],
      );
      return;
    }

    state = state.copyWith(isProcessing: true, blocks: null, isToggled: false);

    // Call native OCR service (fast mode initially)
    var result = await LiveTextService.recognizeTextBlocks(imageBytes, accuracy: 0);

    // Accurate mode fallback if needed
    if (result != null && result.isEmpty) {
      result = await LiveTextService.recognizeTextBlocks(imageBytes, accuracy: 1);
    }

    if (result != null && result.isNotEmpty) {
      _cache[assetId] = result;
    } else {
      _cache[assetId] = []; // cache empty so we don't re-run
    }

    if (mounted) {
      state = state.copyWith(
        isProcessing: false,
        blocks: _cache[assetId],
      );
    }
  }
}

final liveTextProvider = StateNotifierProvider.family.autoDispose<LiveTextNotifier, LiveTextState, String>((ref, id) {
  return LiveTextNotifier();
});
