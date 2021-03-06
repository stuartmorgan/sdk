import "dart:convert";
import "dart:io";

import "package:vm_service/vm_service.dart" as vmService;
import "package:vm_service/vm_service_io.dart" as vmService;

import "dijkstras_sssp_algorithm.dart";

class VMServiceHeapHelper {
  Process _process;
  vmService.VmService _serviceClient;
  bool _started = false;
  final Map<Uri, Map<String, List<String>>> _interests =
      new Map<Uri, Map<String, List<String>>>();
  final Map<Uri, Map<String, List<String>>> _prettyPrints =
      new Map<Uri, Map<String, List<String>>>();
  final bool throwOnPossibleLeak;

  VMServiceHeapHelper(List<Interest> interests, List<Interest> prettyPrints,
      this.throwOnPossibleLeak) {
    if (interests.isEmpty) throw "Empty list of interests given";
    for (Interest interest in interests) {
      Map<String, List<String>> classToFields = _interests[interest.uri];
      if (classToFields == null) {
        classToFields = Map<String, List<String>>();
        _interests[interest.uri] = classToFields;
      }
      List<String> fields = classToFields[interest.className];
      if (fields == null) {
        fields = new List<String>();
        classToFields[interest.className] = fields;
      }
      fields.addAll(interest.fieldNames);
    }
    for (Interest interest in prettyPrints) {
      Map<String, List<String>> classToFields = _prettyPrints[interest.uri];
      if (classToFields == null) {
        classToFields = Map<String, List<String>>();
        _prettyPrints[interest.uri] = classToFields;
      }
      List<String> fields = classToFields[interest.className];
      if (fields == null) {
        fields = new List<String>();
        classToFields[interest.className] = fields;
      }
      fields.addAll(interest.fieldNames);
    }
  }

  void start(List<String> scriptAndArgs) async {
    if (_started) throw "Already started";
    _started = true;
    _process = await Process.start(
        Platform.resolvedExecutable,
        ["--pause_isolates_on_start", "--enable-vm-service=0"]
          ..addAll(scriptAndArgs));
    _process.stdout
        .transform(utf8.decoder)
        .transform(new LineSplitter())
        .listen((line) {
      const kObservatoryListening = 'Observatory listening on ';
      if (line.startsWith(kObservatoryListening)) {
        Uri observatoryUri =
            Uri.parse(line.substring(kObservatoryListening.length));
        _gotObservatoryUri(observatoryUri);
      }
      stdout.writeln("> $line");
    });
    _process.stderr
        .transform(utf8.decoder)
        .transform(new LineSplitter())
        .listen((line) {
      stderr.writeln("> $line");
    });
  }

  void _gotObservatoryUri(Uri observatoryUri) async {
    String wsUriString =
        'ws://${observatoryUri.authority}${observatoryUri.path}ws';
    _serviceClient = await vmService.vmServiceConnectUri(wsUriString,
        log: const StdOutLog());
    await _run();
  }

