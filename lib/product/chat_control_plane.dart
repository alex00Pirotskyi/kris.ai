import 'domain.dart';

enum ChatCapabilityCategory {
  create,
  understand,
  operate,
  quality,
  connections,
  system,
}

enum ChatTargetType {
  project,
  model,
  provider,
  capability,
  runtime,
  workspace,
}

enum ChatActionClass { informational, small, substantial }

enum ChatRiskClass { none, readOnly, execution, mutation, sensitive, destructive }

enum ChatUnderstandingPolicy { never, actions }

enum ChatPlanningPolicy { never, substantial, always }

enum ChatExecutionRoute {
  agent,
  projectAnalyze,
  projectTest,
  projectVerify,
  projectBuild,
  projectRun,
  projectStop,
  projectRestart,
  open,
  connectProvider,
  selectModel,
  ownerMode,
  diagnose,
  navigation,
  help,
}

enum ChatInteractionKind { informational, action, ambiguous }

enum ChatAutocompleteKind { command, mention }

class KristinCapability {
  const KristinCapability({
    required this.id,
    required this.displayName,
    required this.description,
    required this.category,
    required this.slashCommands,
    required this.mentionAliases,
    required this.acceptedTargetTypes,
    required this.actionClass,
    required this.riskClass,
    required this.understandingPolicy,
    required this.planningPolicy,
    required this.route,
    required this.preferredMode,
    this.availableWithoutTarget = true,
  });

  final String id;
  final String displayName;
  final String description;
  final ChatCapabilityCategory category;
  final List<String> slashCommands;
  final List<String> mentionAliases;
  final Set<ChatTargetType> acceptedTargetTypes;
  final ChatActionClass actionClass;
  final ChatRiskClass riskClass;
  final ChatUnderstandingPolicy understandingPolicy;
  final ChatPlanningPolicy planningPolicy;
  final ChatExecutionRoute route;
  final CommandMode preferredMode;
  final bool availableWithoutTarget;

  String get canonicalSlash =>
      slashCommands.isEmpty ? '' : '/${slashCommands.first}';

  bool acceptsTarget(ChatTargetType type) => acceptedTargetTypes.contains(type);
}

