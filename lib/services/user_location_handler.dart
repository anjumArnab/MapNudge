import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import '../models/location_result.dart';
import '../models/user_location.dart';

class UserLocationHandler {
  // Default location (Dhaka, Bangladesh)
  static const LatLng defaultLocation = LatLng(23.8103, 90.4125);

  // Color scheme for different user markers
  final List<double> _markerHues = [
    BitmapDescriptor.hueRed,
    BitmapDescriptor.hueBlue,
    BitmapDescriptor.hueGreen,
    BitmapDescriptor.hueYellow,
    BitmapDescriptor.hueOrange,
    BitmapDescriptor.hueCyan,
    BitmapDescriptor.hueMagenta,
    BitmapDescriptor.hueViolet,
  ];

  // Current location state
  LatLng? _currentLocation;
  bool _isLoadingLocation = false;

  // Getters
  LatLng? get currentLocation => _currentLocation;
  bool get isLoadingLocation => _isLoadingLocation;
  List<double> get markerHues => List.from(_markerHues);

  /// Get current user location with proper error handling
  Future<LocationResult> getCurrentLocation() async {
    _isLoadingLocation = true;

    try {
      // Check if location services are enabled
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        debugPrint('Location services are disabled.');
        _currentLocation = defaultLocation;
        _isLoadingLocation = false;
        return LocationResult.error(
          'Location services are disabled. Using default location.',
          defaultLocation,
        );
      }

      // Check location permission
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          debugPrint('Location permissions are denied');
          _currentLocation = defaultLocation;
          _isLoadingLocation = false;
          return LocationResult.error(
            'Location permission denied. Using default location.',
            defaultLocation,
          );
        }
      }

      if (permission == LocationPermission.deniedForever) {
        debugPrint('Location permissions are permanently denied.');
        _currentLocation = defaultLocation;
        _isLoadingLocation = false;
        return LocationResult.error(
          'Location permission permanently denied. Using default location.',
          defaultLocation,
        );
      }

      // Get current position
      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: Duration(seconds: 15),
      );

      _currentLocation = LatLng(position.latitude, position.longitude);
      _isLoadingLocation = false;

      debugPrint(
        'Current location obtained: ${_currentLocation!.latitude}, ${_currentLocation!.longitude}',
      );

      return LocationResult.success(_currentLocation!);
    } catch (e) {
      debugPrint('Error getting current location: $e');
      _currentLocation = defaultLocation;
      _isLoadingLocation = false;
      return LocationResult.error(
        'Error getting location: ${e.toString()}. Using default location.',
        defaultLocation,
      );
    }
  }

  /// Set default location when location access fails
  LocationResult setDefaultLocation() {
    _currentLocation = defaultLocation;
    _isLoadingLocation = false;
    return LocationResult.success(defaultLocation);
  }

  /// Create marker for current user location
  Future<Marker> createCurrentLocationMarker() async {
    if (_currentLocation == null) {
      throw Exception('Current location not available');
    }

    var currentLocationIcon = await BitmapDescriptor.defaultMarkerWithHue(
      BitmapDescriptor.hueBlue,
    );

    return Marker(
      markerId: MarkerId("current_location"),
      icon: currentLocationIcon,
      position: _currentLocation!,
      infoWindow: InfoWindow(
        title: "Your Current Location",
        snippet:
            "Lat: ${_currentLocation!.latitude.toStringAsFixed(6)}, "
            "Lng: ${_currentLocation!.longitude.toStringAsFixed(6)}",
      ),
    );
  }

  /// Generate markers for all user locations
  Future<Map<MarkerId, Marker>> generateUserMarkers({
    required Map<String, UserLocation> userLocations,
    required String? currentUserId,
  }) async {
    Map<MarkerId, Marker> markers = {};

    if (userLocations.isEmpty) return markers;

    // Add current location marker if available
    if (_currentLocation != null) {
      markers[MarkerId("current_location")] =
          await createCurrentLocationMarker();
    }

    // Add markers for all other users
    int colorIndex = 0;
    for (var entry in userLocations.entries) {
      String userId = entry.key;
      UserLocation userLocation = entry.value;

      // Skip if this is the current user (already have current_location marker)
      if (userId == currentUserId) {
        colorIndex++;
        continue;
      }

      // Create marker for this user
      var userLocationIcon = await BitmapDescriptor.defaultMarkerWithHue(
        _markerHues[colorIndex % _markerHues.length],
      );

      Marker userMarker = Marker(
        markerId: MarkerId("user_$userId"),
        icon: userLocationIcon,
        position: LatLng(userLocation.latitude, userLocation.longitude),
        infoWindow: InfoWindow(
          title: userId,
          snippet:
              "Lat: ${userLocation.latitude.toStringAsFixed(6)}, "
              "Lng: ${userLocation.longitude.toStringAsFixed(6)}\n"
              "Updated: ${_formatTimestamp(userLocation.timestamp)}",
        ),
      );

      markers[MarkerId("user_$userId")] = userMarker;
      colorIndex++;
    }

    return markers;
  }

  /// Calculate camera bounds to show all locations
  CameraUpdate calculateBoundsForAllLocations({
    required Map<String, UserLocation> userLocations,
  }) {
    // Collect all locations
    List<LatLng> allLocations = [];

    // Add current location
    if (_currentLocation != null) {
      allLocations.add(_currentLocation!);
    }

    // Add user locations
    for (var userLocation in userLocations.values) {
      allLocations.add(LatLng(userLocation.latitude, userLocation.longitude));
    }

    if (allLocations.length < 2) {
      // If only one location, just center on it
      return CameraUpdate.newCameraPosition(
        CameraPosition(
          target:
              allLocations.isNotEmpty ? allLocations.first : defaultLocation,
          zoom: 15,
        ),
      );
    }

    // Calculate bounds
    double minLat = allLocations
        .map((loc) => loc.latitude)
        .reduce((a, b) => a < b ? a : b);
    double maxLat = allLocations
        .map((loc) => loc.latitude)
        .reduce((a, b) => a > b ? a : b);
    double minLng = allLocations
        .map((loc) => loc.longitude)
        .reduce((a, b) => a < b ? a : b);
    double maxLng = allLocations
        .map((loc) => loc.longitude)
        .reduce((a, b) => a > b ? a : b);

    // Add padding
    double latPadding = (maxLat - minLat) * 0.2;
    double lngPadding = (maxLng - minLng) * 0.2;

    // Ensure minimum padding
    latPadding = latPadding < 0.01 ? 0.01 : latPadding;
    lngPadding = lngPadding < 0.01 ? 0.01 : lngPadding;

    return CameraUpdate.newLatLngBounds(
      LatLngBounds(
        southwest: LatLng(minLat - latPadding, minLng - lngPadding),
        northeast: LatLng(maxLat + latPadding, maxLng + lngPadding),
      ),
      100.0, // padding
    );
  }

  /// Get camera update to focus on a specific user
  CameraUpdate focusOnUser(UserLocation userLocation) {
    return CameraUpdate.newCameraPosition(
      CameraPosition(
        target: LatLng(userLocation.latitude, userLocation.longitude),
        zoom: 16,
      ),
    );
  }

  /// Get camera update to focus on current location
  CameraUpdate focusOnCurrentLocation() {
    if (_currentLocation == null) {
      throw Exception('Current location not available');
    }

    return CameraUpdate.newCameraPosition(
      CameraPosition(target: _currentLocation!, zoom: 15),
    );
  }

  /// Format timestamp for display
  String _formatTimestamp(String timestamp) {
    try {
      DateTime dateTime = DateTime.parse(timestamp);
      DateTime now = DateTime.now();
      Duration difference = now.difference(dateTime);

      if (difference.inMinutes < 1) {
        return "Just now";
      } else if (difference.inMinutes < 60) {
        return "${difference.inMinutes}m ago";
      } else if (difference.inHours < 24) {
        return "${difference.inHours}h ago";
      } else {
        return "${difference.inDays}d ago";
      }
    } catch (e) {
      return "Unknown";
    }
  }

  /// Check if location permission is available
  Future<bool> isLocationPermissionGranted() async {
    LocationPermission permission = await Geolocator.checkPermission();
    return permission == LocationPermission.always ||
        permission == LocationPermission.whileInUse;
  }

  /// Check if location services are enabled
  Future<bool> isLocationServiceEnabled() async {
    return await Geolocator.isLocationServiceEnabled();
  }

  /// Request location permission
  Future<LocationPermission> requestLocationPermission() async {
    return await Geolocator.requestPermission();
  }

  /// Dispose of resources
  void dispose() {
    _currentLocation = null;
    _isLoadingLocation = false;
  }
}
