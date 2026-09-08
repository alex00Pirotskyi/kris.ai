import '../product_knowledge.dart';

const KristinProductKnowledgeProvider browserProductKnowledgeProvider =
    StaticProductKnowledgeProvider(
  providerId: 'browser_web_studio',
  descriptors: <ProductKnowledgeDescriptor>[
    ProductKnowledgeDescriptor(
      id: 'browser_web_studio',
      title: 'Browser and Web Studio',
      summary:
          'Kristin has an application-owned browser/Web Studio product surface for governed browser sessions, public-page work and local web-project preview. Current usability must come from live browser/runtime observations, not from this product description.',
      keywords: <String>{'browser', 'web', 'studio', 'preview', 'page'},
    ),
  ],
);
