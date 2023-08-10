import 'dart:async';
import 'dart:convert';

import 'package:build/build.dart';
import 'package:glob/glob.dart';
import 'package:source_gen/source_gen.dart';
import 'package:collection/collection.dart';
import 'package:dart_style/dart_style.dart';

import 'generator.dart';

Builder routeBuilder(BuilderOptions options) => LibraryBuilder(
      RouteMetaGenerator(),
      generatedExtension: '.route',
      formatOutput: (code) => code,
      header: '',
      allowSyntaxErrors: true,
    );

Builder routeCollectBuilder(BuilderOptions options) => RouteCollectBuilder();

class RouteCollectBuilder implements Builder {
  @override
  FutureOr<void> build(BuildStep buildStep) async {
    final inputIds = await buildStep.findAssets(Glob('**/*.route')).toList();
    final imports = <String>{};
    final contents = [];
    for (final inputId in inputIds) {
      final content = await buildStep.readAsString(inputId);
      List<String> lines = const LineSplitter().convert(content);
      lines.removeWhere((line) => line.isEmpty || line.startsWith("//"));
      final groupedLines = lines.groupListsBy((line) {
        return line.startsWith('import') ? 0 : 1;
      });
      final import = groupedLines[0];
      if (import != null && import.isNotEmpty) {
        imports.addAll(import);
      }
      final code = groupedLines[1];
      if (code != null && code.isNotEmpty) {
        contents.add(code.join('\n'));
      }
    }

    final code = """
import 'page.dart';
${imports.join('\n')}

class RouteCollector {
  RouteCollector._internal();
  static final RouteCollector _instance = RouteCollector._internal();
  factory RouteCollector() => _instance;

  PageCreator? getPageCreator(String route) => _routeTable[route];

  static final Map<String, PageCreator> _routeTable = {
    ${contents.join('\n')}
  };
}
""";

    buildStep.writeAsString(
      AssetId(buildStep.inputId.package, 'bin/route_table.dart'),
      DartFormatter().format(code),
    );
  }

  @override
  Map<String, List<String>> get buildExtensions => const {
        r'lib/$lib$': ['bin/route_table.dart']
      };
}
