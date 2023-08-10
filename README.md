# Dart APT 简介

APT 是 Annotation Processing Tool 的缩写，即注解处理器。熟悉 Java/Android 开发的小伙伴应该对 APT 并不陌生，例如在 Android 生态中，基本上所有的路由框架都会使用到 APT，通过给 Activity 标记带有路由信息的注解，在编译期通过 APT 扫描被注解的类，获取页面和路由的映射关系，再通过代码生成框架（如 [javapoet](https://github.com/square/javapoet)）生成中间类，然后在 transform 阶段汇总路由表。。。

而在 Dart 中，可以借助官方提供的 [source_gen](https://github.com/dart-lang/source_gen) 来实现注解处理和代码的生成。下面我们以一个例子来介绍 soruce_gen 的使用。

## 创建工程

首先确保电脑安装了 dart 环境，vscode，dart 的 vscode 插件。

打开 vscode，打开命令面板（macOS 快捷键是 ⇧⌘P 或者 F1），搜索 dart 关键字，选择 「Dart: New Project」，选择 「Console Application」，这样就生成了一个默认的 console application 工程。

使用 source_gen 需要在 pubspec.yaml 中添加依赖：

```yaml
dependencies:
  source_gen:
  build_runner:
```

我们还是以路由为例，期望给 page 添加带路由名称的注解，在页面跳转的时候，传入路由名称即可。

假设存在页面 HomePage：

```dart
class HomePage extends Page {}
```

正常的页面跳转：

```dart
Navigator.push(HomePage());
```

期望的页面跳转：

```dart
Navigator.push("/home");
```

## 创建注解：

dart 的注解不像 java 或者 kotlin 那样，会有特定的标识（@interface / annotation class），dart 的注解只需要将类的构造函数定义成 const 即可。

下面我们创建一个 Route 注解：

```dart
/// Route Annotation
class Route {
  final String name;
  
  const Route({required this.name});
}
```

并在 HomePage 类上添加注解：

```dart
@Route(name: "/home")
class HomePage {}
```

## 生成代码

既然我们希望使用路由名称代替创建页面实例，那就需要生成一个路由和实例的映射关系，我们可以先写好我们期望生成的代码模版：

```dart
import 'page.dart';

typedef PageCreator = Page Function();

class RouteCollector {
  RouteCollector._internal();
  static final RouteCollector _instance = RouteCollector._internal();
  factory RouteCollector() => _instance;

  PageCreator? getPageCreator(String route) => _routeTable[route];

  static final Map<String, PageCreator> _routeTable = {
    "/home": () => HomePage(),
    "/main": () => MainPage(),
  };
}
```

我们可以想一想，仅通过一步能否生成上面的代码？

其实是不行的，由于是根据注解来生成的代码，在扫描的时候生成的代码是一对一的，即每一个被注解的类对应一段生成的代码，仅通过一步仅仅能生成类似 `"/home": () => HomePage(),` 这样的代码，无法把每个注解生成的代码聚合成上面我们期望生成的那样。所以需要两步，第二步把第一步生成的中间代码聚合起来，形成最终的我们期望的代码。（当然，也可以像 Android 那样，每个注解生成一个完整的类，第二步聚合这些类。）

1. ### 创建 Generator

source_gen 包中提供了 `GeneratorForAnnotation`，我们需要创建一个 Generator 并继承它，就可以在 generateForAnnotatedElement 方法中获取到注解的信息。

```dart
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
    return '"$route": () => $page(),';
  }
}
```

第一步生成类似如下的代码：

```dart
"/home": () => HomePage(),
```

2. ### 创建 Builder

```dart
import 'package:build/build.dart';
import 'package:source_gen/source_gen.dart';

import 'generator.dart';

// 这里使用的是 LibraryBuilder，还有 PartBuilder，SharedPartBuilder，每个使用场景都不同
// 此方法必须是全局方法
Builder routeBuilder(BuilderOptions options) => LibraryBuilder(
  		// 自定义的 Generator
      RouteMetaGenerator(),
  		// 指定生成的文件后缀名
      generatedExtension: '.route',
  		// 直出，不 format，
      formatOutput: (code) => code,
      // 不带默认的 header
      header: '',
  		// 允许语法错误
      allowSyntaxErrors: true,
    );
```

然后在工程的根目录下创建 build.yaml 文件，并配置 builder：

```yaml
builders:
  routeBuilder:
    import: 'package:dart_source_gen/builder.dart'
    builder_factories: ['routeBuilder']
    build_extensions: { ".dart": [ ".route" ] }
    auto_apply: root_package
    build_to: cache
```

build_to 有 source 和 cache 两种模式，source 会生成文件，cache 则在内存中，这里使用 cache 是因为中间生成的代码只是给第二步使用的临时代码。

然后运行：

```shell
flutter packages pub run build_runner build --delete-conflicting-outputs 
```

至此，第一步的中间代码已经生成了，如果想看输出的效果，可以把 build_to 改成 source 尝试：

```

// **************************************************************************
// RouteMetaGenerator
// **************************************************************************

import "page1.dart";
"/home": () => HomePage(),

import "page1.dart";
"/main": () => MainPage(),

```

第二步，需要我们自己实现一个 Builder：

```dart
import 'dart:async';
import 'dart:convert';

import 'package:build/build.dart';
import 'package:glob/glob.dart';
import 'package:source_gen/source_gen.dart';
import 'package:collection/collection.dart';
import 'package:dart_style/dart_style.dart';

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
```

同样，需要在 build.yaml 中配置：

```yaml
builders:
  routeBuilder:
    import: 'package:dart_source_gen/builder.dart'
    builder_factories: ['routeBuilder']
    build_extensions: { ".dart": [ ".route" ] }
    auto_apply: root_package
    build_to: source
  
  collectPageMetadataBuilder:
    import: 'package:dart_source_gen/builder.dart'
    builder_factories: [ "routeCollectBuilder" ]
    build_extensions: { ".dart": [ "bin/route_table.dart" ] }
    auto_apply: root_package
    required_inputs: ['.route']
    build_to: source
```

再次运行 `flutter packages pub run build_runner build --delete-conflicting-outputs `，生成如下代码：

```dart
import 'page.dart';
import "page1.dart";
import "detail/datail.dart";
import "page2.dart";

class RouteCollector {
  RouteCollector._internal();
  static final RouteCollector _instance = RouteCollector._internal();
  factory RouteCollector() => _instance;

  PageCreator? getPageCreator(String route) => _routeTable[route];

  static final Map<String, PageCreator> _routeTable = {
    "/home": () => HomePage(),
    "/main": () => MainPage(),
    "/detail": () => DetailPage(),
    "/page2": () => Page2(),
  };
}
```