const List<KristinCapability> kKristinCapabilities = <KristinCapability>[
  KristinCapability(
    id: 'build',
    displayName: 'Build',
    description: 'Create or change product code, or build a selected project.',
    category: ChatCapabilityCategory.create,
    slashCommands: <String>['build', 'create'],
    mentionAliases: <String>['build'],
    acceptedTargetTypes: <ChatTargetType>{ChatTargetType.project},
    actionClass: ChatActionClass.substantial,
    riskClass: ChatRiskClass.mutation,
    understandingPolicy: ChatUnderstandingPolicy.actions,
    planningPolicy: ChatPlanningPolicy.substantial,
    route: ChatExecutionRoute.projectBuild,
    preferredMode: CommandMode.build,
  ),
  KristinCapability(
    id: 'fix',
    displayName: 'Fix',
    description: 'Diagnose, repair, and verify a project problem.',
    category: ChatCapabilityCategory.create,
    slashCommands: <String>['fix', 'repair'],
    mentionAliases: <String>['fix'],
    acceptedTargetTypes: <ChatTargetType>{ChatTargetType.project},
    actionClass: ChatActionClass.substantial,
    riskClass: ChatRiskClass.mutation,
    understandingPolicy: ChatUnderstandingPolicy.actions,
    planningPolicy: ChatPlanningPolicy.substantial,
    route: ChatExecutionRoute.agent,
    preferredMode: CommandMode.fix,
  ),
  KristinCapability(
    id: 'search',
    displayName: 'Search',
    description: 'Search current public sources and return grounded findings.',
    category: ChatCapabilityCategory.understand,
    slashCommands: <String>['search', 'web_search', 'research'],
    mentionAliases: <String>['web', 'search'],
    acceptedTargetTypes: <ChatTargetType>{
      ChatTargetType.capability,
      ChatTargetType.workspace,
    },
    actionClass: ChatActionClass.small,
    riskClass: ChatRiskClass.readOnly,
    understandingPolicy: ChatUnderstandingPolicy.actions,
    planningPolicy: ChatPlanningPolicy.never,
    route: ChatExecutionRoute.agent,
    preferredMode: CommandMode.ask,
  ),
  KristinCapability(
    id: 'analyze',
    displayName: 'Analyze',
    description: 'Analyze a selected project without changing it.',
    category: ChatCapabilityCategory.understand,
    slashCommands: <String>['analyze', 'analyse'],
    mentionAliases: <String>['analyze'],
    acceptedTargetTypes: <ChatTargetType>{ChatTargetType.project},
    actionClass: ChatActionClass.small,
    riskClass: ChatRiskClass.readOnly,
    understandingPolicy: ChatUnderstandingPolicy.actions,
    planningPolicy: ChatPlanningPolicy.never,
    route: ChatExecutionRoute.projectAnalyze,
    preferredMode: CommandMode.analyze,
  ),
  KristinCapability(
    id: 'review',
    displayName: 'Review',
    description: 'Review a selected project and report practical findings.',
    category: ChatCapabilityCategory.understand,
    slashCommands: <String>['review', 'audit'],
    mentionAliases: <String>['review'],
    acceptedTargetTypes: <ChatTargetType>{ChatTargetType.project},
    actionClass: ChatActionClass.small,
    riskClass: ChatRiskClass.readOnly,
    understandingPolicy: ChatUnderstandingPolicy.actions,
    planningPolicy: ChatPlanningPolicy.never,
    route: ChatExecutionRoute.projectAnalyze,
    preferredMode: CommandMode.review,
  ),
  KristinCapability(
    id: 'test',
    displayName: 'Test',
    description: 'Run the selected project test profile.',
    category: ChatCapabilityCategory.quality,
    slashCommands: <String>['test'],
    mentionAliases: <String>['test'],
    acceptedTargetTypes: <ChatTargetType>{ChatTargetType.project},
    actionClass: ChatActionClass.small,
    riskClass: ChatRiskClass.execution,
    understandingPolicy: ChatUnderstandingPolicy.actions,
    planningPolicy: ChatPlanningPolicy.never,
    route: ChatExecutionRoute.projectTest,
    preferredMode: CommandMode.run,
    availableWithoutTarget: false,
  ),
  KristinCapability(
    id: 'verify',
    displayName: 'Verify',
    description: 'Verify the selected project or latest governed result.',
    category: ChatCapabilityCategory.quality,
    slashCommands: <String>['verify'],
    mentionAliases: <String>['verification', 'verify'],
    acceptedTargetTypes: <ChatTargetType>{ChatTargetType.project},
    actionClass: ChatActionClass.small,
    riskClass: ChatRiskClass.execution,
    understandingPolicy: ChatUnderstandingPolicy.actions,
    planningPolicy: ChatPlanningPolicy.never,
    route: ChatExecutionRoute.projectVerify,
    preferredMode: CommandMode.review,
    availableWithoutTarget: false,
  ),
  KristinCapability(
    id: 'run',
    displayName: 'Run',
    description: 'Start a selected project through the managed project runtime.',
    category: ChatCapabilityCategory.operate,
    slashCommands: <String>['run', 'start'],
    mentionAliases: <String>['run'],
    acceptedTargetTypes: <ChatTargetType>{
      ChatTargetType.project,
      ChatTargetType.runtime,
    },
    actionClass: ChatActionClass.small,
    riskClass: ChatRiskClass.execution,
    understandingPolicy: ChatUnderstandingPolicy.actions,
    planningPolicy: ChatPlanningPolicy.never,
    route: ChatExecutionRoute.projectRun,
    preferredMode: CommandMode.run,
    availableWithoutTarget: false,
  ),
  KristinCapability(
    id: 'stop',
    displayName: 'Stop',
    description: 'Stop a managed project process safely.',
    category: ChatCapabilityCategory.operate,
    slashCommands: <String>['stop'],
    mentionAliases: <String>['stop'],
    acceptedTargetTypes: <ChatTargetType>{
      ChatTargetType.project,
      ChatTargetType.runtime,
    },
    actionClass: ChatActionClass.small,
    riskClass: ChatRiskClass.execution,
    understandingPolicy: ChatUnderstandingPolicy.actions,
    planningPolicy: ChatPlanningPolicy.never,
    route: ChatExecutionRoute.projectStop,
    preferredMode: CommandMode.run,
    availableWithoutTarget: false,
  ),
  KristinCapability(
    id: 'restart',
    displayName: 'Restart',
    description: 'Restart a managed project process.',
    category: ChatCapabilityCategory.operate,
    slashCommands: <String>['restart'],
    mentionAliases: <String>['restart'],
    acceptedTargetTypes: <ChatTargetType>{
      ChatTargetType.project,
      ChatTargetType.runtime,
    },
    actionClass: ChatActionClass.small,
    riskClass: ChatRiskClass.execution,
    understandingPolicy: ChatUnderstandingPolicy.actions,
    planningPolicy: ChatPlanningPolicy.never,
    route: ChatExecutionRoute.projectRestart,
    preferredMode: CommandMode.run,
    availableWithoutTarget: false,
  ),
  KristinCapability(
    id: 'open',
    displayName: 'Open',
    description: 'Open a project or deep workspace view.',
    category: ChatCapabilityCategory.operate,
    slashCommands: <String>['open'],
    mentionAliases: <String>['open'],
    acceptedTargetTypes: <ChatTargetType>{
      ChatTargetType.project,
      ChatTargetType.workspace,
      ChatTargetType.capability,
    },
    actionClass: ChatActionClass.small,
    riskClass: ChatRiskClass.none,
    understandingPolicy: ChatUnderstandingPolicy.actions,
    planningPolicy: ChatPlanningPolicy.never,
    route: ChatExecutionRoute.open,
    preferredMode: CommandMode.ask,
    availableWithoutTarget: false,
  ),
  KristinCapability(
    id: 'connect',
    displayName: 'Connect',
    description: 'Open the governed connection flow for a provider or service.',
    category: ChatCapabilityCategory.connections,
    slashCommands: <String>['connect'],
    mentionAliases: <String>['connect'],
    acceptedTargetTypes: <ChatTargetType>{ChatTargetType.provider},
    actionClass: ChatActionClass.small,
    riskClass: ChatRiskClass.sensitive,
    understandingPolicy: ChatUnderstandingPolicy.actions,
    planningPolicy: ChatPlanningPolicy.never,
    route: ChatExecutionRoute.connectProvider,
    preferredMode: CommandMode.ask,
    availableWithoutTarget: false,
  ),
  KristinCapability(
    id: 'use',
    displayName: 'Use model',
    description: 'Select a model or provider for the next eligible task.',
    category: ChatCapabilityCategory.connections,
    slashCommands: <String>['use'],
    mentionAliases: <String>['model'],
    acceptedTargetTypes: <ChatTargetType>{
      ChatTargetType.model,
      ChatTargetType.provider,
    },
    actionClass: ChatActionClass.small,
    riskClass: ChatRiskClass.none,
    understandingPolicy: ChatUnderstandingPolicy.actions,
    planningPolicy: ChatPlanningPolicy.never,
    route: ChatExecutionRoute.selectModel,
    preferredMode: CommandMode.ask,
    availableWithoutTarget: false,
  ),
  KristinCapability(
    id: 'owner',
    displayName: 'Owner Mode',
    description: 'Inspect or enter the governed Owner Mode flow.',
    category: ChatCapabilityCategory.system,
    slashCommands: <String>['owner'],
    mentionAliases: <String>['owner'],
    acceptedTargetTypes: <ChatTargetType>{ChatTargetType.capability},
    actionClass: ChatActionClass.small,
    riskClass: ChatRiskClass.sensitive,
    understandingPolicy: ChatUnderstandingPolicy.actions,
    planningPolicy: ChatPlanningPolicy.never,
    route: ChatExecutionRoute.ownerMode,
    preferredMode: CommandMode.ask,
  ),
  KristinCapability(
    id: 'diagnose',
    displayName: 'Diagnose',
    description: 'Run the canonical capability or project health check.',
    category: ChatCapabilityCategory.quality,
    slashCommands: <String>['diagnose', 'doctor'],
    mentionAliases: <String>['doctor', 'diagnostics'],
    acceptedTargetTypes: <ChatTargetType>{
      ChatTargetType.project,
      ChatTargetType.capability,
    },
    actionClass: ChatActionClass.small,
    riskClass: ChatRiskClass.readOnly,
    understandingPolicy: ChatUnderstandingPolicy.actions,
    planningPolicy: ChatPlanningPolicy.never,
    route: ChatExecutionRoute.diagnose,
    preferredMode: CommandMode.analyze,
  ),
  KristinCapability(
    id: 'help',
    displayName: 'Help',
    description: 'Show concise user-facing capability groups and examples.',
    category: ChatCapabilityCategory.system,
    slashCommands: <String>['help'],
    mentionAliases: <String>['help'],
    acceptedTargetTypes: <ChatTargetType>{ChatTargetType.capability},
    actionClass: ChatActionClass.informational,
    riskClass: ChatRiskClass.none,
    understandingPolicy: ChatUnderstandingPolicy.never,
    planningPolicy: ChatPlanningPolicy.never,
    route: ChatExecutionRoute.help,
    preferredMode: CommandMode.ask,
  ),
  KristinCapability(
    id: 'new_chat',
    displayName: 'New chat',
    description: 'Start a fresh conversation.',
    category: ChatCapabilityCategory.system,
    slashCommands: <String>['new'],
    mentionAliases: <String>[],
    acceptedTargetTypes: <ChatTargetType>{},
    actionClass: ChatActionClass.small,
    riskClass: ChatRiskClass.none,
    understandingPolicy: ChatUnderstandingPolicy.never,
    planningPolicy: ChatPlanningPolicy.never,
    route: ChatExecutionRoute.navigation,
    preferredMode: CommandMode.ask,
  ),
  KristinCapability(
    id: 'projects',
    displayName: 'Project Manager',
    description: 'Open the persistent project control workspace.',
    category: ChatCapabilityCategory.system,
    slashCommands: <String>['projects', 'project', 'manager'],
    mentionAliases: <String>['project-manager'],
    acceptedTargetTypes: <ChatTargetType>{ChatTargetType.project},
    actionClass: ChatActionClass.small,
    riskClass: ChatRiskClass.none,
    understandingPolicy: ChatUnderstandingPolicy.never,
    planningPolicy: ChatPlanningPolicy.never,
    route: ChatExecutionRoute.navigation,
    preferredMode: CommandMode.ask,
  ),
  KristinCapability(
    id: 'runs',
    displayName: 'Runs',
    description: 'Open the deep execution view.',
    category: ChatCapabilityCategory.system,
    slashCommands: <String>['runs'],
    mentionAliases: <String>['runs'],
    acceptedTargetTypes: <ChatTargetType>{ChatTargetType.project},
    actionClass: ChatActionClass.small,
    riskClass: ChatRiskClass.none,
    understandingPolicy: ChatUnderstandingPolicy.never,
    planningPolicy: ChatPlanningPolicy.never,
    route: ChatExecutionRoute.navigation,
    preferredMode: CommandMode.ask,
  ),
  KristinCapability(
    id: 'prompts',
    displayName: 'Prompt Studio',
    description: 'Open the advanced prompt workbench.',
    category: ChatCapabilityCategory.system,
    slashCommands: <String>['prompts'],
    mentionAliases: <String>['prompt-studio'],
    acceptedTargetTypes: <ChatTargetType>{ChatTargetType.workspace},
    actionClass: ChatActionClass.small,
    riskClass: ChatRiskClass.none,
    understandingPolicy: ChatUnderstandingPolicy.never,
    planningPolicy: ChatPlanningPolicy.never,
    route: ChatExecutionRoute.navigation,
    preferredMode: CommandMode.ask,
  ),
  KristinCapability(
    id: 'knowledge',
    displayName: 'Knowledge',
    description: 'Open project knowledge and run memory.',
    category: ChatCapabilityCategory.system,
    slashCommands: <String>['knowledge', 'sources', 'memory'],
    mentionAliases: <String>['knowledge'],
    acceptedTargetTypes: <ChatTargetType>{
      ChatTargetType.project,
      ChatTargetType.workspace,
    },
    actionClass: ChatActionClass.small,
    riskClass: ChatRiskClass.none,
    understandingPolicy: ChatUnderstandingPolicy.never,
    planningPolicy: ChatPlanningPolicy.never,
    route: ChatExecutionRoute.navigation,
    preferredMode: CommandMode.ask,
  ),
  KristinCapability(
    id: 'logs',
    displayName: 'Logs',
    description: 'Open the technical log workspace.',
    category: ChatCapabilityCategory.system,
    slashCommands: <String>['logs'],
    mentionAliases: <String>['logs'],
    acceptedTargetTypes: <ChatTargetType>{
      ChatTargetType.project,
      ChatTargetType.workspace,
    },
    actionClass: ChatActionClass.small,
    riskClass: ChatRiskClass.none,
    understandingPolicy: ChatUnderstandingPolicy.never,
    planningPolicy: ChatPlanningPolicy.never,
    route: ChatExecutionRoute.navigation,
    preferredMode: CommandMode.ask,
  ),
];

