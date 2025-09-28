import '../models/user_location.dart';

class RouteInfo {
  final String userId;
  final UserLocation userLocation;
  final String travelMode;
  final String directDistance;
  final String destination;
  final String lastUpdated;

  RouteInfo({
    required this.userId,
    required this.userLocation,
    required this.travelMode,
    required this.directDistance,
    required this.destination,
    required this.lastUpdated,
  });
}
