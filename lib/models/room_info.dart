class RoomInfo {
  final String roomId;
  final List<String> users;
  final int userCount;
  final bool exists;
  final String? message;

  RoomInfo({
    required this.roomId,
    required this.users,
    required this.userCount,
    required this.exists,
    this.message,
  });

  factory RoomInfo.fromJson(Map<String, dynamic> json) {
    return RoomInfo(
      roomId: json['roomId'] ?? '',
      users: List<String>.from(json['users'] ?? []),
      userCount: json['userCount'] ?? 0,
      exists: json['exists'] ?? false,
      message: json['message'],
    );
  }
}