class ChatCapabilityRegistry {
  const ChatCapabilityRegistry({this.capabilities = kKristinCapabilities});

  final List<KristinCapability> capabilities;

  KristinCapability? byId(String id) {
    final normalized = id.trim().toLowerCase();
    for (final capability in capabilities) {
      if (capability.id == normalized) return capability;
    }
    return null;
  }

  KristinCapability? bySlash(String slash) {
    final normalized = slash
        .trim()
        .toLowerCase()
        .replaceFirst(RegExp(r'^/'), '');
    for (final capability in capabilities) {
      if (capability.slashCommands.contains(normalized)) return capability;
    }
    return null;
  }

  KristinCapability? byMention(String mention) {
    final normalized = mention
        .trim()
        .toLowerCase()
        .replaceFirst(RegExp(r'^@'), '');
    for (final capability in capabilities) {
      if (capability.mentionAliases.contains(normalized)) return capability;
    }
    return null;
  }

  List<KristinCapability> searchSlash(String query, {int limit = 8}) {
    final needle = query
        .trim()
        .toLowerCase()
        .replaceFirst(RegExp(r'^/'), '');
    final ranked = <_CapabilityScore>[];
    for (final capability in capabilities) {
      if (capability.slashCommands.isEmpty) continue;
      final aliases = capability.slashCommands;
      final exact = aliases.any((value) => value == needle);
      final prefix = aliases.any((value) => value.startsWith(needle));
      final contains = aliases.any((value) => value.contains(needle)) ||
          capability.displayName.toLowerCase().contains(needle) ||
          capability.description.toLowerCase().contains(needle);
      final score = exact
          ? 0
          : prefix
              ? 1
              : contains
                  ? 2
                  : 3;
      if (needle.isEmpty || score < 3) {
        ranked.add(_CapabilityScore(capability, score));
      }
    }
    ranked.sort((a, b) {
      final score = a.score.compareTo(b.score);
      if (score != 0) return score;
      return a.capability.displayName.compareTo(b.capability.displayName);
    });
    return ranked
        .take(limit)
        .map((entry) => entry.capability)
        .toList(growable: false);
  }

