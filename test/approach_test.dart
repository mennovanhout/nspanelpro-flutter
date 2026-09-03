import 'package:flutter_test/flutter_test.dart';
import 'package:nspanel_app/util/proximity.dart';

void main() {
  List<bool> run(ApproachDetector d, Iterable<double> vs) => [for (final v in vs) d.feed(v)];

  test('the screen settling under the sensor is not an approach', () {
    final d = ApproachDetector(delta: 12);
    // the level shifts by 30 while the dashboard fades into a dark photo
    final shifting = [for (var i = 0; i < 20; i++) 147.0 - 30 + i * 1.5];
    final resting = [for (var i = 0; i < 40; i++) 147.0 + (i.isEven ? 2 : -2)];
    expect(run(d, shifting).any((x) => x), isFalse);
    expect(run(d, resting).any((x) => x), isFalse);
    expect(d.resting, closeTo(147, 3));
  });

  test('noise scales with the level: 410 +/- 15 is rest, a real approach is not', () {
    final d = ApproachDetector(delta: 12);
    run(d, List.filled(40, 410.0));
    expect(run(d, [425, 395, 424, 396]).any((x) => x), isFalse, reason: '15 is under 15% of 410');
    expect(run(d, [500, 500]), [false, true], reason: 'two readings in a row far off');
  });

  test('a single spike is not an approach; two readings are', () {
    final d = ApproachDetector(delta: 12);
    run(d, List.filled(40, 58.0));
    expect(run(d, [90, 58, 58]).any((x) => x), isFalse);
    expect(run(d, [90, 91]), [false, true]);
  });

  test('absolute bounds bypass the baseline', () {
    expect(ApproachDetector(delta: 12, below: 20).feed(10), isTrue);
    expect(ApproachDetector(delta: 12, above: 900).feed(950), isTrue);
    expect(ApproachDetector(delta: 12, above: 900).feed(100), isFalse);
  });
}
