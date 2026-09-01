import 'package:cf_map_flutter/utils/creator_fandom_ordering.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('recommendation order uses interest, X list, then alphabetically', () {
    final result = orderCreatorFandoms(
      fandoms: const ['Zelda', 'Fate', 'Vocaloid', 'Blue Archive', 'Original'],
      interestOrder: const ['Vocaloid', 'Fate'],
      xList: const ['Blue Archive', 'Zelda'],
    );

    expect(
      result,
      const ['Vocaloid', 'Fate', 'Blue Archive', 'Zelda', 'Original'],
    );
  });

  test('catalog order puts Original before X list and alphabetical fallback',
      () {
    final result = orderCreatorFandoms(
      fandoms: const ['Zelda', 'Fate', 'Original', 'Blue Archive', 'Arknights'],
      xList: const ['Fate', 'Blue Archive'],
      originalFirst: true,
    );

    expect(
      result,
      const ['Original', 'Fate', 'Blue Archive', 'Arknights', 'Zelda'],
    );
  });

  test('canonical search match stays ahead of Original and X-list fandoms', () {
    final result = orderCreatorFandoms(
      fandoms: const ['Original', 'Genshin Impact', 'Attack on Titan'],
      interestOrder: const ['Attack on Titan'],
      xList: const ['Genshin Impact', 'Original'],
    );

    expect(result, const ['Attack on Titan', 'Genshin Impact', 'Original']);
  });
}
