/// Minimal repository contracts shared by JSON compatibility stores and the
/// SQLite-backed durable workflow kernel.
abstract interface class EntityRepository<T> {
  Future<List<T>> all();

  Future<T?> get(String id);

  Future<void> put(T item);

  Future<void> putAll(Iterable<T> values);

  Future<void> remove(String id);

  Future<void> removeWhere(bool Function(T item) predicate);

  Future<void> replaceAll(Iterable<T> values);
}

abstract interface class JsonDocumentRepository {
  Future<Object?> read({Object? fallback});

  Future<void> write(Object? value);
}
