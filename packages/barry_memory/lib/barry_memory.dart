library barry_memory;

import 'dart:math' as math;

enum EmbeddingSource { local, remote, none }

class MemoryItem {
  const MemoryItem({required this.id, required this.text, required this.embedding, this.embeddingSource = EmbeddingSource.none});
  final String id;
  final String text;
  final List<double> embedding;
  final EmbeddingSource embeddingSource;

  MemoryItem copyWith({List<double>? embedding, EmbeddingSource? embeddingSource}) {
    return MemoryItem(
      id: id,
      text: text,
      embedding: embedding ?? this.embedding,
      embeddingSource: embeddingSource ?? this.embeddingSource,
    );
  }
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
    final denom = norm == 0 ? 1 : math.sqrt(norm);
    return values.map((e) => e / denom).toList(growable: false);
  }
}

class InMemoryMemoryStore implements MemoryStore, SemanticRetriever, ContextAssembler {
  InMemoryMemoryStore({EmbeddingProvider? embeddingProvider, this.defaultEmbeddingSource = EmbeddingSource.local})
      : _embeddingProvider = embeddingProvider ?? DeterministicEmbeddingProvider();

  final List<MemoryItem> _items = [];
  final EmbeddingProvider _embeddingProvider;
  final EmbeddingSource defaultEmbeddingSource;

  @override
  Future<void> put(MemoryItem item) async {
    if (item.embedding.isNotEmpty) {
      _items.add(item);
      return;
    }
    final generated = _embeddingProvider.embed(item.text);
    _items.add(item.copyWith(embedding: generated, embeddingSource: defaultEmbeddingSource));
  }

  @override
  Future<List<MemoryItem>> all() async => List.unmodifiable(_items);

  @override
  Future<List<MemoryItem>> topK(String query, int k) async {
    if (k <= 0 || _items.isEmpty) return const [];

    final q = _embeddingProvider.embed(query);
    final normalized = _items.where((e) => e.embedding.isNotEmpty).toList(growable: false);
    final sorted = [...normalized]..sort((a, b) => _cos(b.embedding, q).compareTo(_cos(a.embedding, q)));
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
