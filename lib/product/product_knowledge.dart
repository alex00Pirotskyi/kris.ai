final class ProductKnowledgeDescriptor {
  const ProductKnowledgeDescriptor({
    required this.id,
    required this.title,
    required this.summary,
    required this.keywords,
  });

  final String id;
  final String title;
  final String summary;
  final Set<String> keywords;

  Map<String, Object?> toJson() => <String, Object?>{
        'id': id,
        'title': title,
        'summary': summary,
        'keywords': keywords.toList()..sort(),
      };
}

abstract interface class KristinProductKnowledgeProvider {
  String get providerId;
  Iterable<ProductKnowledgeDescriptor> describeProductKnowledge();
}

final class StaticProductKnowledgeProvider
    implements KristinProductKnowledgeProvider {
  const StaticProductKnowledgeProvider({
    required this.providerId,
    required this.descriptors,
  });

  @override
  final String providerId;
  final List<ProductKnowledgeDescriptor> descriptors;

  @override
  Iterable<ProductKnowledgeDescriptor> describeProductKnowledge() => descriptors;
}

final class RegisteredProductKnowledge {
  const RegisteredProductKnowledge({
    required this.providerId,
    required this.descriptor,
  });

  final String providerId;
  final ProductKnowledgeDescriptor descriptor;

  Map<String, Object?> toJson() => <String, Object?>{
        'providerId': providerId,
        ...descriptor.toJson(),
      };
}

/// Provider-owned descriptive product knowledge.
///
/// This registry is metadata only: it cannot advertise live availability,
/// health, authority or execution. Those remain authoritative in the
/// self-awareness/capability and authority layers.
final class KristinProductKnowledgeRegistry {
  final Map<String, KristinProductKnowledgeProvider> _providers =
      <String, KristinProductKnowledgeProvider>{};
  final Map<String, String> _ownerByKnowledgeId = <String, String>{};

  void register(KristinProductKnowledgeProvider provider) {
    final providerId = provider.providerId.trim();
    if (providerId.isEmpty) {
      throw StateError('product_knowledge_provider_id_required');
    }
    if (_providers.containsKey(providerId)) {
      throw StateError('duplicate_product_knowledge_provider:$providerId');
    }

    final descriptors = provider.describeProductKnowledge().toList(growable: false);
    for (final descriptor in descriptors) {
      final id = descriptor.id.trim();
      if (id.isEmpty || descriptor.title.trim().isEmpty || descriptor.summary.trim().isEmpty) {
        throw StateError('invalid_product_knowledge_descriptor:$providerId:$id');
      }
      final existing = _ownerByKnowledgeId[id];
      if (existing != null) {
        throw StateError(
          'duplicate_product_knowledge_id:$id:$existing:$providerId',
        );
      }
    }

    _providers[providerId] = provider;
    for (final descriptor in descriptors) {
      _ownerByKnowledgeId[descriptor.id.trim()] = providerId;
    }
  }

  Iterable<KristinProductKnowledgeProvider> get providers => _providers.values;

  List<RegisteredProductKnowledge> snapshot() {
    final values = <RegisteredProductKnowledge>[];
    final providers = _providers.values.toList()
      ..sort((a, b) => a.providerId.compareTo(b.providerId));
    for (final provider in providers) {
      final descriptors = provider.describeProductKnowledge().toList()
        ..sort((a, b) => a.id.compareTo(b.id));
      for (final descriptor in descriptors) {
        values.add(
          RegisteredProductKnowledge(
            providerId: provider.providerId,
            descriptor: descriptor,
          ),
        );
      }
    }
    return List<RegisteredProductKnowledge>.unmodifiable(values);
  }
}
