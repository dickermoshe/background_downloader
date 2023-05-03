// ignore_for_file: avoid_print, empty_catches

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:background_downloader/background_downloader.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:path/path.dart' hide equals;
import 'package:path_provider/path_provider.dart';

const def = 'default';
var statusCallbackCounter = 0;
var progressCallbackCounter = 0;

var statusCallbackCompleter = Completer<void>();
var progressCallbackCompleter = Completer<void>();
var someProgressCompleter = Completer<void>(); // completes when progress > 0.1
var lastStatus = TaskStatus.enqueued;
var lastProgress = -100.0;
TaskError? lastError;

const workingUrl = 'https://google.com';
const failingUrl = 'https://avmaps-dot-bbflightserver-hrd.appspot'
    '.com/public/get_current_app_data?key=background_downloader_integration_test';
const urlWithContentLength = 'https://storage.googleapis'
    '.com/approachcharts/test/5MB-test.ZIP';
const getTestUrl =
    'https://avmaps-dot-bbflightserver-hrd.appspot.com/public/test_get_data';
const getRedirectTestUrl =
    'https://avmaps-dot-bbflightserver-hrd.appspot.com/public/test_get_redirect';
const postTestUrl =
    'https://avmaps-dot-bbflightserver-hrd.appspot.com/public/test_post_data';
const uploadTestUrl =
    'https://avmaps-dot-bbflightserver-hrd.appspot.com/public/test_upload_file';
const uploadBinaryTestUrl =
    'https://avmaps-dot-bbflightserver-hrd.appspot.com/public/test_upload_binary_file';

const urlWithContentLengthFileSize = 6207471;

const defaultFilename = 'google.html';
const postFilename = 'post.txt';
const uploadFilename = 'a_file.txt';
const largeFilename = '5MB-test.ZIP';

var task = DownloadTask(url: workingUrl, filename: defaultFilename);

var retryTask =
    DownloadTask(url: failingUrl, filename: defaultFilename, retries: 3);

var uploadTask = UploadTask(url: uploadTestUrl, filename: uploadFilename);
var uploadTaskBinary = uploadTask.copyWith(post: 'binary');

void statusCallback(Task task, TaskStatus status) {
  print('statusCallback for $task with status $status');
  lastStatus = status;
  statusCallbackCounter++;
  if (!statusCallbackCompleter.isCompleted && status.isFinalState) {
    statusCallbackCompleter.complete();
  }
}

void statusCallbackWithError(
    Task task, TaskStatus status, TaskError? taskError) {
  print(
      'statusCallbackWithError for $task with status $status and error $taskError');
  lastStatus = status;
  statusCallbackCounter++;
  lastError = taskError;
  if (!statusCallbackCompleter.isCompleted && status.isFinalState) {
    statusCallbackCompleter.complete();
  }
}

void progressCallback(Task task, double progress) {
  print('progressCallback for $task with progress $progress');
  lastProgress = progress;
  progressCallbackCounter++;
  if (!someProgressCompleter.isCompleted && progress > 0) {
    someProgressCompleter.complete();
  }
  if (!progressCallbackCompleter.isCompleted &&
      (progress < 0 || progress == 1)) {
    progressCallbackCompleter.complete();
  }
}

