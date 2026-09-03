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

  List<dynamic> listOr(String key) => this[key] is List ? this[key] as List : const [];
  List<CardConfig> maps(String key) => listOr(key)
      .map((e) => e is Map ? e.cast<String, dynamic>() : (e is String ? {'entity': e} : null))
      .whereType<CardConfig>()
      .toList();

  /// `title` wins, `name` is the older spelling, then the entity's own name.
  String titleOr(String fallback) => str('title') ?? str('name') ?? fallback;
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
  if (direct.isNotEmpty) return direct.whereType<Map>().map((m) => m.cast<String, dynamic>()).toList();
  // sections view: every section's cards, in order
  final sections = (v['sections'] as List?) ?? const [];
  return [
    for (final s in sections.whereType<Map>())
      for (final c in (s['cards'] as List? ?? const []).whereType<Map>()) c.cast<String, dynamic>(),
  ];
}

/// A vertical-stack is a page's worth of cards; anything else is one card.
List<CardConfig> _flatten(CardConfig c) {
  final t = cardType(c);
  if ((t == 'vertical-stack' || t == 'grid') && c['cards'] is List) {
    return c.maps('cards').expand(_flatten).toList();
  }
  return [c];
}
