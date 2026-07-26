import 'dart:math';

class TerrainAssetUsageBalancer {
  static const familyWeights = {'v3': 1, 'v4': 3};

  final Map<String, int> _familyCounts = {'v3': 0, 'v4': 0};
  final Map<String, int> _assetCounts = {};

  String chooseFamily(Iterable<String> availableFamilies) {
    final available = availableFamilies.toSet();
    if (available.isEmpty) {
      throw StateError('At least one terrain family must be available.');
    }
    final totalWeight = familyWeights.values.reduce((a, b) => a + b);
    final totalPlaced = _familyCounts.values.fold(
      0,
      (sum, count) => sum + count,
    );
    final ranked = available.toList()
      ..sort((left, right) {
        final leftWeight = familyWeights[left] ?? 1;
        final rightWeight = familyWeights[right] ?? 1;
        final leftDeficit =
            ((totalPlaced + 1) * leftWeight) -
            ((_familyCounts[left] ?? 0) * totalWeight);
        final rightDeficit =
            ((totalPlaced + 1) * rightWeight) -
            ((_familyCounts[right] ?? 0) * totalWeight);
        final deficitOrder = rightDeficit.compareTo(leftDeficit);
        if (deficitOrder != 0) return deficitOrder;
        final weightOrder = rightWeight.compareTo(leftWeight);
        if (weightOrder != 0) return weightOrder;
        return left.compareTo(right);
      });
    return ranked.first;
  }

  String chooseLeastUsedAsset({
    required Iterable<String> assetNames,
    required int stableValue,
  }) {
    final candidates = assetNames.toList();
    if (candidates.isEmpty) {
      throw StateError('At least one terrain asset must be available.');
    }
    final minimumCount = candidates
        .map((name) => _assetCounts[name] ?? 0)
        .reduce(min);
    final leastUsed =
        candidates
            .where((name) => (_assetCounts[name] ?? 0) == minimumCount)
            .toList()
          ..sort();
    return leastUsed[stableValue % leastUsed.length];
  }

  void record({required String family, required String assetName}) {
    _familyCounts[family] = (_familyCounts[family] ?? 0) + 1;
    _assetCounts[assetName] = (_assetCounts[assetName] ?? 0) + 1;
  }

  int familyCount(String family) => _familyCounts[family] ?? 0;

  int assetCount(String assetName) => _assetCounts[assetName] ?? 0;
}
