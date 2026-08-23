import 'dart:collection';
import 'dart:convert';

class PolicyInputException implements Exception {
  PolicyInputException(this.message);
  final String message;
  @override
  String toString() => 'PolicyInputException: $message';
}

class DeterministicPolicyEngineV2 {
  DeterministicPolicyEngineV2({
    required Map<String, dynamic> accessCatalog,
    required Map<String, dynamic> policyConfig,
  }) : _accessCatalog = _copy(accessCatalog),
       _policyConfig = _copy(policyConfig);

  final Map<String, dynamic> _accessCatalog;
  final Map<String, dynamic> _policyConfig;

  Map<String, dynamic> evaluate(Map<String, dynamic> input) {
    final request = _copy(input);
    if (request['schemaVersion'] != '2.0.0') {
      throw PolicyInputException('request schemaVersion must be 2.0.0');
    }
    final binding = _map(request['binding'], 'binding');
    final effect = _map(request['effect'], 'effect');
    final context = _map(request['context'], 'context');
    final profileId = _string(binding['accessProfileId'], 'accessProfileId');
    final profiles = <String, Map<String, dynamic>>{};
    for (final item in _list(_accessCatalog['profiles'], 'profiles')) {
      final profile = _map(item, 'profile');
      profiles[_string(profile['profileId'], 'profileId')] = profile;
    }
    final profile = profiles[profileId];
    if (profile == null) {
      throw PolicyInputException('unknown access profile: $profileId');
    }

    final capabilityId = _string(binding['capabilityId'], 'capabilityId');
    final toolId = _string(binding['toolId'], 'toolId');
    final actorId = _string(binding['actorId'], 'actorId');
    _string(binding['runId'], 'runId');
    _string(binding['taskId'], 'taskId');

    final reasons = <String>{};
    final registry = _map(
      _policyConfig['capabilityRegistry'],
      'capabilityRegistry',
    );
    final capabilityValue = registry[capabilityId];
    final capability = capabilityValue is Map
        ? Map<String, dynamic>.from(capabilityValue)
        : <String, dynamic>{
            'domain': 'unknown',
            'risk': 'high',
            'tools': <dynamic>[],
          };
    if (capabilityValue is! Map) {
      reasons.add('unknown_capability');
    }
    final tools = _list(
      capability['tools'],
      'capability.tools',
    ).map((item) => item.toString()).toSet();
    if (!tools.contains(toolId)) {
      reasons.add('tool_not_registered_for_capability');
    }
    if (effect['domain'] != capability['domain']) {
      reasons.add('capability_effect_mismatch');
    }
    if (capability['actor'] != null && actorId != capability['actor']) {
      reasons.add('wrong_actor');
    }

    final scope = _baseScope(profile, context);
    final baseScope = _copy(scope);
    final budgets = _profileBudgets(profileId);
    final requestedBudgets = _map(
      request['requestedBudgets'] ?? <String, dynamic>{},
      'requestedBudgets',
    );
    for (final field in budgets.keys.toList(growable: false)) {
      final requested = requestedBudgets[field] ?? budgets[field];
      if (requested is! int || requested < 0) {
        reasons.add('invalid_budget');
        budgets[field] = 0;
      } else {
        budgets[field] = requested < budgets[field]!
            ? requested
            : budgets[field]!;
      }
    }

    var approvalPolicy = profile['approvalPolicy'].toString();
    final deniedCapabilities = <String>{};
    final deniedTools = <String>{};
    var forceDeny = false;
    final overlays =
        _list(
            request['overlays'] ?? <dynamic>[],
            'overlays',
          ).map((item) => _map(item, 'overlay')).toList(growable: false)
          ..sort((left, right) {
            final layer = _layerRank(
              left['layer'],
            ).compareTo(_layerRank(right['layer']));
            return layer != 0
                ? layer
                : _string(
                    left['overlayId'],
                    'overlayId',
                  ).compareTo(_string(right['overlayId'], 'overlayId'));
          });
    for (final overlay in overlays) {
      deniedCapabilities.addAll(_strings(overlay['denyCapabilities']));
      deniedTools.addAll(_strings(overlay['denyTools']));
      forceDeny = forceDeny || overlay['forceDeny'] == true;
      if (overlay.containsKey('pathPrefixes')) {
        scope['pathPrefixes'] = _pathIntersection(
          _strings(scope['pathPrefixes']),
          _strings(
            overlay['pathPrefixes'],
          ).map(_normalizePath).toList(growable: false),
        );
      }
      if (overlay.containsKey('networkDestinations')) {
        scope['networkDestinations'] = _intersection(
          _strings(scope['networkDestinations']),
          _strings(
            overlay['networkDestinations'],
          ).map((item) => item.toLowerCase()).toList(growable: false),
        );
      }
      if (overlay.containsKey('browserProfiles')) {
        scope['browserProfiles'] = _intersection(
          _strings(scope['browserProfiles']),
          _strings(overlay['browserProfiles']),
        );
      }
      if (overlay.containsKey('secretLeaseIds')) {
        scope['secretLeaseIds'] = _intersection(
          _strings(scope['secretLeaseIds']),
          _strings(overlay['secretLeaseIds']),
        );
      }
      final maximums = _map(
        overlay['maxBudgets'] ?? <String, dynamic>{},
        'overlay.maxBudgets',
      );
      for (final entry in maximums.entries) {
        final value = entry.value;
        if (!budgets.containsKey(entry.key) || value is! int || value < 0) {
          reasons.add('invalid_overlay_budget');
        } else if (value < budgets[entry.key]!) {
          budgets[entry.key] = value;
        }
      }
      if (overlay['approvalPolicy'] != null) {
        approvalPolicy = _stricterApproval(
          approvalPolicy,
          overlay['approvalPolicy'].toString(),
        );
      }
    }
    if (deniedCapabilities.contains(capabilityId)) {
      reasons.add('capability_denied_by_overlay');
    }
    if (deniedTools.contains(toolId)) {
      reasons.add('tool_denied_by_overlay');
    }
    if (forceDeny) {
      reasons.add('force_deny');
    }

    final approval = _map(
      request['approval'] ?? <String, dynamic>{},
      'approval',
    );
    final approvalResult = _validApproval(approval);
    if (approvalResult.error != null) {
      reasons.add(approvalResult.error!);
    }

    final widening = _map(
      request['explicitWidening'] ?? <String, dynamic>{},
      'explicitWidening',
    );
    final wideningRequested = const <String>{
      'restorePaths',
      'restoreNetworkDestinations',
      'restoreBrowserProfiles',
      'restoreSecretLeaseIds',
    }.any((key) => _strings(widening[key]).isNotEmpty);
    if (wideningRequested) {
      final wideningApproval = _validApproval(widening);
      if (wideningApproval.error != null) {
        reasons.add(wideningApproval.error!);
      }
      if (!wideningApproval.approved) {
        reasons.add('explicit_widening_not_approved');
      } else {
        for (final path in _strings(widening['restorePaths'])) {
          final normalized = _normalizePath(path);
          if (_strings(
            baseScope['pathPrefixes'],
          ).any((prefix) => _pathWithin(normalized, prefix))) {
            scope['pathPrefixes'] = <String>{
              ..._strings(scope['pathPrefixes']),
              normalized,
            }.toList()..sort();
          } else {
            reasons.add('widening_exceeds_profile_ceiling');
          }
        }
        for (final destination in _strings(
          widening['restoreNetworkDestinations'],
        )) {
          if (_destinationAllowed(
            destination,
            _strings(baseScope['networkDestinations']),
          )) {
            scope['networkDestinations'] = <String>{
              ..._strings(scope['networkDestinations']),
              destination.toLowerCase(),
            }.toList()..sort();
          } else {
            reasons.add('widening_exceeds_profile_ceiling');
          }
        }
        for (final browserProfile in _strings(
          widening['restoreBrowserProfiles'],
        )) {
          final baseProfiles = _strings(baseScope['browserProfiles']);
          if (baseProfiles.contains('*') ||
              baseProfiles.contains(browserProfile)) {
            scope['browserProfiles'] = <String>{
              ..._strings(scope['browserProfiles']),
              browserProfile,
            }.toList()..sort();
          } else {
            reasons.add('widening_exceeds_profile_ceiling');
          }
        }
        for (final leaseId in _strings(widening['restoreSecretLeaseIds'])) {
          if (_strings(baseScope['secretLeaseIds']).contains(leaseId)) {
            scope['secretLeaseIds'] = <String>{
              ..._strings(scope['secretLeaseIds']),
              leaseId,
            }.toList()..sort();
          } else {
            reasons.add('widening_exceeds_profile_ceiling');
          }
        }
      }
    }

    final domain = effect['domain'];
    final action = effect['action'];
    final target = effect['target'];
    if (domain == 'filesystem') {
      final filesystem = _map(scope['filesystem'], 'filesystem');
      if (filesystem[action] != true) {
        reasons.add('filesystem_action_denied');
      }
      if (target is! String ||
          !_strings(
            scope['pathPrefixes'],
          ).any((prefix) => _pathWithin(target, prefix))) {
        reasons.add('path_outside_effective_scope');
      }
    } else if (domain == 'process') {
      final process = _map(scope['process'], 'process');
      final requiredFlag = <String, String>{
        'finite_command': 'finiteCommands',
        'interactive_pty': 'interactivePty',
        'package': 'packages',
        'service': 'services',
      }[action];
      if (action == 'elevation') {
        if (!const <String>{
          'interactive_only',
          'preconfigured',
        }.contains(process['elevation'])) {
          reasons.add('elevation_denied');
        }
      } else if (requiredFlag == null || process[requiredFlag] != true) {
        reasons.add('process_action_denied');
      }
    } else if (domain == 'network') {
      if (target is! String ||
          !_destinationAllowed(
            target,
            _strings(scope['networkDestinations']),
          )) {
        reasons.add('network_destination_denied');
      }
      if (context['privateNetwork'] == true &&
          _map(scope['network'], 'network')['privateAddresses'] != true) {
        reasons.add('private_network_denied');
      }
      if (action == 'listen' &&
          _map(scope['network'], 'network')['listen'] != true) {
        reasons.add('network_listen_denied');
      }
    } else if (domain == 'browser') {
      final profileName = target is String ? target : '';
      final allowed = _strings(scope['browserProfiles']);
      if (!allowed.contains('*') && !allowed.contains(profileName)) {
        reasons.add('browser_profile_denied');
      }
      if (context['authenticatedBrowser'] == true &&
          _map(scope['browser'], 'browser')['authenticatedProfiles'] != true) {
        reasons.add('authenticated_browser_denied');
      }
    } else if (domain == 'secret') {
      final lease = target is String ? target : '';
      if (_map(scope['credentials'], 'credentials')['mode'] == 'none' ||
          !_strings(scope['secretLeaseIds']).contains(lease)) {
        reasons.add('secret_lease_denied');
      }
      if (context['rawReveal'] == true) {
        reasons.add('raw_secret_reveal_denied');
      }
    } else if (domain == 'sandbox') {
      if (profileId != 'isolated_untrusted' || profile['sandboxed'] != true) {
        reasons.add('sandbox_profile_required');
      }
    } else {
      reasons.add('unknown_effect_domain');
    }

    final approvalRequired =
        approvalPolicy == 'always' ||
        (approvalPolicy == 'high_risk_only' && capability['risk'] == 'high');
    String status;
    List<String> reasonCodes;
    if (reasons.isNotEmpty) {
      status = 'deny';
      reasonCodes = reasons.toList()..sort();
    } else if (approvalRequired && !approvalResult.approved) {
      status = 'approval_required';
      reasonCodes = <String>['approval_required'];
    } else {
      status = 'allow';
      reasonCodes = <String>[];
    }

    final decisionId =
        'policy-${_fnv64(_canonical(<String, dynamic>{'request': _normalizeRequestForHash(request), 'policyRevision': _policyConfig['policyRevision']}))}';
    final grantDraft = status == 'allow'
        ? <String, dynamic>{
            'issuer': <String, dynamic>{
              'actorId': 'desktop_host',
              'authority': 'desktop_host:deterministic_policy',
            },
            'binding': <String, dynamic>{
              'runId': binding['runId'],
              'taskId': binding['taskId'],
              'actorId': actorId,
              'toolId': toolId,
              'accessProfileId': profileId,
            },
            'capabilityId': capabilityId,
            'scope': <String, dynamic>{
              'paths': _strings(scope['pathPrefixes']),
              'networkDestinations': _strings(scope['networkDestinations']),
              'browserProfiles': _strings(scope['browserProfiles']),
              'secretLeaseIds': _strings(scope['secretLeaseIds']),
              'effect': _copy(effect),
            },
            'budgets': Map<String, int>.from(budgets),
            'policyDecisionId': decisionId,
          }
        : null;
    return <String, dynamic>{
      'schemaVersion': '2.0.0',
      'decisionId': decisionId,
      'status': status,
      'reasonCodes': reasonCodes,
      'effectiveProfileId': profileId,
      'effectiveScope': scope,
      'effectiveBudgets': budgets,
      'grantDraft': grantDraft,
    };
  }