  List<String> validate() {
    final problems = <String>[];
    final ids = <String>{};
    final slash = <String, String>{};
    final mentions = <String, String>{};
    for (final capability in capabilities) {
      if (!ids.add(capability.id)) {
        problems.add('Duplicate capability id: ${capability.id}');
      }
      for (final alias in capability.slashCommands) {
        final normalized = alias.trim().toLowerCase();
        final existing = slash[normalized];
        if (existing != null && existing != capability.id) {
          problems.add(
            'Slash alias /$normalized maps to both $existing and ${capability.id}.',
          );
        } else {
          slash[normalized] = capability.id;
        }
      }
      for (final alias in capability.mentionAliases) {
        final normalized = alias.trim().toLowerCase();
        final existing = mentions[normalized];
        if (existing != null && existing != capability.id) {
          problems.add(
            'Mention @$normalized maps to both $existing and ${capability.id}.',
          );
        } else {
          mentions[normalized] = capability.id;
        }
      }
    }
    return problems;
  }
}

class _CapabilityScore {
  const _CapabilityScore(this.capability, this.score);

  final KristinCapability capability;
  final int score;
}

class ChatTarget {
  const ChatTarget({
    required this.id,
    required this.type,
    required this.displayName,
    required this.aliases,
    this.description = '',
    this.status = '',
    this.available = true,
  });

  final String id;
  final ChatTargetType type;
  final String displayName;
  final List<String> aliases;
  final String description;
  final String status;
  final bool available;

  bool matches(String value) {
    final normalized = _normalizeMention(value);
    if (_normalizeMention(id) == normalized ||
        _normalizeMention(displayName) == normalized) {
      return true;
    }
    return aliases.any((item) => _normalizeMention(item) == normalized);
  }

  bool fuzzyMatches(String value) {
    final normalized = _normalizeMention(value);
    if (normalized.isEmpty) return true;
    return _normalizeMention(id).contains(normalized) ||
        _normalizeMention(displayName).contains(normalized) ||
        aliases.any((item) => _normalizeMention(item).contains(normalized));
  }
}

class ParsedChatInput {
  const ParsedChatInput({
    required this.originalText,
    required this.commandToken,
    required this.arguments,
    required this.mentions,
  });

  final String originalText;
  final String commandToken;
  final String arguments;
  final List<String> mentions;

