import 'strings.dart';

/// Localized copy used by the saved-listing review/sorting flow.
///
/// Kept next to [AppStrings] rather than branching on language inside widgets.
extension ReviewStrings on AppStrings {
  bool get _ru => lang == 'ru';

  String get noCity => _ru ? 'Без города' : 'No city';
  String get chooseCollectionsToReview =>
      _ru ? 'Какие подборки посмотреть?' : 'Which collections do you want to review?';
  String get cancel => _ru ? 'Отмена' : 'Cancel';
  String get start => _ru ? 'Начать' : 'Start';
  String get sortedTitle => _ru ? 'Отсортированные' : 'Sorted';
  String get sortedEmpty => _ru
      ? 'Здесь появятся квартиры после свайпа вправо'
      : 'Apartments sorted with a right swipe will appear here';
  String get presetLabel => _ru ? 'Пресет' : 'Preset';
  String get deleteCollection => _ru ? 'Удалить список' : 'Delete collection';
  String get reviewSelectionTitle => _ru ? 'Просмотр подборки' : 'Review selection';
  String get selectionReviewed => _ru ? 'Подборка просмотрена' : 'Selection reviewed';
  String get swipeReviewHint =>
      _ru ? '← Скрыть   •   Отсортировать →' : '← Hide   •   Sort →';
  String get sortAction => _ru ? 'Отсортировать' : 'Sort';
  String get roomsUnitShort => _ru ? 'комн.' : 'rooms';

  String apartmentsCount(int count) {
    if (!_ru) return '$count ${count == 1 ? 'apartment' : 'apartments'}';
    final mod10 = count.abs() % 10;
    final mod100 = count.abs() % 100;
    final word = mod10 == 1 && mod100 != 11
        ? 'квартира'
        : (mod10 >= 2 && mod10 <= 4 && (mod100 < 12 || mod100 > 14)
            ? 'квартиры'
            : 'квартир');
    return '$count $word';
  }
}
