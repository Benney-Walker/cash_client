import 'package:cash_client/common/money.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Cedis.tryParse', () {
    test('reads cedis and pesewas', () {
      expect(Cedis.tryParse('50'), const Cedis.pesewas(5000));
      expect(Cedis.tryParse('50.'), const Cedis.pesewas(5000));
      expect(Cedis.tryParse('50.5'), const Cedis.pesewas(5050));
      expect(Cedis.tryParse('50.50'), const Cedis.pesewas(5050));
      expect(Cedis.tryParse('0.01'), const Cedis.pesewas(1));
      expect(Cedis.tryParse(' 7.25 '), const Cedis.pesewas(725));
      expect(Cedis.tryParse('999999999.99'), Cedis.max);
    });

    test('refuses anything that is not a 2-decimal amount', () {
      for (final text in [
        '',
        '.',
        '.5',
        '50.505',
        '-5',
        '5,000',
        'abc',
        '1e3',
        '1000000000',
      ]) {
        expect(Cedis.tryParse(text), isNull, reason: text);
      }
    });
  });

  test('formats as GH₵ with grouping and 2 decimals', () {
    expect(Cedis.zero.format(), 'GH₵ 0.00');
    expect(const Cedis.pesewas(5).format(), 'GH₵ 0.05');
    expect(const Cedis.pesewas(5050).format(), 'GH₵ 50.50');
    expect(const Cedis.pesewas(124000).format(), 'GH₵ 1,240.00');
    expect(const Cedis.pesewas(123456789).format(), 'GH₵ 1,234,567.89');
  });

  test('writes the exact decimal for the request body', () {
    expect(const Cedis.pesewas(5050).toDecimalString(), '50.50');
    expect(const Cedis.pesewas(1).toDecimalString(), '0.01');
    expect(Cedis.max.toDecimalString(), '999999999.99');
  });

  test('reads amounts from responses to the nearest pesewa', () {
    expect(Cedis.fromJson(50), const Cedis.pesewas(5000));
    expect(Cedis.fromJson(50.0), const Cedis.pesewas(5000));
    expect(Cedis.fromJson(0.1 + 0.2), const Cedis.pesewas(30));
    expect(Cedis.fromJson('12.30'), const Cedis.pesewas(1230));
    expect(Cedis.fromJson(null), isNull);
    expect(Cedis.fromJson(double.nan), isNull);
  });
}
