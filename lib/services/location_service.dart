import 'dart:convert';
import 'dart:async';
import 'package:http/http.dart' as http;
import '../models/location.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'package:flutter/foundation.dart';

class LocationService {
  static LocationService? _instance;
  static LocationService get instance {
    _instance ??= LocationService._internal();
    return _instance!;
  }

  LocationService._internal();

  IO.Socket? _socket;
  String? _serverUrl;
  String? _currentRoomId;
  String? _currentUserId;
  bool _isConnected = false;

  // Stream controllers for different events
  final StreamController<Location> _locationStreamController =
      StreamController<Location>.broadcast();
  final StreamController<bool> _connectionStreamController =
      StreamController<bool>.broadcast();
  final StreamController<String> _errorStreamController =
      StreamController<String>.broadcast();
  final StreamController<List<String>> _roomUsersStreamController =
      StreamController<List<String>>.broadcast();

  // Getters for streams
  Stream<Location> get locationStream => _locationStreamController.stream;
  Stream<bool> get connectionStream => _connectionStreamController.stream;
  Stream<String> get errorStream => _errorStreamController.stream;
  Stream<List<String>> get roomUsersStream => _roomUsersStreamController.stream;

  bool get isConnected => _isConnected;
  String? get currentRoomId => _currentRoomId;
  String? get currentUserId => _currentUserId;

  // Connect to server and join room
  Future<bool> connectToServer({
    required String serverUrl,
    required String roomId,
    required String userId,
  }) async {
    try {
      _serverUrl = serverUrl.endsWith('/') ? serverUrl : '$serverUrl/';
      _currentRoomId = roomId;
      _currentUserId = userId;

      // Disconnect existing connection if any
      await disconnect();

      // Create socket connection
      _socket = IO.io(
        _serverUrl,
        IO.OptionBuilder()
            .setTransports(['websocket'])
            .enableAutoConnect()
            .enableForceNew()
            .build(),
      );

      // Set up event listeners
      _setupSocketListeners();

      // Connect and join room
      _socket!.connect();

      // Wait for connection with timeout
      bool connected = await _waitForConnection();

      if (connected) {
        _joinRoom();
      }

      return connected;
    } catch (e) {
      debugPrint('Error connecting to server: $e');
      _errorStreamController.add('Connection failed: $e');
      return false;
    }
  }

  void _setupSocketListeners() {
    if (_socket == null) return;

    _socket!.onConnect((_) {
      debugPrint('Connected to MapNudge server');
      _isConnected = true;
      _connectionStreamController.add(true);
    });

    _socket!.onDisconnect((_) {
      debugPrint('Disconnected from MapNudge server');
      _isConnected = false;
      _connectionStreamController.add(false);
    });

    _socket!.on('room-joined', (data) {
      debugPrint('Successfully joined room: $data');
    });

    _socket!.on('location-received', (data) {
      try {
        final location = Location.fromJson(Map<String, dynamic>.from(data));
        debugPrint('Location received from ${location.fromUserId}');
        _locationStreamController.add(location);
      } catch (e) {
        debugPrint('Error parsing received location: $e');
        _errorStreamController.add('Error parsing location data: $e');
      }
    });

    _socket!.on('location-sent', (data) {
      debugPrint('Location sent confirmation: $data');
    });

    _socket!.on('user-joined', (data) {
      debugPrint('User joined room: $data');
    });

    _socket!.on('user-left', (data) {
      debugPrint('User left room: $data');
    });

    _socket!.on('room-users-updated', (data) {
      try {
        List<String> users = List<String>.from(data['users'] ?? []);
        debugPrint('Room users updated: $users');
        _roomUsersStreamController.add(users);
      } catch (e) {
        debugPrint('Error parsing room users: $e');
      }
    });

    _socket!.on('error', (data) {
      debugPrint('Server error: $data');
      _errorStreamController.add('Server error: ${data['message'] ?? data}');
    });

    _socket!.onConnectError((error) {
      debugPrint('Connection error: $error');
      _errorStreamController.add('Connection error: $error');
    });
  }

  Future<bool> _waitForConnection({int timeoutSeconds = 10}) async {
    final completer = Completer<bool>();
    Timer? timer;

    // Listen for connection
    StreamSubscription? subscription;
    subscription = connectionStream.listen((connected) {
      if (connected) {
        timer?.cancel();
        subscription?.cancel();
        if (!completer.isCompleted) {
          completer.complete(true);
        }
      }
    });

    // Set timeout
    timer = Timer(Duration(seconds: timeoutSeconds), () {
      subscription?.cancel();
      if (!completer.isCompleted) {
        completer.complete(false);
      }
    });

    return completer.future;
  }

  void _joinRoom() {
    if (_socket == null ||
        !_isConnected ||
        _currentRoomId == null ||
        _currentUserId == null) {
      return;
    }

    _socket!.emit('join-room', {
      'roomId': _currentRoomId,
      'userId': _currentUserId,
    });
  }

  // Send location via Socket.IO
  Future<bool> sendLocationViaSocket({
    required double latitude,
    required double longitude,
  }) async {
    try {
      if (_socket == null || !_isConnected) {
        _errorStreamController.add('Not connected to server');
        return false;
      }

      _socket!.emit('send-location', {
        'latitude': latitude,
        'longitude': longitude,
      });

      return true;
    } catch (e) {
      debugPrint('Error sending location via socket: $e');
      _errorStreamController.add('Failed to send location: $e');
      return false;
    }
  }

  // Send location via HTTP POST (alternative method)
  Future<bool> sendLocationViaHttp({
    required double latitude,
    required double longitude,
  }) async {
    try {
      if (_serverUrl == null ||
          _currentRoomId == null ||
          _currentUserId == null) {
        _errorStreamController.add('Not connected to server');
        return false;
      }

      final response = await http.post(
        Uri.parse('${_serverUrl}send-location'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'roomId': _currentRoomId,
          'userId': _currentUserId,
          'latitude': latitude,
          'longitude': longitude,
        }),
      );

      if (response.statusCode == 200) {
        debugPrint('Location sent successfully via HTTP');
        return true;
      } else {
        final error = 'Failed to send location: ${response.statusCode}';
        debugPrint(error);
        _errorStreamController.add(error);
        return false;
      }
    } catch (e) {
      debugPrint('Error sending location via HTTP: $e');
      _errorStreamController.add('Failed to send location: $e');
      return false;
    }
  }

  // Test server connection
  Future<bool> testConnection(String serverUrl) async {
    try {
      final url = serverUrl.endsWith('/') ? serverUrl : '$serverUrl/';
      final response = await http
          .get(Uri.parse(url))
          .timeout(Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        debugPrint('Server test successful: $data');
        return true;
      }
      return false;
    } catch (e) {
      debugPrint('Server test failed: $e');
      return false;
    }
  }

  // Disconnect from server
  Future<void> disconnect() async {
    if (_socket != null) {
      _socket!.disconnect();
      _socket!.dispose();
      _socket = null;
    }

    _isConnected = false;
    _currentRoomId = null;
    _currentUserId = null;
    _serverUrl = null;

    _connectionStreamController.add(false);
  }

  // Clean up resources
  void dispose() {
    disconnect();
    _locationStreamController.close();
    _connectionStreamController.close();
    _errorStreamController.close();
    _roomUsersStreamController.close();
  }
}
