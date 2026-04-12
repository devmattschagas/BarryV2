library barry_memory;

import 'dart:convert';
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

  Map<String, dynamic> toJson() => {
        'id': id,
        'text': text,
        'embedding': embedding,
        'embeddingSource': embeddingSource.name,
      };

  factory MemoryItem.fromJson(Map<String, dynamic> json) => MemoryItem(
        id: json['id'] as String,
        text: json['text'] as String,
        embedding: (json['embedding'] as List<dynamic>? ?? const <dynamic>[]).map((e) => (e as num).toDouble()).toList(),
        embeddingSource: EmbeddingSource.values.firstWhere(
          (e) => e.name == json['embeddingSource'],
          orElse: () => EmbeddingSource.none,
        ),
      );
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
    final values = List<double>.generate(64, (i) => ((text.hashCode >> (i % 16)) & 0xff) / 255);
    final norm = values.fold<double>(0, (p, e) => p + e * e).toDouble();
    final denom = norm == 0 ? 1 : math.sqrt(norm);
    return values.map((e) => e / denom).toList(growable: false);
  }
}

typedef MemorySnapshotLoader = Future<String?> Function();
typedef MemorySnapshotSaver = Future<void> Function(String raw);

class PersistentMemoryStore implements MemoryStore, SemanticRetriever, ContextAssembler {
  PersistentMemoryStore({
    required MemorySnapshotLoader loadSnapshot,
    required MemorySnapshotSaver saveSnapshot,
    EmbeddingProvider? embeddingProvider,
    this.defaultEmbeddingSource = EmbeddingSource.local,
  })  : _loadSnapshot = loadSnapshot,
        _saveSnapshot = saveSnapshot,
        _embeddingProvider = embeddingProvider ?? DeterministicEmbeddingProvider();

  final MemorySnapshotLoader _loadSnapshot;
  final MemorySnapshotSaver _saveSnapshot;
  final EmbeddingProvider _embeddingProvider;
  final EmbeddingSource defaultEmbeddingSource;
  final List<MemoryItem> _items = [];
  bool _hydrated = false;

  Future<void> _ensureHydrated() async {
    if (_hydrated) return;
    _hydrated = true;
    final raw = await _loadSnapshot();
    if (raw == null || raw.trim().isEmpty) return;
    final parsed = jsonDecode(raw) as List<dynamic>;
    _items
      ..clear()
      ..addAll(parsed.whereType<Map<String, dynamic>>().map(MemoryItem.fromJson));
  }

  Future<void> _flush() async {
    final encoded = jsonEncode(_items.map((e) => e.toJson()).toList(growable: false));
    await _saveSnapshot(encoded);
  }

  @override
  Future<void> put(MemoryItem item) async {
    await _ensureHydrated();
    final withEmbedding = item.embedding.isNotEmpty
        ? item
        : item.copyWith(embedding: _embeddingProvider.embed(item.text), embeddingSource: defaultEmbeddingSource);
    _items.add(withEmbedding);
    await _flush();
  }

  @override
  Future<List<MemoryItem>> all() async {
    await _ensureHydrated();
    return List.unmodifiable(_items);
  }

  @override
  Future<List<MemoryItem>> topK(String query, int k) async {
    await _ensureHydrated();
    if (k <= 0 || _items.isEmpty) return const [];

    final q = _embeddingProvider.embed(query);
    final normalized = _items.where((e) => e.embedding.isNotEmpty).toList(growable: false);
    final sorted = [...normalized]..sort((a, b) => _cos(b.embedding, q).compareTo(_cos(a.embedding, q)));
    return sorted.take(k).toList(growable: false);
  }

  @override
  Future<String> assemble(String query) async {
    final best = await topK(query, 6);
    return best.map((e) => '- ${e.text}').join('\n');
  }

  double _cos(List<double> a, List<double> b) {
    double dot = 0;
    for (var i = 0; i < a.length && i < b.length; i++) {
      dot += a[i] * b[i];
    }
    return dot;
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
    final withEmbedding = item.embedding.isNotEmpty
        ? item
        : item.copyWith(embedding: _embeddingProvider.embed(item.text), embeddingSource: defaultEmbeddingSource);
    _items.add(withEmbedding);
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
    final best = await topK(query, 6);
    return best.map((e) => '- ${e.text}').join('\n');
  }

  double _cos(List<double> a, List<double> b) {
    double dot = 0;
    for (var i = 0; i < a.length && i < b.length; i++) {
      dot += a[i] * b[i];
    }
    return dot;
  }
}
