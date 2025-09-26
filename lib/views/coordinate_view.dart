// ignore_for_file: deprecated_member_use

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import '../widgets/app_text_field.dart';
import '../widgets/action_button.dart';
import '../models/connection_status.dart';
import '../models/user_location.dart';
import '../services/location_service.dart';
import '../views/map_view.dart';

class CoordinateView extends StatefulWidget {
  const CoordinateView({super.key});

  @override
  State<CoordinateView> createState() => _CoordinateViewState();
}

class _CoordinateViewState extends State<CoordinateView> {
  double? latitude;
  double? longitude;
  bool isGettingLocation = false;
  bool isSendingLocation = false;
  String? locationStatus;
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _latitudeController = TextEditingController();
  final TextEditingController _longitudeController = TextEditingController();

  // LocationService instance
  final LocationService _locationService = LocationService();

  // Connection state
  bool _isConnected = false;
  String? _currentRoomId;
  String? _currentUserId;
  List<String> _roomUsers = [];
  int _totalLocationsSent = 0;
  DateTime? _lastLocationSent;

  // Stream subscriptions
  StreamSubscription<ConnectionStatus>? _connectionSubscription;
  StreamSubscription<List<String>>? _roomUsersSubscription;
  StreamSubscription<UserLocation>? _locationUpdateSubscription;
  StreamSubscription<String>? _errorSubscription;

  @override
  void initState() {
    super.initState();
    _setupLocationServiceListeners();
    _checkConnectionStatus();
  }

  void _setupLocationServiceListeners() {
    // Listen to connection status changes
    _connectionSubscription = _locationService.connectionStream.listen((
      connectionStatus,
    ) {
      if (mounted) {
        setState(() {
          _isConnected = connectionStatus.isConnected;
          _currentRoomId = connectionStatus.roomId;
          _currentUserId = connectionStatus.userId;
          _roomUsers = connectionStatus.roomUsers;
        });
      }
    });

    // Listen to room users changes
    _roomUsersSubscription = _locationService.roomUsersStream.listen((users) {
      if (mounted) {
        setState(() {
          _roomUsers = users;
        });
      }
    });

    // Listen to location updates from other users
    _locationUpdateSubscription = _locationService.locationUpdateStream.listen((
      location,
    ) {
      if (mounted) {
        _showLocationReceivedNotification(location);
      }
    });

    // Listen to error messages
    _errorSubscription = _locationService.errorStream.listen((error) {
      if (mounted) {
        _showErrorSnackBar(error);
      }
    });
  }

  void _checkConnectionStatus() {
    // Get current connection status from LocationService
    setState(() {
      _isConnected = _locationService.isConnected;
      _currentRoomId = _locationService.currentRoomId;
      _currentUserId = _locationService.currentUserId;
      _roomUsers = _locationService.roomUsers;
    });
  }

