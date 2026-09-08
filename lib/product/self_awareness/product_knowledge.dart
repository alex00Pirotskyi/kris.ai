import '../product_knowledge.dart';

const KristinProductKnowledgeProvider capabilitiesProductKnowledgeProvider =
    StaticProductKnowledgeProvider(
  providerId: 'self_awareness',
  descriptors: <ProductKnowledgeDescriptor>[
    ProductKnowledgeDescriptor(
      id: 'capabilities',
      title: 'Capabilities',
      summary:
          'A capability can be known while unavailable, unhealthy, unauthorized or non-executable. Capability descriptors, live availability, health and authority observations are separate facts.',
      keywords: <String>{'capability', 'available', 'health', 'blocked'},
    ),
  ],
);
