// Copyright (c) 2016, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:observatory/models.dart' as M;

/// Utility class for URIs generation.
abstract class Uris {
  static String _isolatePage(String path, M.IsolateRef isolate,
      {M.ObjectRef object}) {
    return '#' + new Uri(path: path, queryParameters: {
        'isolateId': isolate.id,
        'objectId': object?.id
      }).toString();
  }

  static String inspect(M.IsolateRef isolate, {M.ObjectRef object})
      => _isolatePage('/inspect', isolate, object: object);
  static String debugger(M.IsolateRef isolate)
      => _isolatePage('/debugger', isolate);
  static String classTree(M.IsolateRef isolate)
      => _isolatePage('/class-tree', isolate);
  static String cpuProfiler(M.IsolateRef isolate)
      => _isolatePage('/profiler', isolate);
  static String cpuProfilerTable(M.IsolateRef isolate)
      => _isolatePage('/profiler-table', isolate);
  static String allocationProfiler(M.IsolateRef isolate)
      => _isolatePage('/allocation-profiler', isolate);
  static String heapMap(M.IsolateRef isolate)
      => _isolatePage('/heap-map', isolate);
  static String metrics(M.IsolateRef isolate)
      => _isolatePage('/metrics', isolate);
  static String heapSnapshot(M.IsolateRef isolate)
      => _isolatePage('/heap-snapshot', isolate);
  static String persistentHandles(M.IsolateRef isolate)
      => _isolatePage('/persistent-handles', isolate);
  static String ports(M.IsolateRef isolate)
      => _isolatePage('/ports', isolate);
  static String logging(M.IsolateRef isolate)
      => _isolatePage('/logging', isolate);
  static String vm() => '#/vm';
  static String vmConnect() => '#/vm-connect';
}
