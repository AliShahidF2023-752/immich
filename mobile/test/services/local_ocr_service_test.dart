import 'package:flutter_test/flutter_test.dart';
import 'package:immich_mobile/services/local_ocr.service.dart';
import 'package:immich_mobile/infrastructure/entities/local_ocr.entity.dart';
import 'package:immich_mobile/infrastructure/repositories/local_ocr.repository.dart';
import 'package:mocktail/mocktail.dart';

class MockLocalOcrRepository extends Mock implements LocalOcrRepository {}

class MockOcrProvider extends Mock implements OcrProvider {}

void main() {
  late LocalOcrService sut;
  late MockLocalOcrRepository mockRepo;
  late MockOcrProvider mockProvider;

  setUp(() {
    mockRepo = MockLocalOcrRepository();
    mockProvider = MockOcrProvider();
    sut = LocalOcrService(repository: mockRepo, provider: mockProvider);
  });

  tearDown(() {
    sut.dispose();
  });

  // ---------------------------------------------------------------------------
  // searchText
  // ---------------------------------------------------------------------------

  group('searchText', () {
    test('returns asset IDs from repository search results', () async {
      when(() => mockRepo.search('invoice')).thenAnswer(
        (_) async => [
          const LocalOcrDto(
            assetId: 'id-1',
            filename: 'scan.jpg',
            extractedText: 'invoice total \$100',
            createdAt: _epoch,
            status: OcrStatus.completed,
            failureCount: 0,
          ),
        ],
      );

      final result = await sut.searchText('invoice');
      expect(result, ['id-1']);
    });

    test('returns empty list when repository returns nothing', () async {
      when(() => mockRepo.search('xyz')).thenAnswer((_) async => []);
      final result = await sut.searchText('xyz');
      expect(result, isEmpty);
    });

    test('returns empty list when repository throws', () async {
      when(() => mockRepo.search(any())).thenThrow(Exception('db error'));
      final result = await sut.searchText('query');
      expect(result, isEmpty);
    });
  });
}

// Convenience constant to avoid writing DateTime.now() in every stub.
const _epoch = DateTime(2024, 1, 1);
