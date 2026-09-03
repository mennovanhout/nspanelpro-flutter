import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nspanel_app/ui/info_shell.dart';

void main() {
  Widget host(int columns, int count) => MaterialApp(
        home: Center(
          child: SizedBox(
            width: 320, // 3 x 100 + 2 gaps of 10
            height: 200,
            child: TileGrid(
              columns: columns,
              stretch: true,
              children: [for (var i = 0; i < count; i++) SizedBox(key: ValueKey(i), height: 40)],
            ),
          ),
        ),
      );

  testWidgets('a partial row is shared by the tiles in it, not padded with gaps', (t) async {
    await t.pumpWidget(host(3, 2));
    // two under columns: 3 -> two half-width tiles: (320 - 10) / 2
    expect(t.getSize(find.byKey(const ValueKey(0))).width, 155);
    expect(t.getSize(find.byKey(const ValueKey(1))).width, 155);

    await t.pumpWidget(host(3, 4));
    // a full row of thirds, then the fourth takes the whole row
    expect(t.getSize(find.byKey(const ValueKey(0))).width, 100);
    expect(t.getSize(find.byKey(const ValueKey(3))).width, 320);
    expect(t.getTopLeft(find.byKey(const ValueKey(3))).dy, greaterThan(t.getTopLeft(find.byKey(const ValueKey(0))).dy));
  });
}
