import 'package:flutter/material.dart';
import '../views/coordinate_view.dart';
import '../views/map_view.dart';
import '../services/location_service.dart';

class Homepage extends StatefulWidget {
  const Homepage({super.key});

  @override
  State<Homepage> createState() => _HomepageState();
}

class _HomepageState extends State<Homepage> {
  final LocationService _locationService = LocationService.instance;
  final TextEditingController _serverUrlController = TextEditingController();
  final TextEditingController _roomIdController = TextEditingController();
  final TextEditingController _userIdController = TextEditingController();

  bool _isConnecting = false;
  bool _isConnected = false;
  String? _connectionStatus;
  List<String> _roomUsers = [];

  @override
  void initState() {
    super.initState();
    _setupListeners();

    // Set default values for testing
    _serverUrlController.text =
        'http://localhost:3000'; // Change this to your ngrok URL
    _roomIdController.text = 'room123';
    _userIdController.text =
        'user${DateTime.now().millisecondsSinceEpoch % 1000}';
  }

  void _setupListeners() {
    // Listen for connection status
    _locationService.connectionStream.listen((connected) {
      if (mounted) {
        setState(() {
          _isConnected = connected;
          _connectionStatus =
              connected ? 'Connected successfully!' : 'Disconnected';
          if (!connected) {
            _roomUsers.clear();
          }
        });
      }
    });

    // Listen for errors
    _locationService.errorStream.listen((error) {
      if (mounted) {
        setState(() {
          _connectionStatus = error;
          _isConnecting = false;
        });
        _showErrorDialog(error);
      }
    });

    // Listen for room users updates
    _locationService.roomUsersStream.listen((users) {
      if (mounted) {
        setState(() {
          _roomUsers = users;
        });
      }
    });
  }

  Future<void> _connectToServer() async {
    final serverUrl = _serverUrlController.text.trim();
    final roomId = _roomIdController.text.trim();
    final userId = _userIdController.text.trim();

    if (serverUrl.isEmpty || roomId.isEmpty || userId.isEmpty) {
      _showErrorDialog('Please fill in all fields');
      return;
    }

    setState(() {
      _isConnecting = true;
      _connectionStatus = 'Connecting...';
    });

    // Test connection first
    bool canConnect = await _locationService.testConnection(serverUrl);
    if (!canConnect) {
      setState(() {
        _isConnecting = false;
        _connectionStatus = 'Server not reachable';
      });
      _showErrorDialog('Cannot reach server. Please check the URL.');
      return;
    }

    // Connect to server
    bool connected = await _locationService.connectToServer(
      serverUrl: serverUrl,
      roomId: roomId,
      userId: userId,
    );

    setState(() {
      _isConnecting = false;
    });

    if (connected) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Connected to room: $roomId'),
          backgroundColor: Colors.green.shade600,
        ),
      );
    }
  }

  Future<void> _disconnect() async {
    await _locationService.disconnect();
    setState(() {
      _connectionStatus = null;
      _roomUsers.clear();
    });
  }

  void _showErrorDialog(String message) {
    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: Text('Connection Error'),
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

  Widget _buildConnectionSection() {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Server Connection',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.green.shade700,
              ),
            ),
            const SizedBox(height: 16),

            // Server URL field
            TextField(
              controller: _serverUrlController,
              decoration: InputDecoration(
                labelText: 'Server URL (ngrok)',
                hintText: 'https://your-ngrok-url.ngrok.io',
                prefixIcon: Icon(Icons.cloud),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              enabled: !_isConnected,
            ),

            const SizedBox(height: 12),

            // Room ID field
            TextField(
              controller: _roomIdController,
              decoration: InputDecoration(
                labelText: 'Room ID',
                hintText: 'Enter room ID',
                prefixIcon: Icon(Icons.meeting_room),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              enabled: !_isConnected,
            ),

            const SizedBox(height: 12),

            // User ID field
            TextField(
              controller: _userIdController,
              decoration: InputDecoration(
                labelText: 'Your Name',
                hintText: 'Enter your name',
                prefixIcon: Icon(Icons.person),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              enabled: !_isConnected,
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
                            ? Icons.arrow_back_ios
                            : Icons.connect_without_contact,
                      ),
              label: Text(
                _isConnecting
                    ? 'Connecting...'
                    : (_isConnected ? 'Disconnect' : 'Connect'),
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
                  color:
                      _isConnected ? Colors.green.shade50 : Colors.red.shade50,
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
                    Icon(
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

            // Room users
            if (_isConnected && _roomUsers.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                'Users in room (${_roomUsers.length}):',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: Colors.green.shade700,
                ),
              ),
              const SizedBox(height: 4),
              Wrap(
                spacing: 8,
                children:
                    _roomUsers
                        .map(
                          (user) => Chip(
                            label: Text(user, style: TextStyle(fontSize: 12)),
                            backgroundColor: Colors.green.shade100,
                            materialTapTargetSize:
                                MaterialTapTargetSize.shrinkWrap,
                          ),
                        )
                        .toList(),
              ),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.green.shade50,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // App Icon and Title
              Icon(Icons.location_on, size: 80, color: Colors.green.shade600),
              const SizedBox(height: 16),

              Text(
                'MapNudge',
                style: TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                  color: Colors.green.shade700,
                ),
              ),

              const SizedBox(height: 8),

              Text(
                'Share and View Locations',
                style: TextStyle(fontSize: 16, color: Colors.green.shade600),
              ),

              const SizedBox(height: 32),

              // Connection Section
              _buildConnectionSection(),

              const SizedBox(height: 32),

              // Navigation Buttons (only show when connected)
              if (_isConnected) ...[
                // Send Location Button
                SizedBox(
                  width: double.infinity,
                  height: 60,
                  child: ElevatedButton.icon(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => CoordinateView(),
                        ),
                      );
                    },
                    icon: const Icon(Icons.send),
                    label: const Text(
                      'Send Location',
                      style: TextStyle(fontSize: 18),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green.shade600,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 16),

                // View Map Button
                SizedBox(
                  width: double.infinity,
                  height: 60,
                  child: ElevatedButton.icon(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (context) => MapView()),
                      );
                    },
                    icon: const Icon(Icons.map),
                    label: const Text(
                      'View Map',
                      style: TextStyle(fontSize: 18),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue.shade600,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
              ] else ...[
                // Show connection required message
                Text(
                  'Please connect to a server to start sharing locations',
                  style: TextStyle(
                    color: Colors.orange.shade700,
                    fontWeight: FontWeight.w500,
                  ),
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
    super.dispose();
  }
}