  Map<String, dynamic> _baseScope(
    Map<String, dynamic> profile,
    Map<String, dynamic> context,
  ) {
    final filesystem = _map(profile['filesystem'], 'filesystem');
    final process = _map(profile['process'], 'process');
    final network = _map(profile['network'], 'network');
    final browser = _map(profile['browser'], 'browser');
    final credentials = _map(profile['credentials'], 'credentials');
    final profileId = profile['profileId'];
    final paths = switch (filesystem['scope']) {
      'none' => <String>[],
      'project' => <String>[
        _normalizePath(_string(context['projectRoot'], 'projectRoot')),
      ],
      'current_account' => _strings(
        context['currentAccountRoots'],
      ).map(_normalizePath).toList(growable: false),
      'sandbox' => <String>[
        _normalizePath(_string(context['sandboxRoot'], 'sandboxRoot')),
      ],
      _ => throw PolicyInputException('unsupported filesystem scope'),
    };
    final destinations = switch (network['scope']) {
      'none' => <String>[],
      'unrestricted' => <String>['*'],
      'allowlist' => _strings(
        context[profileId == 'isolated_untrusted'
            ? 'grantDestinations'
            : 'projectDestinations'],
      ),
      _ => throw PolicyInputException('unsupported network scope'),
    };
    final browserProfiles = switch (browser['scope']) {
      'none' => <String>[],
      'isolated' => <String>['isolated'],
      'user_selected' => _strings(context['userSelectedBrowserProfiles']),
      'unrestricted' =>
        _strings(context['availableBrowserProfiles']).isEmpty
            ? <String>['*']
            : _strings(context['availableBrowserProfiles']),
      _ => throw PolicyInputException('unsupported browser scope'),
    };
    return <String, dynamic>{
      'pathPrefixes': paths,
      'networkDestinations': destinations,
      'browserProfiles': browserProfiles,
      'secretLeaseIds': credentials['mode'] == 'none'
          ? <String>[]
          : _strings(context['availableSecretLeaseIds']),
      'filesystem': filesystem,
      'process': process,
      'network': network,
      'browser': browser,
      'credentials': credentials,
    };
  }

