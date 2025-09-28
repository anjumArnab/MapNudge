import 'package:google_maps_flutter/google_maps_flutter.dart';

class LocationResult {
  final bool isSuccess;
  final String? error;
  final LatLng location;

  LocationResult._({
    required this.isSuccess,
    this.error,
    required this.location,
  });

  factory LocationResult.success(LatLng location) {
    return LocationResult._(isSuccess: true, location: location);
  }

  factory LocationResult.error(String error, LatLng fallbackLocation) {
    return LocationResult._(
      isSuccess: false,
      error: error,
      location: fallbackLocation,
    );
  }
}
