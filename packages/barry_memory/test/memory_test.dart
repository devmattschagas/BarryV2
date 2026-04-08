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
}
