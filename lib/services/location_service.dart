import 'dart:async';
import 'dart:developer' as developer;
import '../models/connection_status.dart';
import '../models/user_location.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;

class LocationService {
  // Singleton instance
  static final LocationService _instance = LocationService._internal();
  factory LocationService() => _instance;
  LocationService._internal();

  // Socket.io client
  IO.Socket? _socket;

  // Connection state
  bool _isConnected = false;
  String? _serverUrl;
  String? _currentRoomId;
  String? _currentUserId;
  List<String> _roomUsers = [];

  // User locations storage
  final Map<String, UserLocation> _userLocations = {};

  // Stream controllers for reactive updates
  final StreamController<ConnectionStatus> _connectionController =
      StreamController<ConnectionStatus>.broadcast();
  final StreamController<UserLocation> _locationUpdateController =
      StreamController<UserLocation>.broadcast();
  final StreamController<Map<String, UserLocation>> _allLocationsController =
      StreamController<Map<String, UserLocation>>.broadcast();
  final StreamController<List<String>> _roomUsersController =
      StreamController<List<String>>.broadcast();
  final StreamController<String> _errorController =
      StreamController<String>.broadcast();

  // Getters for streams
  Stream<ConnectionStatus> get connectionStream => _connectionController.stream;
  Stream<UserLocation> get locationUpdateStream =>
      _locationUpdateController.stream;
  Stream<Map<String, UserLocation>> get allLocationsStream =>
      _allLocationsController.stream;
  Stream<List<String>> get roomUsersStream => _roomUsersController.stream;
  Stream<String> get errorStream => _errorController.stream;

  // Getters for current state
  bool get isConnected => _isConnected;
  String? get currentRoomId => _currentRoomId;
  String? get currentUserId => _currentUserId;
  List<String> get roomUsers => List.unmodifiable(_roomUsers);
  Map<String, UserLocation> get userLocations =>
      Map.unmodifiable(_userLocations);
  String? get serverUrl => _serverUrl;

  // Connect to server and join room
  Future<bool> connectToServer({
    required String serverUrl,
    required String roomId,
    required String userId,
  }) async {
    try {
      developer.log('🔌 Attempting to connect to server: $serverUrl');

      // Clean up existing connection
      await disconnect();

      _serverUrl = serverUrl;
      _currentRoomId = roomId;
      _currentUserId = userId;

      // Configure socket options
      _socket = IO.io(
        serverUrl,
        IO.OptionBuilder()
            .setTransports(['websocket']) // Use websocket transport
            .enableAutoConnect() // Auto connect
            .enableReconnection() // Auto reconnect
            .setReconnectionAttempts(5) // Retry attempts
            .setReconnectionDelay(1000) // Delay between attempts
            .setTimeout(10000) // Connection timeout
            .build(),
      );

      // Set up connection event listeners
      _setupConnectionListeners();

      // Set up location event listeners
      _setupLocationListeners();

      // Wait for connection
      final Completer<bool> connectionCompleter = Completer<bool>();
      Timer connectionTimeout = Timer(Duration(seconds: 15), () {
        if (!connectionCompleter.isCompleted) {
          connectionCompleter.complete(false);
        }
      });

      _socket!.onConnect((_) {
        developer.log('Connected to server, joining room...');

        // Join room after connection
        _socket!.emit('join-room', {'roomId': roomId, 'userId': userId});
      });

      _socket!.on('joined-room', (data) {
        connectionTimeout.cancel();
        if (!connectionCompleter.isCompleted) {
          developer.log('Successfully joined room: ${data['roomId']}');
          _handleRoomJoined(data);
          connectionCompleter.complete(true);
        }
      });

      _socket!.onConnectError((error) {
        developer.log('Connection error: $error');
        connectionTimeout.cancel();
        if (!connectionCompleter.isCompleted) {
          _handleConnectionError('Connection failed: $error');
          connectionCompleter.complete(false);
        }
      });

      _socket!.connect();
      return await connectionCompleter.future;
    } catch (e) {
      developer.log('Connection exception: $e');
      _handleConnectionError('Connection failed: $e');
      return false;
    }
  }

