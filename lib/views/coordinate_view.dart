import 'dart:async';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import '../views/map_view.dart';
import '../widgets/custom_coordinate_fields.dart';
import '../widgets/send_location_button.dart';
import '../services/socket_service.dart'; // Import the socket service

class CoordinateView extends StatefulWidget {
  const CoordinateView({super.key});

  @override
  State<CoordinateView> createState() => _CoordinateViewState();
}

class _CoordinateViewState extends State<CoordinateView> {
  final SocketService _socketService = SocketService();
  double? latitude;
  double? longitude;
  bool isGettingLocation = false;
  String? locationStatus;
  bool isConnected = false;
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _latitudeController = TextEditingController();
  final TextEditingController _longitudeController = TextEditingController();

  // Stream subscriptions
  StreamSubscription<bool>? _connectionSubscription;
  StreamSubscription<Map<String, dynamic>>? _identifiedSubscription;
  StreamSubscription<Map<String, dynamic>>? _positionSentSubscription;
  StreamSubscription<Map<String, dynamic>>? _errorSubscription;

  @override
  void initState() {
    super.initState();
    _initializeSocketService();
  }

  Future<void> _initializeSocketService() async {
    // Set up stream subscriptions
    _connectionSubscription = _socketService.connectionStream.listen((
      connected,
    ) {
      setState(() {
        isConnected = connected;
      });

      if (connected) {
        // Identify as coordinate sender when connected
        _socketService.identify(ClientRole.coordinateSender);
      }
    });

    _identifiedSubscription = _socketService.identifiedStream.listen((data) {
      print('Identified successfully: $data');
    });

    _positionSentSubscription = _socketService.positionSentStream.listen((
      data,
    ) {
      print('Position sent confirmation: $data');
    });

    _errorSubscription = _socketService.errorStream.listen((error) {
      _showError('Error: ${error['message'] ?? 'Unknown error'}');
    });

    // Connect to the socket server
    await _socketService.connect();
  }

  Future<void> _getCurrentLocation() async {
    setState(() {
      isGettingLocation = true;
      locationStatus = "Getting current location...";
    });

    try {
      // Check if location services are enabled
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        setState(() {
          isGettingLocation = false;
          locationStatus = "Location services are disabled";
        });
        _showLocationError(
          "Location services are disabled. Please enable location services.",
        );
        return;
      }

      // Check location permission
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          setState(() {
            isGettingLocation = false;
            locationStatus = "Location permission denied";
          });
          _showLocationError(
            "Location permissions are denied. Please grant location permission.",
          );
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        setState(() {
          isGettingLocation = false;
          locationStatus = "Location permission permanently denied";
        });
        _showLocationError(
          "Location permissions are permanently denied. Please enable them in settings.",
        );
        return;
      }

      // Get current position
      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: Duration(seconds: 10),
      );

      setState(() {
        latitude = position.latitude;
        longitude = position.longitude;
        _latitudeController.text = latitude!.toStringAsFixed(6);
        _longitudeController.text = longitude!.toStringAsFixed(6);
        isGettingLocation = false;
        locationStatus = "Location obtained successfully";
      });

      // Automatically send the current location
      _sendCurrentLocation();
    } catch (e) {
      setState(() {
        isGettingLocation = false;
        locationStatus = "Error getting location: ${e.toString()}";
      });
      _showLocationError("Error getting current location: ${e.toString()}");
    }
  }

  void _sendCurrentLocation() {
    if (latitude != null && longitude != null && isConnected) {
      _socketService.sendPosition(latitude!, longitude!);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Current location sent successfully!\nLat: ${latitude!.toStringAsFixed(6)}, Lng: ${longitude!.toStringAsFixed(6)}',
          ),
          backgroundColor: Colors.green.shade600,
          behavior: SnackBarBehavior.floating,
          duration: Duration(seconds: 3),
        ),
      );
    } else if (!isConnected) {
      _showLocationError("Not connected to server. Please wait...");
    }
  }

  void _sendManualLocation() {
    if (!isConnected) {
      _showError("Not connected to server. Please wait...");
      return;
    }

    if (validateAndSave()) {
      _socketService.sendPosition(latitude!, longitude!);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Location sent successfully!'),
          backgroundColor: Colors.green.shade600,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  void _showLocationError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red.shade600,
        behavior: SnackBarBehavior.floating,
        duration: Duration(seconds: 4),
      ),
    );
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red.shade600,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.green.shade50,
      appBar: AppBar(
        backgroundColor: Colors.green.shade600,
        foregroundColor: Colors.white,
        title: Text('Coordinate Sender'),
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
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20.0),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 32),

              Text(
                'MapNudge',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                  color: Colors.green.shade700,
                  letterSpacing: 1.2,
                ),
              ),

              // Connection status indicator
              Container(
                margin: EdgeInsets.only(top: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      isConnected ? Icons.wifi : Icons.wifi_off,
                      color: isConnected ? Colors.green : Colors.red,
                      size: 16,
                    ),
                    SizedBox(width: 4),
                    Text(
                      isConnected ? 'Connected' : 'Connecting...',
                      style: TextStyle(
                        color: isConnected ? Colors.green : Colors.red,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 32),

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
                    onPressed:
                        (isGettingLocation || !isConnected)
                            ? null
                            : _getCurrentLocation,
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
                          : !isConnected
                          ? 'Connecting...'
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
                    Text(
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
                  CustomCoordinateField(
                    controller: _latitudeController,
                    label: 'Latitude',
                    hint: 'Enter latitude',
                    minValue: -90,
                    maxValue: 90,
                    icon: Icons.location_on,
                    onSaved: (value) {
                      latitude = double.parse(value!);
                    },
                  ),
                  const SizedBox(height: 16),
                  CustomCoordinateField(
                    controller: _longitudeController,
                    label: 'Longitude',
                    hint: 'Enter longitude',
                    minValue: -180,
                    maxValue: 180,
                    icon: Icons.location_on,
                    onSaved: (value) {
                      longitude = double.parse(value!);
                    },
                  ),
                  const SizedBox(height: 20),
                  SendLocationButton(
                    onPressed: !isConnected ? null : _sendManualLocation,
                  ),
                ],
              ),

              const SizedBox(height: 24), // Add some bottom padding
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
    _identifiedSubscription?.cancel();
    _positionSentSubscription?.cancel();
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
