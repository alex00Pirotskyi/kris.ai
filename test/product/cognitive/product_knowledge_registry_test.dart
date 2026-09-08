// Behavioural proof for module-owned Kristin product knowledge.
//
// Product knowledge is metadata that each capability area owns. The registry
// exists so a module can describe its own concepts without a central catalog
// becoming the hidden source of production truth, and so two modules can never
// silently claim the same concept.
//
// The safety property under test is the one the whole cognitive design rests
// on: a product description is descriptive only. It may never assert live
// availability, health, or current execution authority, because those are
// separate observations owned by the self-awareness and authority layers.

import 'package:flutter_test/flutter_test.dart';
import 'package:kristin_local_agent/product/authority_product_knowledge.dart';
import 'package:kristin_local_agent/product/browser/product_knowledge.dart';
import 'package:kristin_local_agent/product/chat_product_knowledge.dart';
import 'package:kristin_local_agent/product/cognitive/cognitive_model.dart';
import 'package:kristin_local_agent/product/cognitive/runtime_cognitive_enrichment.dart';
import 'package:kristin_local_agent/product/knowledge_product_knowledge.dart';
import 'package:kristin_local_agent/product/models_product_knowledge.dart';
import 'package:kristin_local_agent/product/owner_product_knowledge.dart';
import 'package:kristin_local_agent/product/product_knowledge.dart';
import 'package:kristin_local_agent/product/project_product_knowledge.dart';
import 'package:kristin_local_agent/product/recovery/product_knowledge.dart';
import 'package:kristin_local_agent/product/self_awareness/product_knowledge.dart';
import 'package:kristin_local_agent/product/task_kernel/product_knowledge.dart';

import 'cognitive_test_support.dart';

/// The production registration list. The gateway builds exactly this set; the
/// test binds to the same providers so a module that stops registering, or
/// starts colliding, fails here rather than in a live conversation.
const List<KristinProductKnowledgeProvider> _productionProviders =
    <KristinProductKnowledgeProvider>[
  chatProductKnowledgeProvider,
  projectProductKnowledgeProvider,
  runsProductKnowledgeProvider,
  knowledgeProductKnowledgeProvider,
  ownerProductKnowledgeProvider,
  browserProductKnowledgeProvider,
  modelsProductKnowledgeProvider,
  taskKernelProductKnowledgeProvider,
  capabilitiesProductKnowledgeProvider,
  recoveryProductKnowledgeProvider,
  authorityProductKnowledgeProvider,
];

KristinProductKnowledgeRegistry _productionRegistry() {
  final registry = KristinProductKnowledgeRegistry();
  for (final provider in _productionProviders) {
    registry.register(provider);
  }
  return registry;
}

ProductKnowledgeDescriptor _descriptor(
  String id, {
  String title = 'Title',
  String summary = 'Summary',
  Set<String> keywords = const <String>{'k'},
}) =>
    ProductKnowledgeDescriptor(
      id: id,
      title: title,
      summary: summary,
      keywords: keywords,
    );

