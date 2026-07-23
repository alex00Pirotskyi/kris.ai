import 'package:flutter_test/flutter_test.dart';
import 'package:kristin_local_agent/product/file_adapters.dart';

void main() {
  test('registry exposes native and sandboxed-core adapters', () {
    const registry = FileAdapterRegistry();
    final all = registry.all;
    expect(all.any((adapter) => adapter.id == 'text'), isTrue);
    expect(all.any((adapter) => adapter.id == 'pdf' && adapter.sandboxRequired),
        isTrue);
    expect(all.any((adapter) => adapter.id == 'ooxml'), isTrue);
  });
}