  Map<String, int> _profileBudgets(String profileId) {
    final all = _map(_policyConfig['profileBudgets'], 'profileBudgets');
    final raw = _map(all[profileId], 'profileBudgets.$profileId');
    return <String, int>{
      for (final field in const <String>[
        'wallClockMs',
        'maxOutputBytes',
        'maxNetworkBytes',
        'maxCostMicros',
        'maxMutations',
      ])
        field: raw[field] as int,
    };
  }

  static _ApprovalResult _validApproval(Map<String, dynamic> value) {
    final approved = value['approved'] == true;
    if (approved &&
        !const <String>{
          'owner',
          'organization_policy',
        }.contains(value['source'])) {
      return const _ApprovalResult(false, 'untrusted_authority_source');
    }
    if (approved &&
        (value['approvalId'] is! String ||
            (value['approvalId'] as String).trim().isEmpty)) {
      return const _ApprovalResult(false, 'approval_identity_missing');
    }
    return _ApprovalResult(approved, null);
  }

  static int _layerRank(dynamic layer) => switch (layer) {
    'organization' => 0,
    'project' => 1,
    'user' => 2,
    _ => throw PolicyInputException('unknown overlay layer'),
  };

  static String _stricterApproval(String left, String right) {
    const ranks = <String, int>{'never': 0, 'high_risk_only': 1, 'always': 2};
    final leftRank = ranks[left];
    final rightRank = ranks[right];
    if (leftRank == null || rightRank == null) {
      throw PolicyInputException('unknown approval policy');
    }
    return leftRank >= rightRank ? left : right;
  }