void main() {
  group('product knowledge registry', () {
    test('an empty provider id is rejected', () {
      final registry = KristinProductKnowledgeRegistry();
      expect(
        () => registry.register(
          StaticProductKnowledgeProvider(
            providerId: '   ',
            descriptors: <ProductKnowledgeDescriptor>[_descriptor('a')],
          ),
        ),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            'product_knowledge_provider_id_required',
          ),
        ),
      );
      expect(registry.snapshot(), isEmpty);
    });

    test('a duplicate provider id is rejected', () {
      final registry = KristinProductKnowledgeRegistry();
      registry.register(
        StaticProductKnowledgeProvider(
          providerId: 'chat',
          descriptors: <ProductKnowledgeDescriptor>[_descriptor('chat')],
        ),
      );
      expect(
        () => registry.register(
          StaticProductKnowledgeProvider(
            providerId: 'chat',
            descriptors: <ProductKnowledgeDescriptor>[_descriptor('other')],
          ),
        ),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains('duplicate_product_knowledge_provider:chat'),
          ),
        ),
      );
      expect(registry.snapshot().length, 1);
    });

    test('a duplicate knowledge id across providers is rejected', () {
      final registry = KristinProductKnowledgeRegistry();
      registry.register(
        StaticProductKnowledgeProvider(
          providerId: 'first',
          descriptors: <ProductKnowledgeDescriptor>[_descriptor('runs')],
        ),
      );
      expect(
        () => registry.register(
          StaticProductKnowledgeProvider(
            providerId: 'second',
            descriptors: <ProductKnowledgeDescriptor>[_descriptor('runs')],
          ),
        ),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains('duplicate_product_knowledge_id:runs:first:second'),
          ),
        ),
      );
      // The rejected provider left no partial registration behind.
      expect(registry.snapshot().length, 1);
      expect(registry.snapshot().single.providerId, 'first');
    });

    test('a duplicate knowledge id inside one provider is rejected', () {
      final registry = KristinProductKnowledgeRegistry();
      expect(
        () => registry.register(
          StaticProductKnowledgeProvider(
            providerId: 'noisy',
            descriptors: <ProductKnowledgeDescriptor>[
              _descriptor('runs'),
              _descriptor('runs', title: 'Runs again'),
            ],
          ),
        ),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains('duplicate_product_knowledge_id:runs'),
          ),
        ),
      );
      expect(registry.snapshot(), isEmpty);
    });

    test('malformed descriptors are rejected', () {
      for (final descriptor in <ProductKnowledgeDescriptor>[
        _descriptor('  '),
        _descriptor('a', title: '   '),
        _descriptor('a', summary: '  '),
      ]) {
        final registry = KristinProductKnowledgeRegistry();
        expect(
          () => registry.register(
            StaticProductKnowledgeProvider(
              providerId: 'p',
              descriptors: <ProductKnowledgeDescriptor>[descriptor],
            ),
          ),
          throwsA(
            isA<StateError>().having(
              (error) => error.message,
              'message',
              contains('invalid_product_knowledge_descriptor'),
            ),
          ),
        );
        expect(registry.snapshot(), isEmpty);
      }
    });

    test('every expected production provider is registered exactly once', () {
      final registry = _productionRegistry();
      final snapshot = registry.snapshot();
      expect(
        snapshot.map((item) => item.providerId).toSet(),
        <String>{
          'chat',
          'project_manager',
          'runs',
          'knowledge_memory',
          'owner_mode',
          'browser_web_studio',
          'models_providers',
          'universal_task_kernel',
          'self_awareness',
          'autonomic_recovery',
          'authority_execution',
        },
      );
      expect(
        snapshot.map((item) => item.descriptor.id).toSet(),
        <String>{
          'chat',
          'project_manager',
          'runs',
          'knowledge',
          'skills',
          'owner_mode',
          'browser_web_studio',
          'models_providers',
          'task_kernel',
          'capabilities',
          'recovery',
          'authority_execution',
        },
      );
      expect(
        snapshot.map((item) => item.descriptor.id).toList().length,
        snapshot.map((item) => item.descriptor.id).toSet().length,
        reason: 'knowledge ids must be globally unique',
      );
    });

    test('provider metadata is descriptive and never live capability state',
        () {
      // A description that asserts a capability is available, healthy, or
      // currently authorized would let stale product text answer questions
      // that only a live observation may answer.
      final forbidden = RegExp(
        r'\b(?:is|are|currently)\s+(?:available|healthy|enabled|active|granted|authorized|running)\b',
        caseSensitive: false,
      );
      for (final item in _productionRegistry().snapshot()) {
        final text = '${item.descriptor.title} ${item.descriptor.summary}';
        expect(
          forbidden.hasMatch(text),
          isFalse,
          reason:
              '${item.descriptor.id} claims live state: ${item.descriptor.summary}',
        );
      }
    });

    test('registered descriptors expose no availability or authority fields',
        () {
      for (final item in _productionRegistry().snapshot()) {
        final json = item.toJson();
        expect(json.keys.toSet(), <String>{
          'providerId',
          'id',
          'title',
          'summary',
          'keywords',
        });
      }
    });

    test('relevance selection is driven by provider-owned metadata', () async {
      final enrichment =
          CognitiveRuntimeEnrichment(productKnowledge: _productionRegistry());
      final substrate = buildTestSubstrate();

      final recovery = enrichment.replaceProductKnowledgeProjection(
        await substrate.compile(
          const CognitiveContextRequest(
            objective: 'recovery repair after a failure',
            pathway: CognitiveReasoningPathway.recovery,
          ),
        ),
        objective: 'recovery repair after a failure',
      );
      final browser = enrichment.replaceProductKnowledgeProjection(
        await substrate.compile(
          const CognitiveContextRequest(
            objective: 'browser web studio preview of a page',
          ),
        ),
        objective: 'browser web studio preview of a page',
      );

      expect(recovery.includedIds, contains('product:recovery'));
      expect(browser.includedIds, contains('product:browser_web_studio'));
      // Ordering follows the descriptors, so the objective's own concept is
      // rendered before unrelated ones.
      final browserSection = productSection(browser.coordinatorGuidance);
      expect(
        browserSection.indexOf('browser_web_studio'),
        lessThan(browserSection.indexOf('recovery')),
      );
    });

    test('the rendered production section is provider-attributed', () async {
      final enrichment =
          CognitiveRuntimeEnrichment(productKnowledge: _productionRegistry());
      final substrate = buildTestSubstrate();
      final projection = enrichment.replaceProductKnowledgeProjection(
        await substrate.compile(
          const CognitiveContextRequest(objective: 'what is owner mode'),
        ),
        objective: 'what is owner mode',
      );
      final section = productSection(projection.coordinatorGuidance);
      expect(section, contains('[provider='));
      for (final line in section.split('\n').skip(1)) {
        expect(line, startsWith('- '));
        expect(line, contains('[provider='));
      }
    });

    test('production relevance does not read the compatibility catalog', () {
      // kKristinProductKnowledge stays only as a fallback for raw callers.
      // If the enrichment layer ever consults it again, provider-owned
      // metadata silently stops deciding what production renders.
      final enrichmentSource =
          sourceOf('lib/product/cognitive/runtime_cognitive_enrichment.dart');
      expect(enrichmentSource, isNot(contains('kKristinProductKnowledge')));

      final gatewaySource =
          sourceOf('lib/product/cognitive/product_runtime_cognitive.dart');
      expect(gatewaySource, isNot(contains('kKristinProductKnowledge')));
      for (final provider in _productionProviders) {
        expect(gatewaySource, contains(providerSymbolFor(provider.providerId)));
      }
    });
  });
}
