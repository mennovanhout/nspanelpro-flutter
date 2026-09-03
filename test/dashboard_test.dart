import 'package:flutter_test/flutter_test.dart';
import 'package:nspanel_app/config/dashboard.dart';

void main() {
  test('the README layout: a panel view holding a swipe card of vertical-stacks', () {
    final pages = pagesFromLovelace({
      'views': [
        {
          'type': 'panel',
          'cards': [
            {
              'type': 'custom:simple-swipe-card',
              'cards': [
                {
                  'type': 'vertical-stack',
                  'cards': [
                    {'type': 'custom:nspanel-light-card', 'entity': 'light.a', 'height': 260},
                    {'type': 'custom:nspanel-light-card', 'entity': 'light.b', 'height': 184},
                  ],
                },
                {
                  'type': 'vertical-stack',
                  'cards': [
                    {'type': 'custom:nspanel-cover-card', 'entity': 'cover.a'},
                  ],
                },
                {'type': 'custom:nspanel-clock-card', 'height': 200},
              ],
            },
          ],
        },
      ],
    });
    expect(pages.length, 3);
    expect(pages[0].cards.length, 2);
    expect(pages[1].cards.length, 1);
    expect(pages[2].cards.length, 1);
    expect(cardType(pages[2].cards[0]), 'nspanel-clock-card');
  });

  test('a plain view with no swipe card is one page, stacks flattened', () {
    final pages = pagesFromLovelace({
      'views': [
        {
          'cards': [
            {'type': 'custom:nspanel-sensor-card', 'entity': 'sensor.a'},
            {
              'type': 'vertical-stack',
              'cards': [
                {'type': 'custom:nspanel-sensor-card', 'entity': 'sensor.b'},
                {'type': 'custom:nspanel-sensor-card', 'entity': 'sensor.c'},
              ],
            },
          ],
        },
        {
          'cards': [
            {'type': 'nspanel-button-card', 'entity': 'script.x'},
          ],
        },
      ],
    });
    expect(pages.length, 2);
    expect(pages[0].cards.map((c) => c['entity']), ['sensor.a', 'sensor.b', 'sensor.c']);
  });

  test('sections views contribute their cards', () {
    final pages = pagesFromLovelace({
      'views': [
        {
          'type': 'sections',
          'sections': [
            {
              'cards': [
                {'type': 'custom:nspanel-clock-card'},
              ],
            },
          ],
        },
      ],
    });
    expect(pages.length, 1);
    expect(pages[0].cards.length, 1);
  });

  test('the custom: prefix is optional and cardType strips it', () {
    expect(cardType({'type': 'custom:nspanel-light-card'}), 'nspanel-light-card');
    expect(cardType({'type': 'nspanel-light-card'}), 'nspanel-light-card');
    expect(cardType({}), '');
  });

  test('option helpers read the types YAML actually produces', () {
    final c = <String, dynamic>{'height': 260, 'live': true, 'name': 'Old', 'entities': ['sensor.a', {'entity': 'sensor.b'}]};
    expect(c.numOr('height', 200), 260);
    expect(c.numOr('missing', 200), 200);
    expect(c.boolOr('live', false), isTrue);
    expect(c.titleOr('fallback'), 'Old');
    expect(c.maps('entities').map((m) => m['entity']), ['sensor.a', 'sensor.b']);
  });

  test('a dashboard with no views yields no pages rather than throwing', () {
    expect(pagesFromLovelace({}), isEmpty);
    expect(pagesFromLovelace({'strategy': {'type': 'original-states'}}), isEmpty);
  });
}
