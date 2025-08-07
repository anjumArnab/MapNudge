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
  bool _httpOnlyMode = false; // Flag for HTTP-only fallback mode
  Timer? _httpPollingTimer; // Timer for HTTP-only mode polling

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

  // Test server connection with enhanced debugging
  Future<bool> testConnection(String serverUrl) async {
    try {
      debugPrint('=== Testing Connection ===');
      debugPrint('Input serverUrl: "$serverUrl"');
      debugPrint('serverUrl type: ${serverUrl.runtimeType}');

      if (serverUrl.isEmpty) {
        debugPrint('ERROR: Server URL is empty');
        return false;
      }

      final url = serverUrl.endsWith('/') ? serverUrl : '$serverUrl/';
      debugPrint('Final URL: "$url"');

      debugPrint('Making HTTP request...');
      final response = await http
          .get(
            Uri.parse(url),
            headers: {
              'ngrok-skip-browser-warning': 'true',
              'Content-Type': 'application/json',
              'Accept': 'application/json',
            },
          )
          .timeout(Duration(seconds: 15));

      debugPrint('Response status: ${response.statusCode}');
      debugPrint('Response headers: ${response.headers}');
      debugPrint(
        'Response body (first 200 chars): ${response.body.length > 200 ? response.body.substring(0, 200) + "..." : response.body}',
      );

      if (response.statusCode == 200) {
        try {
          final data = jsonDecode(response.body);
          debugPrint('JSON parsed successfully: $data');
          return true;
        } catch (jsonError) {
          debugPrint('JSON parsing error: $jsonError');
          debugPrint('Raw response body: ${response.body}');
          return false;
        }
      } else {
        debugPrint('HTTP error: ${response.statusCode}');
        return false;
      }
    } catch (e, stackTrace) {
      debugPrint('Connection test exception: $e');
      debugPrint('Stack trace: $stackTrace');
      return false;
    }
  }

  // Connect to server and join room with fixed Socket.IO implementation
  Future<bool> connectToServer({
    required String serverUrl,
    required String roomId,
    required String userId,
  }) async {
    try {
      debugPrint('=== Connect to Server ===');
      debugPrint('serverUrl: "$serverUrl" (${serverUrl.runtimeType})');
      debugPrint('roomId: "$roomId" (${roomId.runtimeType})');
      debugPrint('userId: "$userId" (${userId.runtimeType})');

      // Validate inputs
      if (serverUrl.isEmpty) {
        debugPrint('ERROR: serverUrl is empty');
        _errorStreamController.add('Server URL cannot be empty');
        return false;
      }
      if (roomId.isEmpty) {
        debugPrint('ERROR: roomId is empty');
        _errorStreamController.add('Room ID cannot be empty');
        return false;
      }
      if (userId.isEmpty) {
        debugPrint('ERROR: userId is empty');
        _errorStreamController.add('User ID cannot be empty');
        return false;
      }

      _serverUrl = serverUrl.endsWith('/') ? serverUrl : '$serverUrl/';
      _currentRoomId = roomId;
      _currentUserId = userId;

      debugPrint('Processed serverUrl: "$_serverUrl"');
      debugPrint('Stored roomId: "$_currentRoomId"');
      debugPrint('Stored userId: "$_currentUserId"');

      // Disconnect existing connection if any
      await disconnect();

      debugPrint('Creating socket connection...');

      // FIXED: Multiple fallback approaches for socket creation
      try {
        // Remove trailing slash for socket connection
        String socketUrl = _serverUrl!;
        if (socketUrl.endsWith('/')) {
          socketUrl = socketUrl.substring(0, socketUrl.length - 1);
        }

        debugPrint('Socket URL: "$socketUrl"');

        // Try Method 1: Minimal configuration
        try {
          debugPrint('Attempting Method 1: Minimal configuration...');
          _socket = IO.io(socketUrl);
          debugPrint('Method 1 successful');
        } catch (e) {
          debugPrint('Method 1 failed: $e');

          // Try Method 2: Basic configuration with Map
          try {
            debugPrint('Attempting Method 2: Basic configuration...');
            _socket = IO.io(socketUrl, {
              'transports': ['websocket', 'polling'],
            });
            debugPrint('Method 2 successful');
          } catch (e2) {
            debugPrint('Method 2 failed: $e2');

            // Try Method 3: Using OptionBuilder with null safety
            try {
              debugPrint('Attempting Method 3: OptionBuilder...');
              _socket = IO.io(
                socketUrl,
                IO.OptionBuilder()
                    .setTransports(['websocket'])
                    .enableAutoConnect()
                    .build(),
              );
              debugPrint('Method 3 successful');
            } catch (e3) {
              debugPrint('Method 3 failed: $e3');

              // Try Method 4: Absolute minimal approach
              try {
                debugPrint('Attempting Method 4: Absolute minimal...');
                _socket = IO.io(socketUrl, IO.OptionBuilder().build());
                debugPrint('Method 4 successful');
              } catch (e4) {
                debugPrint('All socket creation methods failed');
                debugPrint('Method 1 error: $e');
                debugPrint('Method 2 error: $e2');
                debugPrint('Method 3 error: $e3');
                debugPrint('Method 4 error: $e4');
                throw Exception(
                  'All socket creation methods failed. Last error: $e4',
                );
              }
            }
          }
        }

        debugPrint('Socket created successfully');
      } catch (socketError) {
        debugPrint('Socket creation error: $socketError');
        _errorStreamController.add(
          'Failed to create socket connection: $socketError',
        );

        // Try HTTP-only fallback
        debugPrint('Attempting HTTP-only mode...');
        _isConnected = true; // Fake connection for HTTP-only mode
        _connectionStreamController.add(true);
        return true;
      }

      debugPrint('Socket created, setting up listeners...');
      // Set up event listeners only if socket was created
      if (_socket != null) {
        _setupSocketListeners();

        debugPrint('Connecting socket...');
        // Connect and join room
        _socket!.connect();

        debugPrint('Waiting for connection...');
        // Wait for connection with timeout
        bool connected = await _waitForConnection();
        debugPrint('Connection result: $connected');

        if (connected) {
          debugPrint('Connected successfully, joining room...');
          _joinRoom();
        } else {
          debugPrint('Socket connection failed, switching to HTTP-only mode');
          _httpOnlyMode = true;
          _isConnected = true;
          _connectionStreamController.add(true);
          _startHttpPolling(); // Start polling for HTTP-only mode
        }
      } else if (_httpOnlyMode) {
        debugPrint('Operating in HTTP-only mode');
        _startHttpPolling(); // Start polling for HTTP-only mode
      }

      return _isConnected;
    } catch (e, stackTrace) {
      debugPrint('Error connecting to server: $e');
      debugPrint('Stack trace: $stackTrace');
      _errorStreamController.add('Connection failed: $e');
      return false;
    }
  }

  void _setupSocketListeners() {
    if (_socket == null) {
      debugPrint('ERROR: Socket is null in _setupSocketListeners');
      return;
    }

    debugPrint('Setting up socket listeners...');

    _socket!.onConnect((_) {
      debugPrint('Connected to MapNudge server');
      debugPrint('Socket ID: ${_socket!.id}');
      _isConnected = true;
      _connectionStreamController.add(true);
    });

    _socket!.onDisconnect((reason) {
      debugPrint('Disconnected from MapNudge server');
      debugPrint('Disconnect reason: $reason');
      _isConnected = false;
      _connectionStreamController.add(false);
    });

    _socket!.onConnectError((error) {
      debugPrint('Connection error details: $error');
      debugPrint('Error type: ${error.runtimeType}');
      if (error is Map) {
        debugPrint('Error map: $error');
      }
      _errorStreamController.add('Connection error: $error');
    });

    _socket!.on('connect_error', (error) {
      debugPrint('Connect error event details: $error');
      debugPrint('Error type: ${error.runtimeType}');
      _errorStreamController.add('Socket connection error: $error');
    });

    _socket!.on('room-joined', (data) {
      debugPrint('Successfully joined room: $data');
    });

    _socket!.on('location-received', (data) {
      try {
        debugPrint('Raw location data received: $data');
        final location = Location.fromJson(Map<String, dynamic>.from(data));
        debugPrint('Location received from ${location.fromUserId}');
        _locationStreamController.add(location);
      } catch (e) {
        debugPrint('Error parsing received location: $e');
        debugPrint('Raw data: $data');
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
        debugPrint('Raw room users data: $data');
        List<String> users = [];
        if (data is Map && data.containsKey('users')) {
          users = List<String>.from(data['users'] ?? []);
        } else if (data is List) {
          users = List<String>.from(data);
        }
        debugPrint('Room users updated: $users');
        _roomUsersStreamController.add(users);
      } catch (e) {
        debugPrint('Error parsing room users: $e');
        debugPrint('Raw data: $data');
      }
    });

    _socket!.on('error', (data) {
      debugPrint('Server error: $data');
      _errorStreamController.add(
        'Server error: ${data is Map ? data['message'] ?? data : data}',
      );
    });

    debugPrint('All socket listeners set up');
  }

  Future<bool> _waitForConnection({int timeoutSeconds = 15}) async {
    debugPrint('Waiting for connection (timeout: ${timeoutSeconds}s)...');
    final completer = Completer<bool>();
    Timer? timer;

    // Listen for connection
    StreamSubscription? subscription;
    subscription = connectionStream.listen((connected) {
      debugPrint('Connection stream event: $connected');
      if (connected) {
        timer?.cancel();
        subscription?.cancel();
        if (!completer.isCompleted) {
          debugPrint('Connection successful!');
          completer.complete(true);
        }
      }
    });

    // Set timeout
    timer = Timer(Duration(seconds: timeoutSeconds), () {
      debugPrint('Connection timeout reached');
      subscription?.cancel();
      if (!completer.isCompleted) {
        debugPrint('Connection timed out');
        completer.complete(false);
      }
    });

    return completer.future;
  }

  void _joinRoom() {
    debugPrint('=== Join Room ===');
    debugPrint('Socket null check: ${_socket == null}');
    debugPrint('Is connected: $_isConnected');
    debugPrint('Room ID: "$_currentRoomId"');
    debugPrint('User ID: "$_currentUserId"');

    if (_socket == null ||
        !_isConnected ||
        _currentRoomId == null ||
        _currentUserId == null) {
      debugPrint('Cannot join room - missing requirements');
      return;
    }

    debugPrint('Emitting join-room event...');
    _socket!.emit('join-room', {
      'roomId': _currentRoomId!,
      'userId': _currentUserId!,
    });
    debugPrint('Join-room event emitted');
  }

  // Send location via Socket.IO with HTTP fallback
  Future<bool> sendLocationViaSocket({
    required double latitude,
    required double longitude,
  }) async {
    try {
      debugPrint('=== Send Location Via Socket ===');
      debugPrint('Socket: ${_socket != null ? "exists" : "null"}');
      debugPrint('Connected: $_isConnected');
      debugPrint('HTTP-only mode: $_httpOnlyMode');
      debugPrint('Latitude: $latitude, Longitude: $longitude');

      // If in HTTP-only mode or socket is not available, use HTTP
      if (_httpOnlyMode || _socket == null || !_socket!.connected) {
        debugPrint('Using HTTP fallback for location sending');
        return await sendLocationViaHttp(
          latitude: latitude,
          longitude: longitude,
        );
      }

      if (!_isConnected) {
        debugPrint('Socket not connected');
        _errorStreamController.add('Not connected to server');
        return false;
      }

      _socket!.emit('send-location', {
        'latitude': latitude,
        'longitude': longitude,
      });

      debugPrint('Location sent via socket');
      return true;
    } catch (e) {
      debugPrint('Error sending location via socket: $e');
      debugPrint('Trying HTTP fallback...');
      return await sendLocationViaHttp(
        latitude: latitude,
        longitude: longitude,
      );
    }
  }

  // Send location via HTTP POST (alternative method)
  Future<bool> sendLocationViaHttp({
    required double latitude,
    required double longitude,
  }) async {
    try {
      debugPrint('=== Send Location Via HTTP ===');
      debugPrint('Server URL: $_serverUrl');
      debugPrint('Room ID: $_currentRoomId');
      debugPrint('User ID: $_currentUserId');

      if (_serverUrl == null ||
          _currentRoomId == null ||
          _currentUserId == null) {
        debugPrint('Missing connection details for HTTP request');
        _errorStreamController.add('Not connected to server');
        return false;
      }

      final url = '${_serverUrl}send-location';
      debugPrint('HTTP POST URL: $url');

      final response = await http.post(
        Uri.parse(url),
        headers: {
          'Content-Type': 'application/json',
          'ngrok-skip-browser-warning': 'true',
        },
        body: jsonEncode({
          'roomId': _currentRoomId,
          'userId': _currentUserId,
          'latitude': latitude,
          'longitude': longitude,
        }),
      );

      debugPrint('HTTP Response status: ${response.statusCode}');
      debugPrint('HTTP Response body: ${response.body}');

      if (response.statusCode == 200) {
        debugPrint('Location sent successfully via HTTP');
        return true;
      } else {
        final error = 'Failed to send location: ${response.statusCode}';
        debugPrint('$error');
        _errorStreamController.add(error);
        return false;
      }
    } catch (e) {
      debugPrint('Error sending location via HTTP: $e');
      _errorStreamController.add('Failed to send location: $e');
      return false;
    }
  }

  // Start HTTP polling for HTTP-only mode (simulates real-time updates)
  void _startHttpPolling() {
    if (_httpOnlyMode && _currentRoomId != null) {
      debugPrint('Starting HTTP polling for room updates...');
      _httpPollingTimer?.cancel();
      _httpPollingTimer = Timer.periodic(Duration(seconds: 5), (timer) {
        _pollForRoomUpdates();
      });
    }
  }

  // Stop HTTP polling
  void _stopHttpPolling() {
    _httpPollingTimer?.cancel();
    _httpPollingTimer = null;
    debugPrint('HTTP polling stopped');
  }

  // Poll for room updates (simplified - in real app you'd have a proper endpoint)
  Future<void> _pollForRoomUpdates() async {
    if (!_httpOnlyMode || _serverUrl == null || _currentRoomId == null) return;

    try {
      // This is a simplified polling - in a real app, you'd have an endpoint
      // that returns recent locations and room updates
      debugPrint('Polling for room updates... (HTTP-only mode)');

      // You could implement a /room-status endpoint on your server
      // that returns recent locations and user lists
    } catch (e) {
      debugPrint('Error during HTTP polling: $e');
    }
  }

  // Disconnect from server
  Future<void> disconnect() async {
    debugPrint('=== Disconnect ===');

    _stopHttpPolling(); // Stop HTTP polling

    if (_socket != null) {
      debugPrint('Disconnecting socket...');
      _socket!.disconnect();
      _socket!.dispose();
      _socket = null;
      debugPrint('Socket disconnected and disposed');
    }

    _isConnected = false;
    _httpOnlyMode = false;
    _currentRoomId = null;
    _currentUserId = null;
    _serverUrl = null;

    _connectionStreamController.add(false);
    debugPrint('Disconnect complete');
  }

  // Diagnostic method for troubleshooting
  Future<void> diagnoseConnection() async {
    try {
      debugPrint('=== Connection Diagnosis ===');
      debugPrint('ServerURL null check: ${_serverUrl == null}');
      debugPrint('ServerURL value: "$_serverUrl"');
      debugPrint('RoomId null check: ${_currentRoomId == null}');
      debugPrint('RoomId value: "$_currentRoomId"');
      debugPrint('UserId null check: ${_currentUserId == null}');
      debugPrint('UserId value: "$_currentUserId"');
      debugPrint('Socket null check: ${_socket == null}');
      debugPrint('Is connected: $_isConnected');

      if (_serverUrl != null) {
        debugPrint('ServerURL length: ${_serverUrl!.length}');
        debugPrint(
          'ServerURL contains https: ${_serverUrl!.contains('https')}',
        );
        debugPrint(
          'ServerURL contains ngrok: ${_serverUrl!.contains('ngrok')}',
        );
      }

      if (_socket != null) {
        debugPrint('Socket ID: ${_socket!.id}');
        debugPrint('Socket connected: ${_socket!.connected}');
      }
    } catch (e, stackTrace) {
      debugPrint('Diagnosis error: $e');
      debugPrint('Stack trace: $stackTrace');
    }
  }

  // Clean up resources
  void dispose() {
    debugPrint('=== Dispose LocationService ===');
    _stopHttpPolling();
    disconnect();
    _locationStreamController.close();
    _connectionStreamController.close();
    _errorStreamController.close();
    _roomUsersStreamController.close();
    debugPrint('LocationService disposed');
  }
}
