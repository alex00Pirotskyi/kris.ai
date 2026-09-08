import 'product_knowledge.dart';

const KristinProductKnowledgeProvider chatProductKnowledgeProvider =
    StaticProductKnowledgeProvider(
  providerId: 'chat',
  descriptors: <ProductKnowledgeDescriptor>[
    ProductKnowledgeDescriptor(
      id: 'chat',
      title: 'Chat',
      summary:
          'Chat is Kristin\'s conversation surface. Informational turns are read-only reasoning; effectful objectives are handed to governed task understanding/planning rather than executed by conversation text.',
      keywords: <String>{'chat', 'conversation', 'answer', 'assistant'},
    ),
  ],
);
