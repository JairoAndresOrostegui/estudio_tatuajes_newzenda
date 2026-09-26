import 'dart:convert';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:uuid/uuid.dart';

typedef Json = Map<String, dynamic>;
Json asJson(dynamic v) => Map<String, dynamic>.from(v as Map);
List<Json> asRows(dynamic v) => (v as List? ?? []).map(asJson).toList();

class Api {
  final FirebaseFunctions functions;
  Api({FirebaseFunctions? functions})
    : functions =
          functions ?? FirebaseFunctions.instanceFor(region: 'us-central1');
  final Map<String, String> _pending = {};
  Future<Json> call(String name, [Json? data]) async => asJson(
    jsonDecode(
      jsonEncode((await functions.httpsCallable(name).call(data ?? {})).data),
    ),
  );
  Future<Json> session() => call('findinkSession');
  Future<Json> query(
    String collection, {
    String? cursor,
    Json filters = const {},
  }) => call('findinkQuery', {
    'collection': collection,
    'cursor': ?cursor,
    ...filters,
  });
  Future<List<Json>> lookup(String collection) async {
    final rows = <Json>[];
    String? cursor;
    do {
      final page = await query(collection, cursor: cursor);
      rows.addAll(asRows(page['rows']));
      cursor = page['nextCursor'] as String?;
      if (rows.length >= 2000 && cursor != null) {
        throw StateError(
          'El catálogo supera 2000 registros. Archiva registros inactivos.',
        );
      }
    } while (cursor != null);
    return rows;
  }

  Future<Json> command(String action, Json payload) async {
    if (action == 'createUser') return call('findinkCreateUser', payload);
    final signature = jsonEncode([action, payload]);
    final key = _pending.putIfAbsent(signature, () => const Uuid().v4());
    try {
      final result = await call('findinkCommand', {
        'action': action,
        'payload': payload,
        'idempotencyKey': key,
      });
      _pending.remove(signature);
      return result;
    } on FirebaseFunctionsException catch (e) {
      if (![
        'internal',
        'unavailable',
        'deadline-exceeded',
        'unknown',
      ].contains(e.code)) {
        _pending.remove(signature);
      }
      rethrow;
    }
  }

  Future<Json> report(String from, String to, {String dimension = 'all'}) =>
      call('findinkReport', {'from': from, 'to': to, 'dimension': dimension});
}

String readableError(Object e) => e is FirebaseFunctionsException
    ? e.message ?? 'No se pudo conectar. Reintenta.'
    : e
          .toString()
          .replaceFirst('Exception: ', '')
          .replaceFirst('Bad state: ', '');
