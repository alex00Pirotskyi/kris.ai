import 'dart:convert';

import '../crypto_utils.dart';

final RegExp _sha256 = RegExp(r'^[0-9a-f]{64}$');
final RegExp _identity = RegExp(r'^[A-Za-z0-9][A-Za-z0-9._:-]{0,127}$');

final class P3BrowserQualityException implements Exception {
  const P3BrowserQualityException(this.code);

  final String code;

  @override
  String toString() => 'P3BrowserQualityException($code)';
}

void _require(bool condition, String code) {
  if (!condition) {
    throw P3BrowserQualityException(code);
  }
}

void _requireSha256(String value, String code) {
  _require(_sha256.hasMatch(value), code);
}

Object? _canonicalize(Object? value) {
  if (value is Map) {
    final keys = value.keys.map((key) => key.toString()).toList()..sort();
    return <String, Object?>{
      for (final key in keys) key: _canonicalize(value[key]),
    };
  }
  if (value is Iterable) {
    return value.map(_canonicalize).toList(growable: false);
  }
  return value;
}

String _canonicalJson(Map<String, Object?> value) =>
    jsonEncode(_canonicalize(value));

bool _isLoopbackHost(String host) {
  final normalized = host.toLowerCase();
  return normalized == 'localhost' ||
      normalized == '127.0.0.1' ||
      normalized == '::1' ||
      normalized == '[::1]';
}

enum P3BrowserAuditViewport {
  desktop(1440, 900),
  tablet(820, 1180),
  mobile(390, 844);

  const P3BrowserAuditViewport(this.width, this.height);

  final int width;
  final int height;
}

enum P3BrowserAccessibilitySeverity {
  info,
  warning,
  error,
}

final class P3BrowserAccessibilityFinding {
  const P3BrowserAccessibilityFinding({
    required this.ruleId,
    required this.selector,
    required this.message,
    required this.severity,
  });

  final String ruleId;
  final String selector;
  final String message;
  final P3BrowserAccessibilitySeverity severity;

  Map<String, Object?> toJson() => <String, Object?>{
        'ruleId': ruleId,
        'selector': selector,
        'message': message,
        'severity': severity.name,
      };
}

final class P3BrowserLinkCheck {
  const P3BrowserLinkCheck({
    required this.href,
    required this.accessibleName,
    required this.statusCode,
    required this.localOnly,
  });

  final String href;
  final String accessibleName;
  final int statusCode;
  final bool localOnly;

  bool get passed =>
      accessibleName.trim().isNotEmpty && statusCode >= 200 && statusCode < 400;

  Map<String, Object?> toJson() => <String, Object?>{
        'href': href,
        'accessibleName': accessibleName,
        'statusCode': statusCode,
        'localOnly': localOnly,
        'passed': passed,
      };
}

final class P3BrowserFormCheck {
  const P3BrowserFormCheck({
    required this.formId,
    required this.labelledControls,
    required this.totalControls,
    required this.submitReachable,
  });

  final String formId;
  final int labelledControls;
  final int totalControls;
  final bool submitReachable;

  bool get passed =>
      totalControls > 0 && labelledControls == totalControls && submitReachable;

  Map<String, Object?> toJson() => <String, Object?>{
        'formId': formId,
        'labelledControls': labelledControls,
        'totalControls': totalControls,
        'submitReachable': submitReachable,
        'passed': passed,
      };
}

