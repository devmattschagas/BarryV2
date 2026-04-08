library barry_memory;

class MemoryItem {
  const MemoryItem({required this.id, required this.text, required this.embedding});
  final String id;
  final String text;
  final List<double> embedding;
}

abstract interface class MemoryStore {
  Future<void> put(MemoryItem item);
  Future<List<MemoryItem>> all();
}

abstract interface class EmbeddingProvider {
  List<double> embed(String text);
}

abstract interface class SemanticRetriever {
  Future<List<MemoryItem>> topK(String query, int k);
}

abstract interface class ContextAssembler {
  Future<String> assemble(String query);
}

class DeterministicEmbeddingProvider implements EmbeddingProvider {
  @override
  List<double> embed(String text) {
    final values = List<double>.generate(8, (i) => ((text.hashCode >> (i * 4)) & 0xff) / 255);
    final norm = values.fold<double>(0, (p, e) => p + e * e).toDouble();
    final denom = norm == 0 ? 1 : norm;
    return values.map((e) => e / denom).toList(growable: false);
  }
}

class InMemoryMemoryStore implements MemoryStore, SemanticRetriever, ContextAssembler {
  final List<MemoryItem> _items = [];
  final EmbeddingProvider _embeddingProvider = DeterministicEmbeddingProvider();

  @override
  Future<void> put(MemoryItem item) async => _items.add(item);

  @override
  Future<List<MemoryItem>> all() async => List.unmodifiable(_items);

  @override
  Future<List<MemoryItem>> topK(String query, int k) async {
    final q = _embeddingProvider.embed(query);
    final sorted = [..._items]..sort((a, b) => _cos(b.embedding, q).compareTo(_cos(a.embedding, q)));
    return sorted.take(k).toList(growable: false);
  }

  @override
  Future<String> assemble(String query) async {
    final best = await topK(query, 3);
    return best.map((e) => e.text).join('\n');
  }

  double _cos(List<double> a, List<double> b) {
    double dot = 0;
    for (var i = 0; i < a.length && i < b.length; i++) {
      dot += a[i] * b[i];
    }
    return dot;
  }
}
