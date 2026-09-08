import 'product_knowledge.dart';

const KristinProductKnowledgeProvider projectProductKnowledgeProvider =
    StaticProductKnowledgeProvider(
  providerId: 'project_manager',
  descriptors: <ProductKnowledgeDescriptor>[
    ProductKnowledgeDescriptor(
      id: 'project_manager',
      title: 'Project Manager',
      summary:
          'Project Manager represents registered project workspaces and their selected/current project state. Selecting or knowing a project does not itself grant write or execution authority.',
      keywords: <String>{'project', 'workspace', 'manager', 'repository'},
    ),
  ],
);

const KristinProductKnowledgeProvider runsProductKnowledgeProvider =
    StaticProductKnowledgeProvider(
  providerId: 'runs',
  descriptors: <ProductKnowledgeDescriptor>[
    ProductKnowledgeDescriptor(
      id: 'runs',
      title: 'Runs',
      summary:
          'Runs are durable governed executions with plans, permissions, progress, evidence, verification and terminal outcomes. Conversation knowledge is distinct from starting a Run.',
      keywords: <String>{'run', 'execution', 'progress', 'evidence'},
    ),
  ],
);