  bool get hasExplicitCommand => commandToken.isNotEmpty;
}

class ChatCommandMentionParser {
  const ChatCommandMentionParser();

  ParsedChatInput parse(String input) {
    final value = input.trim();
    final commandMatch =
        RegExp(r'^/([A-Za-z][A-Za-z0-9_-]*)').firstMatch(value);
    final command = commandMatch?.group(1)?.toLowerCase() ?? '';
    final arguments = commandMatch == null
        ? value
        : value.substring(commandMatch.end).trimLeft();
    final mentions = RegExp(r'@([A-Za-z0-9][A-Za-z0-9._:-]*)')
        .allMatches(value)
        .map((match) => match.group(1)!.toLowerCase())
        .toSet()
        .toList(growable: false);
    return ParsedChatInput(
      originalText: value,
      commandToken: command,
      arguments: arguments,
      mentions: mentions,
    );
  }
}

class ChatInteractionDecision {
  const ChatInteractionDecision({
    required this.kind,
    required this.parsed,
    required this.capability,
    required this.targets,
    required this.unresolvedMentions,
    required this.interpretedGoal,
    required this.mode,
    required this.riskClass,
    required this.needsUnderstanding,
    required this.needsPlan,
    required this.ambiguous,
  });

  final ChatInteractionKind kind;
  final ParsedChatInput parsed;
  final KristinCapability? capability;
  final List<ChatTarget> targets;
  final List<String> unresolvedMentions;
  final String interpretedGoal;
  final CommandMode mode;
  final ChatRiskClass riskClass;
  final bool needsUnderstanding;
  final bool needsPlan;
  final bool ambiguous;

  bool get explicitCommand => parsed.hasExplicitCommand;
  bool get isAction => kind == ChatInteractionKind.action;
  bool get isInformational => kind == ChatInteractionKind.informational;
}

class ChatInteractionPolicy {
  const ChatInteractionPolicy();

  bool needsUnderstanding(KristinCapability capability) =>
      capability.actionClass != ChatActionClass.informational &&
      capability.understandingPolicy == ChatUnderstandingPolicy.actions;

