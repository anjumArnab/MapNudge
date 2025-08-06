import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import '../views/map_view.dart';
import '../widgets/custom_coordinate_fields.dart';
import '../widgets/send_location_button.dart';
import '../services/location_service.dart';

class CoordinateView extends StatefulWidget {
  const CoordinateView({super.key});

  @override
  State<CoordinateView> createState() => _CoordinateViewState();
}

class _CoordinateViewState extends State<CoordinateView> {
  final LocationService _locationService = LocationService.instance;
  double? latitude;
  double? longitude;
  bool isGettingLocation = false;
  bool isSendingLocation = false;
  String? locationStatus;
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _latitudeController = TextEditingController();
  final TextEditingController _longitudeController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _checkConnectionStatus();
  }

  void _checkConnectionStatus() {
    if (!_locationService.isConnected) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _showNotConnectedDialog();
      });
    }
  }

  void _showNotConnectedDialog() {
    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: Row(
              children: [
                Icon(Icons.warning, color: Colors.orange),
                SizedBox(width: 8),
                Text('Not Connected'),
              ],
            ),
            content: Text(
              'You are not connected to any server. Please go back to homepage and connect to a server first.',
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.of(context).pop(); // Close dialog
                  Navigator.of(context).pop(); // Go back to homepage
                },
                child: Text('Go to Homepage'),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text('Continue Anyway'),
              ),
            ],
          ),
    );
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

      // Show success message
      _showSuccessMessage();
    } catch (e) {
      setState(() {
        isGettingLocation = false;
        locationStatus = "Error getting location: ${e.toString()}";
      });
      _showLocationError("Error getting current location: ${e.toString()}");
    }
  }

  void _showSuccessMessage() {
    if (latitude != null && longitude != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Current location obtained!\nLat: ${latitude!.toStringAsFixed(6)}, Lng: ${longitude!.toStringAsFixed(6)}',
          ),
          backgroundColor: Colors.green.shade600,
          behavior: SnackBarBehavior.floating,
          duration: Duration(seconds: 3),
        ),
      );
    }
  }

  Future<void> _sendLocationToServer() async {
    if (!validateAndSave()) return;

    if (!_locationService.isConnected) {
      _showLocationError('Not connected to server. Please connect first.');
      return;
    }

    setState(() {
      isSendingLocation = true;
    });

    try {
      // Try sending via socket first, fallback to HTTP
      bool success = await _locationService.sendLocationViaSocket(
        latitude: latitude!,
        longitude: longitude!,
      );

      if (!success) {
        // Fallback to HTTP method
        success = await _locationService.sendLocationViaHttp(
          latitude: latitude!,
          longitude: longitude!,
        );
      }

      setState(() {
        isSendingLocation = false;
      });

      if (success) {
        _showLocationSentSuccess();
      } else {
        _showLocationError('Failed to send location. Please try again.');
      }
    } catch (e) {
      setState(() {
        isSendingLocation = false;
      });
      _showLocationError('Error sending location: $e');
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
              'Room: ${_locationService.currentRoomId ?? 'Unknown'}',
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

  Widget _buildConnectionStatus() {
    if (!_locationService.isConnected) {
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
      child: Row(
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
                  'Room: ${_locationService.currentRoomId} | User: ${_locationService.currentUserId}',
                  style: TextStyle(color: Colors.green.shade600, fontSize: 12),
                ),
              ],
            ),
          ),
        ],
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
              const SizedBox(height: 16),

              // Connection Status
              _buildConnectionStatus(),

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

                  // Send Location Button
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton.icon(
                      onPressed:
                          (isSendingLocation ||
                                  latitude == null ||
                                  longitude == null)
                              ? null
                              : _sendManualLocation,
                      icon:
                          isSendingLocation
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
                              : Icon(Icons.send),
                      label: Text(
                        isSendingLocation
                            ? 'Sending Location...'
                            : 'Send Location',
                        style: TextStyle(fontSize: 16),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue.shade600,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
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
