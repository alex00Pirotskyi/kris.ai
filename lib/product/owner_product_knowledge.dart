import 'product_knowledge.dart';

const KristinProductKnowledgeProvider ownerProductKnowledgeProvider =
    StaticProductKnowledgeProvider(
  providerId: 'owner_mode',
  descriptors: <ProductKnowledgeDescriptor>[
    ProductKnowledgeDescriptor(
      id: 'owner_mode',
      title: 'Owner Mode',
      summary:
          'Owner Mode is a separately governed high-authority repair/operation path. Its runtime can be known or available while concrete Owner authority remains unevaluated or absent; cognitive access never enters Owner Mode.',
      keywords: <String>{'owner', 'mode', 'authority', 'repair'},
    ),
  ],
);