  bool needsPlan(
    KristinCapability capability,
    ParsedChatInput parsed, {
    required bool naturalLanguage,
  }) {
    if (capability.planningPolicy == ChatPlanningPolicy.never) return false;
    if (capability.planningPolicy == ChatPlanningPolicy.always) return true;
    if (naturalLanguage) return true;
    final residual = parsed.arguments
        .replaceAll(RegExp(r'@[A-Za-z0-9][A-Za-z0-9._:-]*'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    return residual.split(' ').where((item) => item.isNotEmpty).length > 2;
  }
}

class ChatIntentCompiler {
  const ChatIntentCompiler({
    this.registry = const ChatCapabilityRegistry(),
    this.parser = const ChatCommandMentionParser(),
    this.policy = const ChatInteractionPolicy(),
  });

  final ChatCapabilityRegistry registry;
  final ChatCommandMentionParser parser;
  final ChatInteractionPolicy policy;

  ChatInteractionDecision compile(
    String input, {
    CommandMode inferredMode = CommandMode.ask,
    List<ChatTarget> knownTargets = const <ChatTarget>[],
  }) {
    final parsed = parser.parse(input);
    final targets = <ChatTarget>[];
    final unresolved = <String>[];
    for (final mention in parsed.mentions) {
      ChatTarget? resolved;
      for (final target in knownTargets) {
        if (target.matches(mention)) {
          resolved = target;
          break;
        }
      }
      if (resolved != null) {
        targets.add(resolved);
      } else if (registry.byMention(mention) == null) {
        unresolved.add(mention);
      }
    }

    if (parsed.hasExplicitCommand) {
      final capability = registry.bySlash(parsed.commandToken);
      if (capability == null) {
        return _decision(
          kind: ChatInteractionKind.ambiguous,
          parsed: parsed,
          capability: null,
          targets: targets,
          unresolved: unresolved,
          goal: 'Interpret /${parsed.commandToken} without executing it yet.',
          mode: inferredMode,
          risk: ChatRiskClass.none,
          understanding: true,
          plan: false,
          ambiguous: true,
        );
      }
      if (capability.actionClass == ChatActionClass.informational) {
        return _decision(
          kind: ChatInteractionKind.informational,
          parsed: parsed,
          capability: capability,
          targets: targets,
          unresolved: unresolved,
          goal: _goalFor(capability, parsed, targets),
          mode: capability.preferredMode,
          risk: capability.riskClass,
          understanding: false,
          plan: false,
          ambiguous: unresolved.isNotEmpty,
        );
      }
      return _decision(
        kind: ChatInteractionKind.action,
        parsed: parsed,
        capability: capability,
        targets: targets,
        unresolved: unresolved,
        goal: _goalFor(capability, parsed, targets),
        mode: capability.preferredMode,
        risk: _riskFor(capability, parsed.originalText),
        understanding: policy.needsUnderstanding(capability),
        plan: policy.needsPlan(
          capability,
          parsed,
          naturalLanguage: false,
        ),
        ambiguous: unresolved.isNotEmpty ||
            (!capability.availableWithoutTarget && targets.isEmpty),
      );
    }

    if (_isInformationalLanguage(parsed.originalText)) {
      return _decision(
        kind: ChatInteractionKind.informational,
        parsed: parsed,
        capability: null,
        targets: targets,
        unresolved: unresolved,
        goal: parsed.originalText,
        mode: CommandMode.ask,
        risk: ChatRiskClass.none,
        understanding: false,
        plan: false,
        ambiguous: false,
      );
    }

    final capability = _naturalCapability(parsed.originalText, inferredMode);
    if (capability != null && _isActionLanguage(parsed.originalText)) {
      return _decision(
        kind: ChatInteractionKind.action,
        parsed: parsed,
        capability: capability,
        targets: targets,
        unresolved: unresolved,
        goal: _goalFor(capability, parsed, targets),
        mode: capability.preferredMode,
        risk: _riskFor(capability, parsed.originalText),
        understanding: policy.needsUnderstanding(capability),
        plan: policy.needsPlan(
          capability,
          parsed,
          naturalLanguage: true,
        ),
        ambiguous: unresolved.isNotEmpty,
      );
    }

    if (inferredMode == CommandMode.ask ||
        inferredMode == CommandMode.analyze ||
        inferredMode == CommandMode.review) {
      return _decision(
        kind: ChatInteractionKind.informational,
        parsed: parsed,
        capability: null,
        targets: targets,
        unresolved: unresolved,
        goal: parsed.originalText,
        mode: CommandMode.ask,
        risk: ChatRiskClass.none,
        understanding: false,
        plan: false,
        ambiguous: false,
      );
    }

    final fallback = registry.byId(
      inferredMode == CommandMode.fix ? 'fix' : 'build',
    );
    return _decision(
      kind: ChatInteractionKind.ambiguous,
      parsed: parsed,
      capability: fallback,
      targets: targets,
      unresolved: unresolved,
      goal: parsed.originalText,
      mode: inferredMode,
      risk: fallback?.riskClass ?? ChatRiskClass.mutation,
      understanding: true,
      plan: fallback != null &&
          policy.needsPlan(fallback, parsed, naturalLanguage: true),
      ambiguous: true,
    );
  }

  ChatInteractionDecision _decision({
    required ChatInteractionKind kind,
    required ParsedChatInput parsed,
    required KristinCapability? capability,
    required List<ChatTarget> targets,
    required List<String> unresolved,
    required String goal,
    required CommandMode mode,
    required ChatRiskClass risk,
    required bool understanding,
    required bool plan,
    required bool ambiguous,
  }) {
    return ChatInteractionDecision(
      kind: kind,
      parsed: parsed,
      capability: capability,
      targets: List<ChatTarget>.unmodifiable(targets),
      unresolvedMentions: List<String>.unmodifiable(unresolved),
      interpretedGoal: goal,
      mode: mode,
      riskClass: risk,
      needsUnderstanding: understanding,
      needsPlan: plan,
      ambiguous: ambiguous,
    );
  }

  KristinCapability? _naturalCapability(String input, CommandMode inferredMode) {
    final action = _leadingAction(input);
    const buildActions = <String>{
      'build',
      'create',
      'make',
      'develop',
      'implement',
      'change',
      'add',
      'update',
      'refactor',
      'migrate',
      'delete',
      'remove',
      'rename',
      'move',
    };
    if (buildActions.contains(action)) return registry.byId('build');
    if (const <String>{'fix', 'repair', 'debug'}.contains(action)) {
      return registry.byId('fix');
    }
    if (const <String>{'search', 'research', 'look up'}.contains(action)) {
      return registry.byId('search');
    }
    if (const <String>{'analyze', 'analyse', 'inspect'}.contains(action)) {
      return registry.byId('analyze');
    }
    if (const <String>{'review', 'audit', 'assess'}.contains(action)) {
      return registry.byId('review');
    }
    if (action == 'test') return registry.byId('test');
    if (action == 'verify') return registry.byId('verify');
    if (const <String>{'run', 'launch', 'start'}.contains(action)) {
      return registry.byId('run');
    }
    if (action == 'stop') return registry.byId('stop');
    if (action == 'restart') return registry.byId('restart');
    if (action == 'open') return registry.byId('open');
    if (action == 'connect') return registry.byId('connect');
    if (action == 'use') return registry.byId('use');
    if (action == 'enable owner mode') return registry.byId('owner');
    if (const <String>{'diagnose', 'troubleshoot'}.contains(action)) {
      return registry.byId('diagnose');
    }
    if (inferredMode == CommandMode.build) return registry.byId('build');
    if (inferredMode == CommandMode.fix) return registry.byId('fix');
    if (inferredMode == CommandMode.run) return registry.byId('run');
    if (inferredMode == CommandMode.review) return registry.byId('review');
    return null;
  }

  ChatRiskClass _riskFor(KristinCapability capability, String input) {
    final normalized = _normalized(input);
    if (RegExp(r'^(?:please\s+)?(?:delete|remove)\b')
            .hasMatch(normalized) ||
        RegExp(
          r'\b(?:delete|remove)\s+(?:the\s+)?(?:file|folder|project|data|database)\b',
        ).hasMatch(normalized)) {
      return ChatRiskClass.destructive;
    }
    return capability.riskClass;
  }

  String _goalFor(
    KristinCapability capability,
    ParsedChatInput parsed,
    List<ChatTarget> targets,
  ) {
    final target = targets.isEmpty ? '' : targets.first.displayName;
    final argument = parsed.hasExplicitCommand
        ? parsed.arguments
            .replaceAll(RegExp(r'@[A-Za-z0-9][A-Za-z0-9._:-]*'), ' ')
            .replaceAll(RegExp(r'\s+'), ' ')
            .trim()
        : parsed.originalText.trim();
    switch (capability.id) {
      case 'search':
        return argument.isEmpty
            ? 'Search current public sources.'
            : 'Search current public sources for "$argument" and summarize what is found.';
      case 'run':
        return target.isEmpty ? 'Run the selected project.' : 'Run $target.';
      case 'stop':
        return target.isEmpty ? 'Stop the selected project.' : 'Stop $target.';
      case 'restart':
        return target.isEmpty
            ? 'Restart the selected project.'
            : 'Restart $target.';
      case 'test':
        return target.isEmpty ? 'Test the selected project.' : 'Test $target.';
      case 'verify':
        return target.isEmpty
            ? 'Verify the selected project.'
            : 'Verify $target.';
      case 'analyze':
      case 'review':
        if (target.isNotEmpty) {
          return argument.isEmpty
              ? '${capability.displayName} $target.'
              : '${capability.displayName} $target: $argument.';
        }
        return argument.isEmpty
            ? '${capability.displayName} the selected project.'
            : '${capability.displayName} $argument.';
      case 'connect':
        return target.isEmpty
            ? 'Connect the selected provider through the governed connection flow.'
            : 'Connect $target through the governed connection flow.';
      case 'use':
        return target.isEmpty
            ? 'Use the selected model for the next eligible task.'
            : 'Use $target for the next eligible task.';
      case 'owner':
        return 'Open the governed Owner Mode flow without widening authority automatically.';
      case 'diagnose':
        return target.isEmpty
            ? 'Diagnose the selected project and Kristin capabilities.'
            : 'Diagnose $target.';
      case 'open':
        return target.isEmpty ? 'Open the selected workspace.' : 'Open $target.';
      case 'build':
        if (target.isNotEmpty && argument.isEmpty) {
          return 'Build $target using its canonical project build capability.';
        }
        return argument.isEmpty ? parsed.originalText : 'Build $argument.';
      case 'fix':
        return argument.isEmpty ? parsed.originalText : 'Fix $argument.';
      default:
        return parsed.originalText;
    }
  }
}

class UnderstandingDraft {
  const UnderstandingDraft({
    required this.originalRequest,
    required this.acceptedRequest,
    required this.summary,
    required this.revision,
    required this.alternativeIndex,
  });

  final String originalRequest;
  final String acceptedRequest;
  final String summary;
  final int revision;
  final int alternativeIndex;
}

class UnderstandingHistory {
  const UnderstandingHistory(this.revisions);

  factory UnderstandingHistory.initial(ChatInteractionDecision decision) {
    return UnderstandingHistory(<UnderstandingDraft>[
      UnderstandingDraft(
        originalRequest: decision.parsed.originalText,
        acceptedRequest: decision.parsed.originalText,
        summary: decision.interpretedGoal,
        revision: 1,
        alternativeIndex: 0,
      ),
    ]);
  }

  final List<UnderstandingDraft> revisions;

  UnderstandingDraft get current => revisions.last;

  UnderstandingHistory adjust(String adjustment) {
    final value = adjustment.trim();
    if (value.isEmpty) return this;
    final draft = current;
    return _append(
      UnderstandingDraft(
        originalRequest: draft.originalRequest,
        acceptedRequest: '${draft.acceptedRequest}\n\nAdjustment: $value',
        summary: '${draft.summary}\n\nAdjustment: $value',
        revision: draft.revision + 1,
        alternativeIndex: draft.alternativeIndex,
      ),
    );
  }

  UnderstandingHistory alternate(ChatInteractionDecision decision) {
    final draft = current;
    final index = draft.alternativeIndex + 1;
    final prefix = index.isOdd
        ? 'Same goal, interpreted more narrowly:'
        : 'Same goal, interpreted by outcome first:';
    return _append(
      UnderstandingDraft(
        originalRequest: draft.originalRequest,
        acceptedRequest: draft.acceptedRequest,
        summary: '$prefix ${decision.interpretedGoal.trim()}',
        revision: draft.revision + 1,
        alternativeIndex: index,
      ),
    );
  }

  UnderstandingHistory _append(UnderstandingDraft draft) {
    final values = <UnderstandingDraft>[...revisions, draft];
    if (values.length > 6) {
      values.removeRange(0, values.length - 6);
    }
    return UnderstandingHistory(List<UnderstandingDraft>.unmodifiable(values));
  }
}

class ChatAutocompleteSuggestion {
  const ChatAutocompleteSuggestion({
    required this.kind,
    required this.insertText,
    required this.label,
    required this.description,
    this.capability,
    this.target,
  });

  final ChatAutocompleteKind kind;
  final String insertText;
  final String label;
  final String description;
  final KristinCapability? capability;
  final ChatTarget? target;
}

class ChatAutocompleteEngine {
  const ChatAutocompleteEngine({
    this.registry = const ChatCapabilityRegistry(),
    this.parser = const ChatCommandMentionParser(),
  });

  final ChatCapabilityRegistry registry;
  final ChatCommandMentionParser parser;

  List<ChatAutocompleteSuggestion> suggestions({
    required String text,
    required int cursorOffset,
    List<ChatTarget> targets = const <ChatTarget>[],
    int limit = 7,
  }) {
    final safeOffset = cursorOffset.clamp(0, text.length).toInt();
    final prefix = text.substring(0, safeOffset);
    final trimmedLeft = prefix.trimLeft();
    if (trimmedLeft.startsWith('/') &&
        !trimmedLeft.contains(RegExp(r'\s'))) {
      final query = trimmedLeft.substring(1);
      return registry.searchSlash(query, limit: limit).map((capability) {
        return ChatAutocompleteSuggestion(
          kind: ChatAutocompleteKind.command,
          insertText: '${capability.canonicalSlash} ',
          label: capability.canonicalSlash,
          description: capability.description,
          capability: capability,
        );
      }).toList(growable: false);
    }

    final mentionMatch = RegExp(r'@([A-Za-z0-9._:-]*)$').firstMatch(prefix);
    if (mentionMatch == null) return const <ChatAutocompleteSuggestion>[];
    final query = mentionMatch.group(1) ?? '';
    final parsed = parser.parse(prefix);
    final capability =
        parsed.hasExplicitCommand ? registry.bySlash(parsed.commandToken) : null;
    final accepted =
        capability?.acceptedTargetTypes ?? ChatTargetType.values.toSet();
    final ranked = targets
        .where(
          (target) =>
              accepted.contains(target.type) && target.fuzzyMatches(query),
        )
        .toList(growable: false);
    ranked.sort((a, b) {
      final exact = (a.matches(query) ? 0 : 1).compareTo(b.matches(query) ? 0 : 1);
      if (exact != 0) return exact;
      final availability =
          (b.available ? 1 : 0).compareTo(a.available ? 1 : 0);
      if (availability != 0) return availability;
      return a.displayName.compareTo(b.displayName);
    });
    return ranked.take(limit).map((target) {
      final alias = target.aliases.isEmpty ? target.id : target.aliases.first;
      return ChatAutocompleteSuggestion(
        kind: ChatAutocompleteKind.mention,
        insertText: '@${_normalizeMention(alias)}',
        label: '@${_normalizeMention(alias)}',
        description: target.status.isEmpty ? target.description : target.status,
        target: target,
      );
    }).toList(growable: false);
  }
}

bool isInformationalChatRequest(String input) => _isInformationalLanguage(input);

bool isSemanticActionRequest(String input) => _isActionLanguage(input);

bool _isInformationalLanguage(String input) {
  final normalized = _normalized(input);
  if (normalized.isEmpty) return false;
  if (_isActionLanguage(normalized)) return false;
  if (normalized.endsWith('?')) return true;
  if (RegExp(
    r'^(?:what|why|how|when|where|who|which|whose|is|are|am|was|were|do|does|did|can|could|would|should|will|has|have|had)\b',
  ).hasMatch(normalized)) {
    return true;
  }
  if (RegExp(
    r'^(?:explain|describe|tell me|help me understand|what is|what are)\b',
  ).hasMatch(normalized)) {
    return true;
  }
  if (RegExp(
    r'^(?:hi|hello|hey|hiya|howdy|good morning|good afternoon|good evening)\b',
  ).hasMatch(normalized)) {
    return true;
  }
  return RegExp(
    r'^(?:thanks|thank you|who are you|what can you do|how are you|help|chat)\b',
  ).hasMatch(normalized);
}

bool _isActionLanguage(String input) {
  final normalized = _normalized(input);
  if (normalized.isEmpty) return false;
  const action =
      r'(?:build|create|make|develop|implement|fix|repair|debug|refactor|migrate|run|launch|start|stop|restart|open|search|research|look up|analyze|analyse|inspect|review|audit|assess|test|verify|connect|use|enable owner mode|diagnose|troubleshoot|delete|remove|rename|move|update|change|add)';
  if (RegExp('^(?:please\\s+)?$action\\b').hasMatch(normalized)) return true;
  if (RegExp('^(?:can|could|would|will)\\s+you\\s+$action\\b')
      .hasMatch(normalized)) {
    return true;
  }
  if (RegExp(
    '^i\\s+(?:want|need|would like)\\s+(?:you\\s+to\\s+)?$action\\b',
  ).hasMatch(normalized)) {
    return true;
  }
  return RegExp('^(?:actually\\s+)?$action\\b').hasMatch(normalized);
}

String _leadingAction(String input) {
  final normalized = _normalized(input);
  final cleaned = normalized
      .replaceFirst(RegExp(r'^please\s+'), '')
      .replaceFirst(RegExp(r'^(?:can|could|would|will)\s+you\s+'), '')
      .replaceFirst(
        RegExp(r'^i\s+(?:want|need|would like)\s+(?:you\s+to\s+)?'),
        '',
      )
      .replaceFirst(RegExp(r'^actually\s+'), '');
  for (final phrase in const <String>[
    'enable owner mode',
    'look up',
    'build',
    'create',
    'make',
    'develop',
    'implement',
    'fix',
    'repair',
    'debug',
    'refactor',
    'migrate',
    'run',
    'launch',
    'start',
    'stop',
    'restart',
    'open',
    'search',
    'research',
    'analyze',
    'analyse',
    'inspect',
    'review',
    'audit',
    'assess',
    'test',
    'verify',
    'connect',
    'use',
    'diagnose',
    'troubleshoot',
    'delete',
    'remove',
    'rename',
    'move',
    'update',
    'change',
    'add',
  ]) {
    if (cleaned == phrase || cleaned.startsWith('$phrase ')) return phrase;
  }
  return '';
}

String _normalized(String input) => input
    .trim()
    .toLowerCase()
    .replaceAll(RegExp(r'\s+'), ' ')
    .replaceAll(RegExp(r'[.!]+$'), '');

String _normalizeMention(String input) => input
    .trim()
    .toLowerCase()
    .replaceFirst(RegExp(r'^@'), '')
    .replaceAll(RegExp(r'\s+'), '-');
