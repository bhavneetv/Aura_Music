import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/source_mode.dart';
import '../services/storage/storage_service.dart';

class SourceModeNotifier extends Notifier<SourceMode> {
  @override
  SourceMode build() {
    return StorageService.getSourceMode();
  }

  Future<void> setMode(SourceMode mode) async {
    state = mode;
    await StorageService.setSourceMode(mode);
  }
}

final sourceModeProvider = NotifierProvider<SourceModeNotifier, SourceMode>(() {
  return SourceModeNotifier();
});