  // Set up connection-related event listeners
  void _setupConnectionListeners() {
    if (_socket == null) return;

    _socket!.onConnect((_) {
      developer.log('Socket connected');
    });

    _socket!.onDisconnect((reason) {
      developer.log('Socket disconnected: $reason');
      _isConnected = false;
      _connectionController.add(
        ConnectionStatus(isConnected: false, message: 'Disconnected: $reason'),
      );
    });

    _socket!.on('user-joined', (data) {
      developer.log('User joined: ${data['userId']}');
      _handleUserJoined(data);
    });

    _socket!.on('user-left', (data) {
      developer.log('User left: ${data['userId']}');
      _handleUserLeft(data);
    });

    _socket!.on('error', (data) {
      developer.log('Server error: ${data['message']}');
      _errorController.add(data['message'] ?? 'Unknown server error');
    });
  }

  // Set up location-related event listeners
  void _setupLocationListeners() {
    if (_socket == null) return;

    _socket!.on('location-update', (data) {
      developer.log('Location update received: ${data['userId']}');
      _handleLocationUpdate(data);
    });

    _socket!.on('existing-locations', (data) {
      developer.log('Existing locations received');
      _handleExistingLocations(data);
    });

    _socket!.on('all-locations', (data) {
      developer.log('All locations received');
      _handleAllLocations(data);
    });

    _socket!.on('location-shared', (data) {
      developer.log('Location shared successfully');
      // Optional: Handle confirmation
    });
  }

  // Handle successful room join
  void _handleRoomJoined(Map<String, dynamic> data) {
    _isConnected = true;
    _currentRoomId = data['roomId'];
    _currentUserId = data['userId'];
    _roomUsers = List<String>.from(data['usersInRoom'] ?? []);

    _connectionController.add(
      ConnectionStatus(
        isConnected: true,
        roomId: _currentRoomId,
        userId: _currentUserId,
        message: data['message'],
        roomUsers: _roomUsers,
      ),
    );

    _roomUsersController.add(_roomUsers);
  }

  // Handle user joined event
  void _handleUserJoined(Map<String, dynamic> data) {
    String userId = data['userId'];
    _roomUsers = List<String>.from(data['usersInRoom'] ?? []);

    _roomUsersController.add(_roomUsers);

    // Update connection status
    _connectionController.add(
      ConnectionStatus(
        isConnected: true,
        roomId: _currentRoomId,
        userId: _currentUserId,
        message: data['message'],
        roomUsers: _roomUsers,
      ),
    );
  }

  // Handle user left event
  void _handleUserLeft(Map<String, dynamic> data) {
    String userId = data['userId'];
    _roomUsers = List<String>.from(data['usersInRoom'] ?? []);

    // Remove user's location
    _userLocations.remove(userId);

    _roomUsersController.add(_roomUsers);
    _allLocationsController.add(Map.from(_userLocations));

    // Update connection status
    _connectionController.add(
      ConnectionStatus(
        isConnected: true,
        roomId: _currentRoomId,
        userId: _currentUserId,
        message: data['message'],
        roomUsers: _roomUsers,
      ),
    );
  }

  // Handle location update from another user
  void _handleLocationUpdate(Map<String, dynamic> data) {
    final location = UserLocation.fromJson(data);
    _userLocations[location.userId] = location;

    _locationUpdateController.add(location);
    _allLocationsController.add(Map.from(_userLocations));
  }

  // Handle existing locations when joining room
  void _handleExistingLocations(Map<String, dynamic> data) {
    data.forEach((userId, locationData) {
      final location = UserLocation.fromJson({
        'userId': userId,
        ...locationData,
      });
      _userLocations[userId] = location;
    });

    _allLocationsController.add(Map.from(_userLocations));
  }

