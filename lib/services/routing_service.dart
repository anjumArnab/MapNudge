import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;

class RoutingService {
  final String _baseUrl = 'https://api.openrouteservice.org/v2/directions';
  final String _apiKey;

  RoutingService(this._apiKey);

  /// Get route between two points
  Future<List<LatLng>?> getRoute({
    required LatLng origin,
    required LatLng destination,
    String profile =
        'driving-car', // driving-car, foot-walking, cycling-regular
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/$profile'),
        headers: {'Authorization': _apiKey, 'Content-Type': 'application/json'},
        body: jsonEncode({
          'coordinates': [
            [origin.longitude, origin.latitude], // OpenRoute uses [lng, lat]
            [destination.longitude, destination.latitude],
          ],
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return _parseRouteCoordinates(data);
      } else {
        debugPrint(
          'Routing API Error: ${response.statusCode} - ${response.body}',
        );
        return null;
      }
    } catch (e) {
      debugPrint('Routing Error: $e');
      return null;
    }
  }

  /// Get route through multiple waypoints
  Future<List<LatLng>?> getMultiPointRoute({
    required List<LatLng> waypoints,
    String profile = 'driving-car',
  }) async {
    if (waypoints.length < 2) return null;

    try {
      final coordinates =
          waypoints.map((point) => [point.longitude, point.latitude]).toList();

      final response = await http.post(
        Uri.parse('$_baseUrl/$profile'),
        headers: {'Authorization': _apiKey, 'Content-Type': 'application/json'},
        body: jsonEncode({'coordinates': coordinates}),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return _parseRouteCoordinates(data);
      } else {
        debugPrint(
          'Multi-point Routing Error: ${response.statusCode} - ${response.body}',
        );
        return null;
      }
    } catch (e) {
      debugPrint('Multi-point Routing Error: $e');
      return null;
    }
  }

  /// Create polyline from route coordinates
  Polyline createPolyline({
    required String polylineId,
    required List<LatLng> coordinates,
    Color color = Colors.blue,
    int width = 4,
    List<PatternItem>? patterns,
  }) {
    return Polyline(
      polylineId: PolylineId(polylineId),
      points: coordinates,
      color: color,
      width: width,
      patterns: patterns ?? [PatternItem.dash(15), PatternItem.gap(8)],
    );
  }

  /// Get straight line route (fallback)
  List<LatLng> getStraightLineRoute({
    required LatLng origin,
    required LatLng destination,
  }) {
    return [origin, destination];
  }

  /// Calculate route distance in kilometers
  double calculateRouteDistance(List<LatLng> coordinates) {
    if (coordinates.length < 2) return 0.0;

    double totalDistance = 0.0;
    for (int i = 0; i < coordinates.length - 1; i++) {
      totalDistance += _calculateDistance(coordinates[i], coordinates[i + 1]);
    }
    return totalDistance;
  }

  /// Calculate estimated travel time in minutes (rough estimate)
  int calculateEstimatedTime(
    List<LatLng> coordinates, {
    double averageSpeedKmh = 50.0,
  }) {
    double distanceKm = calculateRouteDistance(coordinates);
    return (distanceKm / averageSpeedKmh * 60).round();
  }

  // Private helper methods
  List<LatLng>? _parseRouteCoordinates(Map<String, dynamic> data) {
    try {
      if (data['routes'] == null || data['routes'].isEmpty) {
        return null;
      }

      final route = data['routes'][0];
      final geometry = route['geometry'];

      if (geometry['coordinates'] != null) {
        final List<dynamic> coordinates = geometry['coordinates'];
        return coordinates
            .map(
              (coord) => LatLng(coord[1], coord[0]),
            ) // Convert [lng, lat] to LatLng
            .toList();
      }

      return null;
    } catch (e) {
      debugPrint('Error parsing route coordinates: $e');
      return null;
    }
  }

  double _calculateDistance(LatLng from, LatLng to) {
    const double earthRadius = 6371; // Earth's radius in kilometers

    double lat1Rad = from.latitude * (3.14159265359 / 180);
    double lat2Rad = to.latitude * (3.14159265359 / 180);
    double deltaLatRad = (to.latitude - from.latitude) * (3.14159265359 / 180);
    double deltaLngRad =
        (to.longitude - from.longitude) * (3.14159265359 / 180);

    double a =
        (sin(deltaLatRad / 2) * sin(deltaLatRad / 2)) +
        (cos(lat1Rad) *
            cos(lat2Rad) *
            sin(deltaLngRad / 2) *
            sin(deltaLngRad / 2));
    double c = 2 * atan2(sqrt(a), sqrt(1 - a));

    return earthRadius * c;
  }
}

// Helper functions for math operations
double sin(double value) => value - (value * value * value) / 6;
double cos(double value) => 1 - (value * value) / 2;
double sqrt(double value) => value < 0 ? double.nan : _sqrtNewton(value, value);
double atan2(double y, double x) => y / x; // Simplified approximation

double _sqrtNewton(double value, double guess) {
  double nextGuess = (guess + value / guess) / 2;
  if ((nextGuess - guess).abs() < 0.0001) return nextGuess;
  return _sqrtNewton(value, nextGuess);
}
