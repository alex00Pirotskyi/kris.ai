import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String source(String path) => File(path).readAsStringSync();

void main() {
  test(
    'Chat follows a linked steering continuation without authority inheritance',
    () {
      final session = source('lib/product/kristin_conversation_session.dart');
      final studio = source('lib/product/chat_control_plane_studio.dart');
      final runtime = source('lib/product/product_runtime.dart');
      expect(session, contains('replaceRunWithContinuation'));
      expect(session, contains('continuation.sourceRunId != source.id'));
      expect(
        studio,
        contains('steeringContinuationForSourceRun(refreshed.id)'),
      );
      expect(studio, contains('commandPlanningContexts'));
      expect(
        studio,
        contains('canonicalPlan = continuationContext.canonicalPlan'),
      );
      expect(studio, contains('canonicalPlan = null'));
      expect(
        studio,
        contains('Review permissions for the reconciled continuation'),
      );
      expect(runtime, contains('steeringContinuationForSourceRun'));
    },
  );

  test(
    'Details projects canonical live activity and hides raw token deltas',
    () {
      final view = source('lib/product/chat_control_plane_studio_view.dart');
      expect(view, contains("'Recent activity'"));
      expect(view, contains('signal.kind != LiveRunSignalKind.modelTextDelta'));
      expect(view, contains('signal.kind != LiveRunSignalKind.heartbeat'));
      expect(view, contains('_activityLabel'));
    },
  );
}
