import 'dart:async';
import 'dart:convert';

import 'package:cash_client/api/api_exception.dart';
import 'package:cash_client/collector/collector_api.dart';
import 'package:cash_client/collector/collector_models.dart';
import 'package:cash_client/collector/idempotency.dart';
import 'package:cash_client/common/money.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../support/fakes.dart';

Matcher failsWith(ApiFailure failure) => throwsA(
      isA<ApiException>().having((e) => e.failure, 'failure', failure),
    );

void main() {
  group('fetchMembers', () {
    test('reads names and savings/shares accounts', () async {
      final backend = FakeCollectorBackend.working();

      final members = await backend.api.fetchMembers();

      expect(backend.requests.single.method, 'GET');
      expect(backend.requests.single.url.toString(),
          '$testBaseUrl/api/collector/v1/members');
      expect(members.map((m) => m.name), ['Ama Owusu', 'Yaw Boateng']);
      expect(members.first.paymentTypes,
          [PaymentType.savings, PaymentType.shares]);
      expect(members.first.accountFor(PaymentType.shares)?.accountNumber,
          '3002345678');
      expect(members.last.paymentTypes, [PaymentType.savings]);
    });

    test('skips account types collectors cannot pay into', () async {
      final backend = FakeCollectorBackend(
        (_) => http.Response(
          jsonEncode([
            {
              'memberName': 'Efua Asante',
              'accounts': [
                {'accountNumber': '2000000001', 'accountType': 'CURRENT'},
                {'accountNumber': '1000000001', 'accountType': 'SAVINGS'},
              ],
            },
          ]),
          200,
        ),
      );

      final members = await backend.api.fetchMembers();

      expect(members.single.accounts.single.accountNumber, '1000000001');
    });

    test('a malformed list is an unexpected response', () {
      final backend =
          FakeCollectorBackend((_) => http.Response('{"oops":true}', 200));
      expect(backend.api.fetchMembers(),
          failsWith(ApiFailure.unexpectedResponse));
    });
  });

  group('recordPayment', () {
    test('posts the payment with the amount as an exact decimal', () async {
      final backend = FakeCollectorBackend.working();

      final payment = await backend.api.recordPayment(
        idempotencyKey: 'key-1',
        type: PaymentType.savings,
        accountNumber: '1002345678',
        amount: const Cedis.pesewas(5050),
        description: '  Market day  ',
      );

      final request = backend.paymentRequests.single;
      expect(request.url.toString(), '$testBaseUrl/api/collector/v1/payments');
      expect(request.headers['Content-Type'], startsWith('application/json'));
      // The amount must reach the backend as the literal 50.50, not a float.
      expect(request.body, contains('"amount":50.50'));
      expect(jsonDecode(request.body), {
        'idempotencyKey': 'key-1',
        'type': 'SAVINGS',
        'accountNumber': '1002345678',
        'amount': 50.5,
        'description': 'Market day',
      });
      expect(payment.status, PaymentStatus.pending);
      expect(payment.amount, const Cedis.pesewas(5000));
      expect(payment.correctionWindow, const Duration(minutes: 10));
    });

    test('leaves out an empty note', () async {
      final backend = FakeCollectorBackend.working();

      await backend.api.recordPayment(
        idempotencyKey: 'key-2',
        type: PaymentType.shares,
        accountNumber: '3002345678',
        amount: const Cedis.pesewas(2000),
        description: '   ',
      );

      final body = jsonDecode(backend.paymentRequests.single.body) as Map;
      expect(body.containsKey('description'), isFalse);
      expect(body['type'], 'SHARES');
    });

    test('backend refusals carry their message', () async {
      final backend = FakeCollectorBackend(
        (_) => http.Response(
          errorBody(409, "This member's first deposit must be made at the office"),
          409,
        ),
      );

      try {
        await backend.api.recordPayment(
          idempotencyKey: 'k',
          type: PaymentType.savings,
          accountNumber: '1',
          amount: const Cedis.pesewas(100),
        );
        fail('expected an ApiException');
      } on ApiException catch (e) {
        expect(e.failure, ApiFailure.conflict);
        expect(
          collectorErrorMessage(e, networkMessage: 'offline'),
          "This member's first deposit must be made at the office",
        );
      }
    });

    test('403, 404 and 400 map to their failures', () async {
      for (final (status, failure) in [
        (403, ApiFailure.forbidden),
        (404, ApiFailure.notFound),
        (400, ApiFailure.validation),
      ]) {
        final backend = FakeCollectorBackend(
          (_) => http.Response(errorBody(status, 'No'), status),
        );
        await expectLater(
          backend.api.recordPayment(
            idempotencyKey: 'k',
            type: PaymentType.savings,
            accountNumber: '1',
            amount: const Cedis.pesewas(100),
          ),
          failsWith(failure),
        );
      }
    });

    test('a dropped connection or timeout is a network failure', () async {
      final dropped = CollectorApi(
        baseUrl: testBaseUrl,
        client: MockClient((_) async => throw http.ClientException('reset')),
      );
      final slow = CollectorApi(
        baseUrl: testBaseUrl,
        timeout: const Duration(milliseconds: 10),
        client: MockClient((_) => Completer<http.Response>().future),
      );
      for (final api in [dropped, slow]) {
        await expectLater(api.fetchMembers(), failsWith(ApiFailure.network));
      }
    });
  });

  test('an offline payment carries recordedAt in the backend\'s time',
      () async {
    final backend = FakeCollectorBackend.working();

    await backend.api.recordPayment(
      idempotencyKey: 'k',
      type: PaymentType.savings,
      accountNumber: '1002345678',
      amount: const Cedis.pesewas(100),
      recordedAt: DateTime.utc(2026, 11, 15, 9, 5, 7),
    );

    final body = jsonDecode(backend.paymentRequests.single.body) as Map;
    expect(body['recordedAt'], '2026-11-15T09:05:07');
  });

  test('online payments leave recordedAt out', () async {
    final backend = FakeCollectorBackend.working();
    await backend.api.recordPayment(
      idempotencyKey: 'k',
      type: PaymentType.savings,
      accountNumber: '1',
      amount: const Cedis.pesewas(100),
    );
    final body = jsonDecode(backend.paymentRequests.single.body) as Map;
    expect(body.containsKey('recordedAt'), isFalse);
  });

  test('backend time is Accra time, which is UTC', () {
    // 11:30 at UTC+2 is 09:30 in Accra.
    final elsewhere = DateTime.parse('2026-11-15T11:30:00+02:00');
    expect(backendLocalTime(elsewhere), '2026-11-15T09:30:00');
  });

  test('refusals are the backend turning a payment down, not failures to '
      'reach it', () {
    for (final status in [400, 403, 404, 409, 422]) {
      expect(isRefusal(ApiException.fromResponse(status, '{}')), isTrue,
          reason: '$status');
    }
    for (final error in [
      const ApiException(ApiFailure.network),
      const ApiException(ApiFailure.unauthorized),
      ApiException.fromResponse(500, '{}'),
      ApiException.fromResponse(503, '{}'),
      const ApiException(ApiFailure.unexpectedResponse, statusCode: 200),
      StateError('x'),
    ]) {
      expect(isRefusal(error), isFalse, reason: '$error');
    }
  });

  test('idempotency keys are random version 4 UUIDs', () {
    final keys = {for (var i = 0; i < 200; i++) newIdempotencyKey()};
    expect(keys, hasLength(200));
    final uuid4 = RegExp(
      r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
    );
    expect(keys.every(uuid4.hasMatch), isTrue);
    // Within the backend's 100-character limit.
    expect(keys.first.length, 36);
  });
}
