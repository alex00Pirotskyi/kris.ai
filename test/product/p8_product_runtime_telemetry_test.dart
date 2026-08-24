import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kristin_local_agent/product/product_runtime.dart';

void main() {
  test('ProductRuntime owns opt-in content-free telemetry lifecycle', () async {
    final directory = await Directory.systemTemp.createTemp(
      'kristin-p8-runtime-telemetry-',
    );
    final runtime = await ProductRuntime.initialize(dataRoot: directory.path);
    addTearDown(() async {
      await runtime.close();
      if (await directory.exists()) {
        await directory.delete(recursive: true);
      }
    });

    expect(runtime.telemetry.policy.optedIn, isFalse);
    expect(runtime.previewTelemetry()['eventCount'], 0);

    await runtime.updateSettings(
      runtime.settings.copyWith(
        telemetryOptIn: true,
        telemetryRetentionDays: 2,
        telemetryMaxBufferedEvents: 500,
      ),
    );
    expect(runtime.telemetry.policy.optedIn, isTrue);

    await runtime.events.publish(
      'model.request_completed',
      'run-sensitive-identity',
      <String, dynamic>{
        'prompt': 'private prompt content',
        'projectPath': r'C:\private\project',
        'durationMilliseconds': 7,
      },
    );
    await Future<void>.delayed(Duration.zero);

    final preview = runtime.previewTelemetry();
    expect(preview['eventCount'], 1);
    final encoded = preview.toString();
    expect(encoded, isNot(contains('private prompt content')));
    expect(encoded, isNot(contains(r'C:\private\project')));
    expect(encoded, isNot(contains('run-sensitive-identity')));

    final export = File('${directory.path}/telemetry-export.json');
    await runtime.exportTelemetry(export);
    expect(await export.readAsString(), contains('"contentCollection": false'));

    runtime.deleteTelemetry();
    expect(runtime.previewTelemetry()['eventCount'], 0);
    await runtime.updateSettings(
      runtime.settings.copyWith(telemetryOptIn: false),
    );
    expect(runtime.telemetry.policy.optedIn, isFalse);
  });
}
