import 'product_knowledge.dart';

const KristinProductKnowledgeProvider authorityProductKnowledgeProvider =
    StaticProductKnowledgeProvider(
  providerId: 'authority_execution',
  descriptors: <ProductKnowledgeDescriptor>[
    ProductKnowledgeDescriptor(
      id: 'authority_execution',
      title: 'Authority and execution',
      summary:
          'Knowledge, capability availability and model proposals never mint permissions. Concrete effects remain constrained by the existing authority service, grants, Owner boundaries and the Runner/tool allow-list.',
      keywords: <String>{'authority', 'permission', 'grant', 'tool', 'runner'},
    ),
  ],
);
