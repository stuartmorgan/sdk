// Copyright (c) 2014, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:typed_data';

import 'package:analyzer/file_system/file_system.dart';
import 'package:analyzer/src/generated/source_io.dart';
import 'package:analyzer/src/source/source_resource.dart';
import 'package:path/path.dart' as pathos;
import 'package:watcher/watcher.dart';

/// An in-memory implementation of [ResourceProvider].
/// Use `/` as a path separator.
class MemoryResourceProvider implements ResourceProvider {
  final Map<String, _MemoryResource> _pathToResource =
      HashMap<String, _MemoryResource>();
  final Map<String, Uint8List> _pathToBytes = HashMap<String, Uint8List>();
  final Map<String, int> _pathToTimestamp = HashMap<String, int>();
  final Map<String, List<StreamController<WatchEvent>>> _pathToWatchers =
      HashMap<String, List<StreamController<WatchEvent>>>();
  int nextStamp = 0;

  final pathos.Context _pathContext;

  MemoryResourceProvider(
      {pathos.Context context, @deprecated bool isWindows = false})
      : _pathContext = context ??= pathos.style == pathos.Style.windows
            // On Windows, ensure that the current drive matches
            // the drive inserted by MemoryResourceProvider.convertPath
            // so that packages are mapped to the correct drive
            ? pathos.Context(current: 'C:\\')
            : pathos.context;

  @override
  pathos.Context get pathContext => _pathContext;

  /// Convert the given posix [path] to conform to this provider's path context.
  ///
  /// This is a utility method for testing; paths passed in to other methods in
  /// this class are never converted automatically.
  String convertPath(String path) {
    if (pathContext.style == pathos.windows.style) {
      if (path.startsWith(pathos.posix.separator)) {
        path = r'C:' + path;
      }
      path = path.replaceAll(pathos.posix.separator, pathos.windows.separator);
    }
    return path;
  }

  /// Delete the file with the given path.
  void deleteFile(String path) {
    _checkFileAtPath(path);
    _pathToResource.remove(path);
    _pathToBytes.remove(path);
    _pathToTimestamp.remove(path);
    _notifyWatchers(path, ChangeType.REMOVE);
  }

  /// Delete the folder with the given path
  /// and recursively delete nested files and folders.
  void deleteFolder(String path) {
    _checkFolderAtPath(path);
    _MemoryFolder folder = _pathToResource[path];
    for (Resource child in folder.getChildren()) {
      if (child is File) {
        deleteFile(child.path);
      } else if (child is Folder) {
        deleteFolder(child.path);
      } else {
        throw 'failed to delete resource: $child';
      }
    }
    _pathToResource.remove(path);
    _pathToBytes.remove(path);
    _pathToTimestamp.remove(path);
    _notifyWatchers(path, ChangeType.REMOVE);
  }

  @override
  File getFile(String path) {
    _ensureAbsoluteAndNormalized(path);
    return _MemoryFile(this, path);
  }

  @override
  Folder getFolder(String path) {
    _ensureAbsoluteAndNormalized(path);
    return _MemoryFolder(this, path);
  }

  @override
  Future<List<int>> getModificationTimes(List<Source> sources) async {
    return sources.map((source) {
      String path = source.fullName;
      return _pathToTimestamp[path] ?? -1;
    }).toList();
  }

  @override
  Resource getResource(String path) {
    _ensureAbsoluteAndNormalized(path);
    return _pathToResource[path] ?? _MemoryFile(this, path);
  }

  @override
  Folder getStateLocation(String pluginId) {
    var path = convertPath('/user/home/$pluginId');
    return newFolder(path);
  }

  void modifyFile(String path, String content) {
    _checkFileAtPath(path);
    _pathToBytes[path] = utf8.encode(content) as Uint8List;
    _pathToTimestamp[path] = nextStamp++;
    _notifyWatchers(path, ChangeType.MODIFY);
  }

  /// Create a resource representing a dummy link (that is, a File object which
  /// appears in its parent directory, but whose `exists` property is false)
  File newDummyLink(String path) {
    _ensureAbsoluteAndNormalized(path);
    newFolder(pathContext.dirname(path));
    _MemoryDummyLink link = _MemoryDummyLink(this, path);
    _pathToResource[path] = link;
    _pathToTimestamp[path] = nextStamp++;
    _notifyWatchers(path, ChangeType.ADD);
    return link;
  }

