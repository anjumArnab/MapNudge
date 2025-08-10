class ConnectionStatus {
  final bool isConnected;
  final String? roomId;
  final String? userId;
  final String? message;
  final List<String> roomUsers;

  ConnectionStatus({
    required this.isConnected,
    this.roomId,
    this.userId,
    this.message,
    this.roomUsers = const [],
  });

  @override
  String toString() {
    return 'ConnectionStatus(connected: $isConnected, room: $roomId, user: $userId, users: $roomUsers)';
  }
}