void main() {
  setUp(() async {
    Logger.root.level = Level.ALL;
    Logger.root.onRecord.listen((LogRecord rec) {
      print('${rec.loggerName}>${rec.level.name}: ${rec.time}: ${rec.message}');
    });
    // recreate the tasks
    task = DownloadTask(url: workingUrl, filename: defaultFilename);
    retryTask =
        DownloadTask(url: failingUrl, filename: defaultFilename, retries: 3);
    uploadTask = UploadTask(url: uploadTestUrl, filename: uploadFilename);
    uploadTaskBinary =
        uploadTask.copyWith(url: uploadBinaryTestUrl, post: 'binary');
    // copy the test file to upload from assets to documents directory
    Directory directory = await getApplicationDocumentsDirectory();
    var uploadFilePath = join(directory.path, uploadFilename);
    ByteData data = await rootBundle.load("assets/$uploadFilename");
    final buffer = data.buffer;
    File(uploadFilePath).writeAsBytesSync(
        buffer.asUint8List(data.offsetInBytes, data.lengthInBytes));
    // reset counters
    statusCallbackCounter = 0;
    progressCallbackCounter = 0;
    statusCallbackCompleter = Completer<void>();
    progressCallbackCompleter = Completer<void>();
    someProgressCompleter = Completer<void>();
    lastStatus = TaskStatus.enqueued;
    lastError = null;
    FileDownloader().destroy();
    final path =
        join((await getApplicationDocumentsDirectory()).path, task.filename);
    try {
      File(path).deleteSync();
    } on FileSystemException {}
  });

  tearDown(() async {
    FileDownloader().destroy();
    if (Platform.isAndroid || Platform.isIOS) {
      await FileDownloader()
          .downloaderForTesting
          .setForceFailPostOnBackgroundChannel(false);
    }
    Future.delayed(const Duration(milliseconds: 250));
  });

  group('Initialization', () {
    test('registerCallbacks', () {
      expect(() => FileDownloader().registerCallbacks(), throwsAssertionError);
      FileDownloader().registerCallbacks(taskStatusCallback: statusCallback);
      FileDownloader().registerCallbacks(
          group: 'test', taskProgressCallback: progressCallback);
    });

    test('uploadTask', () {
      var task = UploadTask(url: uploadTestUrl, filename: uploadFilename);
      expect(task.fileField, equals('file'));
      expect(task.mimeType, equals('text/plain'));
      task = UploadTask(
          url: uploadTestUrl,
          filename: uploadFilename,
          fileField: 'fileField',
          mimeType: 'someThing');
      expect(task.fileField, equals('fileField'));
      expect(task.mimeType, equals('someThing'));
    });
  });

  group('Enqueuing tasks', () {
    testWidgets('enqueue', (tester) async {
      var path =
          join((await getApplicationDocumentsDirectory()).path, task.filename);
      await enqueueAndFileExists(path);
      expect(lastStatus, equals(TaskStatus.complete));
      // with subdirectory
      task = DownloadTask(
          url: workingUrl, directory: 'test', filename: defaultFilename);
      path = join((await getApplicationDocumentsDirectory()).path, 'test',
          task.filename);
      await enqueueAndFileExists(path);
      // cache directory
      task = DownloadTask(
          url: workingUrl,
          filename: defaultFilename,
          baseDirectory: BaseDirectory.temporary);
      path = join((await getTemporaryDirectory()).path, task.filename);
      await enqueueAndFileExists(path);
      // applicationSupport directory
      task = DownloadTask(
          url: workingUrl,
          filename: defaultFilename,
          baseDirectory: BaseDirectory.applicationSupport);
      path = join((await getApplicationSupportDirectory()).path, task.filename);
      await enqueueAndFileExists(path);
      // applicationLibrary directory
      task = DownloadTask(
          url: workingUrl,
          filename: defaultFilename,
          baseDirectory: BaseDirectory.applicationLibrary);
      path = await task.filePath();
      await enqueueAndFileExists(path);

      // test url with encoded parameter
      task = DownloadTask(
          url: getTestUrl,
          urlQueryParameters: {'json': 'true', 'test': 'with%20space'},
          filename: defaultFilename);
      path =
          join((await getApplicationDocumentsDirectory()).path, task.filename);
      expect(
          await FileDownloader().download(task), equals(TaskStatus.complete));
      final result = jsonDecode(await File(path).readAsString());
      expect(result['args']['json'], equals('true'));
      expect(result['args']['test'], equals('with space'));
      await File(path).delete();
      print('Finished enqueue');
    });

    testWidgets('enqueue with progress', (widgetTester) async {
      FileDownloader().registerCallbacks(
          taskStatusCallback: statusCallback,
          taskProgressCallback: progressCallback);
      expect(await FileDownloader().enqueue(task), isTrue);
      await statusCallbackCompleter.future;
      expect(statusCallbackCounter, equals(3));
      // because we have not set progressUpdates to something that provides
      // progress updates, we should just get no updates
      expect(progressCallbackCompleter.isCompleted, isFalse);
      expect(progressCallbackCounter, equals(0));
      statusCallbackCounter = 0;
      statusCallbackCompleter = Completer();
      task = DownloadTask(
          url: workingUrl,
          filename: defaultFilename,
          updates: Updates.statusAndProgress);
      expect(await FileDownloader().enqueue(task), isTrue);
      await progressCallbackCompleter.future;
      // because google.com has no content-length, we only expect the 0.0 and
      // 1.0 progress update
      expect(progressCallbackCounter, equals(2));
      await statusCallbackCompleter.future;
      expect(statusCallbackCounter, equals(3));
      // now try a file that has content length
      statusCallbackCounter = 0;
      progressCallbackCounter = 0;
      statusCallbackCompleter = Completer<void>();
      progressCallbackCompleter = Completer<void>();
      task = DownloadTask(
          url: urlWithContentLength,
          filename: defaultFilename,
          updates: Updates.statusAndProgress);
      expect(await FileDownloader().enqueue(task), isTrue);
      await progressCallbackCompleter.future;
      expect(progressCallbackCounter, greaterThan(1));
      await statusCallbackCompleter.future;
      expect(statusCallbackCounter, equals(3));
      print('Finished enqueue with progress');
    });

    testWidgets('enqueue with non-default group callbacks',
        (widgetTester) async {
      FileDownloader()
          .registerCallbacks(group: 'test', taskStatusCallback: statusCallback);
      // enqueue task with 'default' group, so no status updates should come
      var path =
          join((await getApplicationDocumentsDirectory()).path, task.filename);
      try {
        File(path).deleteSync();
      } on FileSystemException {}
      expect(await FileDownloader().enqueue(task), isTrue);
      await Future.delayed(const Duration(seconds: 3)); // can't know for sure!
      expect(File(path).existsSync(), isTrue); // file still downloads
      expect(statusCallbackCompleter.isCompleted, isFalse);
      expect(statusCallbackCounter, equals(0));
      await FileDownloader().cancelTaskWithId(task.taskId);
      print('Finished enqueue with non-default group callbacks');
    });

    testWidgets('enqueue with event listener for status updates',
        (widgetTester) async {
      final path =
          join((await getApplicationDocumentsDirectory()).path, task.filename);
      try {
        File(path).deleteSync();
      } on FileSystemException {}
      expect(await FileDownloader().enqueue(task), isTrue);
      await Future.delayed(const Duration(seconds: 3)); // can't know for sure!
      expect(File(path).existsSync(), isTrue); // file still downloads
      try {
        File(path).deleteSync();
      } on FileSystemException {}
      print(
          'Check log output -> should have warned that there is no callback or listener');
      // Register listener. For testing convenience, we simply route the event
      // to the completer function we have defined
      final subscription = FileDownloader().updates.listen((event) {
        if (event is TaskStatusUpdate) {
          if (event.status != TaskStatus.failed) {
            expect(event.error, isNull);
          } else {
            // expect 403 not found error, coming up in second test
            print(event.status);
            expect(event.error, isNotNull);
            expect(event.error?.type, equals(ErrorType.httpResponse));
            expect(event.error?.httpResponseCode, equals(403));
            expect(event.error?.description.toLowerCase(), equals('forbidden'));
          }
          statusCallbackWithError(event.task, event.status, event.error);
        }
      });
      expect(await FileDownloader().enqueue(task), isTrue);
      await statusCallbackCompleter.future;
      expect(statusCallbackCounter, equals(3));
      expect(lastStatus, equals(TaskStatus.complete));
      expect(File(path).existsSync(), isTrue);
      // test with a failing url and check the error
      statusCallbackCompleter = Completer();
      task = DownloadTask(url: failingUrl, filename: 'test');
      expect(await FileDownloader().enqueue(task), isTrue);
      await statusCallbackCompleter.future;
      expect(lastStatus, equals(TaskStatus.failed));
      final error = lastError!;
      expect(error.type, equals(ErrorType.httpResponse));
      expect(error.httpResponseCode, equals(403));
      expect(error.description.toLowerCase(), equals('forbidden'));
      subscription.cancel();
    });

    testWidgets('enqueue with event listener and callback for status updates',
        (widgetTester) async {
      FileDownloader().registerCallbacks(taskStatusCallback: statusCallback);
      final path =
          join((await getApplicationDocumentsDirectory()).path, task.filename);
      // Register listener. Because we also have a callback registered, no
      // events should be received
      bool receivedEvent = false;
      final subscription = FileDownloader().updates.listen((event) {
        receivedEvent = true;
      });
      expect(await FileDownloader().enqueue(task), isTrue);
      await statusCallbackCompleter.future;
      expect(statusCallbackCounter, equals(3));
      expect(lastStatus, equals(TaskStatus.complete));
      expect(File(path).existsSync(), isTrue);
      expect(receivedEvent, isFalse);
      subscription.cancel();
    });

    testWidgets('enqueue with event listener for progress updates',
        (widgetTester) async {
      task = DownloadTask(
          url:
              'https://storage.googleapis.com/approachcharts/test/5MB-test.ZIP',
          filename: defaultFilename,
          updates: Updates.progress);
      final path =
          join((await getApplicationDocumentsDirectory()).path, task.filename);
      // Register listener. For testing convenience, we simply route the event
      // to the completer function we have defined
      final subscription = FileDownloader().updates.listen((event) {
        expect(event is TaskProgressUpdate, isTrue);
        if (event is TaskProgressUpdate) {
          progressCallback(event.task, event.progress);
        }
      });
      expect(await FileDownloader().enqueue(task), isTrue);
      await progressCallbackCompleter.future;
      expect(progressCallbackCounter, greaterThan(1));
      expect(File(path).existsSync(), isTrue);
      await subscription.cancel();
    });

    testWidgets('enqueue with redirect', (widgetTester) async {
      task = DownloadTask(url: getRedirectTestUrl, filename: defaultFilename);
      final path =
          join((await getApplicationDocumentsDirectory()).path, task.filename);
      FileDownloader().registerCallbacks(taskStatusCallback: statusCallback);
      expect(await FileDownloader().enqueue(task), isTrue);
      await statusCallbackCompleter.future;
      expect(lastStatus, equals(TaskStatus.complete));
      final contents = await File(path).readAsString();
      print(contents);
      expect(contents.startsWith("{'args': {'redirected': 'true'}"), isTrue);
      File(path).deleteSync();
    });

    testWidgets('enqueue and test file equality', (widgetTester) async {
      FileDownloader().registerCallbacks(taskStatusCallback: statusCallback);
      task = DownloadTask(url: urlWithContentLength, filename: defaultFilename);
      expect(await FileDownloader().enqueue(task), isTrue);
      await statusCallbackCompleter.future;
      expect(lastStatus, TaskStatus.complete);
      expect(
          await fileEqualsLargeTestFile(File(await task.filePath())), isTrue);
    });

    testWidgets('enqueue long Android task that times out',
        (widgetTester) async {
      // This is an Android implementation detail. Android tasks timeout
      // after 10 minutes, so to prevent a long download from failing
      // we pause the task and resume after a brief pause
      // NOTE: to test this, set the taskTimeoutMillis to a low value to
      // force an early timeout.
      if (Platform.isAndroid) {
        final timeOut =
            await FileDownloader().downloaderForTesting.getTaskTimeout();
        if (timeOut < const Duration(minutes: 1)) {
          FileDownloader().registerCallbacks(
              taskStatusCallback: statusCallback,
              taskProgressCallback: progressCallback);
          task = DownloadTask(
              url: urlWithContentLength,
              filename: defaultFilename,
              updates: Updates.statusAndProgress);
          expect(await FileDownloader().enqueue(task), isTrue);
          await statusCallbackCompleter.future;
          expect(lastStatus, equals(TaskStatus.failed)); // timed out
          expect(statusCallbackCounter, equals(3));
          task = task.copyWith(taskId: 'autoResume', allowPause: true);
          statusCallbackCompleter = Completer();
          statusCallbackCounter = 0;
          expect(await FileDownloader().enqueue(task), isTrue);
          await statusCallbackCompleter.future;
          expect(lastStatus, equals(TaskStatus.complete)); // now success
          expect(statusCallbackCounter, greaterThanOrEqualTo(6)); // min 1 pause
          expect(await fileEqualsLargeTestFile(File(await task.filePath())),
              isTrue);
        } else {
          print('Skipping test because taskTimeoutMillis is too high');
        }
      }
    });

    testWidgets('enqueue with invalid (malformed) url', (widgetTester) async {
      var task = DownloadTask(url: 'invalid%url.com', filename: 'test.html');
      expect(await FileDownloader().enqueue(task), isFalse);
      task = DownloadTask(
          url: 'http://google.com?query=5&some%other=true',
          filename: 'test.html');
      expect(await FileDownloader().enqueue(task), isFalse);
      task = DownloadTask(
          url: 'http://google.com?query=5&some%20other=true',
          filename: 'test.html');
      expect(await FileDownloader().enqueue(task), isTrue);
      await FileDownloader().cancelTaskWithId(task.taskId);
    });
  });

  group('Queue and task management', () {
    testWidgets('reset', (widgetTester) async {
      FileDownloader().registerCallbacks(taskStatusCallback: statusCallback);
      expect(await FileDownloader().enqueue(task), isTrue);
      expect(await FileDownloader().reset(group: 'non-default'), equals(0));
      expect(await FileDownloader().reset(), equals(1));
      await statusCallbackCompleter.future;
      // on iOS, the quick cancellation may not yield a 'running' state
      expect(statusCallbackCounter, lessThanOrEqualTo(3));
      expect(lastStatus, equals(TaskStatus.canceled));
      print('Finished reset');
    });

    testWidgets('allTaskIds', (widgetTester) async {
      FileDownloader().registerCallbacks(taskStatusCallback: statusCallback);
      expect(await FileDownloader().enqueue(task), isTrue);
      expect(await FileDownloader().allTaskIds(group: 'non-default'), isEmpty);
      expect((await FileDownloader().allTaskIds()).length, equals(1));
      await statusCallbackCompleter.future;
      expect(statusCallbackCounter, equals(3));
      expect(lastStatus, equals(TaskStatus.complete));
      print('Finished allTaskIds');
    });

    testWidgets('allTasks', (widgetTester) async {
      FileDownloader().registerCallbacks(taskStatusCallback: statusCallback);
      expect(await FileDownloader().enqueue(task), isTrue);
      expect(await FileDownloader().allTasks(group: 'non-default'), isEmpty);
      final tasks = await FileDownloader().allTasks();
      expect(tasks.length, equals(1));
      expect(tasks.first, equals(task));
      await statusCallbackCompleter.future;
      expect(statusCallbackCounter, equals(3));
      expect(lastStatus, equals(TaskStatus.complete));
      print('Finished alTasks');
    });

    testWidgets('cancelTasksWithIds', (widgetTester) async {
      FileDownloader().registerCallbacks(
          taskStatusCallback: statusCallback,
          taskProgressCallback: progressCallback);
      expect(await FileDownloader().enqueue(task), isTrue);
      var taskIds = await FileDownloader().allTaskIds();
      expect(taskIds.length, equals(1));
      expect(taskIds.first, equals(task.taskId));
      expect(await FileDownloader().cancelTasksWithIds(taskIds), isTrue);
      await statusCallbackCompleter.future;
      // on iOS, the quick cancellation may not yield a 'running' state
      expect(statusCallbackCounter, lessThanOrEqualTo(3));
      expect(lastStatus, equals(TaskStatus.canceled));
      // now do the same for a longer running task, cancel after some progress
      statusCallbackCounter = 0;
      statusCallbackCompleter = Completer();
      someProgressCompleter = Completer();
      task = DownloadTask(
          url: urlWithContentLength,
          filename: defaultFilename,
          updates: Updates.statusAndProgress);
      expect(await FileDownloader().enqueue(task), isTrue);
      await someProgressCompleter.future;
      taskIds = await FileDownloader().allTaskIds();
      expect(taskIds.length, equals(1));
      expect(taskIds.first, equals(task.taskId));
      expect(await FileDownloader().cancelTasksWithIds(taskIds), isTrue);
      await statusCallbackCompleter.future;
      expect(statusCallbackCounter, equals(3));
      expect(lastStatus, equals(TaskStatus.canceled));
      print('Finished cancelTasksWithIds');
    });

    testWidgets('taskForId', (widgetTester) async {
      final complexTask = DownloadTask(
          url: workingUrl,
          filename: defaultFilename,
          headers: {'Auth': 'Test'},
          directory: 'directory',
          metaData: 'someMetaData');
      FileDownloader().registerCallbacks(taskStatusCallback: statusCallback);
      expect(await FileDownloader().taskForId('something'), isNull);
      expect(await FileDownloader().enqueue(complexTask), isTrue);
      expect(await FileDownloader().taskForId('something'), isNull);
      expect(await FileDownloader().taskForId(complexTask.taskId),
          equals(complexTask));
      await statusCallbackCompleter.future;
      expect(statusCallbackCounter, equals(3));
      expect(lastStatus, equals(TaskStatus.complete));
      print('Finished taskForId');
    });

    testWidgets('DownloadTask to and from Json', (widgetTester) async {
      final complexTask = DownloadTask(
          url: postTestUrl,
          filename: defaultFilename,
          headers: {'Auth': 'Test'},
          post: 'TestPost',
          directory: 'directory',
          baseDirectory: BaseDirectory.temporary,
          group: 'someGroup',
          updates: Updates.statusAndProgress,
          requiresWiFi: true,
          retries: 5,
          allowPause: false,
          // cannot be true if post != null
          metaData: 'someMetaData');
      final now = DateTime.now();
      expect(now.difference(complexTask.creationTime).inMilliseconds,
          lessThan(100));
      FileDownloader().registerCallbacks(
          group: complexTask.group, taskStatusCallback: statusCallback);
      expect(await FileDownloader().taskForId(complexTask.taskId), isNull);
      expect(await FileDownloader().enqueue(complexTask), isTrue);
      final task = await FileDownloader().taskForId(complexTask.taskId);
      expect(task, equals(complexTask));
      if (task != null) {
        expect(task.taskId, equals(complexTask.taskId));
        expect(task.url, equals(complexTask.url));
        expect(task.filename, equals(complexTask.filename));
        expect(task.headers, equals(complexTask.headers));
        expect(task.post, equals(complexTask.post));
        expect(task.directory, equals(complexTask.directory));
        expect(task.baseDirectory, equals(complexTask.baseDirectory));
        expect(task.group, equals(complexTask.group));
        expect(task.updates, equals(complexTask.updates));
        expect(task.requiresWiFi, equals(complexTask.requiresWiFi));
        expect(task.allowPause, equals(complexTask.allowPause));
        expect(task.retries, equals(complexTask.retries));
        expect(task.retriesRemaining, equals(complexTask.retriesRemaining));
        expect(task.retriesRemaining, equals(task.retries));
        expect(task.metaData, equals(complexTask.metaData));
        expect(
            task.creationTime
                .difference(complexTask.creationTime)
                .inMilliseconds
                .abs(),
            lessThan(100));
      }
      await statusCallbackCompleter.future;
      expect(lastStatus, equals(TaskStatus.complete));
    });

    testWidgets('UploadTask to and from Json', (widgetTester) async {
      final complexTask = UploadTask(
          url: uploadTestUrl,
          filename: uploadFilename,
          headers: {'Auth': 'Test'},
          post: null,
          fileField: 'fileField',
          mimeType: 'text/html',
          fields: {'name': 'value'},
          group: 'someGroup',
          updates: Updates.statusAndProgress,
          requiresWiFi: true,
          retries: 1,
          allowPause: false,
          // cannot be true if post != null
          metaData: 'someMetaData');
      final now = DateTime.now();
      expect(now.difference(complexTask.creationTime).inMilliseconds,
          lessThan(100));
      FileDownloader().registerCallbacks(
          group: complexTask.group, taskStatusCallback: statusCallback);
      expect(await FileDownloader().taskForId(complexTask.taskId), isNull);
      expect(await FileDownloader().enqueue(complexTask), isTrue);
      final task = await FileDownloader().taskForId(complexTask.taskId);
      expect(task is UploadTask, isTrue);
      expect(task, equals(complexTask));
      if (task != null && task is UploadTask) {
        expect(task.taskId, equals(complexTask.taskId));
        expect(task.url, equals(complexTask.url));
        expect(task.filename, equals(complexTask.filename));
        expect(task.headers, equals(complexTask.headers));
        expect(task.post, equals(complexTask.post));
        expect(task.fileField, equals(complexTask.fileField));
        expect(task.mimeType, equals(complexTask.mimeType));
        expect(task.fields, equals(complexTask.fields));
        expect(task.directory, equals(complexTask.directory));
        expect(task.baseDirectory, equals(complexTask.baseDirectory));
        expect(task.group, equals(complexTask.group));
        expect(task.updates, equals(complexTask.updates));
        expect(task.requiresWiFi, equals(complexTask.requiresWiFi));
        expect(task.allowPause, equals(complexTask.allowPause));
        expect(task.retries, equals(complexTask.retries));
        expect(task.retriesRemaining, equals(complexTask.retriesRemaining));
        expect(task.retriesRemaining, equals(task.retries));
        expect(task.metaData, equals(complexTask.metaData));
        expect(
            task.creationTime
                .difference(complexTask.creationTime)
                .inMilliseconds
                .abs(),
            lessThan(100));
      }
      await statusCallbackCompleter.future;

      /// Should trigger 'notFound' because the fileField is not set to 'file
      /// which is what the server expects
      expect(lastStatus, equals(TaskStatus.notFound));
    });

    testWidgets('copyWith', (widgetTester) async {
      final complexTask = DownloadTask(
          taskId: 'uniqueId',
          url: postTestUrl,
          filename: defaultFilename,
          headers: {'Auth': 'Test'},
          post: 'TestPost',
          directory: 'directory',
          baseDirectory: BaseDirectory.temporary,
          group: 'someGroup',
          updates: Updates.statusAndProgress,
          requiresWiFi: true,
          retries: 5,
          metaData: 'someMetaData');
      final now = DateTime.now();
      expect(now.difference(complexTask.creationTime).inMilliseconds,
          lessThan(100));
      final task = complexTask.copyWith(); // all the same
      expect(task.taskId, equals(complexTask.taskId));
      expect(task.url, equals(complexTask.url));
      expect(task.filename, equals(complexTask.filename));
      expect(task.headers, equals(complexTask.headers));
      expect(task.post, equals(complexTask.post));
      expect(task.directory, equals(complexTask.directory));
      expect(task.baseDirectory, equals(complexTask.baseDirectory));
      expect(task.group, equals(complexTask.group));
      expect(task.updates, equals(complexTask.updates));
      expect(task.requiresWiFi, equals(complexTask.requiresWiFi));
      expect(task.retries, equals(complexTask.retries));
      expect(task.retriesRemaining, equals(complexTask.retriesRemaining));
      expect(task.retriesRemaining, equals(task.retries));
      expect(task.metaData, equals(complexTask.metaData));
      expect(task.creationTime, equals(complexTask.creationTime));
    });

    test('downloadTask url and urlQueryParameters', () {
      final task0 = DownloadTask(
          url: 'url with space',
          filename: defaultFilename,
          urlQueryParameters: {});
      expect(task0.url, equals('url with space'));
      final task1 = DownloadTask(
          url: 'url',
          filename: defaultFilename,
          urlQueryParameters: {'param1': '1', 'param2': 'with space'});
      expect(task1.url, equals('url?param1=1&param2=with space'));
      final task2 = DownloadTask(
          url: 'url?param0=0',
          filename: defaultFilename,
          urlQueryParameters: {'param1': '1', 'param2': 'with space'});
      expect(task2.url, equals('url?param0=0&param1=1&param2=with space'));
      final task4 =
          DownloadTask(url: urlWithContentLength, filename: defaultFilename);
      expect(task4.url, equals(urlWithContentLength));
    });

    test('downloadTask filename', () {
      final task0 = DownloadTask(url: workingUrl);
      expect(task0.filename.isNotEmpty, isTrue);
      final task1 = DownloadTask(url: workingUrl, filename: defaultFilename);
      expect(task1.filename, equals(defaultFilename));
      expect(
          () => DownloadTask(
              url: workingUrl, filename: 'somedir/$defaultFilename'),
          throwsArgumentError);
    });

    test('downloadTask directory', () {
      final task0 = DownloadTask(url: workingUrl);
      expect(task0.directory.isEmpty, isTrue);
      final task1 = DownloadTask(url: workingUrl, directory: 'testDir');
      expect(task1.directory, equals('testDir'));
      expect(() => DownloadTask(url: workingUrl, directory: '/testDir'),
          throwsArgumentError);
    });

    testWidgets('suggestedFilename', (widgetTester) async {
      // delete old downloads
      task = DownloadTask(url: urlWithContentLength, filename: '5MB-test.ZIP');
      try {
        File(await task.filePath()).deleteSync();
      } catch (e) {}
      task =
          DownloadTask(url: urlWithContentLength, filename: '5MB-test (1).ZIP');
      try {
        File(await task.filePath()).deleteSync();
      } catch (e) {}
      task =
          DownloadTask(url: urlWithContentLength, filename: '5MB-test (2).ZIP');
      try {
        File(await task.filePath()).deleteSync();
      } catch (e) {}
      task = DownloadTask(url: urlWithContentLength);
      final startingFileName = task.filename;
      final task2 = await task.withSuggestedFilename();
      expect(task2.filename, isNot(equals(startingFileName)));
      expect(task2.filename, equals('5MB-test.ZIP'));
      FileDownloader().registerCallbacks(taskStatusCallback: statusCallback);
      expect(await FileDownloader().enqueue(task2), isTrue);
      await statusCallbackCompleter.future;
      expect(lastStatus, equals(TaskStatus.complete));
      // again, should yield same filename
      final task3 = await task.withSuggestedFilename();
      expect(task3.filename, equals('5MB-test.ZIP'));
      // again with 'unique' should yield (1) filename
      final task4 = await task.withSuggestedFilename(unique: true);
      expect(task4.filename, equals('5MB-test (1).ZIP'));
      statusCallbackCompleter = Completer(); // reset
      expect(await FileDownloader().enqueue(task4), isTrue);
      await statusCallbackCompleter.future;
      expect(lastStatus, equals(TaskStatus.complete));
      // again with 'unique' should yield (2) filename
      final task5 = await task.withSuggestedFilename(unique: true);
      expect(task5.filename, equals('5MB-test (2).ZIP'));
    });
  });

  group('Convenience downloads', () {
    testWidgets('download with await', (widgetTester) async {
      var path =
          join((await getApplicationDocumentsDirectory()).path, task.filename);
      var exists = await File(path).exists();
      if (exists) {
        await File(path).delete();
      }
      final status = await FileDownloader().download(task);
      expect(status, equals(TaskStatus.complete));
      exists = await File(path).exists();
      expect(exists, isTrue);
      await File(path).delete();
    });

    testWidgets('multiple download with futures', (widgetTester) async {
      final secondTask =
          task.copyWith(taskId: 'secondTask', filename: 'second.html');
      var path =
          join((await getApplicationDocumentsDirectory()).path, task.filename);
      var exists = await File(path).exists();
      if (exists) {
        await File(path).delete();
      }
      path = join(
          (await getApplicationDocumentsDirectory()).path, secondTask.filename);
      exists = await File(path).exists();
      if (exists) {
        await File(path).delete();
      }
      // note that using a Future (without await) is unusual and is done here
      // just for testing.  Normal use would be
      // var result = await FileDownloader().download(task);
      final taskFuture = FileDownloader().download(task);
      final secondTaskFuture = FileDownloader().download(secondTask);
      var statuses = await Future.wait([taskFuture, secondTaskFuture]);
      for (var status in statuses) {
        expect(status, equals(TaskStatus.complete));
      }
      exists = await File(path).exists();
      expect(exists, isTrue);
      await File(path).delete();
      path =
          join((await getApplicationDocumentsDirectory()).path, task.filename);
      exists = await File(path).exists();
      expect(exists, isTrue);
      await File(path).delete();
    });

    testWidgets('batch download', (widgetTester) async {
      final tasks = <DownloadTask>[];
      final docDir = (await getApplicationDocumentsDirectory()).path;
      for (int n = 0; n < 3; n++) {
        final filename = 'google$n.html';
        final filepath = join(docDir, filename);
        if (File(filepath).existsSync()) {
          File(filepath).deleteSync();
        }
        // only task with n==1 will fail
        tasks.add(n != 1
            ? DownloadTask(url: workingUrl, filename: filename)
            : DownloadTask(url: failingUrl, filename: filename));
      }
      final result = await FileDownloader().downloadBatch(tasks);
      // confirm results contain two successes and one failure
      expect(result.numSucceeded, equals(2));
      expect(result.numFailed, equals(1));
      final succeeded = result.succeeded;
      expect(succeeded.length, equals(2));
      final succeededFilenames = succeeded.map((e) => e.filename);
      expect(succeededFilenames.contains('google0.html'), isTrue);
      expect(succeededFilenames.contains('google1.html'), isFalse);
      expect(succeededFilenames.contains('google2.html'), isTrue);
      final failed = result.failed;
      expect(failed.length, equals(1));
      final failedFilenames = failed.map((e) => e.filename);
      expect(failedFilenames.contains('google0.html'), isFalse);
      expect(failedFilenames.contains('google1.html'), isTrue);
      expect(failedFilenames.contains('google2.html'), isFalse);
      // confirm files exist
      expect(File(join(docDir, 'google0.html')).existsSync(), isTrue);
      expect(File(join(docDir, 'google1.html')).existsSync(), isFalse);
      expect(File(join(docDir, 'google2.html')).existsSync(), isTrue);
      // cleanup
      for (int n = 0; n < 3; n++) {
        final filename = 'google$n.html';
        final filepath = join(docDir, filename);
        if (File(filepath).existsSync()) {
          File(filepath).deleteSync();
        }
      }
      print('Finished batch download');
    });

    testWidgets('batch download with batch callback', (widgetTester) async {
      final tasks = <DownloadTask>[];
      final docDir = (await getApplicationDocumentsDirectory()).path;
      for (int n = 0; n < 3; n++) {
        final filename = 'google$n.html';
        final filepath = join(docDir, filename);
        if (File(filepath).existsSync()) {
          File(filepath).deleteSync();
        }
        // only task with n==1 will fail
        tasks.add(n != 1
            ? DownloadTask(url: workingUrl, filename: filename)
            : DownloadTask(url: failingUrl, filename: filename));
      }
      var numSucceeded = 0;
      var numFailed = 0;
      var numCalled = 0;
      await FileDownloader().downloadBatch(tasks,
          batchProgressCallback: (succeeded, failed) {
        print('Succeeded: $succeeded, failed: $failed');
        numCalled++;
        numSucceeded = succeeded;
        numFailed = failed;
      });
      expect(numCalled, equals(4)); // also called with 0, 0 at start
      expect(numSucceeded, equals(2));
      expect(numFailed, equals(1));

      // cleanup
      for (int n = 0; n < 3; n++) {
        final filename = 'google$n.html';
        final filepath = join(docDir, filename);
        if (File(filepath).existsSync()) {
          File(filepath).deleteSync();
        }
      }
      print('Finished batch download with callback');
    });

    testWidgets('batch download with task callback', (widgetTester) async {
      final failTask =
          DownloadTask(url: failingUrl, filename: defaultFilename, retries: 2);
      final task3 = task.copyWith(taskId: 'task3');
      final result = await FileDownloader().downloadBatch(
          [task, failTask, task3],
          taskStatusCallback: statusCallback,
          taskProgressCallback: progressCallback);
      expect(result.numSucceeded, equals(2));
      expect(result.numFailed, equals(1));
      expect(result.failed.first.taskId, equals(failTask.taskId));
      expect(statusCallbackCounter,
          equals(15)); // 3 attempts + 2 retry attempts, each 3
      expect(progressCallbackCounter, greaterThanOrEqualTo(10));
    });

    testWidgets('convenience download with callbacks', (widgetTester) async {
      var result = await FileDownloader()
          .download(task, onStatus: (status) => statusCallback(task, status));
      expect(result, equals(TaskStatus.complete));
      expect(statusCallbackCounter, equals(3));
      expect(progressCallbackCompleter.isCompleted, isFalse);
      expect(progressCallbackCounter, equals(0));
      // reset for round two with progress callback
      statusCallbackCounter = 0;
      progressCallbackCounter = 0;
      statusCallbackCompleter = Completer<void>();
      progressCallbackCompleter = Completer<void>();
      task = DownloadTask(url: urlWithContentLength, filename: defaultFilename);
      result = await FileDownloader().download(task,
          onStatus: (status) => statusCallback(task, status),
          onProgress: (progress) => progressCallback(task, progress));
      expect(result, equals(TaskStatus.complete));
      expect(statusCallbackCounter, equals(3));
      expect(progressCallbackCounter, greaterThan(1));
      expect(lastProgress, equals(1.0));
      print('Finished convenience download with callbacks');
    });

    testWidgets('parallel convenience downloads with callbacks',
        (widgetTester) async {
      var a = 0, b = 0, c = 0;
      var p1 = 0.0, p2 = 0.0, p3 = 0.0;
      final failTask =
          DownloadTask(url: failingUrl, filename: defaultFilename, retries: 2);
      var failingResult = FileDownloader().download(failTask,
          onStatus: (status) => a++, onProgress: (progress) => p1 += progress);
      var successResult = FileDownloader().download(task,
          onStatus: (status) => b++, onProgress: (progress) => p2 += progress);
      var successResult2 = FileDownloader().download(
          task.copyWith(taskId: 'second'),
          onStatus: (status) => c++,
          onProgress: (progress) => p3 += progress);
      await Future.wait([failingResult, successResult, successResult2]);
      expect(a, equals(9));
      expect(b, equals(3));
      expect(c, equals(3)); // number of calls to the closure status update
      if (Platform.isAndroid) {
        // sum of calls to the closure progress update
        expect(p1, equals(-9.0)); // retry [-4] retry [-4] failed [-1]
        expect(p2, equals(1.0)); // complete [1]
        expect(p3, equals(1.0)); // complete [1]
      }
      if (Platform.isIOS) {
        // sum of calls to the closure progress update
        expect(p1, closeTo(-4 - 4 - 1 + 3 * 0.999, 0.1)); // retry [-4] retry
        // [-4] failed [-1]
        // + 3 * 0.999
        expect(p2, closeTo(1.0, 0.1)); // complete [1]
        expect(p3, closeTo(1.0, 0.1)); // complete [1]
      }
      successResult.then((value) => expect(value, equals(TaskStatus.complete)));
      successResult2
          .then((value) => expect(value, equals(TaskStatus.complete)));
      failingResult.then((value) => expect(value, equals(TaskStatus.failed)));
      print('Finished parallel convenience downloads with callbacks');
    });

    testWidgets('simple parallel convenience downloads with callbacks',
        (widgetTester) async {
      final failTask =
          DownloadTask(url: failingUrl, filename: defaultFilename, retries: 2);
      var failingResult = FileDownloader().download(failTask,
          onStatus: (status) => statusCallback(failTask, status));
      var successResult = FileDownloader()
          .download(task, onStatus: (status) => statusCallback(task, status));
      await Future.wait([successResult, failingResult]);
      successResult.then((value) => expect(value, equals(TaskStatus.complete)));
      failingResult.then((value) => expect(value, equals(TaskStatus.failed)));
      expect(statusCallbackCounter, equals(12));
      print('Finished simple parallel convenience downloads with callbacks');
    });
  });

  group('Retries', () {
    testWidgets('basic retry logic', (widgetTester) async {
      FileDownloader().registerCallbacks(taskStatusCallback: statusCallback);
      expect(retryTask.retriesRemaining, equals(retryTask.retries));
      expect(await FileDownloader().enqueue(retryTask), isTrue);
      await Future.delayed(const Duration(seconds: 4));
      final retriedTask = await FileDownloader().taskForId(retryTask.taskId);
      expect(retriedTask, equals(retryTask));
      if (retriedTask != null) {
        expect(retriedTask.retriesRemaining, lessThan(retriedTask.retries));
      }
      await statusCallbackCompleter.future;
      expect(lastStatus, equals(TaskStatus.failed));
      // enqueued, running, waitingToRetry/failed for each try
      expect(statusCallbackCounter, equals((retryTask.retries + 1) * 3));
    });

    testWidgets('basic with progress updates', (widgetTester) async {
      FileDownloader().registerCallbacks(
          taskStatusCallback: statusCallback,
          taskProgressCallback: progressCallback);
      final retryTaskWithProgress =
          retryTask.copyWith(updates: Updates.statusAndProgress);
      expect(await FileDownloader().enqueue(retryTaskWithProgress), isTrue);
      await Future.delayed(const Duration(seconds: 6));
      expect(lastProgress, equals(progressWaitingToRetry));
      // iOS emits 0.0 & 0.999 progress updates for a 403 response with the
      // text of the response, before sharing the response code, triggering
      // the -4.0 progress response.
      // On other platforms, only 0.0 & -4.0 is emitted
      expect(progressCallbackCounter, equals(Platform.isIOS ? 6 : 4));
      await statusCallbackCompleter.future;
      expect(lastStatus, equals(TaskStatus.failed));
      // wait a sec for the last progress update
      await Future.delayed(const Duration(seconds: 1));
      expect(lastProgress, equals(progressFailed));
    });

    testWidgets('retry with cancellation', (widgetTester) async {
      FileDownloader().registerCallbacks(taskStatusCallback: statusCallback);
      expect(await FileDownloader().enqueue(retryTask), isTrue);
      await Future.delayed(const Duration(seconds: 6));
      final retriedTask = await FileDownloader().taskForId(retryTask.taskId);
      expect(retriedTask, equals(retryTask));
      if (retriedTask != null) {
        expect(retriedTask.retriesRemaining, lessThan(retriedTask.retries));
        expect(await FileDownloader().cancelTasksWithIds([retriedTask.taskId]),
            isTrue);
        await statusCallbackCompleter.future;
        expect(lastStatus, equals(TaskStatus.canceled));
        // 3 callbacks for each try, plus one for cancel
        expect(
            statusCallbackCounter,
            equals(
                (retriedTask.retries - retriedTask.retriesRemaining) * 3 + 1));
      }
      expect(await FileDownloader().taskForId(retryTask.taskId), isNull);
    });

    testWidgets('retry progress updates with cancellation',
        (widgetTester) async {
      FileDownloader().registerCallbacks(
          taskStatusCallback: statusCallback,
          taskProgressCallback: progressCallback);
      final retryTaskWithProgress =
          retryTask.copyWith(updates: Updates.statusAndProgress);
      expect(await FileDownloader().enqueue(retryTaskWithProgress), isTrue);
      expect(progressCallbackCounter, equals(0));
      await Future.delayed(const Duration(seconds: 6));
      expect(lastProgress, equals(progressWaitingToRetry));
      // iOS emits 0.0 & 0.999 progress updates for a 403 response with the
      // text of the response, before sharing the response code, triggering
      // the -4.0 progress response.
      // On other platforms, only 0.0 & -4.0 is emitted
      expect(progressCallbackCounter, equals(Platform.isIOS ? 6 : 4));
      final retriedTask = await FileDownloader().taskForId(retryTask.taskId);
      expect(retriedTask, equals(retryTask));
      if (retriedTask != null) {
        expect(retriedTask.retriesRemaining, lessThan(retriedTask.retries));
        expect(await FileDownloader().cancelTasksWithIds([retriedTask.taskId]),
            isTrue);
        await statusCallbackCompleter.future;
        expect(lastStatus, equals(TaskStatus.canceled));
        await Future.delayed(const Duration(milliseconds: 500));
        expect(lastProgress, equals(progressCanceled));
        expect(await FileDownloader().taskForId(retryTask.taskId), isNull);
      }
    });

    testWidgets('queue management: allTasks with retries',
        (widgetTester) async {
      FileDownloader().registerCallbacks(taskStatusCallback: statusCallback);
      expect(await FileDownloader().enqueue(retryTask), isTrue);
      expect(await FileDownloader().enqueue(task), isTrue);
      final allTasks = await FileDownloader().allTasks();
      expect(allTasks.length, equals(2));
      expect(allTasks.contains(retryTask), isTrue);
      expect(allTasks.contains(task), isTrue);
      final nonRetryTasksBeforeWait =
          await FileDownloader().allTasks(includeTasksWaitingToRetry: false);
      expect(nonRetryTasksBeforeWait.length, equals(2));
      expect(nonRetryTasksBeforeWait.contains(retryTask), isTrue);
      expect(nonRetryTasksBeforeWait.contains(task), isTrue);
      await Future.delayed(const Duration(seconds: 4));
      // after wait the regular task has disappeared
      final nonRetryTasksAfterWait =
          await FileDownloader().allTasks(includeTasksWaitingToRetry: false);
      expect(nonRetryTasksAfterWait.length, equals(0));
      final allTasksAfterWait = await FileDownloader().allTasks();
      expect(allTasksAfterWait.length, equals(1));
      expect(allTasksAfterWait.contains(retryTask), isTrue);
      await FileDownloader().cancelTasksWithIds([retryTask.taskId]);
    });

    testWidgets('queue management: taskForId with retries',
        (widgetTester) async {
      FileDownloader().registerCallbacks(taskStatusCallback: statusCallback);
      expect(await FileDownloader().enqueue(retryTask), isTrue);
      expect(await FileDownloader().enqueue(task), isTrue); // regular task
      expect(await FileDownloader().taskForId(retryTask.taskId),
          equals(retryTask));
      expect(await FileDownloader().taskForId(task.taskId), equals(task));
      await Future.delayed(const Duration(seconds: 4));
      // after wait the regular task has disappeared
      expect(await FileDownloader().taskForId(retryTask.taskId),
          equals(retryTask));
      expect(await FileDownloader().taskForId(task.taskId), isNull);
      await FileDownloader().cancelTasksWithIds([retryTask.taskId]);
    });
  });

  group('DownloadTask with POST request', () {
    testWidgets('post DownloadTask with post is empty body',
        (widgetTester) async {
      final task = DownloadTask(
          url: postTestUrl,
          urlQueryParameters: {'request-type': 'post-empty'},
          filename: postFilename,
          headers: {'Header1': 'headerValue1'},
          post: '');
      final path =
          join((await getApplicationDocumentsDirectory()).path, task.filename);
      expect(
          await FileDownloader().download(task), equals(TaskStatus.complete));
      final result = jsonDecode(await File(path).readAsString());
      print(result);
      expect(result['args']['request-type'], equals('post-empty'));
      expect(result['headers']['Header1'], equals('headerValue1'));
      expect((result['data'] as String).isEmpty, isTrue);
      expect(result['json'], isNull);
    });

    testWidgets('post DownloadTask with post is String', (widgetTester) async {
      final task = DownloadTask(
          url: postTestUrl,
          urlQueryParameters: {'request-type': 'post-String'},
          filename: postFilename,
          headers: {'content-type': 'text/plain'},
          post: 'testPost');
      final path =
          join((await getApplicationDocumentsDirectory()).path, task.filename);
      expect(
          await FileDownloader().download(task), equals(TaskStatus.complete));
      final result = jsonDecode(await File(path).readAsString());
      print(result);
      expect(result['args']['request-type'], equals('post-String'));
      // note: Content-Type may include charset= on some platforms
      expect(result['headers']['Content-Type'], contains('text/plain'));
      expect(result['data'], equals('testPost'));
      expect(result['json'], isNull);
    });

    testWidgets('post DownloadTask with post is Uint8List',
        (widgetTester) async {
      final task = DownloadTask(
          url: postTestUrl,
          urlQueryParameters: {'request-type': 'post-Uint8List'},
          filename: postFilename,
          headers: {'Content-Type': 'application/octet-stream'},
          post: Uint8List.fromList('testPost'.codeUnits));
      final path =
          join((await getApplicationDocumentsDirectory()).path, task.filename);
      expect(
          await FileDownloader().download(task), equals(TaskStatus.complete));
      final result = jsonDecode(await File(path).readAsString());
      print(result);
      expect(result['args']['request-type'], equals('post-Uint8List'));
      // note: Content-Type may include charset= on some platforms
      expect(result['headers']['Content-Type'],
          contains('application/octet-stream'));
      expect(result['data'], equals('testPost'));
      expect(result['json'], isNull);
    });

    testWidgets('post DownloadTask with post is JsonString',
        (widgetTester) async {
      final task = DownloadTask(
          url: postTestUrl,
          urlQueryParameters: {'request-type': 'post-json'},
          filename: postFilename,
          headers: {
            'Header1': 'headerValue1',
            'content-type': 'application/json'
          },
          post: '{"field1": 1}');
      final path =
          join((await getApplicationDocumentsDirectory()).path, task.filename);
      expect(
          await FileDownloader().download(task), equals(TaskStatus.complete));
      final result = jsonDecode(await File(path).readAsString());
      print(result);
      expect(result['args']['request-type'], equals('post-json'));
      expect(result['headers']['Header1'], equals('headerValue1'));
      expect(result['data'], equals('{"field1": 1}'));
      // confirm the server side interpreted this as JSON
      expect(result['json'], equals({'field1': 1}));
    });

    testWidgets('post DownloadTask with post is invalid type',
        (widgetTester) async {
      expect(
          () => DownloadTask(
              url: postTestUrl,
              urlQueryParameters: {'request-type': 'invalid'},
              filename: postFilename,
              headers: {'Header1': 'headerValue1'},
              post: {'invalid': 'map'}),
          throwsA(isA<TypeError>()));
    });
  });

  group('Request', () {
    testWidgets('get request', (widgetTester) async {
      final request = Request(
          url: getTestUrl,
          urlQueryParameters: {'json': 'true', 'request-type': 'get%20it'},
          headers: {'Header1': 'headerValue1'});
      // note: json=true required to get results as JSON string
      final response = await FileDownloader().request(request);
      expect(response.statusCode, equals(200));
      final result = jsonDecode(response.body);
      expect(result['args']['json'], equals('true'));
      expect(result['args']['request-type'], equals('get it'));
      expect(result['headers']['Header1'], equals('headerValue1'));
    });

    testWidgets('post request with post is empty body', (widgetTester) async {
      final request = Request(
          url: postTestUrl,
          urlQueryParameters: {'request-type': 'post-empty'},
          headers: {'Header1': 'headerValue1'},
          post: '');
      final response = await FileDownloader().request(request);
      expect(response.statusCode, equals(200));
      final result = jsonDecode(response.body);
      expect(result['args']['request-type'], equals('post-empty'));
      expect(result['headers']['Header1'], equals('headerValue1'));
      expect((result['data'] as String).isEmpty, isTrue);
      expect(result['json'], isNull);
    });

    testWidgets('post request with post is String', (widgetTester) async {
      final request = Request(
          url: postTestUrl,
          urlQueryParameters: {'request-type': 'post-String'},
          headers: {'Header1': 'headerValue1'},
          post: 'testPost');
      final response = await FileDownloader().request(request);
      expect(response.statusCode, equals(200));
      final result = jsonDecode(response.body);
      expect(result['args']['request-type'], equals('post-String'));
      expect(result['headers']['Header1'], equals('headerValue1'));
      expect(result['data'], equals('testPost'));
      expect(result['json'], isNull);
    });

    testWidgets('post request with post is Uint8List', (widgetTester) async {
      final request = Request(
          url: postTestUrl,
          urlQueryParameters: {'request-type': 'post-Uint8List'},
          headers: {'Header1': 'headerValue1'},
          post: Uint8List.fromList('testPost'.codeUnits));
      final response = await FileDownloader().request(request);
      expect(response.statusCode, equals(200));
      final result = jsonDecode(response.body);
      expect(result['args']['request-type'], equals('post-Uint8List'));
      expect(result['headers']['Header1'], equals('headerValue1'));
      expect(result['data'], equals('testPost'));
      expect(result['json'], isNull);
    });

    testWidgets('post request with post is JsonString', (widgetTester) async {
      final request = Request(
          url: postTestUrl,
          urlQueryParameters: {'request-type': 'post-json'},
          headers: {
            'Header1': 'headerValue1',
            'content-type': 'application/json'
          },
          post: '{"field1": 1}');
      final response = await FileDownloader().request(request);
      expect(response.statusCode, equals(200));
      final result = jsonDecode(response.body);
      expect(result['args']['request-type'], equals('post-json'));
      expect(result['headers']['Header1'], equals('headerValue1'));
      expect(result['data'], equals('{"field1": 1}'));
      // confirm the server side interpreted this as JSON
      expect(result['json'], equals({'field1': 1}));
    });

    testWidgets('post request with post is invalid type', (widgetTester) async {
      expect(
          () => Request(
              url: postTestUrl,
              urlQueryParameters: {'request-type': 'invalid'},
              headers: {'Header1': 'headerValue1'},
              post: {'invalid': 'map'}),
          throwsA(isA<TypeError>()));
    });

    testWidgets('get request with server error, no retries',
        (widgetTester) async {
      final request = Request(url: failingUrl);
      final response = await FileDownloader().request(request);
      expect(response.statusCode, equals(403));
      expect(response.reasonPhrase, equals('Forbidden'));
    });

    testWidgets('get request with server error, with retries',
        (widgetTester) async {
      // There is no easy way to confirm the retries are happening, because the
      // Request object is modified within the Isolate and not passed back to
      // the main isolate. We therefore observe the three retries by
      // examining the server logs
      final request = Request(url: failingUrl, retries: 3);
      final response = await FileDownloader().request(request);
      expect(response.statusCode, equals(403));
      expect(response.reasonPhrase, equals('Forbidden'));
    });

    testWidgets('get request with malformed url error, no retries',
        (widgetTester) async {
      final request = Request(url: 'somethingRandom');
      final response = await FileDownloader().request(request);
      expect(response.statusCode, equals(499));
      expect(
          response.reasonPhrase,
          equals(
              'Invalid argument(s): No host specified in URI somethingRandom'));
    });
  });

  group('Basic upload', () {
    testWidgets('enqueue multipart file', (widgetTester) async {
      FileDownloader().registerCallbacks(
          taskStatusCallback: statusCallback,
          taskProgressCallback: progressCallback);
      expect(
          await FileDownloader()
              .enqueue(uploadTask.copyWith(updates: Updates.statusAndProgress)),
          isTrue);
      await statusCallbackCompleter.future;
      expect(statusCallbackCounter, equals(3));
      expect(lastStatus, equals(TaskStatus.complete));
      expect(progressCallbackCounter, greaterThan(1));
      expect(lastProgress, equals(progressComplete));
      print('Finished enqueue multipart file');
    });

    testWidgets('enqueue w/o file', (widgetTester) async {
      FileDownloader().registerCallbacks(
          taskStatusCallback: statusCallback,
          taskProgressCallback: progressCallback);
      // try the binary upload to a multipart endpoint
      final failingUploadTask = uploadTask.copyWith(
          post: 'binary', updates: Updates.statusAndProgress);
      expect(await FileDownloader().enqueue(failingUploadTask), isTrue);
      await statusCallbackCompleter.future;
      expect(statusCallbackCounter, equals(3));
      expect(lastStatus, equals(TaskStatus.notFound));
      expect(progressCallbackCounter, greaterThan(1));
      expect(lastProgress, equals(progressNotFound));
      print('Finished enqueue w/o file');
    });

    testWidgets('enqueue binary file', (widgetTester) async {
      FileDownloader().registerCallbacks(
          taskStatusCallback: statusCallback,
          taskProgressCallback: progressCallback);
      final task = uploadTask.copyWith(
          url: uploadBinaryTestUrl,
          post: 'binary',
          updates: Updates.statusAndProgress);
      expect(await FileDownloader().enqueue(task), isTrue);
      await statusCallbackCompleter.future;
      expect(statusCallbackCounter, equals(3));
      expect(lastStatus, equals(TaskStatus.complete));
      expect(progressCallbackCounter, greaterThan(1));
      expect(lastProgress, equals(progressComplete));
      print('Finished enqueue binary file');
    });

    testWidgets('enqueue multipart with fields', (widgetTester) async {
      FileDownloader().registerCallbacks(
          taskStatusCallback: statusCallback,
          taskProgressCallback: progressCallback);
      expect(
          await FileDownloader().enqueue(uploadTask.copyWith(
              fields: {'field1': 'value1', 'field2': 'check\u2713'},
              updates: Updates.statusAndProgress)),
          isTrue);
      await statusCallbackCompleter.future;
      expect(statusCallbackCounter, equals(3));
      expect(lastStatus, equals(TaskStatus.complete));
      expect(progressCallbackCounter, greaterThan(1));
      expect(lastProgress, equals(progressComplete));
      print('Finished enqueue multipart with fields');
    });

    testWidgets('upload task creation with errors', (widgetTester) async {
      expect(
          () => UploadTask(
              url: uploadTestUrl,
              filename: defaultFilename,
              fields: {'name': 'value'},
              post: 'binary'),
          throwsAssertionError);
    });
  });

  group('Convenience uploads', () {
    testWidgets('upload with await', (widgetTester) async {
      final status = await FileDownloader().upload(uploadTask);
      expect(status, equals(TaskStatus.complete));
    });

    testWidgets('multiple upload with futures', (widgetTester) async {
      final secondTask = uploadTask.copyWith(taskId: 'secondTask');
      // note that using a Future (without await) is unusual and is done here
      // just for testing.  Normal use would be
      // var result = await FileDownloader().upload(task);
      final taskFuture = FileDownloader().upload(uploadTask);
      final secondTaskFuture = FileDownloader().upload(secondTask);
      var statuses = await Future.wait([taskFuture, secondTaskFuture]);
      for (var status in statuses) {
        expect(status, equals(TaskStatus.complete));
      }
    });

    testWidgets('batch upload', (widgetTester) async {
      final failingUploadTask =
          uploadTask.copyWith(taskId: 'fails', post: 'binary');
      final tasks = <UploadTask>[
        uploadTask,
        failingUploadTask,
        uploadTask.copyWith(taskId: 'third')
      ];
      final result = await FileDownloader().uploadBatch(tasks);
      // confirm results contain two successes and one failure
      expect(result.numSucceeded, equals(2));
      expect(result.numFailed, equals(1));
      final succeeded = result.succeeded;
      expect(succeeded.length, equals(2));
      final succeededTaskIds = succeeded.map((e) => e.taskId);
      expect(succeededTaskIds.contains(tasks[0].taskId), isTrue);
      expect(succeededTaskIds.contains(tasks[1].taskId), isFalse);
      expect(succeededTaskIds.contains(tasks[2].taskId), isTrue);
      final failed = result.failed;
      expect(failed.length, equals(1));
      final failedTaskIds = failed.map((e) => e.taskId);
      expect(failedTaskIds.contains(tasks[0].taskId), isFalse);
      expect(failedTaskIds.contains(tasks[1].taskId), isTrue);
      expect(failedTaskIds.contains(tasks[2].taskId), isFalse);
      print('Finished batch upload');
    });

    testWidgets('batch upload with callback', (widgetTester) async {
      final failingUploadTask =
          uploadTask.copyWith(taskId: 'fails', post: 'binary');
      final tasks = <UploadTask>[
        uploadTask,
        failingUploadTask,
        uploadTask.copyWith(taskId: 'third')
      ];
      var numSucceeded = 0;
      var numFailed = 0;
      var numCalled = 0;
      await FileDownloader().uploadBatch(tasks,
          batchProgressCallback: (succeeded, failed) {
        print('Succeeded: $succeeded, failed: $failed');
        numCalled++;
        numSucceeded = succeeded;
        numFailed = failed;
      });
      expect(numCalled, equals(4)); // also called with 0, 0 at start
      expect(numSucceeded, equals(2));
      expect(numFailed, equals(1));
      print('Finished batch upload with callback');
    });

    testWidgets('convenience upload with callbacks', (widgetTester) async {
      var result = await FileDownloader().upload(uploadTask,
          onStatus: (status) => statusCallback(uploadTask, status));
      expect(result, equals(TaskStatus.complete));
      expect(statusCallbackCounter, equals(3));
      expect(progressCallbackCompleter.isCompleted, isFalse);
      expect(progressCallbackCounter, equals(0));
      // reset for round two with progress callback
      statusCallbackCounter = 0;
      progressCallbackCounter = 0;
      statusCallbackCompleter = Completer<void>();
      progressCallbackCompleter = Completer<void>();
      final task2 = uploadTask.copyWith(taskId: 'second');
      result = await FileDownloader().upload(task2,
          onStatus: (status) => statusCallback(task2, status),
          onProgress: (progress) => progressCallback(task2, progress));
      expect(result, equals(TaskStatus.complete));
      expect(statusCallbackCounter, equals(3));
      expect(progressCallbackCounter, greaterThan(1));
      expect(lastProgress, equals(1.0));
      print('Finished convenience upload with callbacks');
    });
  });

  group('Cancellation', () {
    testWidgets('cancel enqueued tasks', (widgetTester) async {
      var cancelCounter = 0;
      var completeCounter = 0;
      FileDownloader().registerCallbacks(taskStatusCallback: (task, status) {
        if (status == TaskStatus.canceled) {
          cancelCounter++;
        }
        if (status == TaskStatus.complete) {
          completeCounter++;
        }
      });
      final tasks = <DownloadTask>[];
      for (var n = 1; n < 20; n++) {
        tasks.add(DownloadTask(url: urlWithContentLength));
      }
      for (var task in tasks) {
        expect(await FileDownloader().enqueue(task), equals(true));
        if (task == tasks.first) {
          await Future.delayed(const Duration(seconds: 1));
        }
      }
      await Future.delayed(const Duration(seconds: 1));
      expect(
          await FileDownloader()
              .cancelTasksWithIds(await FileDownloader().allTaskIds()),
          equals(true));
      await Future.delayed(const Duration(seconds: 2));
      expect(cancelCounter + completeCounter, equals(tasks.length));
      final docsDir = await getApplicationDocumentsDirectory();
      for (var task in tasks) {
        final file = File(join(docsDir.path, task.filename));
        if (file.existsSync()) {
          file.deleteSync();
        }
      }
    });

    /// If a task fails immediately, eg due to a malformed url, it
    /// must still be cancellable. This test cancels a failing task
    /// immediately after enqueueing it, and should succeed in doing so
    testWidgets('immediately cancel a task that fails immediately',
        (widgetTester) async {
      FileDownloader().registerCallbacks(taskStatusCallback: statusCallback);
      final task = DownloadTask(url: 'file://doesNotExist', filename: 'test');
      if (Platform.isAndroid) {
        // on Android, enqueue fails immediately
        expect(await FileDownloader().enqueue(task), equals(false));
      } else {
        expect(await FileDownloader().enqueue(task), equals(true));
        expect(
            await FileDownloader().cancelTaskWithId(task.taskId), equals(true));
        await statusCallbackCompleter.future;
        if (Platform.isIOS) {
          // canot avoid fail on iOS
          expect(lastStatus, equals(TaskStatus.failed));
        } else {
          expect(lastStatus, equals(TaskStatus.canceled));
        }
      }
    });
  });

  group('Tracking', () {
    testWidgets('activate tracking', (widgetTester) async {
      await FileDownloader().database.deleteAllRecords();
      await FileDownloader()
          .registerCallbacks(
              taskStatusCallback: statusCallback,
              taskProgressCallback: progressCallback)
          .trackTasks(markDownloadedComplete: false);
      task = DownloadTask(
          url: urlWithContentLength,
          filename: defaultFilename,
          updates: Updates.statusAndProgress);
      expect(await FileDownloader().enqueue(task), equals(true));
      await someProgressCompleter.future;
      // after some progress, expect status running and some progress in database
      final record = await FileDownloader().database.recordForId(task.taskId);
      expect(record, isNotNull);
      expect(record?.taskId, equals(task.taskId));
      expect(record?.taskStatus, equals(TaskStatus.running));
      expect(record?.progress, greaterThan(0));
      expect(record?.progress, equals(lastProgress));
      expect(record?.error, isNull);
      await statusCallbackCompleter.future;
      // completed
      final record2 = await FileDownloader().database.recordForId(task.taskId);
      expect(record2, isNotNull);
      expect(record2?.taskId, equals(task.taskId));
      expect(record2?.taskStatus, equals(TaskStatus.complete));
      expect(record2?.progress, equals(progressComplete));
      expect(record2?.error, isNull);
      final records = await FileDownloader().database.allRecords();
      expect(records.length, equals(1));
      expect(records.first, equals(record2));
    });

    testWidgets('set, get and delete record', (widgetTester) async {
      await FileDownloader().database.deleteAllRecords();
      await FileDownloader()
          .registerCallbacks(taskStatusCallback: statusCallback)
          .trackTasks();
      task = DownloadTask(url: workingUrl, filename: defaultFilename);
      expect(await FileDownloader().enqueue(task), equals(true));
      await statusCallbackCompleter.future;
      final record = await FileDownloader().database.recordForId(task.taskId);
      expect(record?.task.taskId, equals(task.taskId));
      final firsTaskId = task.taskId;
      // task with url as id
      statusCallbackCompleter = Completer();
      task = DownloadTask(
          taskId: workingUrl, url: workingUrl, filename: defaultFilename);
      expect(await FileDownloader().enqueue(task), equals(true));
      await statusCallbackCompleter.future;
      final record2 = await FileDownloader().database.recordForId(task.taskId);
      expect(record2?.task.taskId, equals(task.taskId));
      final records = await FileDownloader().database.allRecords();
      expect(records.length, equals(2));
      await FileDownloader().database.deleteRecordWithId(task.taskId);
      final records2 = await FileDownloader().database.allRecords();
      expect(records2.length, equals(1));
      expect(records2.first.taskId, equals(firsTaskId));
    });

    testWidgets('allRecords', (widgetTester) async {
      await FileDownloader().database.deleteAllRecords();
      await FileDownloader()
          .registerCallbacks(taskStatusCallback: statusCallback)
          .trackTasks();
      task = DownloadTask(
          taskId: workingUrl, // contains illegal characters
          url: workingUrl,
          filename: defaultFilename);
      expect(await FileDownloader().enqueue(task), equals(true));
      await statusCallbackCompleter.future;
      final records = await FileDownloader().database.allRecords();
      expect(records.length, equals(1));
      expect(records.first.taskId, equals(task.taskId));
      expect(records.first.taskStatus, equals(TaskStatus.complete));
      expect(records.first.progress, equals(progressComplete));
    });

    testWidgets('markDownloadedComplete', (widgetTester) async {
      await FileDownloader().database.deleteAllRecords();
      await FileDownloader()
          .registerCallbacks(
              taskStatusCallback: statusCallback,
              taskProgressCallback: progressCallback)
          .trackTasks(markDownloadedComplete: false);
      final filePath = await task.filePath();
      if (File(filePath).existsSync()) {
        File(filePath).deleteSync();
      }
      // start a download, then cancel
      task = DownloadTask(
          url: urlWithContentLength,
          filename: defaultFilename,
          updates: Updates.statusAndProgress);
      expect(await FileDownloader().enqueue(task), equals(true));
      await someProgressCompleter.future;
      await FileDownloader().cancelTasksWithIds([task.taskId]);
      await Future.delayed(const Duration(milliseconds: 500));
      final record = await FileDownloader().database.recordForId(task.taskId);
      expect(record?.taskStatus, equals(TaskStatus.canceled));
      expect(File(filePath).existsSync(), isFalse);
      // reactivate tracking, this time with markDownloadedComplete = true
      await FileDownloader().trackTasks();
      // because no file, status does not change
      final record2 = await FileDownloader().database.recordForId(task.taskId);
      expect(record2?.taskStatus, equals(TaskStatus.canceled));
      expect(record2?.progress, equals(record?.progress));
      // create a 'downloaded' file (even though the task was canceled)
      await File(filePath).writeAsString('test');
      // reactivate tracking, again with markDownloadedComplete = true
      await FileDownloader().trackTasks();
      // status and progress should now reflect 'complete'
      final record3 = await FileDownloader().database.recordForId(task.taskId);
      expect(record3?.taskStatus, equals(TaskStatus.complete));
      expect(record3?.progress, equals(progressComplete));
      print('Finished markDownloadedComplete');
    });

    testWidgets('track with error', (widgetTester) async {
      await FileDownloader().database.deleteAllRecords();
      await FileDownloader()
          .registerCallbacks(
              taskStatusCallback: statusCallback,
              taskProgressCallback: progressCallback)
          .trackTasks(markDownloadedComplete: false);
      task = DownloadTask(
          url: failingUrl,
          filename: defaultFilename,
          updates: Updates.statusAndProgress);
      expect(await FileDownloader().enqueue(task), equals(true));
      await statusCallbackCompleter.future;
      expect(lastStatus, equals(TaskStatus.failed));
      // failed
      final record = await FileDownloader().database.recordForId(task.taskId);
      expect(record, isNotNull);
      expect(record?.taskId, equals(task.taskId));
      expect(record?.taskStatus, equals(TaskStatus.failed));
      expect(record?.progress, equals(progressFailed));
      expect(record?.error, isNotNull);
      final error = (record?.error)!;
      expect(error.type, equals(ErrorType.httpResponse));
      expect(error.httpResponseCode, equals(403));
      expect(error.description.toLowerCase(), equals('forbidden'));
      final records = await FileDownloader().database.allRecords();
      expect(records.length, equals(1));
    });
  });

  group('Pause and resume', () {
    testWidgets('taskCanResume', (tester) async {
      FileDownloader().registerCallbacks(
          taskStatusCallback: statusCallback,
          taskProgressCallback: progressCallback);
      task = DownloadTask(
          url: urlWithContentLength,
          filename: defaultFilename,
          updates: Updates.statusAndProgress,
          allowPause: true);
      expect(await FileDownloader().enqueue(task), equals(true));
      await someProgressCompleter.future;
      final canResume = await FileDownloader().taskCanResume(task);
      expect(canResume, isTrue);
      expect(await FileDownloader().cancelTasksWithIds([task.taskId]), isTrue);
      // now don't set 'allowPause'
      statusCallbackCompleter = Completer();
      someProgressCompleter = Completer();
      task = DownloadTask(
          url: urlWithContentLength,
          filename: defaultFilename,
          updates: Updates.statusAndProgress);
      expect(await FileDownloader().enqueue(task), equals(true));
      await someProgressCompleter.future;
      final canResume2 = await FileDownloader().taskCanResume(task);
      expect(canResume2, isFalse); // task allowPause not set
      expect(await FileDownloader().cancelTasksWithIds([task.taskId]), isTrue);
    });

    testWidgets('pause and resume task', (widgetTester) async {
      FileDownloader().registerCallbacks(
          taskStatusCallback: statusCallback,
          taskProgressCallback: progressCallback);
      task = DownloadTask(
          url: urlWithContentLength,
          filename: defaultFilename,
          updates: Updates.statusAndProgress,
          allowPause: true);
      expect(await FileDownloader().enqueue(task), equals(true));
      await someProgressCompleter.future;
      expect(await FileDownloader().pause(task), isTrue);
      await Future.delayed(const Duration(milliseconds: 200));
      expect(lastStatus, equals(TaskStatus.paused));
      // resume
      expect(await FileDownloader().resume(task), isTrue);
      await statusCallbackCompleter.future;
      expect(lastStatus, equals(TaskStatus.complete));
      expect(
          await fileEqualsLargeTestFile(File(await task.filePath())), isTrue);
    });

    testWidgets('pause task that cannot be paused', (widgetTester) async {
      FileDownloader().registerCallbacks(
          taskStatusCallback: statusCallback,
          taskProgressCallback: progressCallback);
      task = DownloadTask(
          url: urlWithContentLength,
          filename: defaultFilename,
          updates: Updates.statusAndProgress,
          allowPause: false);
      expect(await FileDownloader().enqueue(task), equals(true));
      await someProgressCompleter.future;
      final canResume = await FileDownloader().taskCanResume(task);
      expect(canResume, isFalse);
      expect(await FileDownloader().pause(task), isFalse);
      await statusCallbackCompleter.future;
      expect(lastStatus, equals(TaskStatus.complete));
    });

    testWidgets('cancel a paused task', (widgetTester) async {
      FileDownloader().registerCallbacks(
          taskStatusCallback: statusCallback,
          taskProgressCallback: progressCallback);
      task = DownloadTask(
          url: urlWithContentLength,
          filename: defaultFilename,
          updates: Updates.statusAndProgress,
          allowPause: true);
      expect(await FileDownloader().enqueue(task), equals(true));
      await someProgressCompleter.future;
      expect(await FileDownloader().pause(task), isTrue);
      await Future.delayed(const Duration(milliseconds: 200));
      expect(lastStatus, equals(TaskStatus.paused));
      final downloader = FileDownloader().downloaderForTesting;
      expect(downloader.getResumeData(task.taskId), isNotNull);
      final resumeData = await downloader.getResumeData(task.taskId);
      final tempFilePath = resumeData!.data;
      if (!Platform.isIOS) {
        // on iOS we don't have access to the temp file directly
        expect(File(tempFilePath).existsSync(), isTrue);
        expect(File(tempFilePath).lengthSync(),
            equals(resumeData.requiredStartByte));
      }
      expect(await FileDownloader().cancelTasksWithIds([task.taskId]), isTrue);
      await Future.delayed(const Duration(milliseconds: 200));
      expect(lastStatus, equals(TaskStatus.canceled));
      expect(File(tempFilePath).existsSync(), isFalse);
    });

    testWidgets('multiple pause and resume', (widgetTester) async {
      // Note: this test is flaky as it depends on internet connection
      // speed. If the test fails, it is likely because the task completed
      // before the initial pause command, or did not have time for two
      // pause/resume cycles -> shorten interval
      var interval = Platform.isAndroid || Platform.isIOS
          ? const Duration(milliseconds: 1000)
          : const Duration(milliseconds: 2000);
      FileDownloader().registerCallbacks(taskStatusCallback: statusCallback);
      task = DownloadTask(
          url: urlWithContentLength,
          filename: defaultFilename,
          allowPause: true);
      expect(await FileDownloader().enqueue(task), equals(true));
      var result = TaskStatus.enqueued;
      while (result != TaskStatus.complete) {
        await Future.delayed(interval);
        result = lastStatus;
        if (result != TaskStatus.complete) {
          expect(await FileDownloader().pause(task), isTrue);
          while (lastStatus != TaskStatus.paused) {
            await Future.delayed(const Duration(milliseconds: 250));
          }
          expect(await FileDownloader().resume(task), isTrue);
        }
      }
      expect(
          await fileEqualsLargeTestFile(File(await task.filePath())), isTrue);
      expect(statusCallbackCounter, greaterThanOrEqualTo(9)); // min 2 pause
    });

    testWidgets('Pause and resume a convenience download',
        (widgetTester) async {
      task = DownloadTask(
          url: urlWithContentLength,
          filename: defaultFilename,
          allowPause: true);
      // kick off convenience download but do not wait for the result
      unawaited(FileDownloader().download(task,
          onStatus: (status) => statusCallback(task, status),
          onProgress: (progress) => progressCallback(task, progress)));
      await someProgressCompleter.future;
      expect(await FileDownloader().pause(task), equals(true));
      await Future.delayed(const Duration(milliseconds: 250));
      expect(lastStatus, equals(TaskStatus.paused));
      expect(await FileDownloader().resume(task), equals(true));
      await statusCallbackCompleter.future;
      expect(lastStatus, equals(TaskStatus.complete));
      expect(lastProgress, equals(progressComplete));
    });
  });

  group('Persistence', () {
    testWidgets(
        'Local storage for resumeData, statusUpdates and progressUpdates',
        (widgetTester) async {
      if (Platform.isAndroid || Platform.isIOS) {
        final downloader = FileDownloader().downloaderForTesting;
        await downloader.setForceFailPostOnBackgroundChannel(true);
        FileDownloader().registerCallbacks(
            taskStatusCallback: statusCallback,
            taskProgressCallback: progressCallback);
        task = DownloadTask(
            url: urlWithContentLength,
            filename: defaultFilename,
            updates: Updates.statusAndProgress,
            allowPause: true);
        expect(await FileDownloader().enqueue(task), equals(true));
        await someProgressCompleter.future;
        final canResume = await FileDownloader().taskCanResume(task);
        expect(canResume, isTrue);
        expect(await FileDownloader().pause(task), isTrue);
        await Future.delayed(const Duration(milliseconds: 500));
        // clear the stored data
        await downloader.removeResumeData(task.taskId);
        await downloader.removePausedTask(task.taskId);
        await Future.delayed(const Duration(milliseconds: 200));
        expect((await downloader.getResumeData(task.taskId)), isNull);
        expect((await downloader.getPausedTask(task.taskId)), isNull);
        // reset last status and progress, then retrieve 'missing' data
        lastStatus = TaskStatus.enqueued; // must change to paused
        final oldLastProgress = lastProgress;
        lastProgress = -1; // must change to a real value
        await downloader
            .retrieveLocallyStoredData(); // triggers status & prog update
        await Future.delayed(const Duration(milliseconds: 500));
        expect(lastStatus, equals(TaskStatus.paused));
        expect(lastProgress, equals(oldLastProgress));
        expect((await downloader.getResumeData(task.taskId))?.taskId,
            equals(task.taskId));
        expect((await downloader.getPausedTask(task.taskId)), equals(task));
        // confirm all popped data is gone
        final resumeDataMap =
            await downloader.popUndeliveredData(Undelivered.resumeData);
        expect(resumeDataMap.length, equals(0));
        final statusUpdateMap =
            await downloader.popUndeliveredData(Undelivered.statusUpdates);
        expect(statusUpdateMap.length, equals(0));
        final progressUpdateMap =
            await downloader.popUndeliveredData(Undelivered.progressUpdates);
        expect(progressUpdateMap.length, equals(0));
        expect(await FileDownloader().cancelTaskWithId(task.taskId), isTrue);
      }
    });
  });

  group('Notifications', () {
    // NOTE: notifications are difficult to test in an integration test, so
    // passing tests in this group is not sufficient evidence that they
    // are working properly
    testWidgets('NotificationConfig', (widgetTester) async {
      FileDownloader()
          .configureNotification(running: TaskNotification('Title', 'Body'));
      FileDownloader().registerCallbacks(
          taskStatusCallback: statusCallback,
          taskProgressCallback: progressCallback);
      task = DownloadTask(
          url: urlWithContentLength,
          filename: defaultFilename,
          updates: Updates.statusAndProgress,
          allowPause: true);
      expect(await FileDownloader().enqueue(task), equals(true));
      await statusCallbackCompleter.future;
    });

    testWidgets('openFile', (widgetTester) async {
      final result = await FileDownloader().download(task);
      expect(result, equals(TaskStatus.complete));
      var success = await FileDownloader().openFile(task: task);
      if (!Platform.isAndroid) {
        expect(success, isTrue);
        // change to a .txt file
        final filePath = await task.filePath();
        await File(filePath).rename(join(
            dirname(filePath), '${basenameWithoutExtension(filePath)}.txt'));
        task = task.copyWith(filename: 'google.txt');
        success = await FileDownloader().openFile(task: task);
        expect(success, isTrue);
        success =
            await FileDownloader().openFile(filePath: await task.filePath());
        expect(success, isTrue);
        // change to a non-existent file
        task = task.copyWith(filename: 'nonexistentFile.html');
        success = await FileDownloader().openFile(task: task);
        expect(success, isFalse);
        // change to a file without extension
        task = task.copyWith(filename: 'fileWithoutExtension');
        success = await FileDownloader().openFile(task: task);
        expect(success, isFalse);
      } else {
        expect(success, isFalse); // on Android cannot access docsdir
        // change to a .txt file
        final filePath = await task.filePath();
        await File(filePath).rename(join(
            dirname(filePath), '${basenameWithoutExtension(filePath)}.txt'));
        task = task.copyWith(filename: 'google.txt');
        final newFilename = await FileDownloader()
            .moveToSharedStorage(task, SharedStorage.external);
        print(newFilename);
        success = await FileDownloader().openFile(filePath: newFilename);
        expect(success, isTrue);
      }
    });
  });

  group('Shared storage', () {
    test('move task to shared storage', () async {
      var filePath = await task.filePath();
      await FileDownloader().download(task);
      final path = await FileDownloader()
          .moveToSharedStorage(task, SharedStorage.downloads);
      print('Path in downloads is $path');
      expect(path, isNotNull);
      expect(File(filePath).existsSync(), isFalse);
      expect(File(path!).existsSync(), isTrue);
      File(path).deleteSync();
    });

    test('move task to shared storage with directory', () async {
      var filePath = await task.filePath();
      await FileDownloader().download(task);
      final path = await FileDownloader().moveToSharedStorage(
          task, SharedStorage.downloads,
          directory: 'subdirectory');
      print('Path in downloads is $path');
      expect(path, isNotNull);
      expect(File(filePath).existsSync(), isFalse);
      expect(File(path!).existsSync(), isTrue);
      File(path).deleteSync();
      expect(dirname(path).endsWith('subdirectory'), isTrue);
      Directory(dirname(path)).deleteSync();
    });

    test('try to move text file to images -> error', () async {
      // Note: this test will fail on Android API below 30, as that API
      // does not have a problem storing a text file in images
      if (Platform.isAndroid) {
        var filePath = await task.filePath();
        await FileDownloader().download(task);
        final path = await FileDownloader()
            .moveToSharedStorage(task, SharedStorage.images);
        expect(path, isNull);
        expect(File(filePath).existsSync(), isTrue);
      }
    });

    test('move while overriding mime type', () async {
      if (Platform.isAndroid) {
        var filePath = await task.filePath();
        await FileDownloader().download(task);
        final path = await FileDownloader().moveToSharedStorage(
            task, SharedStorage.images,
            mimeType: 'image/jpeg');
        print('Path in downloads is $path');
        expect(path, isNotNull);
        expect(File(filePath).existsSync(), isFalse);
        expect(File(path!).existsSync(), isTrue);
        File(path).deleteSync();
      }
    });

    test('move file to shared storage - all types', () async {
      for (var destination in SharedStorage.values) {
        await FileDownloader().download(task);
        var filePath = await task.filePath();
        expect(File(filePath).existsSync(), isTrue);
        // rename the file extension to accommodate requirement for shared
        // storage (e.g. an .html file cannot be stored in 'images')
        switch (destination) {
          case SharedStorage.images:
            final newFilePath = filePath.replaceFirst('.html', '.jpg');
            await File(filePath).rename(newFilePath);
            filePath = newFilePath;
            break;
          case SharedStorage.video:
            final newFilePath = filePath.replaceFirst('.html', '.mp4');
            await File(filePath).rename(newFilePath);
            filePath = newFilePath;
            break;
          case SharedStorage.audio:
            final newFilePath = filePath.replaceFirst('.html', '.mp3');
            await File(filePath).rename(newFilePath);
            filePath = newFilePath;
            break;
          default:
            break;
        }
        final path = await FileDownloader()
            .moveFileToSharedStorage(filePath, destination);
        print('Path in shared storage for $destination is $path');
        if (Platform.isAndroid ||
            destination == SharedStorage.downloads ||
            (Platform.isIOS &&
                destination != SharedStorage.files &&
                destination != SharedStorage.external)) {
          expect(path, isNotNull);
          expect(File(filePath).existsSync(), isFalse);
          expect(File(path!).existsSync(), isTrue);
          File(path).deleteSync();
        } else {
          // otherwise expect null
          expect(path, isNull);
          File(filePath).deleteSync();
        }
      }
    });
  });

  group('Error details', () {
    testWidgets('httpResponse: 403', (widgetTester) async {
      FileDownloader().registerCallbacks(
          taskStatusCallbackWithError: statusCallbackWithError);
      task = DownloadTask(url: failingUrl, filename: 'test');
      expect(await FileDownloader().enqueue(task), isTrue);
      await statusCallbackCompleter.future;
      final error = lastError!;
      expect(error.type, equals(ErrorType.httpResponse));
      expect(error.httpResponseCode, equals(403));
      expect(error.description.toLowerCase(), equals('forbidden'));
    });

    testWidgets('fileSystem: File to upload does not exist',
        (widgetTester) async {
      if (!Platform.isIOS) {
        FileDownloader().registerCallbacks(
            taskStatusCallbackWithError: statusCallbackWithError);
        uploadTask = uploadTask.copyWith(filename: 'doesNotExist');
        expect(await FileDownloader().enqueue(uploadTask), isTrue);
        await statusCallbackCompleter.future;
        final error = lastError!;
        expect(error.type, equals(ErrorType.fileSystem));
        expect(error.description.startsWith('File to upload does not exist'),
            isTrue);
      }
    });
  });
}

/// Helper: make sure [task] is set as desired, and this will enqueue, wait for
/// complete, and return true if file is at the desired [path]
Future<void> enqueueAndFileExists(String path) async {
  print('enqueueAndFileExists with path $path');
  statusCallbackCounter = 0;
  statusCallbackCompleter = Completer();
  FileDownloader().destroy();
  FileDownloader().registerCallbacks(taskStatusCallback: statusCallback);
  try {
    File(path).deleteSync();
  } on FileSystemException {}
  expect(await FileDownloader().enqueue(task), isTrue);
  await statusCallbackCompleter.future;
  expect(File(path).existsSync(), isTrue);
  print('Found file at $path');
  try {
    File(path).deleteSync();
  } on FileSystemException {}
  // Expect 3 status callbacks: enqueued + running + complete
  expect(statusCallbackCounter, equals(3));
}

/// Returns true if the supplied file equals the large test file
Future<bool> fileEqualsLargeTestFile(File file) async {
  ByteData data = await rootBundle.load("assets/$largeFilename");
  final targetData = data.buffer.asUint8List();
  final fileData = file.readAsBytesSync();
  print('target= ${targetData.length} and file= ${fileData.length}');
  return listEquals(targetData, fileData);
}