  static List<String> _intersection(
    List<String> current,
    List<String> constraint,
  ) {
    if (constraint.isEmpty) {
      return <String>[];
    }
    if (current.contains('*')) {
      return (constraint.toSet().toList()..sort());
    }
    if (constraint.contains('*')) {
      return (current.toSet().toList()..sort());
    }
    return (current.toSet().intersection(constraint.toSet()).toList()..sort());
  }

  static List<String> _pathIntersection(
    List<String> current,
    List<String> constraint,
  ) {
    final result = <String>{};
    for (final left in current) {
      for (final right in constraint) {
        if (_pathWithin(left, right)) {
          result.add(_normalizePath(left));
        } else if (_pathWithin(right, left)) {
          result.add(_normalizePath(right));
        }
      }
    }
    return result.toList()..sort();
  }

  static bool _pathWithin(String path, String prefix) {
    final normalizedPath = _normalizePath(path);
    final normalizedPrefix = _normalizePath(prefix);
    return normalizedPrefix == '/' ||
        normalizedPath == normalizedPrefix ||
        normalizedPath.startsWith('$normalizedPrefix/');
  }

  static String _normalizePath(String value) {
    var text = value.trim().replaceAll('\\', '/');
    var drive = '';
    if (text.length >= 2 && text[1] == ':') {
      drive = text.substring(0, 2).toLowerCase();
      text = text.substring(2);
    }
    final stack = <String>[];
    for (final part in text.split('/')) {
      if (part.isEmpty || part == '.') {
        continue;
      }
      if (part == '..') {
        if (stack.isEmpty) {
          throw PolicyInputException(
            'path traversal is not a valid policy target',
          );
        }
        stack.removeLast();
      } else {
        stack.add(part);
      }
    }
    final body = '/${stack.join('/')}';
    return drive.isEmpty ? body : '$drive$body';
  }

