import 'dart:async';
import 'package:flutter/material.dart';
import '../widgets/app_text_field.dart';
import '../widgets/action_button.dart';
import '../models/connection_status.dart';
import '../services/location_service.dart';
import '../views/coordinate_view.dart';
import '../views/map_view.dart';

class Homepage extends StatefulWidget {
  const Homepage({super.key});

  @override
  State<Homepage> createState() => _HomepageState();
}

class _HomepageState extends State<Homepage> {
  final TextEditingController _serverUrlController = TextEditingController();
  final TextEditingController _roomIdController = TextEditingController();
  final TextEditingController _userIdController = TextEditingController();

  // LocationService instance
  final LocationService _locationService = LocationService();

  // Connection state
  bool _isConnecting = false;
  bool _isConnected = false;
  String? _connectionStatus;
  List<String> _roomUsers = [];

  // Stream subscriptions
  StreamSubscription<ConnectionStatus>? _connectionSubscription;
  StreamSubscription<List<String>>? _roomUsersSubscription;
  StreamSubscription<String>? _errorSubscription;

  @override
  void initState() {
    super.initState();

    // Set default values for testing
    _serverUrlController.text = '';
    _roomIdController.text = '';
    _userIdController.text = '';

    // Initialize LocationService listeners
    _setupLocationServiceListeners();

    // Check if already connected
    _checkExistingConnection();
  }

  void _setupLocationServiceListeners() {
    // Listen to connection status changes
    _connectionSubscription = _locationService.connectionStream.listen(
      (connectionStatus) {
        if (mounted) {
          setState(() {
            _isConnected = connectionStatus.isConnected;
            _connectionStatus = connectionStatus.message;
            _roomUsers = connectionStatus.roomUsers;

            if (connectionStatus.isConnected) {
              _isConnecting = false;
            }
          });

          // Show connection success/failure messages
          if (connectionStatus.isConnected && connectionStatus.roomId != null) {
            _showSuccessSnackBar(
              'Connected to room: ${connectionStatus.roomId}',
            );
          } else if (!connectionStatus.isConnected &&
              connectionStatus.message != null) {
            _showErrorSnackBar(connectionStatus.message!);
          }
        }
      },
      onError: (error) {
        if (mounted) {
          setState(() {
            _isConnecting = false;
            _isConnected = false;
            _connectionStatus = 'Connection error: $error';
          });
          _showErrorSnackBar('Connection failed: $error');
        }
      },
    );

    // Listen to room users changes
    _roomUsersSubscription = _locationService.roomUsersStream.listen((users) {
      if (mounted) {
        setState(() {
          _roomUsers = users;
        });
      }
    });

    // Listen to error messages
    _errorSubscription = _locationService.errorStream.listen((error) {
      if (mounted) {
        _showErrorSnackBar(error);
      }
    });
  }

  void _checkExistingConnection() {
    // Check if LocationService is already connected
    if (_locationService.isConnected) {
      setState(() {
        _isConnected = true;
        _connectionStatus = 'Already connected';
        _roomUsers = _locationService.roomUsers;

        // Update controllers with current connection info
        if (_locationService.serverUrl != null) {
          _serverUrlController.text = _locationService.serverUrl!;
        }
        if (_locationService.currentRoomId != null) {
          _roomIdController.text = _locationService.currentRoomId!;
        }
        if (_locationService.currentUserId != null) {
          _userIdController.text = _locationService.currentUserId!;
        }
      });
    }
  }

