import 'package:build/src/builder/build_step.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:dart_source_gen/route.dart';
import 'package:source_gen/source_gen.dart';

class RouteMetaGenerator extends GeneratorForAnnotation<Route> {
  @override
  generateForAnnotatedElement(
    Element element,
    ConstantReader annotation,
    BuildStep buildStep,
  ) {
    final route = annotation.peek('name')?.stringValue;
    final page = element.name;
    final import = element.source?.fullName;
    String output = "";
    if (import != null && import.isNotEmpty) {
        output += 'import "${import.substring(import.indexOf("bin") + 4)}";\n';
    }
    output += '"$route": () => $page(),';
    return output;
  }
}
