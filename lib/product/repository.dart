import 'domain.dart';

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

/// Optional server-side filtering for stores that can do it without loading
/// the whole collection.
///
/// Evidence is the collection that made this necessary: it grows for the life
/// of the installation, and the run hot path only ever wants the rows for one
/// run. Reading every row and filtering in Dart turned a bounded lookup into a
/// full-history scan on every work-item attempt and every 2-second run refresh.
///
/// Stores that cannot filter natively simply do not implement this, and callers
/// fall back to [EntityRepository.all].
abstract interface class ScopedEntityQuery<T> {
  /// Records whose top-level JSON [field] equals [value].
  Future<List<T>> whereFieldEquals(String field, String value);
}

/// Optional indexed access to the most recent runs.
///
/// The activity view polls this every two seconds while a run is executing.
/// Each run row carries a whole run snapshot -- contract, plan, work items,
/// budget -- so loading every run to keep one project's newest hundred made
/// that poll scale with total run history. `runs` already carries an index on
/// (project_id, updated_at DESC, id) for exactly this query.
abstract interface class ScopedRunQuery {
  Future<List<RunRecord>> recentRuns({String? projectId, required int limit});
}

abstract interface class JsonDocumentRepository {
  Future<Object?> read({Object? fallback});

  Future<void> write(Object? value);
}
