import 'product_knowledge.dart';

const KristinProductKnowledgeProvider modelsProductKnowledgeProvider =
    StaticProductKnowledgeProvider(
  providerId: 'models_providers',
  descriptors: <ProductKnowledgeDescriptor>[
    ProductKnowledgeDescriptor(
      id: 'models_providers',
      title: 'Models and providers',
      summary:
          'Language models/providers are replaceable reasoning engines used by Kristin. Provider discovery and the selected exact model are runtime state; a model must not infer Kristin\'s product capabilities from its own pretrained abilities.',
      keywords: <String>{'model', 'provider', 'ollama', 'reasoning'},
    ),
  ],
);