  void _showLocationReceivedNotification(UserLocation location) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(Icons.location_on, color: Colors.white, size: 20),
            SizedBox(width: 8),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'New location from ${location.userId}',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  Text(
                    'Lat: ${location.latitude.toStringAsFixed(6)}, Lng: ${location.longitude.toStringAsFixed(6)}',
                    style: TextStyle(fontSize: 12),
                  ),
                ],
              ),
            ),
          ],
        ),
        backgroundColor: Colors.blue.shade600,
        behavior: SnackBarBehavior.floating,
        duration: Duration(seconds: 3),
        action: SnackBarAction(
          label: 'View Map',
          textColor: Colors.white,
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => const MapView()),
            );
          },
        ),
      ),
    );
  }

  Future<void> _getCurrentLocation() async {
    setState(() {
      isGettingLocation = true;
      locationStatus = "Checking location services...";
    });

    try {
      // Check if location services are enabled
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        setState(() {
          isGettingLocation = false;
          locationStatus = "Location services are disabled";
        });

        // Show dialog to enable location services
        _showLocationServiceDialog();
        return;
      }

      setState(() {
        locationStatus = "Checking location permissions...";
      });

      // Check location permission
      LocationPermission permission = await Geolocator.checkPermission();

      if (permission == LocationPermission.denied) {
        setState(() {
          locationStatus = "Requesting location permission...";
        });

        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          setState(() {
            isGettingLocation = false;
            locationStatus = "Location permission denied";
          });
          _showLocationError(
            "Location permissions are denied. Please grant location permission in your device settings.",
          );
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        setState(() {
          isGettingLocation = false;
          locationStatus = "Location permission permanently denied";
        });
        _showLocationPermissionDialog();
        return;
      }

      setState(() {
        locationStatus = "Getting your location...";
      });

      // Get current position with timeout
      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: Duration(seconds: 30), // Increased timeout for Android
      ).timeout(
        Duration(seconds: 35),
        onTimeout: () {
          throw Exception('Location request timed out. Please try again.');
        },
      );

      setState(() {
        latitude = position.latitude;
        longitude = position.longitude;
        _latitudeController.text = latitude!.toStringAsFixed(6);
        _longitudeController.text = longitude!.toStringAsFixed(6);
        isGettingLocation = false;
        locationStatus =
            "Location obtained successfully (accuracy: ${position.accuracy.toStringAsFixed(1)}m)";
      });

      // Show success message
      _showSuccessMessage();
    } catch (e) {
      setState(() {
        isGettingLocation = false;
        locationStatus = "Error getting location: ${e.toString()}";
      });

      String errorMessage = e.toString();
      if (errorMessage.contains('permissions')) {
        _showLocationPermissionDialog();
      } else if (errorMessage.contains('timeout')) {
        _showLocationTimeoutDialog();
      } else {
        _showLocationError("Error getting current location: $errorMessage");
      }
    }
  }

  void _showLocationServiceDialog() {
    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: Row(
              children: [
                Icon(Icons.location_off, color: Colors.orange.shade600),
                SizedBox(width: 8),
                Text('Enable Location'),
              ],
            ),
            content: Text(
              'Please enable location services in your device settings to get your current location.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text('Ok'),
              ),
            ],
          ),
    );
  }

  void _showLocationPermissionDialog() {
    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: Row(
              children: [
                Icon(Icons.warning, color: Colors.red.shade600),
                SizedBox(width: 8),
                Text('Location Permission Required'),
              ],
            ),
            content: Text(
              'This app needs location permission to get your current coordinates. Please grant location permission in your device settings.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () async {
                  Navigator.of(context).pop();
                  // Open app settings
                  await Geolocator.openAppSettings();
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red.shade600,
                ),
                child: Text(
                  'Open Settings',
                  style: TextStyle(color: Colors.white),
                ),
              ),
            ],
          ),
    );
  }

  void _showLocationTimeoutDialog() {
    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: Row(
              children: [
                Icon(Icons.access_time, color: Colors.orange.shade600),
                SizedBox(width: 8),
                Text('Location Timeout'),
              ],
            ),
            content: Text(
              'Getting your location is taking longer than expected. Please make sure:\n\n'
              '• You are in an area with good GPS signal\n'
              '• Location services are enabled\n'
              '• You are not indoors or under heavy cover',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () {
                  Navigator.of(context).pop();
                  _getCurrentLocation(); // Retry
                },
                child: Text('Try Again'),
              ),
            ],
          ),
    );
  }

  void _showSuccessMessage() {
    if (latitude != null && longitude != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.check_circle, color: Colors.white, size: 20),
                  SizedBox(width: 8),
                  Text(
                    'Location obtained successfully!',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              SizedBox(height: 4),
              Text(
                'Lat: ${latitude!.toStringAsFixed(6)}, Lng: ${longitude!.toStringAsFixed(6)}',
                style: TextStyle(fontSize: 12),
              ),
            ],
          ),
          backgroundColor: Colors.green.shade600,
          behavior: SnackBarBehavior.floating,
          duration: Duration(seconds: 3),
        ),
      );
    }
  }

  Future<void> _sendLocationToServer() async {
    if (!_isConnected) {
      _showErrorSnackBar('Not connected to server. Please connect first.');
      return;
    }

    if (!validateAndSave()) return;

    setState(() {
      isSendingLocation = true;
    });

    try {
      // Send location using LocationService
      final success = await _locationService.shareLocation(
        latitude: latitude!,
        longitude: longitude!,
      );

      setState(() {
        isSendingLocation = false;
      });

      if (success) {
        setState(() {
          _totalLocationsSent++;
          _lastLocationSent = DateTime.now();
        });
        _showLocationSentSuccess();
      } else {
        _showErrorSnackBar('Failed to send location. Please try again.');
      }
    } catch (e) {
      setState(() {
        isSendingLocation = false;
      });
      _showErrorSnackBar('Error sending location: $e');
    }
  }

  void _showLocationSentSuccess() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.check_circle, color: Colors.white, size: 20),
                SizedBox(width: 8),
                Text(
                  'Location sent successfully!',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ],
            ),
            SizedBox(height: 4),
            Text(
              'Lat: ${latitude!.toStringAsFixed(6)}, Lng: ${longitude!.toStringAsFixed(6)}',
              style: TextStyle(fontSize: 12),
            ),
            Text(
              'Shared with ${_roomUsers.length - 1} other users',
              style: TextStyle(fontSize: 12),
            ),
          ],
        ),
        backgroundColor: Colors.green.shade600,
        behavior: SnackBarBehavior.floating,
        duration: Duration(seconds: 4),
      ),
    );
  }

  void _sendManualLocation() {
    _sendLocationToServer();
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

  void _showLocationError(String message) {
    _showErrorSnackBar(message);
  }

  void _showLocationStats() {
    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: Row(
              children: [
                Icon(Icons.analytics, color: Colors.blue.shade600),
                SizedBox(width: 8),
                Text('Location Stats'),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildStatRow('Locations Sent', '$_totalLocationsSent'),
                _buildStatRow(
                  'Last Sent',
                  _lastLocationSent != null
                      ? '${_lastLocationSent!.hour}:${_lastLocationSent!.minute.toString().padLeft(2, '0')}'
                      : 'Never',
                ),
                _buildStatRow('Users in Room', '${_roomUsers.length}'),
                _buildStatRow('Other Users', '${_roomUsers.length - 1}'),
                if (_locationService.userLocations.isNotEmpty) ...[
                  SizedBox(height: 8),
                  Text(
                    'Recent locations:',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  ..._locationService.userLocations.entries
                      .take(3)
                      .map(
                        (entry) => Padding(
                          padding: EdgeInsets.only(left: 8, top: 2),
                          child: Text(
                            '${entry.key}: ${entry.value.latitude.toStringAsFixed(4)}, ${entry.value.longitude.toStringAsFixed(4)}',
                            style: TextStyle(fontSize: 12),
                          ),
                        ),
                      ),
                ],
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text('Close'),
              ),
              if (_locationService.userLocations.isNotEmpty)
                ElevatedButton(
                  onPressed: () {
                    Navigator.of(context).pop();
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (context) => const MapView()),
                    );
                  },
                  child: Text('View All on Map'),
                ),
            ],
          ),
    );
  }

  Widget _buildStatRow(String label, String value) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label),
          Text(value, style: TextStyle(fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _buildConnectionStatus() {
    if (!_isConnected) {
      return Container(
        padding: EdgeInsets.all(12),
        margin: EdgeInsets.only(bottom: 16),
        decoration: BoxDecoration(
          color: Colors.red.shade50,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.red.shade300),
        ),
        child: Row(
          children: [
            Icon(Icons.warning, color: Colors.red.shade600, size: 20),
            SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Not Connected to Server',
                    style: TextStyle(
                      color: Colors.red.shade700,
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                  Text(
                    'Locations won\'t be shared with other users',
                    style: TextStyle(color: Colors.red.shade600, fontSize: 12),
                  ),
                ],
              ),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text('Connect', style: TextStyle(fontSize: 12)),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: EdgeInsets.all(12),
      margin: EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.green.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.green.shade300),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Icon(Icons.check_circle, color: Colors.green.shade600, size: 20),
              SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Connected to Server',
                      style: TextStyle(
                        color: Colors.green.shade700,
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                    Text(
                      'Room: $_currentRoomId | User: $_currentUserId',
                      style: TextStyle(
                        color: Colors.green.shade600,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (_roomUsers.length > 1) ...[
            SizedBox(height: 8),
            Row(
              children: [
                Icon(Icons.people, color: Colors.green.shade600, size: 16),
                SizedBox(width: 8),
                Text(
                  'Online (${_roomUsers.length}): ',
                  style: TextStyle(
                    color: Colors.green.shade600,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                Expanded(
                  child: Text(
                    _roomUsers
                        .where((user) => user != _currentUserId)
                        .join(', '),
                    style: TextStyle(
                      color: Colors.green.shade600,
                      fontSize: 12,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
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
        title: Text('Send Location'),
        actions: [
          // Navigation button to MapView
          IconButton(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const MapView()),
              );
            },
            icon: Icon(Icons.map),
            tooltip: 'View Map',
          ),
          // Location stats
          if (_isConnected)
            IconButton(
              onPressed: _showLocationStats,
              icon: Icon(Icons.analytics),
              tooltip: 'Location Stats',
            ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20.0),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Connection Status
              _buildConnectionStatus(),

              const SizedBox(height: 5),

              if (_totalLocationsSent > 0)
                Text(
                  'Locations sent: $_totalLocationsSent',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12, color: Colors.green.shade600),
                ),

              const SizedBox(height: 24),

              // Current Location Section
              Column(
                children: [
                  Text(
                    'Use Current Location',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: Colors.green.shade700,
                    ),
                  ),
                  const SizedBox(height: 12),
                  ElevatedButton.icon(
                    onPressed: isGettingLocation ? null : _getCurrentLocation,
                    icon:
                        isGettingLocation
                            ? SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  Colors.white,
                                ),
                              ),
                            )
                            : Icon(Icons.my_location),
                    label: Text(
                      isGettingLocation
                          ? 'Getting Location...'
                          : 'Get Current Location',
                      style: TextStyle(fontSize: 16),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green.shade600,
                      foregroundColor: Colors.white,
                      padding: EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 12,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                  if (locationStatus != null) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color:
                            locationStatus!.contains('Error') ||
                                    locationStatus!.contains('denied') ||
                                    locationStatus!.contains('disabled')
                                ? Colors.red.shade50
                                : Colors.green.shade50,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color:
                              locationStatus!.contains('Error') ||
                                      locationStatus!.contains('denied') ||
                                      locationStatus!.contains('disabled')
                                  ? Colors.red.shade300
                                  : Colors.green.shade300,
                        ),
                      ),
                      child: Text(
                        locationStatus!,
                        style: TextStyle(
                          fontSize: 12,
                          color:
                              locationStatus!.contains('Error') ||
                                      locationStatus!.contains('denied') ||
                                      locationStatus!.contains('disabled')
                                  ? Colors.red.shade600
                                  : Colors.green.shade600,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ],
                ],
              ),

              const SizedBox(height: 24),

              // OR Divider
              Row(
                children: [
                  Expanded(child: Divider(color: Colors.green.shade300)),
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16),
                    child: Text(
                      'OR',
                      style: TextStyle(
                        color: Colors.green.shade600,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  Expanded(child: Divider(color: Colors.green.shade300)),
                ],
              ),

              const SizedBox(height: 24),

              // Manual Input Section
              Column(
                children: [
                  Text(
                    'Enter Coordinates Manually',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: Colors.green.shade700,
                    ),
                  ),
                  const SizedBox(height: 16),

                  AppTextField(
                    controller: _latitudeController,
                    label: 'Latitude',
                    hint: 'Enter latitude (-90 to 90)',
                    icon: Icons.location_on,
                    minValue: -90,
                    maxValue: 90,
                    onSaved: (value) {
                      latitude = double.parse(value!);
                    },
                  ),

                  const SizedBox(height: 16),
                  AppTextField(
                    controller: _longitudeController,
                    label: 'Longitude',
                    hint: 'Enter longitude (-180 to 180)',
                    icon: Icons.location_on,
                    minValue: -180,
                    maxValue: 180,
                    onSaved: (value) {
                      latitude = double.parse(value!);
                    },
                  ),
                  const SizedBox(height: 20),

                  // Send Location to Room (with loading & disabled state)
                  ActionButton(
                    label:
                        isSendingLocation
                            ? 'Sending Location...'
                            : !_isConnected
                            ? 'Connect to Server First'
                            : 'Send Location to Room',
                    icon: Icons.send,
                    backgroundColor:
                        !_isConnected
                            ? Colors.grey.shade400
                            : Colors.blue.shade600,
                    foregroundColor: Colors.white,
                    isLoading: isSendingLocation,
                    onPressed:
                        (isSendingLocation ||
                                latitude == null ||
                                longitude == null ||
                                !_isConnected)
                            ? null
                            : _sendManualLocation,
                    height: 50,
                    borderRadius: 8,
                  ),
                ],
              ),

              const SizedBox(height: 24),

              // Help text
              if (!_isConnected)
                Container(
                  padding: EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.blue.shade300),
                  ),
                  child: Column(
                    children: [
                      Icon(Icons.info, color: Colors.blue.shade600),
                      SizedBox(height: 8),
                      Text(
                        'Connect to server first to share your location with other users in real-time!',
                        style: TextStyle(
                          color: Colors.blue.shade700,
                          fontSize: 12,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _latitudeController.dispose();
    _longitudeController.dispose();

    // Cancel stream subscriptions
    _connectionSubscription?.cancel();
    _roomUsersSubscription?.cancel();
    _locationUpdateSubscription?.cancel();
    _errorSubscription?.cancel();

    super.dispose();
  }

  bool validateAndSave() {
    final form = _formKey.currentState;
    if (form!.validate()) {
      form.save();
      return true;
    } else {
      return false;
    }
  }
}