  File newFile(String path, String content, [int stamp]) {
    _ensureAbsoluteAndNormalized(path);
    _MemoryFile file = _newFile(path);
    _pathToBytes[path] = utf8.encode(content) as Uint8List;
    _pathToTimestamp[path] = stamp ?? nextStamp++;
    _notifyWatchers(path, ChangeType.ADD);
    return file;
  }

  File newFileWithBytes(String path, List<int> bytes, [int stamp]) {
    _ensureAbsoluteAndNormalized(path);
    _MemoryFile file = _newFile(path);
    _pathToBytes[path] = Uint8List.fromList(bytes);
    _pathToTimestamp[path] = stamp ?? nextStamp++;
    _notifyWatchers(path, ChangeType.ADD);
    return file;
  }

  Folder newFolder(String path) {
    _ensureAbsoluteAndNormalized(path);
    if (!pathContext.isAbsolute(path)) {
      throw ArgumentError("Path must be absolute : $path");
    }
    _MemoryResource resource = _pathToResource[path];
    if (resource == null) {
      String parentPath = pathContext.dirname(path);
      if (parentPath != path) {
        newFolder(parentPath);
      }
      _MemoryFolder folder = _MemoryFolder(this, path);
      _pathToResource[path] = folder;
      _pathToTimestamp[path] = nextStamp++;
      _notifyWatchers(path, ChangeType.ADD);
      return folder;
    } else if (resource is _MemoryFolder) {
      _notifyWatchers(path, ChangeType.ADD);
      return resource;
    } else {
      String message =
          'Folder expected at ' "'$path'" 'but ${resource.runtimeType} found';
      throw ArgumentError(message);
    }
  }

  File updateFile(String path, String content, [int stamp]) {
    _ensureAbsoluteAndNormalized(path);
    newFolder(pathContext.dirname(path));
    _MemoryFile file = _MemoryFile(this, path);
    _pathToResource[path] = file;
    _pathToBytes[path] = utf8.encode(content) as Uint8List;
    _pathToTimestamp[path] = stamp ?? nextStamp++;
    _notifyWatchers(path, ChangeType.MODIFY);
    return file;
  }

  /// Write a representation of the file system on the given [sink].
  void writeOn(StringSink sink) {
    List<String> paths = _pathToResource.keys.toList();
    paths.sort();
    paths.forEach(sink.writeln);
  }

  void _checkFileAtPath(String path) {
    // TODO(brianwilkerson) Consider throwing a FileSystemException rather than
    // an ArgumentError.
    _MemoryResource resource = _pathToResource[path];
    if (resource is! _MemoryFile) {
      if (resource == null) {
        throw ArgumentError('File expected at "$path" but does not exist');
      }
      throw ArgumentError(
          'File expected at "$path" but ${resource.runtimeType} found');
    }
  }

  void _checkFolderAtPath(String path) {
    // TODO(brianwilkerson) Consider throwing a FileSystemException rather than
    // an ArgumentError.
    _MemoryResource resource = _pathToResource[path];
    if (resource is! _MemoryFolder) {
      throw ArgumentError(
          'Folder expected at "$path" but ${resource.runtimeType} found');
    }
  }

  /// The file system abstraction supports only absolute and normalized paths.
  /// This method is used to validate any input paths to prevent errors later.
  void _ensureAbsoluteAndNormalized(String path) {
    if (!pathContext.isAbsolute(path)) {
      throw ArgumentError("Path must be absolute : $path");
    }
    if (pathContext.normalize(path) != path) {
      throw ArgumentError("Path must be normalized : $path");
    }
  }

  /// Create a new [_MemoryFile] without any content.
  _MemoryFile _newFile(String path) {
    String folderPath = pathContext.dirname(path);
    _MemoryResource folder = _pathToResource[folderPath];
    if (folder == null) {
      newFolder(folderPath);
    } else if (folder is! Folder) {
      throw ArgumentError('Cannot create file ($path) as child of file');
    }
    _MemoryFile file = _MemoryFile(this, path);
    _pathToResource[path] = file;
    return file;
  }

  void _notifyWatchers(String path, ChangeType changeType) {
    _pathToWatchers.forEach((String watcherPath,
        List<StreamController<WatchEvent>> streamControllers) {
      if (watcherPath == path || pathContext.isWithin(watcherPath, path)) {
        for (StreamController<WatchEvent> streamController
            in streamControllers) {
          streamController.add(WatchEvent(changeType, path));
        }
      }
    });
  }