  // Handle all locations response
  void _handleAllLocations(Map<String, dynamic> data) {
    _userLocations.clear();
    data.forEach((userId, locationData) {
      final location = UserLocation.fromJson({
        'userId': userId,
        ...locationData,
      });
      _userLocations[userId] = location;
    });

    _allLocationsController.add(Map.from(_userLocations));
  }

  // Handle connection errors
  void _handleConnectionError(String error) {
    _isConnected = false;
    _connectionController.add(
      ConnectionStatus(isConnected: false, message: error),
    );
    _errorController.add(error);
  }

  // Share current location with room
  Future<bool> shareLocation({
    required double latitude,
    required double longitude,
  }) async {
    if (!_isConnected || _socket == null) {
      _errorController.add('Not connected to server');
      return false;
    }

    if (_currentRoomId == null || _currentUserId == null) {
      _errorController.add('Room or user ID not set');
      return false;
    }

    try {
      developer.log('Sharing location: $latitude, $longitude');

      _socket!.emit('share-location', {
        'roomId': _currentRoomId,
        'userId': _currentUserId,
        'latitude': latitude,
        'longitude': longitude,
      });

      // Update local location
      final myLocation = UserLocation(
        userId: _currentUserId!,
        latitude: latitude,
        longitude: longitude,
        timestamp: DateTime.now().toIso8601String(),
      );
      _userLocations[_currentUserId!] = myLocation;
      _allLocationsController.add(Map.from(_userLocations));

      return true;
    } catch (e) {
      developer.log('Error sharing location: $e');
      _errorController.add('Failed to share location: $e');
      return false;
    }
  }

  // Request all current locations in room
  Future<void> requestAllLocations() async {
    if (!_isConnected || _socket == null || _currentRoomId == null) {
      _errorController.add('Not connected to server or room');
      return;
    }

    try {
      developer.log('Requesting all locations');
      _socket!.emit('get-all-locations', {'roomId': _currentRoomId});
    } catch (e) {
      developer.log('Error requesting locations: $e');
      _errorController.add('Failed to get locations: $e');
    }
  }

  // Leave current room
  Future<void> leaveRoom() async {
    if (_socket != null && _isConnected) {
      developer.log('Leaving room');
      _socket!.emit('leave-room');
    }

    _isConnected = false;
    _currentRoomId = null;
    _currentUserId = null;
    _roomUsers.clear();
    _userLocations.clear();

    _connectionController.add(
      ConnectionStatus(isConnected: false, message: 'Left room'),
    );
  }

  // Disconnect from server
  Future<void> disconnect() async {
    if (_socket != null) {
      developer.log('Disconnecting from server');

      await leaveRoom();

      _socket!.disconnect();
      _socket!.dispose();
      _socket = null;
    }

    _serverUrl = null;
    _isConnected = false;
  }

  // Check server health
  Future<bool> checkServerHealth() async {
    if (_serverUrl == null) return false;

    try {
      // This would require http package for REST call to server health endpoint
      // For now, just check socket connection
      return _isConnected;
    } catch (e) {
      developer.log('Health check failed: $e');
      return false;
    }
  }

  // Get specific user location
  UserLocation? getUserLocation(String userId) {
    return _userLocations[userId];
  }

  // Get current user's location
  UserLocation? getMyLocation() {
    if (_currentUserId == null) return null;
    return _userLocations[_currentUserId!];
  }

  // Clear all stored locations
  void clearLocations() {
    _userLocations.clear();
    _allLocationsController.add({});
  }

  // Dispose all resources
  Future<void> dispose() async {
    developer.log('Disposing LocationService');

    await disconnect();

    await _connectionController.close();
    await _locationUpdateController.close();
    await _allLocationsController.close();
    await _roomUsersController.close();
    await _errorController.close();
  }
}
