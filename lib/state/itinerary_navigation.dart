import 'package:hooks_riverpod/hooks_riverpod.dart';

final itineraryEditorProvider =
    NotifierProvider<ItineraryEditorNavigation, bool>(
      ItineraryEditorNavigation.new,
    );

class ItineraryEditorNavigation extends Notifier<bool> {
  @override
  bool build() => false;
  void open() => state = true;
  void close() => state = false;
}

/// One-shot request to focus and expand the editor's transport sheet.
/// -1: departure, -2: return, >=0: segment after that sightseeing stop.
final itineraryTransportRequestProvider =
    NotifierProvider<ItineraryTransportRequest, int?>(
      ItineraryTransportRequest.new,
    );

class ItineraryTransportRequest extends Notifier<int?> {
  @override
  int? build() => null;

  void open(int segment) => state = segment;
  void clear() => state = null;
}