  void _run() async {
    vmService.VM vm = await _serviceClient.getVM();
    if (vm.isolates.length != 1) {
      throw "Expected 1 isolate, got ${vm.isolates.length}";
    }
    vmService.IsolateRef isolateRef = vm.isolates.single;
    await _forceGC(isolateRef.id);

    assert(await _isPausedAtStart(isolateRef.id));
    await _serviceClient.resume(isolateRef.id);

    int iterationNumber = 1;
    while (true) {
      await _waitUntilPaused(isolateRef.id);
      print("Iteration: #$iterationNumber");
      iterationNumber++;
      await _forceGC(isolateRef.id);

      vmService.HeapSnapshotGraph heapSnapshotGraph =
          await vmService.HeapSnapshotGraph.getSnapshot(
              _serviceClient, isolateRef);
      HeapGraph graph = convertHeapGraph(heapSnapshotGraph);

      Set<String> seenPrints = {};
      Set<String> duplicatePrints = {};
      Map<String, List<HeapGraphElement>> groupedByToString = {};
      for (HeapGraphClassActual c in graph.classes) {
        Map<String, List<String>> interests = _interests[c.libraryUri];
        if (interests != null && interests.isNotEmpty) {
          List<String> fieldsToUse = interests[c.name];
          if (fieldsToUse != null && fieldsToUse.isNotEmpty) {
            for (HeapGraphElement instance in c.instances) {
              StringBuffer sb = new StringBuffer();
              sb.writeln("Instance: ${instance}");
              if (instance is HeapGraphElementActual) {
                for (String fieldName in fieldsToUse) {
                  String prettyPrinted = instance
                      .getField(fieldName)
                      .getPrettyPrint(_prettyPrints);
                  sb.writeln("  $fieldName: "
                      "${prettyPrinted}");
                }
              }
              String sbToString = sb.toString();
              if (!seenPrints.add(sbToString)) {
                duplicatePrints.add(sbToString);
              }
              groupedByToString[sbToString] ??= [];
              groupedByToString[sbToString].add(instance);
            }
          }
        }
      }
      if (duplicatePrints.isNotEmpty) {
        print("======================================");
        print("WARNING: Duplicated pretty prints of objects.");
        print("This might be a memory leak!");
        print("");
        for (String s in duplicatePrints) {
          int count = groupedByToString[s].length;
          print("$s ($count)");
          print("");
        }
        print("======================================");
        for (String duplicateString in duplicatePrints) {
          print("$duplicateString:");
          List<HeapGraphElement> Function(HeapGraphElement target)
              dijkstraTarget = dijkstra(graph.elements.first, graph);
          for (HeapGraphElement duplicate
              in groupedByToString[duplicateString]) {
            print("${duplicate} pointed to from:");
            List<HeapGraphElement> shortestPath = dijkstraTarget(duplicate);
            for (int i = 0; i < shortestPath.length - 1; i++) {
              HeapGraphElement thisOne = shortestPath[i];
              HeapGraphElement nextOne = shortestPath[i + 1];
              String indexFieldName;
              if (thisOne is HeapGraphElementActual) {
                HeapGraphClass c = thisOne.class_;
                if (c is HeapGraphClassActual) {
                  for (vmService.HeapSnapshotField field in c.origin.fields) {
                    if (thisOne.references[field.index] == nextOne) {
                      indexFieldName = field.name;
                    }
                  }
                }
              }
              if (indexFieldName == null) {
                indexFieldName = "no field found; index "
                    "${thisOne.references.indexOf(nextOne)}";
              }
              print("  $thisOne -> $nextOne ($indexFieldName)");
            }
            print("---------------------------");
          }
        }

        if (throwOnPossibleLeak) throw "Possible leak detected.";
      }
      await _serviceClient.resume(isolateRef.id);
    }
  }

  List<HeapGraphElement> Function(HeapGraphElement target) dijkstra(
      HeapGraphElement source, HeapGraph heapGraph) {
    Map<HeapGraphElement, int> elementNum = {};
    Map<HeapGraphElement, GraphNode<HeapGraphElement>> elements = {};
    elements[heapGraph.elementSentinel] =
        new GraphNode<HeapGraphElement>(heapGraph.elementSentinel);
    elementNum[heapGraph.elementSentinel] = elements.length;
    for (HeapGraphElementActual element in heapGraph.elements) {
      elements[element] = new GraphNode<HeapGraphElement>(element);
      elementNum[element] = elements.length;
    }

    for (HeapGraphElementActual element in heapGraph.elements) {
      GraphNode<HeapGraphElement> node = elements[element];
      for (HeapGraphElement out in element.references) {
        node.addOutgoing(elements[out]);
      }
    }

    DijkstrasAlgorithm<HeapGraphElement> result =
        new DijkstrasAlgorithm<HeapGraphElement>(
      elements.values,
      elements[source],
      (HeapGraphElement a, HeapGraphElement b) {
        if (identical(a, b)) {
          throw "Comparing two identical ones was unexpected";
        }
        return elementNum[a] - elementNum[b];
      },
      (HeapGraphElement a, HeapGraphElement b) {
        if (identical(a, b)) return 0;
        // Prefer not to go via sentinel and via "Context".
        if (b is HeapGraphElementSentinel) return 100;
        HeapGraphElementActual bb = b;
        if (bb.class_ is HeapGraphClassSentinel) return 100;
        HeapGraphClassActual c = bb.class_;
        if (c.name == "Context") {
          if (c.libraryUri.toString().isEmpty) return 100;
        }
        return 1;
      },
    );

    return (HeapGraphElement target) {
      return result.getPathFromTarget(elements[source], elements[target]);
    };
  }

