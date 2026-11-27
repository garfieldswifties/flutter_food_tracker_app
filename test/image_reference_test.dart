import 'dart:convert';

import 'package:flutter_food_tracker_app/models/food_photo.dart';
import 'package:flutter_food_tracker_app/models/food_tracker.dart';
import 'package:flutter_food_tracker_app/services/supabase_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'support/synthetic_image.dart';

const _origin = 'https://food-test.example.invalid';
const _path = 'foods/11111111-1111-4111-8111-111111111111.png';
const _bucket = SupabaseService.bucket;
const _image = '$_origin/storage/v1/object/public/$_bucket/$_path';
const _alias = '$_image?download=food.png';
const _foreignOrigin =
    'https://other.example.invalid/storage/v1/object/public/$_bucket/$_path';
const _foreignBucket = '$_origin/storage/v1/object/public/other/$_path';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _FakeBackend backend;
  late SupabaseService service;
  setUp(() {
    backend = _FakeBackend();
    final client = SupabaseClient(
      _origin,
      'sb_publishable_mock',
      httpClient: MockClient(backend.respond),
      authOptions: const AuthClientOptions(autoRefreshToken: false),
    );
    addTearDown(client.dispose);
    service = SupabaseService(client, Uri.parse(_origin));
  });

  test(
    'identical URLs reference the same image after deleting one row',
    () async {
      final first = backend.add(1, _image);
      backend.add(2, _image);

      expect((await service.deleteFood(first)).cleanupIssue, isNull);
      expect(backend.removedPaths, isEmpty);
    },
  );

  test(
    'URLs with different query parameters reference the same image',
    () async {
      final first = backend.add(1, '$_image?cacheNonce=first');
      backend.add(2, _alias);

      expect(service.displayImage(_alias), _image);
      expect((await service.deleteFood(first)).cleanupIssue, isNull);
      expect(backend.removedPaths, isEmpty);
    },
  );

  test('deleting the last reference removes the object exactly once', () async {
    final first = backend.add(1, _image);
    final last = backend.add(2, _alias);

    await service.deleteFood(first);
    expect(backend.removedPaths, isEmpty);
    expect((await service.deleteFood(last)).cleanupIssue, isNull);
    expect(backend.removedPaths, [_path]);
  });

  test(
    'replacing a photo preserves the old object used by another row',
    () async {
      final first = backend.add(1, _image);
      final remaining = backend.add(2, _alias);
      final photo = await FoodPhoto.decode(await syntheticPng(0xff99cc33));

      final result = await service.updateFood(first, first.input, photo);

      expect(result.cleanupIssue, isNull);
      expect(result.food.imageUrl, isNot(_image));
      expect(backend.uploadedPaths, hasLength(1));
      expect(backend.removedPaths, isEmpty);
      expect(backend.rows[remaining.id]?['foodImageUrl'], _alias);
    },
  );

  test(
    'a reference query failure retains the file and reports its path',
    () async {
      final first = backend.add(1, _image);
      backend.failReferenceLookup = true;

      final result = await service.deleteFood(first);

      expect(result.cleanupIssue?.objectPath, _path);
      expect(
        result.cleanupIssue?.message,
        contains('ยืนยันการอ้างอิงรูปไม่ได้'),
      );
      expect(backend.removedPaths, isEmpty);
    },
  );

  for (final entry in {
    'outside the project': _foreignOrigin,
    'outside the bucket': _foreignBucket,
    'over HTTP':
        'http://food-test.example.invalid/storage/v1/object/public/$_bucket/$_path',
  }.entries) {
    test('an image ${entry.key} is not used for storage removal', () async {
      final first = backend.add(1, entry.value);

      final result = await service.deleteFood(first);

      expect(result.cleanupIssue?.message, 'URL รูปเดิมนอกขอบเขต');
      expect(result.cleanupIssue?.objectPath, isNull);
      expect(backend.referenceCursors, isEmpty);
      expect(backend.removedPaths, isEmpty);
    });
  }

  test(
    'a short page can precede a reference when the API caps row count',
    () async {
      final first = backend.add(1, _image);
      final unrelated = backend.add(2, _foreignOrigin);
      backend.add(3, _alias);
      backend.referenceRowCap = 1;

      expect((await service.deleteFood(first)).cleanupIssue, isNull);
      expect(backend.referenceCursors, [null, unrelated.id]);
      expect(backend.removedPaths, isEmpty);
    },
  );

  for (final entry in {
    'percent-encoded object name': _image.replaceFirst(
      '11111111',
      '%311111111',
    ),
    'URL fragment': '$_image#preview',
    'encoded prefix, query and fragment':
        '${_image.replaceFirst('/storage/', '/%73torage/').replaceFirst('/foods/', '/%66oods/')}?download=photo.png#preview',
  }.entries) {
    test('protects a later reference with ${entry.key}', () async {
      final first = backend.add(1, _image);
      final unrelated = backend.add(2, _foreignOrigin);
      backend.add(3, entry.value);
      backend.referenceRowCap = 1;

      expect((await service.deleteFood(first)).cleanupIssue, isNull);
      expect(backend.removedPaths, isEmpty);
      expect(backend.referenceCursors, [null, unrelated.id]);
    });
  }

  test(
    'several short nonmatching pages are completed before removing the file',
    () async {
      final first = backend.add(1, _image);
      final otherOrigin = backend.add(2, _foreignOrigin);
      final otherBucket = backend.add(3, _foreignBucket);
      backend.referenceRowCap = 1;

      expect((await service.deleteFood(first)).cleanupIssue, isNull);
      expect(backend.referenceCursors, [null, otherOrigin.id, otherBucket.id]);
      expect(backend.removedPaths, [_path]);
    },
  );

  test('ambiguous same-bucket encoding keeps the object for review', () async {
    final first = backend.add(1, _image);
    backend.add(2, _image.replaceFirst('11111111', '%2531111111'));

    final result = await service.deleteFood(first);
    expect(result.cleanupIssue?.objectPath, _path);
    expect(backend.removedPaths, isEmpty);
  });
}