final class P3BrowserQualitySnapshot {
  P3BrowserQualitySnapshot({
    required this.pageId,
    required this.observationId,
    required this.url,
    required this.viewport,
    required this.screenshotSha256,
    required this.domSha256,
    required this.accessibilitySha256,
    required List<P3BrowserLinkCheck> links,
    required List<P3BrowserFormCheck> forms,
    required List<P3BrowserAccessibilityFinding> accessibilityFindings,
  })  : links = List<P3BrowserLinkCheck>.unmodifiable(links),
        forms = List<P3BrowserFormCheck>.unmodifiable(forms),
        accessibilityFindings =
            List<P3BrowserAccessibilityFinding>.unmodifiable(
          accessibilityFindings,
        ) {
    _require(_identity.hasMatch(pageId), 'browser_quality_page_id_invalid');
    _require(
      _identity.hasMatch(observationId),
      'browser_quality_observation_id_invalid',
    );
    _require(
        url.hasScheme && url.host.isNotEmpty, 'browser_quality_url_invalid');
    _requireSha256(
      screenshotSha256,
      'browser_quality_screenshot_hash_invalid',
    );
    _requireSha256(domSha256, 'browser_quality_dom_hash_invalid');
    _requireSha256(
      accessibilitySha256,
      'browser_quality_accessibility_hash_invalid',
    );
    _require(links.length <= 4096, 'browser_quality_links_unbounded');
    _require(forms.length <= 512, 'browser_quality_forms_unbounded');
    _require(
      accessibilityFindings.length <= 4096,
      'browser_quality_accessibility_findings_unbounded',
    );
  }

  final String pageId;
  final String observationId;
  final Uri url;
  final P3BrowserAuditViewport viewport;
  final String screenshotSha256;
  final String domSha256;
  final String accessibilitySha256;
  final List<P3BrowserLinkCheck> links;
  final List<P3BrowserFormCheck> forms;
  final List<P3BrowserAccessibilityFinding> accessibilityFindings;

  Map<String, Object?> toJson() => <String, Object?>{
        'pageId': pageId,
        'observationId': observationId,
        'url': url.toString(),
        'viewport': <String, Object?>{
          'name': viewport.name,
          'width': viewport.width,
          'height': viewport.height,
        },
        'screenshotSha256': screenshotSha256,
        'domSha256': domSha256,
        'accessibilitySha256': accessibilitySha256,
        'links': links.map((item) => item.toJson()).toList(growable: false),
        'forms': forms.map((item) => item.toJson()).toList(growable: false),
        'accessibilityFindings': accessibilityFindings
            .map((item) => item.toJson())
            .toList(growable: false),
      };

  String get snapshotSha256 => Sha256.text(_canonicalJson(toJson()));
}

final class P3BrowserVisualDiff {
  P3BrowserVisualDiff({
    required this.baselineScreenshotSha256,
    required this.currentScreenshotSha256,
    required this.changedPixels,
    required this.totalPixels,
    this.maxChangedRatio = 0.01,
  }) {
    _requireSha256(
      baselineScreenshotSha256,
      'browser_visual_baseline_hash_invalid',
    );
    _requireSha256(
      currentScreenshotSha256,
      'browser_visual_current_hash_invalid',
    );
    _require(totalPixels > 0, 'browser_visual_total_pixels_invalid');
    _require(
      changedPixels >= 0 && changedPixels <= totalPixels,
      'browser_visual_changed_pixels_invalid',
    );
    _require(
      maxChangedRatio >= 0 && maxChangedRatio <= 1,
      'browser_visual_threshold_invalid',
    );
  }

  final String baselineScreenshotSha256;
  final String currentScreenshotSha256;
  final int changedPixels;
  final int totalPixels;
  final double maxChangedRatio;

  double get changedRatio => changedPixels / totalPixels;
  bool get passed => changedRatio <= maxChangedRatio;

  Map<String, Object?> toJson() => <String, Object?>{
        'baselineScreenshotSha256': baselineScreenshotSha256,
        'currentScreenshotSha256': currentScreenshotSha256,
        'changedPixels': changedPixels,
        'totalPixels': totalPixels,
        'changedRatio': changedRatio,
        'maxChangedRatio': maxChangedRatio,
        'passed': passed,
      };
}

final class P3BrowserQualityReport {
  P3BrowserQualityReport({
    required this.snapshot,
    required this.visualDiff,
  });

  final P3BrowserQualitySnapshot snapshot;
  final P3BrowserVisualDiff visualDiff;

  bool get accessibilityPassed => snapshot.accessibilityFindings.every(
        (item) => item.severity != P3BrowserAccessibilitySeverity.error,
      );
  bool get linksPassed => snapshot.links.every((item) => item.passed);
  bool get formsPassed => snapshot.forms.every((item) => item.passed);
  bool get passed =>
      visualDiff.passed && accessibilityPassed && linksPassed && formsPassed;

