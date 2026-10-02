/// A card config is the same map Lovelace holds - the YAML from the cards
/// repo's README, as JSON. The app renders the `custom:nspanel-*` cards in it
/// natively and leaves everything else alone.
typedef CardConfig = Map<String, dynamic>;

class PanelPage {
  const PanelPage(this.cards);
  final List<CardConfig> cards;
}

/// `custom:nspanel-light-card` -> `nspanel-light-card`.
String cardType(CardConfig c) =>
    (c['type']?.toString() ?? '').replaceFirst(RegExp(r'^custom:'), '');

extension CardOpts on CardConfig {
  double numOr(String key, double d) => (this[key] as num?)?.toDouble() ?? d;
  int intOr(String key, int d) => (this[key] as num?)?.toInt() ?? d;
  bool boolOr(String key, bool d) => this[key] is bool ? this[key] as bool : d;
  String? str(String key) {
    return this[key]?.toString();
  }

  List<dynamic> listOr(String key) =>
      this[key] is List ? this[key] as List : const [];
  List<CardConfig> maps(String key) => listOr(key)
      .map(
        (e) => e is Map
            ? e.cast<String, dynamic>()
            : (e is String ? {'entity': e} : null),
      )
      .whereType<CardConfig>()
      .toList();

  /// `title` wins, `name` is the older spelling, then the entity's own name.
  String titleOr(String fallback) => str('title') ?? str('name') ?? fallback;
}

/// How the pages are shown: the swipe card's own options. `dots` is the
/// nspanel-swipe-card spelling, `show_pagination` simple-swipe-card's; both
/// are honoured so a dashboard moves over by changing one word.
class PagerOptions {
  const PagerOptions({this.dots = true, this.start = 0});
  final bool dots;
  final int start;
}

PagerOptions pagerOptionsFromLovelace(Map<String, dynamic> config) {
  final views = (config['views'] as List?) ?? const [];
  for (final v in views) {
    if (v is! Map) continue;
    for (final c in _cardsOf(v)) {
      if (cardType(c).endsWith('swipe-card') && c['cards'] is List) {
        var dots = true;
        if (c['dots'] is bool) {
          dots = c['dots'] as bool;
        } else if (c['show_pagination'] is bool) {
          dots = c['show_pagination'] as bool;
        }
        final n = (c['cards'] as List).length;
        final start = ((c['start'] as num?)?.toInt() ?? 0).clamp(
          0,
          n > 0 ? n - 1 : 0,
        );
        return PagerOptions(dots: dots, start: start);
      }
    }
  }
  return const PagerOptions();
}

/// Turn a Lovelace dashboard into pages for the panel.
///
/// The layout the cards' README recommends is one panel view holding a swipe
/// card, whose children (usually vertical-stacks) are the pages. That is what
/// this reads first. A view with no swipe card becomes one page of its cards,
/// vertical-stacks flattened into it, so a plain dashboard still renders.
List<PanelPage> pagesFromLovelace(Map<String, dynamic> config) {
  final views = (config['views'] as List?) ?? const [];
  final pages = <PanelPage>[];

  for (final v in views) {
    if (v is! Map) continue;
    final cards = _cardsOf(v);
    CardConfig? swipe;
    for (final c in cards) {
      if (cardType(c).endsWith('swipe-card') && c['cards'] is List) {
        swipe = c;
        break;
      }
    }
    if (swipe != null) {
      for (final child in swipe.maps('cards')) {
        pages.add(PanelPage(_flatten(child)));
      }
    } else if (cards.isNotEmpty) {
      pages.add(PanelPage(cards.expand(_flatten).toList()));
    }
  }
  return pages;
}

List<CardConfig> _cardsOf(Map v) {
  final direct = (v['cards'] as List?) ?? const [];
  if (direct.isNotEmpty) {
    return direct
        .whereType<Map>()
        .map((m) => m.cast<String, dynamic>())
        .toList();
  }
  // sections view: every section's cards, in order
  final sections = (v['sections'] as List?) ?? const [];
  return [
    for (final s in sections.whereType<Map>())
      for (final c in (s['cards'] as List? ?? const []).whereType<Map>())
        c.cast<String, dynamic>(),
  ];
}

/// A page is a vertical stack, so a top-level vertical-stack unwraps into
/// the page - one level only. Stacks nested inside it, and any horizontal
/// stack or grid, stay whole and render as layout (see the registry).
/// The screensaver card is config for the app, not a card, and is dropped.
List<CardConfig> _flatten(CardConfig c) {
  final t = cardType(c);
  if (t == 'nspanel-screensaver') return const [];
  if (t == 'vertical-stack' && c['cards'] is List) {
    return c
        .maps('cards')
        .where((x) => cardType(x) != 'nspanel-screensaver')
        .toList();
  }
  return [c];
}