  _MemoryFile _renameFileSync(_MemoryFile file, String newPath) {
    String path = file.path;
    if (newPath == path) {
      return file;
    }
    _MemoryResource existingNewResource = _pathToResource[newPath];
    if (existingNewResource is _MemoryFolder) {
      throw FileSystemException(
          path, 'Could not be renamed: $newPath is a folder.');
    }
    _MemoryFile newFile = _newFile(newPath);
    _pathToResource.remove(path);
    _pathToBytes[newPath] = _pathToBytes.remove(path);
    _pathToTimestamp[newPath] = _pathToTimestamp.remove(path);
    if (existingNewResource != null) {
      _notifyWatchers(newPath, ChangeType.REMOVE);
    }
    _notifyWatchers(path, ChangeType.REMOVE);
    _notifyWatchers(newPath, ChangeType.ADD);
    return newFile;
  }

  void _setFileContent(_MemoryFile file, List<int> bytes) {
    String path = file.path;
    _pathToResource[path] = file;
    _pathToBytes[path] = Uint8List.fromList(bytes);
    _pathToTimestamp[path] = nextStamp++;
    _notifyWatchers(path, ChangeType.MODIFY);
  }
}

/// An in-memory implementation of [File] which acts like a symbolic link to a
/// non-existent file.
class _MemoryDummyLink extends _MemoryResource implements File {
  _MemoryDummyLink(MemoryResourceProvider provider, String path)
      : super(provider, path);

  @override
  Stream<WatchEvent> get changes {
    throw FileSystemException(path, "File does not exist");
  }

  @override
  bool get exists => false;

  @override
  int get lengthSync {
    throw FileSystemException(path, 'File could not be read');
  }

  @override
  int get modificationStamp {
    int stamp = _provider._pathToTimestamp[path];
    if (stamp == null) {
      throw FileSystemException(path, "File does not exist");
    }
    return stamp;
  }

  @override
  File copyTo(Folder parentFolder) {
    throw FileSystemException(path, 'File could not be copied');
  }

  @override
  Source createSource([Uri uri]) {
    throw FileSystemException(path, 'File could not be read');
  }

  @override
  void delete() {
    throw FileSystemException(path, 'File could not be deleted');
  }

  @override
  bool isOrContains(String path) {
    return path == this.path;
  }

  @override
  Uint8List readAsBytesSync() {
    throw FileSystemException(path, 'File could not be read');
  }

  @override
  String readAsStringSync() {
    throw FileSystemException(path, 'File could not be read');
  }

  @override
  File renameSync(String newPath) {
    throw FileSystemException(path, 'File could not be renamed');
  }

  @override
  File resolveSymbolicLinksSync() {
    return throw FileSystemException(path, "File does not exist");
  }

  @override
  void writeAsBytesSync(List<int> bytes) {
    throw FileSystemException(path, 'File could not be written');
  }

  @override
  void writeAsStringSync(String content) {
    throw FileSystemException(path, 'File could not be written');
  }
}

/// An in-memory implementation of [File].
class _MemoryFile extends _MemoryResource implements File {
  _MemoryFile(MemoryResourceProvider provider, String path)
      : super(provider, path);

  @override
  bool get exists => _provider._pathToResource[path] is _MemoryFile;

  @override
  int get lengthSync {
    return readAsBytesSync().length;
  }

  @override
  int get modificationStamp {
    int stamp = _provider._pathToTimestamp[path];
    if (stamp == null) {
      throw FileSystemException(path, 'File "$path" does not exist.');
    }
    return stamp;
  }

  @override
  File copyTo(Folder parentFolder) {
    parentFolder.create();
    File destination = parentFolder.getChildAssumingFile(shortName);
    destination.writeAsBytesSync(readAsBytesSync());
    return destination;
  }

  @override
  Source createSource([Uri uri]) {
    uri ??= _provider.pathContext.toUri(path);
    return FileSource(this, uri);
  }

  @override
  void delete() {
    _provider.deleteFile(path);
  }

  @override
  bool isOrContains(String path) {
    return path == this.path;
  }

  @override
  Uint8List readAsBytesSync() {
    Uint8List content = _provider._pathToBytes[path];
    if (content == null) {
      throw FileSystemException(path, 'File "$path" does not exist.');
    }
    return content;
  }