  Map<String, Object?> toJson() => <String, Object?>{
        'snapshot': snapshot.toJson(),
        'snapshotSha256': snapshot.snapshotSha256,
        'visualDiff': visualDiff.toJson(),
        'accessibilityPassed': accessibilityPassed,
        'linksPassed': linksPassed,
        'formsPassed': formsPassed,
        'passed': passed,
      };

  String get reportSha256 => Sha256.text(_canonicalJson(toJson()));
}

enum P3BrowserSecurityDecision {
  allow,
  quarantine,
  block,
  takeover,
}

final class P3BrowserSecurityGuard {
  const P3BrowserSecurityGuard();

  static final RegExp _promptInjectionPattern = RegExp(
    r'(ignore\s+(all\s+)?(previous|prior)\s+instructions|system\s+prompt|developer\s+message|tool\s*call|exfiltrat(e|ion)|reveal\s+(a\s+)?secret)',
    caseSensitive: false,
  );
  static final RegExp _unsafeDownloadExtension = RegExp(
    r'\.(exe|dll|msi|scr|ps1|bat|cmd|com|jar)$',
    caseSensitive: false,
  );

  bool containsPromptInjection(String visibleText) =>
      _promptInjectionPattern.hasMatch(visibleText);

  void requireLoopbackNavigation(Uri target, {int redirectDepth = 0}) {
    _require(
      target.scheme == 'http' || target.scheme == 'https',
      'browser_navigation_scheme_blocked',
    );
    _require(
      _isLoopbackHost(target.host),
      'browser_navigation_non_loopback_blocked',
    );
    _require(
      redirectDepth >= 0 && redirectDepth <= 5,
      'browser_redirect_chain_unbounded',
    );
  }

  void requireFreshTarget({
    required String activePageId,
    required String targetPageId,
    required String currentObservationId,
    required String targetObservationId,
  }) {
    _require(
      activePageId == targetPageId,
      'browser_tab_confusion_blocked',
    );
    _require(
      currentObservationId == targetObservationId,
      'browser_stale_target_blocked',
    );
  }

  void requireProfileIsolation({
    required String activeProfileId,
    required String requestedProfileId,
  }) {
    _require(
      activeProfileId == requestedProfileId,
      'browser_cross_profile_access_blocked',
    );
  }

  P3BrowserSecurityDecision classifyDownload({
    required String filename,
    required String contentType,
    required int payloadBytes,
  }) {
    _require(
      payloadBytes >= 0 && payloadBytes <= 128 * 1024 * 1024,
      'browser_download_size_blocked',
    );
    final normalizedType = contentType.trim().toLowerCase();
    if (_unsafeDownloadExtension.hasMatch(filename) ||
        normalizedType == 'application/x-msdownload' ||
        normalizedType == 'application/x-msdos-program') {
      return P3BrowserSecurityDecision.block;
    }
    return P3BrowserSecurityDecision.quarantine;
  }

  P3BrowserSecurityDecision classifyVisibleText(String visibleText) =>
      containsPromptInjection(visibleText)
          ? P3BrowserSecurityDecision.takeover
          : P3BrowserSecurityDecision.allow;
}

enum P3BrowserTaskRecipeKind {
  research,
  formCompletion,
  authenticatedDownload,
  webTesting,
  dataExtraction,
}

final class P3BrowserTaskRecipeStep {
  const P3BrowserTaskRecipeStep({
    required this.id,
    required this.operation,
    required this.requiresFreshObservation,
    this.mutating = false,
  });

  final String id;
  final String operation;
  final bool requiresFreshObservation;
  final bool mutating;

  Map<String, Object?> toJson() => <String, Object?>{
        'id': id,
        'operation': operation,
        'requiresFreshObservation': requiresFreshObservation,
        'mutating': mutating,
      };
}

final class P3BrowserTaskRecipe {
  const P3BrowserTaskRecipe({
    required this.id,
    required this.kind,
    required this.description,
    required this.steps,
  });

