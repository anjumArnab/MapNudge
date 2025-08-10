class UserLocation {
  final String userId;
  final double latitude;
  final double longitude;
  final String timestamp;

  UserLocation({
    required this.userId,
    required this.latitude,
    required this.longitude,
    required this.timestamp,
  });

  factory UserLocation.fromJson(Map<String, dynamic> json) {
    return UserLocation(
      userId: json['userId'] ?? '',
      latitude: (json['latitude'] ?? 0.0).toDouble(),
      longitude: (json['longitude'] ?? 0.0).toDouble(),
      timestamp: json['timestamp'] ?? DateTime.now().toIso8601String(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'userId': userId,
      'latitude': latitude,
      'longitude': longitude,
      'timestamp': timestamp,
    };
  }

  @override
  String toString() {
    return 'UserLocation(userId: $userId, lat: $latitude, lng: $longitude, time: $timestamp)';
  }
}