  @override
  String readAsStringSync() {
    Uint8List content = _provider._pathToBytes[path];
    if (content == null) {
      throw FileSystemException(path, 'File "$path" does not exist.');
    }
    return utf8.decode(content);
  }

  @override
  File renameSync(String newPath) {
    return _provider._renameFileSync(this, newPath);
  }

  @override
  File resolveSymbolicLinksSync() => this;

  @override
  void writeAsBytesSync(List<int> bytes) {
    _provider._setFileContent(this, bytes);
  }

  @override
  void writeAsStringSync(String content) {
    _provider._setFileContent(this, utf8.encode(content));
  }
}

/// An in-memory implementation of [Folder].
class _MemoryFolder extends _MemoryResource implements Folder {
  _MemoryFolder(MemoryResourceProvider provider, String path)
      : super(provider, path);

  @override
  bool get exists => _provider._pathToResource[path] is _MemoryFolder;

  @override
  String canonicalizePath(String relPath) {
    relPath = _provider.pathContext.normalize(relPath);
    String childPath = _provider.pathContext.join(path, relPath);
    childPath = _provider.pathContext.normalize(childPath);
    return childPath;
  }

  @override
  bool contains(String path) {
    return _provider.pathContext.isWithin(this.path, path);
  }

  @override
  Folder copyTo(Folder parentFolder) {
    Folder destination = parentFolder.getChildAssumingFolder(shortName);
    destination.create();
    for (Resource child in getChildren()) {
      child.copyTo(destination);
    }
    return destination;
  }

  @override
  void create() {
    _provider.newFolder(path);
  }

  @override
  void delete() {
    _provider.deleteFolder(path);
  }

  @override
  Resource getChild(String relPath) {
    String childPath = canonicalizePath(relPath);
    return _provider._pathToResource[childPath] ??
        _MemoryFile(_provider, childPath);
  }

  @override
  _MemoryFile getChildAssumingFile(String relPath) {
    String childPath = canonicalizePath(relPath);
    _MemoryResource resource = _provider._pathToResource[childPath];
    if (resource is _MemoryFile) {
      return resource;
    }
    return _MemoryFile(_provider, childPath);
  }

  @override
  _MemoryFolder getChildAssumingFolder(String relPath) {
    String childPath = canonicalizePath(relPath);
    _MemoryResource resource = _provider._pathToResource[childPath];
    if (resource is _MemoryFolder) {
      return resource;
    }
    return _MemoryFolder(_provider, childPath);
  }

  @override
  List<Resource> getChildren() {
    if (!exists) {
      throw FileSystemException(path, 'Folder does not exist.');
    }
    List<Resource> children = <Resource>[];
    _provider._pathToResource.forEach((resourcePath, resource) {
      if (_provider.pathContext.dirname(resourcePath) == path) {
        children.add(resource);
      }
    });
    return children;
  }

  @override
  bool isOrContains(String path) {
    if (path == this.path) {
      return true;
    }
    return contains(path);
  }

  @override
  Folder resolveSymbolicLinksSync() => this;

  @override
  Uri toUri() => _provider.pathContext.toUri(path + '/');
}

/// An in-memory implementation of [Resource].
abstract class _MemoryResource implements Resource {
  final MemoryResourceProvider _provider;
  @override
  final String path;

  _MemoryResource(this._provider, this.path);

  Stream<WatchEvent> get changes {
    StreamController<WatchEvent> streamController =
        StreamController<WatchEvent>();
    if (!_provider._pathToWatchers.containsKey(path)) {
      _provider._pathToWatchers[path] = <StreamController<WatchEvent>>[];
    }
    _provider._pathToWatchers[path].add(streamController);
    streamController.done.then((_) {
      _provider._pathToWatchers[path].remove(streamController);
      if (_provider._pathToWatchers[path].isEmpty) {
        _provider._pathToWatchers.remove(path);
      }
    });
    return streamController.stream;
  }

  @override
  int get hashCode => path.hashCode;

  @override
  Folder get parent {
    String parentPath = _provider.pathContext.dirname(path);
    if (parentPath == path) {
      return null;
    }
    return _provider.getFolder(parentPath);
  }

  @override
  String get shortName => _provider.pathContext.basename(path);

  @override
  bool operator ==(Object other) {
    if (runtimeType != other.runtimeType) {
      return false;
    }
    return path == (other as _MemoryResource).path;
  }

  @override
  String toString() => path;

  @override
  Uri toUri() => _provider.pathContext.toUri(path);
}