class _FakeBackend {
  final rows = <String, Map<String, Object?>>{};
  final removedPaths = <String>[];
  final uploadedPaths = <String>[];
  final referenceCursors = <String?>[];
  bool failReferenceLookup = false;
  int referenceRowCap = 100;

  FoodTracker add(int position, String url) {
    final id =
        '00000000-0000-4000-8000-${position.toString().padLeft(12, '0')}';
    final row = <String, Object?>{
      'id': id,
      'created_at': '2026-11-27T00:00:00Z',
      'foodDate': '2026-11-27',
      'foodMeal': 'เช้า',
      'foodName': 'อาหารทดสอบ $position',
      'foodPrice': 15.0,
      'foodPerson': 1,
      'foodImageUrl': url,
    };
    rows[id] = row;
    return FoodTracker.fromJson(row);
  }

  Future<http.Response> respond(http.Request request) async {
    http.Response json(Object data, [int status = 200]) => http.Response(
      jsonEncode(data),
      status,
      headers: {'content-type': 'application/json; charset=utf-8'},
      request: request,
    );

    final url = request.url;
    expect(url.origin, _origin);
    const object = '/storage/v1/object/$_bucket';
    if (url.path == object && request.method == 'DELETE') {
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      final paths = (body['prefixes'] as List).cast<String>();
      removedPaths.addAll(paths);
      return json([
        for (final path in paths) {'name': path},
      ]);
    }
    if (url.path.startsWith('$object/foods/') && request.method == 'POST') {
      expect(request.headers['x-upsert'], 'false');
      final path = url.path.substring(object.length + 1);
      uploadedPaths.add(path);
      return json({'Key': '$_bucket/$path'});
    }
    expect(url.path, '/rest/v1/${SupabaseService.table}');
    final query = url.queryParameters;
    if (request.method == 'GET') {
      expect(query['select'], 'id,foodImageUrl');
      expect(query['order'], startsWith('id.asc'));
      expect(query['foodImageUrl'], 'not.is.null');
      final cursor = query['id']?.substring('gt.'.length);
      if (cursor != null) expect(query['id'], 'gt.$cursor');
      referenceCursors.add(cursor);
      if (failReferenceLookup) {
        return json({'code': '42501', 'message': 'read failed'}, 403);
      }
      final matching =
          rows.entries
              .where(
                (row) =>
                    (cursor == null || row.key.compareTo(cursor) > 0) &&
                    row.value['foodImageUrl'] != null,
              )
              .toList()
            ..sort((left, right) => left.key.compareTo(right.key));
      return json(
        matching.take(referenceRowCap).map((entry) => entry.value).toList(),
      );
    }
    final id = query['id']!.substring('eq.'.length);
    final row = rows[id]!;
    if (request.method == 'DELETE') {
      rows.remove(id);
    } else {
      expect(request.method, 'PATCH');
      row.addAll((jsonDecode(request.body) as Map).cast<String, Object?>());
    }
    return json([row]);
  }
}
