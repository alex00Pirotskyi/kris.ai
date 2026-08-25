import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kristin_local_agent/product/application_runtime_provisioner.dart';

void main() {
  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('kristin-runtime-slot-');
  });

  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  AtomicApplicationRuntimeSlot<String> slot() =>
      AtomicApplicationRuntimeSlot<String>(
        applicationDataRoot: root,
        runtimeKind: 'test',
        validate: (applicationRoot) async {
          final file = File(
            '${applicationRoot.path}${Platform.pathSeparator}runtime'
            '${Platform.pathSeparator}test${Platform.pathSeparator}current'
            '${Platform.pathSeparator}identity.txt',
          );
          if (!await file.exists()) throw StateError('test_runtime_missing');
          return (await file.readAsString()).trim();
        },
      );

  Future<void> writeCurrent(String value) async {
    final file = File(
      '${root.path}${Platform.pathSeparator}runtime'
      '${Platform.pathSeparator}test${Platform.pathSeparator}current'
      '${Platform.pathSeparator}identity.txt',
    );
    await file.parent.create(recursive: true);
    await file.writeAsString('$value\n', flush: true);
  }

  Future<void> materialize(Directory destination, String value) async {
    await destination.create(recursive: true);
    await File(
      '${destination.path}${Platform.pathSeparator}identity.txt',
    ).writeAsString('$value\n', flush: true);
  }

  test('fresh missing runtime materializes validates and promotes', () async {
    var installs = 0;
    final result = await slot().ensure(
      targetIdentity: 'fresh',
      repair: false,
      matches: (value) => value == 'fresh',
      materialize: (destination) async {
        installs++;
        await materialize(destination, 'fresh');
      },
    );

    expect(result, 'fresh');
    expect(installs, 1);
    expect(
      await File(
        '${root.path}${Platform.pathSeparator}runtime'
        '${Platform.pathSeparator}test${Platform.pathSeparator}current'
        '${Platform.pathSeparator}identity.txt',
      ).readAsString(),
      'fresh\n',
    );
  });

  test('valid current runtime is a fast path', () async {
    await writeCurrent('fresh');
    var installs = 0;

    final result = await slot().ensure(
      targetIdentity: 'fresh',
      repair: false,
      matches: (value) => value == 'fresh',
      materialize: (destination) async {
        installs++;
        await materialize(destination, 'fresh');
      },
    );

    expect(result, 'fresh');
    expect(installs, 0);
  });

  test('stale identity is replaced only after staged validation', () async {
    await writeCurrent('stale');

    final result = await slot().ensure(
      targetIdentity: 'fresh',
      repair: false,
      matches: (value) => value == 'fresh',
      materialize: (destination) => materialize(destination, 'fresh'),
    );

    expect(result, 'fresh');
    final leftovers = await Directory(
      '${root.path}${Platform.pathSeparator}runtime'
      '${Platform.pathSeparator}test',
    ).list().toList();
    expect(
      leftovers.where((item) => item.path.contains('previous-')),
      isEmpty,
    );
  });

  test('invalid staged runtime never replaces a valid current runtime',
      () async {
    await writeCurrent('stable');

    await expectLater(
      slot().ensure(
        targetIdentity: 'desired',
        repair: false,
        matches: (value) => value == 'desired',
        materialize: (destination) => materialize(destination, 'corrupt'),
      ),
      throwsA(isA<StateError>()),
    );

    final current = File(
      '${root.path}${Platform.pathSeparator}runtime'
      '${Platform.pathSeparator}test${Platform.pathSeparator}current'
      '${Platform.pathSeparator}identity.txt',
    );
    expect((await current.readAsString()).trim(), 'stable');
  });

  test('interrupted previous runtime is restored before a new install',
      () async {
    final previous = File(
      '${root.path}${Platform.pathSeparator}runtime'
      '${Platform.pathSeparator}test${Platform.pathSeparator}previous-crash'
      '${Platform.pathSeparator}identity.txt',
    );
    await previous.parent.create(recursive: true);
    await previous.writeAsString('stable\n', flush: true);
    final staleStaging = File(
      '${root.path}${Platform.pathSeparator}runtime'
      '${Platform.pathSeparator}test${Platform.pathSeparator}staging-crash'
      '${Platform.pathSeparator}runtime${Platform.pathSeparator}test'
      '${Platform.pathSeparator}current${Platform.pathSeparator}identity.txt',
    );
    await staleStaging.parent.create(recursive: true);
    await staleStaging.writeAsString('partial\n', flush: true);
    var installs = 0;

    final result = await slot().ensure(
      targetIdentity: 'stable',
      repair: false,
      matches: (value) => value == 'stable',
      materialize: (destination) async {
        installs++;
        await materialize(destination, 'stable');
      },
    );

    expect(result, 'stable');
    expect(installs, 0);
    expect(await staleStaging.exists(), isFalse);
  });

  test('failed materialization is retryable and cleans in-flight state',
      () async {
    final runtimeSlot = slot();
    var attempts = 0;

    Future<String> ensure() => runtimeSlot.ensure(
          targetIdentity: 'fresh',
          repair: true,
          matches: (value) => value == 'fresh',
          materialize: (destination) async {
            attempts++;
            if (attempts == 1) {
              throw StateError('simulated_acquisition_failure');
            }
            await materialize(destination, 'fresh');
          },
        );

    await expectLater(ensure(), throwsA(isA<StateError>()));
    expect(await ensure(), 'fresh');
    expect(attempts, 2);
  });

  test('same target identity shares one in-flight provisioning operation',
      () async {
    final runtimeSlot = slot();
    final entered = Completer<void>();
    final release = Completer<void>();
    var installs = 0;

    Future<String> ensure() => runtimeSlot.ensure(
          targetIdentity: 'fresh',
          repair: false,
          matches: (value) => value == 'fresh',
          materialize: (destination) async {
            installs++;
            if (!entered.isCompleted) entered.complete();
            await release.future;
            await materialize(destination, 'fresh');
          },
        );

    final first = ensure();
    await entered.future;
    final second = ensure();
    expect(identical(first, second), isTrue);
    release.complete();

    expect(await first, 'fresh');
    expect(await second, 'fresh');
    expect(installs, 1);
  });
}