  Future<void> _connectToServer() async {
    final serverUrl = _serverUrlController.text.trim();
    final roomId = _roomIdController.text.trim();
    final userId = _userIdController.text.trim();

    // Validation
    if (serverUrl.isEmpty || roomId.isEmpty || userId.isEmpty) {
      _showErrorDialog('Please fill in all fields');
      return;
    }

    // Basic URL validation
    if (!_isValidUrl(serverUrl)) {
      _showErrorDialog(
        'Please enter a valid server URL (e.g., https://abc123.ngrok.io)',
      );
      return;
    }

    // User ID validation (no spaces, special characters)
    if (!_isValidUserId(userId)) {
      _showErrorDialog(
        'User ID should contain only letters, numbers, and underscores',
      );
      return;
    }

    setState(() {
      _isConnecting = true;
      _connectionStatus = 'Connecting to server...';
    });

    try {
      // Attempt connection using LocationService
      final success = await _locationService.connectToServer(
        serverUrl: serverUrl,
        roomId: roomId,
        userId: userId,
      );

      if (!success) {
        setState(() {
          _isConnecting = false;
          _isConnected = false;
          _connectionStatus = 'Failed to connect to server';
        });
      }
      // Success handling is done through the stream listener
    } catch (e) {
      setState(() {
        _isConnecting = false;
        _isConnected = false;
        _connectionStatus = 'Connection error: $e';
      });
      _showErrorSnackBar('Connection failed: $e');
    }
  }

  Future<void> _disconnect() async {
    setState(() {
      _isConnecting = true;
      _connectionStatus = 'Disconnecting...';
    });

    try {
      await _locationService.disconnect();

      setState(() {
        _isConnected = false;
        _isConnecting = false;
        _connectionStatus = null;
        _roomUsers.clear();
      });

      _showSuccessSnackBar('Disconnected successfully');
    } catch (e) {
      setState(() {
        _isConnecting = false;
      });
      _showErrorSnackBar('Disconnect failed: $e');
    }
  }

  bool _isValidUrl(String url) {
    try {
      final uri = Uri.parse(url);
      return uri.hasScheme && (uri.scheme == 'http' || uri.scheme == 'https');
    } catch (e) {
      return false;
    }
  }

  bool _isValidUserId(String userId) {
    // Allow letters, numbers, and underscores only
    final regex = RegExp(r'^[a-zA-Z0-9_]+$');
    return regex.hasMatch(userId) && userId.length >= 2 && userId.length <= 20;
  }