  final String id;
  final P3BrowserTaskRecipeKind kind;
  final String description;
  final List<P3BrowserTaskRecipeStep> steps;

  Map<String, Object?> toJson() => <String, Object?>{
        'id': id,
        'kind': kind.name,
        'description': description,
        'steps': steps.map((item) => item.toJson()).toList(growable: false),
      };
}

abstract final class P3BrowserTaskRecipes {
  static const List<P3BrowserTaskRecipe> all = <P3BrowserTaskRecipe>[
    P3BrowserTaskRecipe(
      id: 'p3.recipe.research',
      kind: P3BrowserTaskRecipeKind.research,
      description: 'Observe, navigate structured links, extract cited facts.',
      steps: <P3BrowserTaskRecipeStep>[
        P3BrowserTaskRecipeStep(
          id: 'observe',
          operation: 'observe',
          requiresFreshObservation: true,
        ),
        P3BrowserTaskRecipeStep(
          id: 'follow-link',
          operation: 'click-structured-link',
          requiresFreshObservation: true,
        ),
        P3BrowserTaskRecipeStep(
          id: 'extract',
          operation: 'extract-visible-data',
          requiresFreshObservation: true,
        ),
      ],
    ),
    P3BrowserTaskRecipe(
      id: 'p3.recipe.form-completion',
      kind: P3BrowserTaskRecipeKind.formCompletion,
      description: 'Inspect labelled controls, fill, verify, then submit.',
      steps: <P3BrowserTaskRecipeStep>[
        P3BrowserTaskRecipeStep(
          id: 'inspect-form',
          operation: 'inspect-form',
          requiresFreshObservation: true,
        ),
        P3BrowserTaskRecipeStep(
          id: 'fill',
          operation: 'fill-labelled-controls',
          requiresFreshObservation: true,
          mutating: true,
        ),
        P3BrowserTaskRecipeStep(
          id: 'submit',
          operation: 'submit-form',
          requiresFreshObservation: true,
          mutating: true,
        ),
        P3BrowserTaskRecipeStep(
          id: 'verify',
          operation: 'verify-postcondition',
          requiresFreshObservation: true,
        ),
      ],
    ),
    P3BrowserTaskRecipe(
      id: 'p3.recipe.authenticated-download',
      kind: P3BrowserTaskRecipeKind.authenticatedDownload,
      description:
          'Authenticate locally, verify identity, quarantine download.',
      steps: <P3BrowserTaskRecipeStep>[
        P3BrowserTaskRecipeStep(
          id: 'authenticate',
          operation: 'authenticate',
          requiresFreshObservation: true,
          mutating: true,
        ),
        P3BrowserTaskRecipeStep(
          id: 'observe-authenticated',
          operation: 'observe',
          requiresFreshObservation: true,
        ),
        P3BrowserTaskRecipeStep(
          id: 'download',
          operation: 'download-to-quarantine',
          requiresFreshObservation: true,
          mutating: true,
        ),
      ],
    ),
    P3BrowserTaskRecipe(
      id: 'p3.recipe.web-testing',
      kind: P3BrowserTaskRecipeKind.webTesting,
      description:
          'Exercise responsive, visual, accessibility, link and form checks.',
      steps: <P3BrowserTaskRecipeStep>[
        P3BrowserTaskRecipeStep(
          id: 'responsive',
          operation: 'run-responsive-checks',
          requiresFreshObservation: true,
        ),
        P3BrowserTaskRecipeStep(
          id: 'visual',
          operation: 'compare-screenshot',
          requiresFreshObservation: true,
        ),
        P3BrowserTaskRecipeStep(
          id: 'accessibility',
          operation: 'audit-accessibility',
          requiresFreshObservation: true,
        ),
        P3BrowserTaskRecipeStep(
          id: 'links-forms',
          operation: 'check-links-and-forms',
          requiresFreshObservation: true,
        ),
      ],
    ),
    P3BrowserTaskRecipe(
      id: 'p3.recipe.data-extraction',
      kind: P3BrowserTaskRecipeKind.dataExtraction,
      description:
          'Observe structured rows, paginate or scroll, emit bounded data.',
      steps: <P3BrowserTaskRecipeStep>[
        P3BrowserTaskRecipeStep(
          id: 'observe',
          operation: 'observe',
          requiresFreshObservation: true,
        ),
        P3BrowserTaskRecipeStep(
          id: 'scroll',
          operation: 'bounded-infinite-scroll',
          requiresFreshObservation: true,
        ),
        P3BrowserTaskRecipeStep(
          id: 'extract',
          operation: 'extract-structured-rows',
          requiresFreshObservation: true,
        ),
      ],
    ),
  ];

