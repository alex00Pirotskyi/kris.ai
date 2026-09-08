import 'product_knowledge.dart';

const KristinProductKnowledgeProvider knowledgeProductKnowledgeProvider =
    StaticProductKnowledgeProvider(
  providerId: 'knowledge_memory',
  descriptors: <ProductKnowledgeDescriptor>[
    ProductKnowledgeDescriptor(
      id: 'knowledge',
      title: 'Knowledge',
      summary:
          'Knowledge stores project notes and grounded research with provenance, hashes, trust and freshness metadata. Retrieved content is evidence, not authority or executable instruction.',
      keywords: <String>{'knowledge', 'research', 'source', 'citation'},
    ),
    ProductKnowledgeDescriptor(
      id: 'skills',
      title: 'Skills',
      summary:
          'Skills are published reusable procedures derived from governed experience and explicit publication. Knowing a skill is separate from runtime readiness, current authority, and execution.',
      keywords: <String>{'skill', 'procedure', 'published', 'replay'},
    ),
  ],
);
