import 'package:barry_memory/barry_memory.dart';
import 'package:test/test.dart';

void main() {
  test('retrieves topK', () async {
    final store = InMemoryMemoryStore();
    final embed = DeterministicEmbeddingProvider();
    await store.put(MemoryItem(id: '1', text: 'alpha', embedding: embed.embed('alpha')));
    final out = await store.topK('alpha', 1);
    expect(out.first.id, '1');
  });

  test('autogenerates embedding when item embedding is empty', () async {
    final store = InMemoryMemoryStore();
    await store.put(const MemoryItem(id: '2', text: 'beta', embedding: []));
    final all = await store.all();
    expect(all.single.embedding, isNotEmpty);
    expect(all.single.embeddingSource, EmbeddingSource.local);
  });
}
