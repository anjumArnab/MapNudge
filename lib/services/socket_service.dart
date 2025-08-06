import 'dart:async';
import 'dart:convert';
import 'package:socket_io_client/socket_io_client.dart' as IO;

enum ClientRole { mapViewer, coordinateSender }

class SocketService {
  static final SocketService _instance = SocketService._internal();
  factory SocketService() => _instance;
  SocketService._internal();

  IO.Socket? _socket;
  bool _isConnected = false;
  String? _clientId;
  ClientRole? _currentRole;
  String _roomId = 'default-room';

  // Stream controllers for different events
  final StreamController<bool> _connectionController =
      StreamController<bool>.broadcast();
  final StreamController<Map<String, dynamic>> _positionChangeController =
      StreamController<Map<String, dynamic>>.broadcast();
  final StreamController<Map<String, dynamic>> _positionRequestController =
      StreamController<Map<String, dynamic>>.broadcast();
  final StreamController<Map<String, dynamic>> _clientJoinedController =
      StreamController<Map<String, dynamic>>.broadcast();
  final StreamController<Map<String, dynamic>> _clientLeftController =
      StreamController<Map<String, dynamic>>.broadcast();
  final StreamController<Map<String, dynamic>> _errorController =
      StreamController<Map<String, dynamic>>.broadcast();
  final StreamController<Map<String, dynamic>> _positionSentController =
      StreamController<Map<String, dynamic>>.broadcast();
  final StreamController<Map<String, dynamic>> _identifiedController =
      StreamController<Map<String, dynamic>>.broadcast();

  // Getters for streams
  Stream<bool> get connectionStream => _connectionController.stream;
  Stream<Map<String, dynamic>> get positionChangeStream =>
      _positionChangeController.stream;
  Stream<Map<String, dynamic>> get positionRequestStream =>
      _positionRequestController.stream;
  Stream<Map<String, dynamic>> get clientJoinedStream =>
      _clientJoinedController.stream;
  Stream<Map<String, dynamic>> get clientLeftStream =>
      _clientLeftController.stream;
  Stream<Map<String, dynamic>> get errorStream => _errorController.stream;
  Stream<Map<String, dynamic>> get positionSentStream =>
      _positionSentController.stream;
  Stream<Map<String, dynamic>> get identifiedStream =>
      _identifiedController.stream;

  // Getters
  bool get isConnected => _isConnected;
  String? get clientId => _clientId;
  ClientRole? get currentRole => _currentRole;
  String get roomId => _roomId;

  Future<void> connect({
    String serverUrl = "http://localhost:3200",
    String? customRoomId,
  }) async {
    if (_isConnected && _socket != null) {
      print('Already connected to socket');
      return;
    }

    if (customRoomId != null) {
      _roomId = customRoomId;
    }

    try {
      _socket = IO.io(serverUrl, <String, dynamic>{
        'transports': ['websocket', 'polling'],
        'autoConnect': true,
      });

      _socket!.connect();

      // Set up event listeners
      _setupEventListeners();

      print('Socket connection initiated to $serverUrl');
    } catch (e) {
      print('Socket initialization error: $e');
      _errorController.add({
        'type': 'connection_error',
        'message': 'Failed to initialize socket connection: $e',
      });
    }
  }

  void _setupEventListeners() {
    if (_socket == null) return;

    _socket!.onConnect((data) {
      print('Connected: ${_socket!.id}');
      _clientId = _socket!.id;
      _isConnected = true;
      _connectionController.add(true);
    });

    _socket!.onDisconnect((data) {
      print('Disconnected: $data');
      _isConnected = false;
      _clientId = null;
      _currentRole = null;
      _connectionController.add(false);
    });

    _socket!.on('identified', (data) {
      print('Identified successfully: $data');
      _identifiedController.add(
        data is Map<String, dynamic> ? data : {'data': data},
      );
    });

    _socket!.on('position-change', (data) {
      print('Received position data: $data');
      try {
        Map<String, dynamic> positionData;
        if (data is String) {
          positionData = jsonDecode(data);
        } else if (data is Map<String, dynamic>) {
          positionData = data;
        } else {
          positionData = {'data': data};
        }
        _positionChangeController.add(positionData);
      } catch (e) {
        print('Error processing position data: $e');
        _errorController.add({
          'type': 'position_processing_error',
          'message': 'Failed to process position data: $e',
        });
      }
    });

    _socket!.on('position-request', (data) {
      print('Position requested by: $data');
      _positionRequestController.add(
        data is Map<String, dynamic> ? data : {'data': data},
      );
    });

    _socket!.on('position-sent', (data) {
      print('Position sent confirmation: $data');
      _positionSentController.add(
        data is Map<String, dynamic> ? data : {'data': data},
      );
    });

    _socket!.on('client-joined', (data) {
      print('Client joined: $data');
      _clientJoinedController.add(
        data is Map<String, dynamic> ? data : {'data': data},
      );
    });

    _socket!.on('client-left', (data) {
      print('Client left: $data');
      _clientLeftController.add(
        data is Map<String, dynamic> ? data : {'data': data},
      );
    });

    _socket!.on('error', (data) {
      print('Socket error: $data');
      Map<String, dynamic> errorData;
      if (data is Map<String, dynamic>) {
        errorData = data;
      } else {
        errorData = {'message': data?.toString() ?? 'Unknown error'};
      }
      _errorController.add(errorData);
    });
  }

  Future<void> identify(ClientRole role, {String? customRoomId}) async {
    if (!_isConnected || _socket == null) {
      print('Cannot identify: Socket not connected');
      return;
    }

    if (customRoomId != null) {
      _roomId = customRoomId;
    }

    _currentRole = role;

    final String roleString =
        role == ClientRole.mapViewer ? 'map-viewer' : 'coordinate-sender';

    _socket!.emit('identify', {'role': roleString, 'roomId': _roomId});

    print('Identifying as $roleString in room $_roomId');
  }

  void sendPosition(double latitude, double longitude) {
    if (!_isConnected || _socket == null) {
      print('Cannot send position: Socket not connected');
      _errorController.add({
        'type': 'connection_error',
        'message': 'Not connected to server',
      });
      return;
    }

    final coords = {"lat": latitude, "lng": longitude};

    _socket!.emit('position-change', coords);
    print('Position sent: $coords');
  }

  void requestPosition() {
    if (!_isConnected || _socket == null) {
      print('Cannot request position: Socket not connected');
      _errorController.add({
        'type': 'connection_error',
        'message': 'Not connected to server',
      });
      return;
    }

    _socket!.emit('request-position');
    print('Position request sent');
  }

  void joinRoom(String roomId) {
    if (!_isConnected || _socket == null) {
      print('Cannot join room: Socket not connected');
      return;
    }

    _roomId = roomId;
    _socket!.emit('join-room', {'roomId': roomId});
    print('Joined room: $roomId');
  }

  void leaveRoom(String roomId) {
    if (!_isConnected || _socket == null) {
      print('Cannot leave room: Socket not connected');
      return;
    }

    _socket!.emit('leave-room', {'roomId': roomId});
    print('Left room: $roomId');
  }

  void disconnect() {
    if (_socket != null) {
      _socket!.disconnect();
      _socket = null;
    }
    _isConnected = false;
    _clientId = null;
    _currentRole = null;
    print('Socket disconnected manually');
  }

  void dispose() {
    disconnect();
    _connectionController.close();
    _positionChangeController.close();
    _positionRequestController.close();
    _clientJoinedController.close();
    _clientLeftController.close();
    _errorController.close();
    _positionSentController.close();
    _identifiedController.close();
  }
}
