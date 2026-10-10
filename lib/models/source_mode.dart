enum SourceMode {
  hybrid,
  jiosaavn,
  youtube;

  String get label {
    switch (this) {
      case SourceMode.hybrid:
        return 'Hybrid (Recommended)';
      case SourceMode.jiosaavn:
        return 'JioSaavn Only';
      case SourceMode.youtube:
        return 'YouTube Only';
    }
  }

  String get description {
    switch (this) {
      case SourceMode.hybrid:
        return 'JioSaavn first, automatic YouTube fallback';
      case SourceMode.jiosaavn:
        return 'Fast streaming, JioSaavn catalog only';
      case SourceMode.youtube:
        return 'Vast audio catalog with covers, remixes & live versions';
    }
  }

  String get key => name;

  static SourceMode fromKey(String? key) {
    if (key == null) return SourceMode.hybrid;
    return SourceMode.values.firstWhere(
      (mode) => mode.name == key,
      orElse: () => SourceMode.hybrid,
    );
  }
}
