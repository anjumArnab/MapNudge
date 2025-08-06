class Location {
  final String fromUserId;
  final double latitude;
  final double longitude;
  final DateTime timestamp;

  Location({
    required this.fromUserId,
    required this.latitude,
    required this.longitude,
    required this.timestamp,
  });

  factory Location.fromJson(Map<String, dynamic> json) {
    return Location(
      fromUserId: json['fromUserId'] ?? '',
      latitude: json['latitude']?.toDouble() ?? 0.0,
      longitude: json['longitude']?.toDouble() ?? 0.0,
      timestamp: DateTime.parse(
        json['timestamp'] ?? DateTime.now().toIso8601String(),
      ),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'fromUserId': fromUserId,
      'latitude': latitude,
      'longitude': longitude,
      'timestamp': timestamp.toIso8601String(),
    };
  }
}
