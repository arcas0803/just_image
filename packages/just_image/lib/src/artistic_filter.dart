/// Available artistic filters.
///
/// ```dart
/// final result = await File('photo.jpg')
///     .justImage
///     .filter(ArtisticFilterName.cinematic)
///     .encode(const WebpOutput())
///     .run();
/// ```
enum ArtisticFilterName {
  vintage,
  sepia,
  cool,
  warm,
  marine,
  dramatic,
  lomo,
  retro,
  noir,
  bloom,
  polaroid,
  goldenHour,
  arctic,
  cinematic,
  fade;

  /// The snake_case name used in the Rust JSON protocol.
  String get jsonName {
    return switch (this) {
      ArtisticFilterName.vintage => 'vintage',
      ArtisticFilterName.sepia => 'sepia',
      ArtisticFilterName.cool => 'cool',
      ArtisticFilterName.warm => 'warm',
      ArtisticFilterName.marine => 'marine',
      ArtisticFilterName.dramatic => 'dramatic',
      ArtisticFilterName.lomo => 'lomo',
      ArtisticFilterName.retro => 'retro',
      ArtisticFilterName.noir => 'noir',
      ArtisticFilterName.bloom => 'bloom',
      ArtisticFilterName.polaroid => 'polaroid',
      ArtisticFilterName.goldenHour => 'golden_hour',
      ArtisticFilterName.arctic => 'arctic',
      ArtisticFilterName.cinematic => 'cinematic',
      ArtisticFilterName.fade => 'fade',
    };
  }
}
