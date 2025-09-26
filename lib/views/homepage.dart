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

  // Page controller for swipe functionality
  final PageController _pageController = PageController();
  int _currentPage = 0;

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
              // Auto-navigate to third section when connected
              _animateToPage(2);
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

  void _animateToPage(int page) {
    _pageController.animateToPage(
      page,
      duration: Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
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

      // Navigate back to connection section after disconnect
      _animateToPage(1);
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

  // Section 1: App Introduction
  Widget _buildIntroSection() {
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // App Title
          Text(
            'Map Nudge',
            style: TextStyle(
              fontSize: 32,
              fontWeight: FontWeight.bold,
              color: Colors.green.shade700,
            ),
          ),

          SizedBox(height: 16),

          // App Description
          Text(
            'Map Nudge is a location sharing application. First establish connection with server and share your location then show it on map.',
            style: TextStyle(
              fontSize: 16,
              color: Colors.grey.shade600,
              height: 1.5,
            ),
            textAlign: TextAlign.center,
          ),

          SizedBox(height: 48),

          // Get Started Button
          ElevatedButton.icon(
            onPressed: () => _animateToPage(1),
            label: Text('Get Started'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green.shade600,
              foregroundColor: Colors.white,
              padding: EdgeInsets.symmetric(horizontal: 32, vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              textStyle: TextStyle(fontSize: 16),
            ),
          ),
        ],
      ),
    );
  }

  // Section 2: Connection Section (existing _buildConnectionSection)
  Widget _buildConnectionSection() {
    return Padding(
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
        ],
      ),
    );
  }

  // Section 3: Actions Section
  Widget _buildActionsSection() {
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Room Info
          Container(
            padding: EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              children: [
                Text(
                  'Room: ${_locationService.currentRoomId ?? "Unknown"}',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey.shade700,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  '${_roomUsers.length} user(s) online',
                  style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
                ),
              ],
            ),
          ),

          SizedBox(height: 48),

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
      ),
    );
  }

  // Page Indicator Dots
  Widget _buildPageIndicator() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(
        _isConnected ? 3 : 2, // Show 3 dots only when connected
        (index) => Container(
          margin: EdgeInsets.symmetric(horizontal: 4),
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color:
                _currentPage == index
                    ? Colors.green.shade600
                    : Colors.grey.shade300,
          ),
        ),
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
      body: Column(
        children: [
          Expanded(
            child: PageView(
              controller: _pageController,
              onPageChanged: (index) {
                // Prevent accessing third page if not connected
                if (index == 2 && !_isConnected) {
                  _animateToPage(_currentPage);
                  return;
                }
                setState(() {
                  _currentPage = index;
                });
              },
              children: [
                // Section 1: App Introduction
                SafeArea(child: _buildIntroSection()),

                // Section 2: Connection Section
                SafeArea(
                  child: SingleChildScrollView(
                    child: _buildConnectionSection(),
                  ),
                ),

                // Section 3: Actions Section (only accessible when connected)
                if (_isConnected) SafeArea(child: _buildActionsSection()),
              ],
            ),
          ),

          // Page Indicator
          Container(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: _buildPageIndicator(),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _serverUrlController.dispose();
    _roomIdController.dispose();
    _userIdController.dispose();
    _pageController.dispose();

    // Cancel stream subscriptions
    _connectionSubscription?.cancel();
    _roomUsersSubscription?.cancel();
    _errorSubscription?.cancel();

    super.dispose();
  }
}
