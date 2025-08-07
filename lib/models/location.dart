// Create or update your models/location.dart file
class Location {
  final String fromUserId;
  final double latitude;
  final double longitude;
  final String timestamp;

  Location({
    required this.fromUserId,
    required this.latitude,
    required this.longitude,
    required this.timestamp,
  });

  factory Location.fromJson(Map<String, dynamic> json) {
    // Safe parsing with null checks and defaults
    return Location(
      fromUserId: json['fromUserId']?.toString() ?? 'unknown',
      latitude: (json['latitude'] as num?)?.toDouble() ?? 0.0,
      longitude: (json['longitude'] as num?)?.toDouble() ?? 0.0,
      timestamp:
          json['timestamp']?.toString() ?? DateTime.now().toIso8601String(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'fromUserId': fromUserId,
      'latitude': latitude,
      'longitude': longitude,
      'timestamp': timestamp,
    };
  }

  @override
  String toString() {
    return 'Location(fromUserId: $fromUserId, lat: $latitude, lng: $longitude, timestamp: $timestamp)';
  }
}