  static P3BrowserTaskRecipe byKind(P3BrowserTaskRecipeKind kind) =>
      all.singleWhere((item) => item.kind == kind);
}

final class P3BrowserRecipeReceipt {
  P3BrowserRecipeReceipt._({
    required this.recipeId,
    required this.sessionId,
    required this.pageId,
    required this.observationSha256,
    required this.inputSha256,
    required this.outputSha256,
    required this.qualityReportSha256,
    required this.completedStepIds,
    required this.receiptSha256,
  });

  factory P3BrowserRecipeReceipt.issue({
    required P3BrowserTaskRecipe recipe,
    required String sessionId,
    required String pageId,
    required String observationSha256,
    required Map<String, Object?> input,
    required Object? output,
    required String qualityReportSha256,
    required List<String> completedStepIds,
  }) {
    _require(
        _identity.hasMatch(sessionId), 'browser_recipe_session_id_invalid');
    _require(_identity.hasMatch(pageId), 'browser_recipe_page_id_invalid');
    _requireSha256(
      observationSha256,
      'browser_recipe_observation_hash_invalid',
    );
    _requireSha256(
      qualityReportSha256,
      'browser_recipe_quality_hash_invalid',
    );
    final expectedSteps = recipe.steps.map((item) => item.id).toList();
    _require(
      completedStepIds.length == expectedSteps.length &&
          completedStepIds.asMap().entries.every(
                (entry) => entry.value == expectedSteps[entry.key],
              ),
      'browser_recipe_steps_incomplete',
    );
    final inputSha = Sha256.text(_canonicalJson(input));
    final outputSha = Sha256.text(jsonEncode(_canonicalize(output)));
    final payload = <String, Object?>{
      'recipeId': recipe.id,
      'sessionId': sessionId,
      'pageId': pageId,
      'observationSha256': observationSha256,
      'inputSha256': inputSha,
      'outputSha256': outputSha,
      'qualityReportSha256': qualityReportSha256,
      'completedStepIds': completedStepIds,
    };
    return P3BrowserRecipeReceipt._(
      recipeId: recipe.id,
      sessionId: sessionId,
      pageId: pageId,
      observationSha256: observationSha256,
      inputSha256: inputSha,
      outputSha256: outputSha,
      qualityReportSha256: qualityReportSha256,
      completedStepIds: List<String>.unmodifiable(completedStepIds),
      receiptSha256: Sha256.text(_canonicalJson(payload)),
    );
  }

  final String recipeId;
  final String sessionId;
  final String pageId;
  final String observationSha256;
  final String inputSha256;
  final String outputSha256;
  final String qualityReportSha256;
  final List<String> completedStepIds;
  final String receiptSha256;

  Map<String, Object?> toJson() => <String, Object?>{
        'recipeId': recipeId,
        'sessionId': sessionId,
        'pageId': pageId,
        'observationSha256': observationSha256,
        'inputSha256': inputSha256,
        'outputSha256': outputSha256,
        'qualityReportSha256': qualityReportSha256,
        'completedStepIds': completedStepIds,
        'receiptSha256': receiptSha256,
      };

  bool verify() {
    final payload = <String, Object?>{
      'recipeId': recipeId,
      'sessionId': sessionId,
      'pageId': pageId,
      'observationSha256': observationSha256,
      'inputSha256': inputSha256,
      'outputSha256': outputSha256,
      'qualityReportSha256': qualityReportSha256,
      'completedStepIds': completedStepIds,
    };
    return _sha256.hasMatch(receiptSha256) &&
        Sha256.text(_canonicalJson(payload)) == receiptSha256;
  }
}