  Future<void> _waitUntilPaused(String isolateId) async {
    int nulls = 0;
    while (true) {
      bool result = await _isPaused(isolateId);
      if (result == null) {
        nulls++;
        if (nulls > 5) {
          // We've now asked for the isolate 5 times and in all cases gotten
          // `Sentinel`. Most likely things aren't working for whatever reason.
          return;
        }
      } else if (result) {
        return;
      } else {
        await Future.delayed(const Duration(milliseconds: 100));
      }
    }
  }

  Future<bool> _isPaused(String isolateId) async {
    dynamic tmp = await _serviceClient.getIsolate(isolateId);
    if (tmp is vmService.Isolate) {
      vmService.Isolate isolate = tmp;
      if (isolate.pauseEvent.kind != "Resume") return true;
      return false;
    }
    return null;
  }

  Future<bool> _isPausedAtStart(String isolateId) async {
    dynamic tmp = await _serviceClient.getIsolate(isolateId);
    if (tmp is vmService.Isolate) {
      vmService.Isolate isolate = tmp;
      return isolate.pauseEvent.kind == "PauseStart";
    }
    return false;
  }

  Future<void> _forceGC(String isolateId) async {
    await _waitUntilIsolateIsRunnable(isolateId);
    int expectGcAfter = new DateTime.now().millisecondsSinceEpoch;
    while (true) {
      vmService.AllocationProfile allocationProfile =
          await _serviceClient.getAllocationProfile(isolateId, gc: true);
      if (allocationProfile.dateLastServiceGC != null &&
          allocationProfile.dateLastServiceGC >= expectGcAfter) {
        return;
      }
    }
  }

  Future<bool> _isIsolateRunnable(String isolateId) async {
    dynamic tmp = await _serviceClient.getIsolate(isolateId);
    if (tmp is vmService.Isolate) {
      vmService.Isolate isolate = tmp;
      return isolate.runnable;
    }
    return null;
  }

  Future<void> _waitUntilIsolateIsRunnable(String isolateId) async {
    int nulls = 0;
    while (true) {
      bool result = await _isIsolateRunnable(isolateId);
      if (result == null) {
        nulls++;
        if (nulls > 5) {
          // We've now asked for the isolate 5 times and in all cases gotten
          // `Sentinel`. Most likely things aren't working for whatever reason.
          return;
        }
      } else if (result) {
        return;
      } else {
        await Future.delayed(const Duration(milliseconds: 100));
      }
    }
  }
}

class Interest {
  final Uri uri;
  final String className;
  final List<String> fieldNames;

  Interest(this.uri, this.className, this.fieldNames);
}

class StdOutLog implements vmService.Log {
  const StdOutLog();

  @override
  void severe(String message) {
    print("> SEVERE: $message");
  }

  @override
  void warning(String message) {
    print("> WARNING: $message");
  }
}

HeapGraph convertHeapGraph(vmService.HeapSnapshotGraph graph) {
  HeapGraphClassSentinel classSentinel = new HeapGraphClassSentinel();
  List<HeapGraphClassActual> classes = [];
  for (int i = 0; i < graph.classes.length; i++) {
    vmService.HeapSnapshotClass c = graph.classes[i];
    classes.add(new HeapGraphClassActual(c));
  }

  HeapGraphElementSentinel elementSentinel = new HeapGraphElementSentinel();
  List<HeapGraphElementActual> elements = [];
  for (int i = 0; i < graph.objects.length; i++) {
    vmService.HeapSnapshotObject o = graph.objects[i];
    elements.add(new HeapGraphElementActual(o));
  }

  for (int i = 0; i < graph.objects.length; i++) {
    vmService.HeapSnapshotObject o = graph.objects[i];
    HeapGraphElementActual converted = elements[i];
    if (o.classId == 0) {
      converted.class_ = classSentinel;
    } else {
      converted.class_ = classes[o.classId - 1];
    }
    converted.class_.instances.add(converted);
    for (int refId in o.references) {
      HeapGraphElement ref;
      if (refId == 0) {
        ref = elementSentinel;
      } else {
        ref = elements[refId - 1];
      }
      converted.references.add(ref);
      ref.referenced.add(converted);
    }
  }

  return new HeapGraph(classSentinel, classes, elementSentinel, elements);
}