  void _showSuccessSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(Icons.check_circle, color: Colors.white, size: 20),
            SizedBox(width: 8),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: Colors.green.shade600,
        behavior: SnackBarBehavior.floating,
        duration: Duration(seconds: 3),
      ),
    );
  }

  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(Icons.error, color: Colors.white, size: 20),
            SizedBox(width: 8),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: Colors.red.shade600,
        behavior: SnackBarBehavior.floating,
        duration: Duration(seconds: 4),
      ),
    );
  }

  void _showErrorDialog(String message) {
    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: Row(
              children: [
                Icon(Icons.warning, color: Colors.orange.shade600),
                SizedBox(width: 8),
                Text('Input Error'),
              ],
            ),
            content: Text(message),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text('OK'),
              ),
            ],
          ),
    );
  }

  void _showConnectionInfo() {
    if (!_isConnected) return;

    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: Row(
              children: [
                Icon(Icons.info, color: Colors.blue.shade600),
                SizedBox(width: 8),
                Text('Connection Info'),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildInfoRow(
                  'Server',
                  _locationService.serverUrl ?? 'Unknown',
                ),
                _buildInfoRow(
                  'Room ID',
                  _locationService.currentRoomId ?? 'Unknown',
                ),
                _buildInfoRow(
                  'Your ID',
                  _locationService.currentUserId ?? 'Unknown',
                ),
                _buildInfoRow('Users Online', '${_roomUsers.length}'),
                SizedBox(height: 8),
                Text(
                  'Users in room:',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                SizedBox(height: 4),
                ..._roomUsers.map((user) => Text('• $user')).toList(),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text('Close'),
              ),
            ],
          ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 70,
            child: Text(
              '$label:',
              style: TextStyle(fontWeight: FontWeight.w500),
            ),
          ),
          Expanded(
            child: Text(value, style: TextStyle(color: Colors.grey.shade700)),
          ),
        ],
      ),
    );
  }

  Widget _buildConnectionSection() {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Server Connection',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.green.shade700,
                ),
              ),
              if (_isConnected)
                IconButton(
                  onPressed: _showConnectionInfo,
                  icon: Icon(Icons.info_outline),
                  tooltip: 'Connection Info',
                ),
            ],
          ),
          const SizedBox(height: 16),

          // Server URL field
          AppTextField(
            controller: _serverUrlController,
            label: 'Server URL (ngrok)',
            hint: 'https://abc123.ngrok.io',
            icon: Icons.cloud,
            helperText: 'Use your ngrok URL here',
            enabled: !_isConnected && !_isConnecting,
            keyboardType: TextInputType.url,
          ),

          const SizedBox(height: 12),

          // Room ID field
          AppTextField(
            controller: _roomIdController,
            label: 'Room ID',
            hint: 'Enter room ID to share with friends',
            icon: Icons.cloud,
            helperText: 'Share this ID with others to connect',
            enabled: !_isConnected && !_isConnecting,
          ),

          const SizedBox(height: 12),

          // User ID field
          AppTextField(
            controller: _userIdController,
            label: 'Your Name/ID',
            hint: 'Enter your unique identifier',
            icon: Icons.person,
            helperText: 'Letters, numbers, and underscores only',
            enabled: !_isConnected && !_isConnecting,
            maxLength: 20,
          ),

          const SizedBox(height: 16),

          // Connection button
          ElevatedButton.icon(
            onPressed:
                _isConnecting
                    ? null
                    : (_isConnected ? _disconnect : _connectToServer),
            icon:
                _isConnecting
                    ? SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                    : Icon(
                      _isConnected
                          ? Icons.logout
                          : Icons.connect_without_contact,
                    ),
            label: Text(
              _isConnecting
                  ? 'Connecting...'
                  : (_isConnected ? 'Disconnect' : 'Connect to Server'),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor:
                  _isConnected ? Colors.red.shade600 : Colors.green.shade600,
              foregroundColor: Colors.white,
              padding: EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),

          // Connection status
          if (_connectionStatus != null) ...[
            const SizedBox(height: 8),
            Container(
              padding: EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: _isConnected ? Colors.green.shade50 : Colors.red.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color:
                      _isConnected
                          ? Colors.green.shade300
                          : Colors.red.shade300,
                ),
              ),
              child: Row(
                children: [
                  _isConnecting
                      ? SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.blue.shade600,
                        ),
                      )
                      : Icon(
                        _isConnected ? Icons.check_circle : Icons.error,
                        color:
                            _isConnected
                                ? Colors.green.shade600
                                : Colors.red.shade600,
                        size: 16,
                      ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _connectionStatus!,
                      style: TextStyle(
                        color:
                            _isConnected
                                ? Colors.green.shade600
                                : Colors.red.shade600,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],

          // Health check button (optional)
          if (_isConnected) ...[
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: () async {
                final isHealthy = await _locationService.checkServerHealth();
                _showSuccessSnackBar(
                  isHealthy
                      ? 'Server connection is healthy'
                      : 'Server connection issues detected',
                );
              },
              icon: Icon(Icons.health_and_safety, size: 16),
              label: Text('Check Connection', style: TextStyle(fontSize: 12)),
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.green.shade600,
        foregroundColor: Colors.white,
        title: Text('Map Nudge'),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Connection Section
              _buildConnectionSection(),

              const SizedBox(height: 32),

              // Navigation Buttons (only show when connected)
              if (_isConnected) ...[
                // Send Location Button
                ActionButton(
                  label: 'Send Location',
                  icon: Icons.send,
                  backgroundColor: Colors.green.shade600,
                  foregroundColor: Colors.white,
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (context) => CoordinateView()),
                    );
                  },
                ),

                const SizedBox(height: 16),

                // View Map Button
                ActionButton(
                  label: 'View Map',
                  icon: Icons.map,
                  backgroundColor: Colors.blue.shade600,
                  foregroundColor: Colors.white,
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (context) => MapView()),
                    );
                  },
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _serverUrlController.dispose();
    _roomIdController.dispose();
    _userIdController.dispose();

    // Cancel stream subscriptions
    _connectionSubscription?.cancel();
    _roomUsersSubscription?.cancel();
    _errorSubscription?.cancel();

    super.dispose();
  }
}
