import '../product_knowledge.dart';

const KristinProductKnowledgeProvider recoveryProductKnowledgeProvider =
    StaticProductKnowledgeProvider(
  providerId: 'autonomic_recovery',
  descriptors: <ProductKnowledgeDescriptor>[
    ProductKnowledgeDescriptor(
      id: 'recovery',
      title: 'Recovery',
      summary:
          'Recovery observes failures, classifies recoverability and can route bounded repair work through existing governed mechanisms. Recovery knowledge does not bypass permissions or widen tools.',
      keywords: <String>{'recovery', 'failure', 'repair', 'diagnostic'},
    ),
  ],
);