class HeapGraph {
  final HeapGraphClassSentinel classSentinel;
  final List<HeapGraphClassActual> classes;
  final HeapGraphElementSentinel elementSentinel;
  final List<HeapGraphElementActual> elements;

  HeapGraph(
      this.classSentinel, this.classes, this.elementSentinel, this.elements);
}

abstract class HeapGraphElement {
  /// Outbound references, i.e. this element points to elements in this list.
  List<HeapGraphElement> references = [];

  /// Inbound references, i.e. this element is pointed to by these elements.
  Set<HeapGraphElement> referenced = {};

  String getPrettyPrint(Map<Uri, Map<String, List<String>>> prettyPrints) {
    if (this is HeapGraphElementActual) {
      HeapGraphElementActual me = this;
      if (me.class_.toString() == "_OneByteString") {
        return '"${me.origin.data}"';
      }
      if (me.class_.toString() == "_SimpleUri") {
        return "_SimpleUri["
            "${me.getField("_uri").getPrettyPrint(prettyPrints)}]";
      }
      if (me.class_.toString() == "_Uri") {
        return "_Uri[${me.getField("scheme").getPrettyPrint(prettyPrints)}:"
            "${me.getField("path").getPrettyPrint(prettyPrints)}]";
      }
      if (me.class_ is HeapGraphClassActual) {
        HeapGraphClassActual c = me.class_;
        Map<String, List<String>> classToFields = prettyPrints[c.libraryUri];
        if (classToFields != null) {
          List<String> fields = classToFields[c.name];
          if (fields != null) {
            return "${c.name}[" +
                fields.map((field) {
                  return "$field: ${me.getField(field).getPrettyPrint(prettyPrints)}";
                }).join(", ") +
                "]";
          }
        }
      }
    }
    return toString();
  }
}

class HeapGraphElementSentinel extends HeapGraphElement {
  String toString() => "HeapGraphElementSentinel";
}

class HeapGraphElementActual extends HeapGraphElement {
  final vmService.HeapSnapshotObject origin;
  HeapGraphClass class_;

  HeapGraphElementActual(this.origin);

  HeapGraphElement getField(String name) {
    if (class_ is HeapGraphClassActual) {
      HeapGraphClassActual c = class_;
      for (vmService.HeapSnapshotField field in c.origin.fields) {
        if (field.name == name) {
          return references[field.index];
        }
      }
    }
    return null;
  }

  List<MapEntry<String, HeapGraphElement>> getFields() {
    List<MapEntry<String, HeapGraphElement>> result = [];
    if (class_ is HeapGraphClassActual) {
      HeapGraphClassActual c = class_;
      for (vmService.HeapSnapshotField field in c.origin.fields) {
        result.add(new MapEntry(field.name, references[field.index]));
      }
    }
    return result;
  }

  String toString() {
    if (origin.data is vmService.HeapSnapshotObjectNoData) {
      return "Instance of $class_";
    }
    if (origin.data is vmService.HeapSnapshotObjectLengthData) {
      vmService.HeapSnapshotObjectLengthData data = origin.data;
      return "Instance of $class_ length = ${data.length}";
    }
    return "Instance of $class_; data: '${origin.data}'";
  }
}

abstract class HeapGraphClass {
  List<HeapGraphElement> instances = [];
}

class HeapGraphClassSentinel extends HeapGraphClass {
  String toString() => "HeapGraphClassSentinel";
}

class HeapGraphClassActual extends HeapGraphClass {
  final vmService.HeapSnapshotClass origin;

  HeapGraphClassActual(this.origin) {
    assert(origin != null);
  }

  String get name => origin.name;

  Uri get libraryUri => origin.libraryUri;

  String toString() => name;
}
