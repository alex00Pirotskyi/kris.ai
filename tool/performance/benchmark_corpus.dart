import 'dart:io';

final class BenchmarkCorpusSpec {
  const BenchmarkCorpusSpec({
    required this.id,
    required this.fileCount,
    required this.linesPerFile,
  });

  final String id;
  final int fileCount;
  final int linesPerFile;
}

const BenchmarkCorpusSpec smallBenchmarkCorpus = BenchmarkCorpusSpec(
  id: 'small',
  fileCount: 64,
  linesPerFile: 16,
);

const BenchmarkCorpusSpec mediumBenchmarkCorpus = BenchmarkCorpusSpec(
  id: 'medium',
  fileCount: 1500,
  linesPerFile: 24,
);

const BenchmarkCorpusSpec largeBenchmarkCorpus = BenchmarkCorpusSpec(
  id: 'large',
  fileCount: 10000,
  linesPerFile: 32,
);

final class BenchmarkCorpus {
  const BenchmarkCorpus({
    required this.spec,
    required this.root,
    required this.mutableFile,
  });

  final BenchmarkCorpusSpec spec;
  final Directory root;
  final File mutableFile;
}

Future<BenchmarkCorpus> createBenchmarkCorpus(
  Directory parent,
  BenchmarkCorpusSpec spec,
) async {
  final root = Directory(
    '${parent.path}${Platform.pathSeparator}${spec.id}',
  );
  if (await root.exists()) {
    await root.delete(recursive: true);
  }
  await root.create(recursive: true);
  final shared = Directory(
    '${root.path}${Platform.pathSeparator}lib'
    '${Platform.pathSeparator}shared',
  );
  await shared.create(recursive: true);
  await File(
    '${shared.path}${Platform.pathSeparator}common.dart',
  ).writeAsString(
    '''final class CommonValue {
  const CommonValue(this.value);

  final int value;
}
''',
    flush: true,
  );

  const batchSize = 64;
  for (var start = 0; start < spec.fileCount; start += batchSize) {
    final end = (start + batchSize).clamp(0, spec.fileCount).toInt();
    await Future.wait(<Future<void>>[
      for (var index = start; index < end; index++)
        _writeFeature(root, spec, index),
    ]);
  }

  final mutableFile = File(
    '${root.path}${Platform.pathSeparator}lib'
    '${Platform.pathSeparator}group_000'
    '${Platform.pathSeparator}feature_000000.dart',
  );
  return BenchmarkCorpus(
    spec: spec,
    root: root,
    mutableFile: mutableFile,
  );
}

Future<void> mutateBenchmarkCorpus(BenchmarkCorpus corpus) async {
  final prior = await corpus.mutableFile.readAsString();
  final marker =
      prior.contains('mutationGeneration = 1000001') ? 2000002 : 1000001;
  final updated = prior.replaceFirst(
    'const mutationGeneration = 0;',
    'const mutationGeneration = $marker;',
  );
  if (updated == prior) {
    await corpus.mutableFile.writeAsString(
      '$prior\nconst mutationGeneration = $marker;\n',
      flush: true,
    );
  } else {
    await corpus.mutableFile.writeAsString(updated, flush: true);
  }
}

Future<void> _writeFeature(
  Directory root,
  BenchmarkCorpusSpec spec,
  int index,
) async {
  final group = (index ~/ 100).toString().padLeft(3, '0');
  final serial = index.toString().padLeft(6, '0');
  final directory = Directory(
    '${root.path}${Platform.pathSeparator}lib'
    '${Platform.pathSeparator}group_$group',
  );
  await directory.create(recursive: true);
  final filler = StringBuffer();
  for (var line = 0; line < spec.linesPerFile; line++) {
    filler.writeln(
      '  int deterministicValue$line(int input) => '
      'input + $index + $line;',
    );
  }
  final source = '''import '../shared/common.dart';

const mutationGeneration = 0;

final class Feature$serial {
  const Feature$serial();

  CommonValue buildCommon(int input) => CommonValue(input + $index);

  String get symbolLabel => 'Feature$serial';

$filler}
''';
  await File(
    '${directory.path}${Platform.pathSeparator}feature_$serial.dart',
  ).writeAsString(source, flush: true);
}