  static bool _destinationAllowed(String host, List<String> allowed) {
    final value = host.trim().toLowerCase().replaceFirst(RegExp(r'[.]$'), '');
    for (final item in allowed) {
      final pattern = item.trim().toLowerCase().replaceFirst(
        RegExp(r'[.]$'),
        '',
      );
      if (pattern == '*') {
        return true;
      }
      if (pattern.startsWith('*.')) {
        final suffix = pattern.substring(1);
        if (value == pattern.substring(2) || value.endsWith(suffix)) {
          return true;
        }
      }
      if (value == pattern) {
        return true;
      }
    }
    return false;
  }

  static Map<String, dynamic> _normalizeRequestForHash(
    Map<String, dynamic> request,
  ) {
    final result = _copy(request);
    final overlays =
        _list(
            result['overlays'] ?? <dynamic>[],
            'overlays',
          ).map((item) => _map(item, 'overlay')).toList(growable: false)
          ..sort((left, right) {
            final layer = _layerRank(
              left['layer'],
            ).compareTo(_layerRank(right['layer']));
            return layer != 0
                ? layer
                : left['overlayId'].toString().compareTo(
                    right['overlayId'].toString(),
                  );
          });
    result['overlays'] = overlays;
    return result;
  }

  static String _canonical(dynamic value) => jsonEncode(_sort(value));

  static String _fnv64(String value) {
    var hash = 0xcbf29ce484222325;
    for (final byte in utf8.encode(value)) {
      hash ^= byte;
      hash = (hash * 0x100000001b3) & 0xffffffffffffffff;
    }
    return hash.toRadixString(16).padLeft(16, '0');
  }

  static dynamic _sort(dynamic value) {
    if (value is Map) {
      final result = SplayTreeMap<String, dynamic>();
      for (final entry in value.entries) {
        result[entry.key.toString()] = _sort(entry.value);
      }
      return result;
    }
    if (value is List) {
      return value.map<dynamic>(_sort).toList(growable: false);
    }
    return value;
  }

  static Map<String, dynamic> _copy(Map<String, dynamic> value) =>
      Map<String, dynamic>.from(jsonDecode(jsonEncode(value)) as Map);

  static Map<String, dynamic> _map(dynamic value, String field) {
    if (value is! Map) {
      throw PolicyInputException('$field must be an object');
    }
    return Map<String, dynamic>.from(value);
  }

  static List<dynamic> _list(dynamic value, String field) {
    if (value is! List) {
      throw PolicyInputException('$field must be an array');
    }
    return List<dynamic>.from(value);
  }

  static List<String> _strings(dynamic value) {
    if (value == null) {
      return <String>[];
    }
    if (value is! List) {
      throw PolicyInputException('value must be an array');
    }
    return value
        .map((item) => _string(item, 'value[]'))
        .toList(growable: false);
  }

  static String _string(dynamic value, String field) {
    if (value is! String || value.trim().isEmpty) {
      throw PolicyInputException('$field must be non-empty');
    }
    return value.trim();
  }
}

class _ApprovalResult {
  const _ApprovalResult(this.approved, this.error);
  final bool approved;
  final String? error;
}
