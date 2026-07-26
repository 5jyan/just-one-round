class TerrainBlockCache<T> {
  TerrainBlockCache({required this.blockWidth});

  final int blockWidth;
  final Map<int, T> _values = {};

  T? operator [](int blockIndex) => _values[blockIndex];

  T? freezeIfComplete({
    required int blockIndex,
    required Iterable<int> columnIndexes,
    required T Function() build,
  }) {
    final frozen = _values[blockIndex];
    if (frozen != null) return frozen;

    final blockStart = blockIndex * blockWidth;
    final indexes = columnIndexes.toSet();
    final isComplete =
        indexes.length == blockWidth &&
        [
          for (var offset = 0; offset < blockWidth; offset++)
            blockStart + offset,
        ].every(indexes.contains);
    if (!isComplete) return null;

    final value = build();
    _values[blockIndex] = value;
    return value;
  }

  void retainBlocks(Iterable<int> liveBlockIndexes) {
    final live = liveBlockIndexes.toSet();
    _values.removeWhere((blockIndex, _) => !live.contains(blockIndex));
  }
}
