import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:flutter_polyline_points/flutter_polyline_points.dart';
import 'package:geolocator/geolocator.dart';
import '../models/route_info.dart';
import '../models/user_location.dart';

class RouteService {
  static const String googleApiKey = "YOUR_GOOGLE_API_KEY_HERE";
  final PolylinePoints _polylinePoints = PolylinePoints();

  // Route display settings
  String _routeMode = 'driving'; // driving, walking, transit
  List<String> _selectedUsers = []; // Empty means show routes to all users

  // Color scheme for routes
  final List<Color> _polylineColors = [
    Colors.red,
    Colors.blue,
    Colors.green,
    Colors.orange,
    Colors.purple,
    Colors.cyan,
    Colors.pink,
    Colors.indigo,
  ];

  // Getters
  String get routeMode => _routeMode;
  List<String> get selectedUsers => List.from(_selectedUsers);
  List<Color> get polylineColors => List.from(_polylineColors);

  // Setters
  void setRouteMode(String mode) {
    _routeMode = mode;
  }

  void setSelectedUsers(List<String> users) {
    _selectedUsers = List.from(users);
  }

  void addSelectedUser(String userId) {
    if (!_selectedUsers.contains(userId)) {
      _selectedUsers.add(userId);
    }
  }

  void removeSelectedUser(String userId) {
    _selectedUsers.remove(userId);
  }

  void clearSelectedUsers() {
    _selectedUsers.clear();
  }

  bool isApiKeyConfigured() {
    return googleApiKey != "YOUR_GOOGLE_API_KEY_HERE";
  }

  /// Get polyline points between two locations using Google Directions API
  Future<List<LatLng>> getPolylinePoints(
    LatLng origin,
    LatLng destination,
  ) async {
    List<LatLng> polylineCoordinates = [];

    try {
      PolylineRequest request = PolylineRequest(
        origin: PointLatLng(origin.latitude, origin.longitude),
        destination: PointLatLng(destination.latitude, destination.longitude),
        mode: _getTravelMode(),
      );

      PolylineResult result = await _polylinePoints.getRouteBetweenCoordinates(
        googleApiKey: googleApiKey,
        request: request,
      );

      if (result.points.isNotEmpty) {
        result.points.forEach((PointLatLng point) {
          polylineCoordinates.add(LatLng(point.latitude, point.longitude));
        });
      } else {
        debugPrint('No route found between $origin and $destination');
        // Fallback to direct line
        polylineCoordinates = [origin, destination];
      }
    } catch (e) {
      debugPrint('Error getting polyline points: $e');
      // Fallback to direct line
      polylineCoordinates = [origin, destination];
    }

    return polylineCoordinates;
  }

  /// Generate polylines for routes from current location to selected users
  Future<Map<PolylineId, Polyline>> generateRoutes({
    required LatLng currentLocation,
    required Map<String, UserLocation> userLocations,
    required String? currentUserId,
    required Function(String userId, UserLocation userLocation) onRouteTap,
  }) async {
    Map<PolylineId, Polyline> polylines = {};
    int colorIndex = 0;

    try {
      // Determine target users for routes
      List<String> targetUsers =
          _selectedUsers.isEmpty
              ? userLocations.keys
                  .where((userId) => userId != currentUserId)
                  .toList()
              : _selectedUsers;

      for (String userId in targetUsers) {
        UserLocation? userLocation = userLocations[userId];
        if (userLocation == null || userId == currentUserId) continue;

        LatLng destination = LatLng(
          userLocation.latitude,
          userLocation.longitude,
        );

        List<LatLng> polylineCoordinates = await getPolylinePoints(
          currentLocation,
          destination,
        );

        if (polylineCoordinates.isNotEmpty) {
          PolylineId polylineId = PolylineId("route_to_$userId");
          Polyline polyline = Polyline(
            polylineId: polylineId,
            points: polylineCoordinates,
            color: _polylineColors[colorIndex % _polylineColors.length],
            width: 4,
            patterns:
                _routeMode == 'walking'
                    ? [PatternItem.dash(10), PatternItem.gap(10)]
                    : [],
            onTap: () => onRouteTap(userId, userLocation),
          );

          polylines[polylineId] = polyline;
        }

        colorIndex++;
      }
    } catch (e) {
      debugPrint('Error generating routes: $e');
      rethrow;
    }

    return polylines;
  }

  /// Calculate direct distance between two points in kilometers
  double calculateDistance(LatLng from, LatLng to) {
    return Geolocator.distanceBetween(
          from.latitude,
          from.longitude,
          to.latitude,
          to.longitude,
        ) /
        1000; // Convert to kilometers
  }

  /// Get travel mode for API request
  TravelMode _getTravelMode() {
    switch (_routeMode) {
      case 'walking':
        return TravelMode.walking;
      case 'transit':
        return TravelMode.transit;
      case 'driving':
      default:
        return TravelMode.driving;
    }
  }

  /// Get route information for display
  RouteInfo getRouteInfo({
    required String userId,
    required UserLocation userLocation,
    required LatLng currentLocation,
  }) {
    double distance = calculateDistance(
      currentLocation,
      LatLng(userLocation.latitude, userLocation.longitude),
    );

    return RouteInfo(
      userId: userId,
      userLocation: userLocation,
      travelMode: _routeMode.toUpperCase(),
      directDistance: '${distance.toStringAsFixed(2)} km',
      destination:
          '${userLocation.latitude.toStringAsFixed(6)}, ${userLocation.longitude.toStringAsFixed(6)}',
      lastUpdated: _formatTimestamp(userLocation.timestamp),
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

  /// Dispose of resources
  void dispose() {
    _selectedUsers.clear();
  }
}
