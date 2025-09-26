// ignore_for_file: deprecated_member_use

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_polyline_points/flutter_polyline_points.dart';
import 'package:map_nudge/OPEN_ROUTE_SERVICE.dart';
import '../services/location_service.dart';
import '../models/user_location.dart';
import '../models/connection_status.dart';

class MapView extends StatefulWidget {
  const MapView({super.key});

  @override
  State<MapView> createState() => _MapViewState();
}

class _MapViewState extends State<MapView> {
  late Map<MarkerId, Marker> _markers;
  late Map<PolylineId, Polyline> _polylines;
  final Completer<GoogleMapController> _controller = Completer();
  LatLng? currentLocation;
  PolylinePoints polylinePoints = PolylinePoints();
  bool isLoadingLocation = true;
  bool isLoadingUserLocations = true;

  // LocationService instance
  final LocationService _locationService = LocationService();

  // Connection and user data
  bool _isConnected = false;
  String? _currentUserId;
  Map<String, UserLocation> _userLocations = {};
  List<String> _roomUsers = [];

  // Stream subscriptions
  StreamSubscription<ConnectionStatus>? _connectionSubscription;
  StreamSubscription<Map<String, UserLocation>>? _allLocationsSubscription;
  StreamSubscription<UserLocation>? _locationUpdateSubscription;
  StreamSubscription<List<String>>? _roomUsersSubscription;
  StreamSubscription<String>? _errorSubscription;

  // Color scheme for different users
  final List<double> _markerHues = [
    BitmapDescriptor.hueRed,
    BitmapDescriptor.hueBlue,
    BitmapDescriptor.hueGreen,
    BitmapDescriptor.hueYellow,
    BitmapDescriptor.hueOrange,
    BitmapDescriptor.hueCyan,
    BitmapDescriptor.hueMagenta,
    BitmapDescriptor.hueViolet,
  ];

  @override
  void initState() {
    super.initState();
    _markers = <MarkerId, Marker>{};
    _polylines = <PolylineId, Polyline>{};
    _setupLocationServiceListeners();
    _checkConnectionStatus();
    _getCurrentLocation();
  }

  void _setupLocationServiceListeners() {
    // Listen to connection status changes
    _connectionSubscription = _locationService.connectionStream.listen((
      connectionStatus,
    ) {
      if (mounted) {
        setState(() {
          _isConnected = connectionStatus.isConnected;
          _currentUserId = connectionStatus.userId;
          _roomUsers = connectionStatus.roomUsers;
        });

        if (!connectionStatus.isConnected) {
          _showError('Disconnected from server');
        }
      }
    });

    // Listen to all locations updates
    _allLocationsSubscription = _locationService.allLocationsStream.listen((
      locations,
    ) {
      if (mounted) {
        setState(() {
          _userLocations = locations;
          isLoadingUserLocations = false;
        });
        _updateUserMarkers();
        _createPolylinesFromCurrentUser();
      }
    });

    // Listen to individual location updates
    _locationUpdateSubscription = _locationService.locationUpdateStream.listen((
      location,
    ) {
      if (mounted) {
        _showLocationUpdateNotification(location);
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

    // Listen to error messages
    _errorSubscription = _locationService.errorStream.listen((error) {
      if (mounted) {
        _showError(error);
      }
    });
  }

  void _checkConnectionStatus() {
    setState(() {
      _isConnected = _locationService.isConnected;
      _currentUserId = _locationService.currentUserId;
      _roomUsers = _locationService.roomUsers;
      _userLocations = _locationService.userLocations;
    });

    if (_isConnected) {
      // Request all current locations
      _locationService.requestAllLocations();
    }
  }

  void _showLocationUpdateNotification(UserLocation location) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(Icons.location_on, color: Colors.white, size: 20),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                '${location.userId} updated their location',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        backgroundColor: Colors.blue.shade600,
        behavior: SnackBarBehavior.floating,
        duration: Duration(seconds: 2),
      ),
    );
  }

  Future<void> _getCurrentLocation() async {
    setState(() {
      isLoadingLocation = true;
    });

    try {
      // Check if location services are enabled
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        print('Location services are disabled.');
        _showError('Location services are disabled. Using default location.');
        await _setDefaultLocation();
        return;
      }

      // Check location permission
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          print('Location permissions are denied');
          _showError('Location permission denied. Using default location.');
          await _setDefaultLocation();
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        print('Location permissions are permanently denied.');
        _showError(
          'Location permission permanently denied. Using default location.',
        );
        await _setDefaultLocation();
        return;
      }

      // Get current position
      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: Duration(seconds: 15),
      );

      setState(() {
        currentLocation = LatLng(position.latitude, position.longitude);
        isLoadingLocation = false;
      });

      // Add marker for current location
      await _addCurrentLocationMarker();

      // Move camera to current location
      if (_controller.isCompleted) {
        final GoogleMapController controller = await _controller.future;
        controller.animateCamera(
          CameraUpdate.newCameraPosition(
            CameraPosition(target: currentLocation!, zoom: 15),
          ),
        );
      }

      // Update user markers and polylines
      _updateUserMarkers();
      _createPolylinesFromCurrentUser();

      print(
        'Current location obtained: ${currentLocation!.latitude}, ${currentLocation!.longitude}',
      );
    } catch (e) {
      print('Error getting current location: $e');
      _showError(
        'Error getting location: ${e.toString()}. Using default location.',
      );
      await _setDefaultLocation();
    }
  }

  Future<void> _setDefaultLocation() async {
    setState(() {
      currentLocation = LatLng(23.8103, 90.4125); // Dhaka, Bangladesh default
      isLoadingLocation = false;
    });

    await _addCurrentLocationMarker();

    if (_controller.isCompleted) {
      final GoogleMapController controller = await _controller.future;
      controller.animateCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(target: currentLocation!, zoom: 15),
        ),
      );
    }

    _updateUserMarkers();
    _createPolylinesFromCurrentUser();
  }

  Future<void> _addCurrentLocationMarker() async {
    if (currentLocation == null) return;

    var currentLocationIcon = await BitmapDescriptor.defaultMarkerWithHue(
      BitmapDescriptor.hueBlue,
    );

    Marker currentMarker = Marker(
      markerId: MarkerId("current_location"),
      icon: currentLocationIcon,
      position: currentLocation!,
      infoWindow: InfoWindow(
        title: "Your Current Location",
        snippet:
            "Lat: ${currentLocation!.latitude.toStringAsFixed(6)}, "
            "Lng: ${currentLocation!.longitude.toStringAsFixed(6)}",
      ),
    );

    setState(() {
      _markers[MarkerId("current_location")] = currentMarker;
    });
  }

  Future<void> _updateUserMarkers() async {
    if (_userLocations.isEmpty) return;

    // Clear existing user markers (keep current location)
    _markers.removeWhere(
      (key, value) =>
          key.value != "current_location" && key.value.startsWith("user_"),
    );

    // Add markers for all users
    int colorIndex = 0;
    for (var entry in _userLocations.entries) {
      String userId = entry.key;
      UserLocation userLocation = entry.value;

      // Skip if this is the current user (already have current_location marker)
      if (userId == _currentUserId) {
        colorIndex++;
        continue;
      }

      // Create marker for this user
      var userLocationIcon = await BitmapDescriptor.defaultMarkerWithHue(
        _markerHues[colorIndex % _markerHues.length],
      );

      Marker userMarker = Marker(
        markerId: MarkerId("user_$userId"),
        icon: userLocationIcon,
        position: LatLng(userLocation.latitude, userLocation.longitude),
        infoWindow: InfoWindow(
          title: userId,
          snippet:
              "Lat: ${userLocation.latitude.toStringAsFixed(6)}, "
              "Lng: ${userLocation.longitude.toStringAsFixed(6)}\n"
              "Updated: ${_formatTimestamp(userLocation.timestamp)}",
        ),
        onTap: () => _showUserLocationDetails(userLocation),
      );

      setState(() {
        _markers[MarkerId("user_$userId")] = userMarker;
      });

      colorIndex++;
    }

    // Show all locations on map if there are multiple users
    if (_userLocations.length > 1) {
      await _showAllLocations();
    }
  }

  String _formatTimestamp(String timestamp) {
    try {
      DateTime dateTime = DateTime.parse(timestamp);
      DateTime now = DateTime.now();
      Duration difference = now.difference(dateTime);

      if (difference.inMinutes < 1) {
        return "Just now";
      } else if (difference.inMinutes < 60) {
        return "${difference.inMinutes}m ago";
      } else if (difference.inHours < 24) {
        return "${difference.inHours}h ago";
      } else {
        return "${difference.inDays}d ago";
      }
    } catch (e) {
      return "Unknown";
    }
  }

  void _showUserLocationDetails(UserLocation userLocation) {
    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: Row(
              children: [
                Icon(Icons.person, color: Colors.blue.shade600),
                SizedBox(width: 8),
                Text(userLocation.userId),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildInfoRow(
                  'Latitude',
                  userLocation.latitude.toStringAsFixed(8),
                ),
                _buildInfoRow(
                  'Longitude',
                  userLocation.longitude.toStringAsFixed(8),
                ),
                _buildInfoRow(
                  'Last Updated',
                  _formatTimestamp(userLocation.timestamp),
                ),
                if (currentLocation != null) ...[
                  SizedBox(height: 8),
                  _buildInfoRow(
                    'Distance',
                    '${_calculateDistance(currentLocation!, LatLng(userLocation.latitude, userLocation.longitude)).toStringAsFixed(2)} km',
                  ),
                ],
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text('Close'),
              ),
              ElevatedButton(
                onPressed: () {
                  Navigator.of(context).pop();
                  _focusOnUser(userLocation);
                },
                child: Text('Focus on Map'),
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
            width: 80,
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

  double _calculateDistance(LatLng from, LatLng to) {
    return Geolocator.distanceBetween(
          from.latitude,
          from.longitude,
          to.latitude,
          to.longitude,
        ) /
        1000; // Convert to kilometers
  }

  Future<void> _focusOnUser(UserLocation userLocation) async {
    final GoogleMapController controller = await _controller.future;
    controller.animateCamera(
      CameraUpdate.newCameraPosition(
        CameraPosition(
          target: LatLng(userLocation.latitude, userLocation.longitude),
          zoom: 16,
        ),
      ),
    );
  }

  Future<void> _showAllLocations() async {
    if (!_controller.isCompleted) return;
    if (_userLocations.isEmpty && currentLocation == null) return;

    final GoogleMapController controller = await _controller.future;

    // Collect all locations
    List<LatLng> allLocations = [];

    // Add current location
    if (currentLocation != null) {
      allLocations.add(currentLocation!);
    }

    // Add user locations
    for (var userLocation in _userLocations.values) {
      allLocations.add(LatLng(userLocation.latitude, userLocation.longitude));
    }

    if (allLocations.length < 2) return;

    // Calculate bounds
    double minLat = allLocations
        .map((loc) => loc.latitude)
        .reduce((a, b) => a < b ? a : b);
    double maxLat = allLocations
        .map((loc) => loc.latitude)
        .reduce((a, b) => a > b ? a : b);
    double minLng = allLocations
        .map((loc) => loc.longitude)
        .reduce((a, b) => a < b ? a : b);
    double maxLng = allLocations
        .map((loc) => loc.longitude)
        .reduce((a, b) => a > b ? a : b);

    // Add padding
    double latPadding = (maxLat - minLat) * 0.2;
    double lngPadding = (maxLng - minLng) * 0.2;

    // Ensure minimum padding
    latPadding = latPadding < 0.01 ? 0.01 : latPadding;
    lngPadding = lngPadding < 0.01 ? 0.01 : lngPadding;

    controller.animateCamera(
      CameraUpdate.newLatLngBounds(
        LatLngBounds(
          southwest: LatLng(minLat - latPadding, minLng - lngPadding),
          northeast: LatLng(maxLat + latPadding, maxLng + lngPadding),
        ),
        100.0, // padding
      ),
    );
  }

  Future<void> _createPolylinesFromCurrentUser() async {
    if (currentLocation == null || _userLocations.isEmpty) return;

    // Clear existing polylines
    _polylines.clear();

    // Create polylines from current user to all other users
    for (var entry in _userLocations.entries) {
      String userId = entry.key;
      UserLocation userLocation = entry.value;

      // Skip if this is the current user
      if (userId == _currentUserId) continue;

      await _createPolylineToUser(userId, userLocation);
    }
  }

  Future<void> _createPolylineToUser(
    String userId,
    UserLocation userLocation,
  ) async {
    if (currentLocation == null) return;

    List<LatLng> polylineCoordinates = [];
    LatLng destination = LatLng(userLocation.latitude, userLocation.longitude);

    try {
      // For now, use a simple straight line
      polylineCoordinates.add(currentLocation!);
      polylineCoordinates.add(destination);

      PolylineResult result = await polylinePoints.getRouteBetweenCoordinates(
        googleApiKey: openRouteServiceApiKey,
        request: PolylineRequest(
          origin: PointLatLng(
            currentLocation!.latitude,
            currentLocation!.longitude,
          ),
          destination: PointLatLng(destination.latitude, destination.longitude),
          mode: TravelMode.driving,
        ),
      );

      if (result.points.isNotEmpty) {
        polylineCoordinates.clear();
        for (var point in result.points) {
          polylineCoordinates.add(LatLng(point.latitude, point.longitude));
        }
      } else {
        // Fallback to straight line
        polylineCoordinates.clear();
        polylineCoordinates.add(currentLocation!);
        polylineCoordinates.add(destination);
      }
    } catch (e) {
      print('Error creating polyline to $userId: $e');
      // Fallback to straight line
      polylineCoordinates.clear();
      polylineCoordinates.add(currentLocation!);
      polylineCoordinates.add(destination);
    }

    // Use different colors for different polylines
    List<Color> polylineColors = [
      Colors.red,
      Colors.blue,
      Colors.green,
      Colors.orange,
      Colors.purple,
      Colors.cyan,
      Colors.pink,
      Colors.brown,
    ];

    int colorIndex = _userLocations.keys.toList().indexOf(userId);
    Color polylineColor = polylineColors[colorIndex % polylineColors.length];

    PolylineId polylineId = PolylineId("route_to_$userId");
    Polyline polyline = Polyline(
      polylineId: polylineId,
      color: polylineColor,
      points: polylineCoordinates,
      width: 3,
      patterns: [PatternItem.dash(15), PatternItem.gap(8)],
    );

    setState(() {
      _polylines[polylineId] = polyline;
    });
  }

  void _showError(String message) {
    if (mounted) {
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
  }

  void _refreshData() async {
    setState(() {
      isLoadingLocation = true;
      isLoadingUserLocations = true;
    });

    // Refresh current location
    await _getCurrentLocation();

    // Request fresh user locations from server
    if (_isConnected) {
      _locationService.requestAllLocations();
    }

    setState(() {
      isLoadingUserLocations = false;
    });
  }

  void _showConnectionInfo() {
    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: Row(
              children: [
                Icon(
                  _isConnected ? Icons.check_circle : Icons.error,
                  color:
                      _isConnected
                          ? Colors.green.shade600
                          : Colors.red.shade600,
                ),
                SizedBox(width: 8),
                Text('Connection Status'),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildInfoRow(
                  'Status',
                  _isConnected ? 'Connected' : 'Disconnected',
                ),
                if (_isConnected) ...[
                  _buildInfoRow(
                    'Room ID',
                    _locationService.currentRoomId ?? 'Unknown',
                  ),
                  _buildInfoRow('Your ID', _currentUserId ?? 'Unknown'),
                  _buildInfoRow('Users Online', '${_roomUsers.length}'),
                  _buildInfoRow(
                    'Locations Received',
                    '${_userLocations.length}',
                  ),
                  SizedBox(height: 8),
                  Text(
                    'Users in room:',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  SizedBox(height: 4),
                  ..._roomUsers
                      .map(
                        (user) => Padding(
                          padding: EdgeInsets.only(left: 8),
                          child: Text(
                            '• $user${user == _currentUserId ? " (You)" : ""}',
                            style: TextStyle(
                              fontSize: 12,
                              color:
                                  user == _currentUserId
                                      ? Colors.blue.shade600
                                      : null,
                            ),
                          ),
                        ),
                      )
                      .toList(),
                ],
              ],
            ),
            actions: [
              if (_isConnected)
                TextButton(
                  onPressed: () {
                    Navigator.of(context).pop();
                    _refreshData();
                  },
                  child: Text('Refresh'),
                ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text('Close'),
              ),
            ],
          ),
    );
  }

  @override
  void dispose() {
    // Cancel stream subscriptions
    _connectionSubscription?.cancel();
    _allLocationsSubscription?.cancel();
    _locationUpdateSubscription?.cancel();
    _roomUsersSubscription?.cancel();
    _errorSubscription?.cancel();

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Map View'),
        backgroundColor: Colors.green.shade600,
        foregroundColor: Colors.white,
        actions: [
          // Connection info
          IconButton(
            onPressed: _showConnectionInfo,
            icon: Icon(_isConnected ? Icons.wifi : Icons.wifi_off),
            tooltip: 'Connection Info',
          ),
        ],
      ),
      body:
          isLoadingLocation || currentLocation == null
              ? Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircularProgressIndicator(
                      color: Colors.green.shade600,
                      strokeWidth: 3,
                    ),
                    SizedBox(height: 20),
                    Text(
                      'Loading map...',
                      style: TextStyle(
                        color: Colors.green.shade600,
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    if (!_isConnected) ...[
                      SizedBox(height: 10),
                      Text(
                        'Not connected to server',
                        style: TextStyle(
                          color: Colors.red.shade600,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ],
                ),
              )
              : Stack(
                children: [
                  GoogleMap(
                    initialCameraPosition: CameraPosition(
                      target: currentLocation!,
                      zoom: 15,
                    ),
                    mapType: MapType.normal,
                    onMapCreated: (GoogleMapController controller) {
                      if (!_controller.isCompleted) {
                        _controller.complete(controller);
                      }
                    },
                    markers: Set<Marker>.of(_markers.values),
                    polylines: Set<Polyline>.of(_polylines.values),
                    myLocationEnabled: true,
                    myLocationButtonEnabled: true,
                    compassEnabled: true,
                    mapToolbarEnabled: true,
                  ),
                  // User count overlay
                  if (_isConnected && _userLocations.isNotEmpty)
                    Positioned(
                      top: 16,
                      right: 16,
                      child: Container(
                        padding: EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.1),
                              blurRadius: 4,
                              offset: Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.people,
                              size: 16,
                              color: Colors.green.shade600,
                            ),
                            SizedBox(width: 4),
                            Text(
                              '${_userLocations.length + 1}', // +1 for current user
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Colors.green.shade600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
      floatingActionButtonLocation: FloatingActionButtonLocation.startFloat,
      floatingActionButton: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          // Show all locations button
          if (_userLocations.isNotEmpty)
            FloatingActionButton(
              heroTag: "show_all_locations",
              mini: true,
              shape: CircleBorder(),
              onPressed: _showAllLocations,
              backgroundColor: Colors.purple.shade600,
              tooltip: 'Show All Locations',
              child: Icon(Icons.zoom_out_map, color: Colors.white, size: 20),
            ),
          SizedBox(height: 10),
          // Refresh data button
          FloatingActionButton(
            heroTag: "refresh_data",
            mini: true,
            shape: CircleBorder(),
            onPressed: _refreshData,
            backgroundColor: Colors.blue.shade600,
            tooltip: 'Refresh Data',
            child: Icon(Icons.refresh, color: Colors.white, size: 20),
          ),
          SizedBox(height: 10),
          // Refresh current location button
          FloatingActionButton(
            heroTag: "refresh_current_location",
            shape: CircleBorder(),
            onPressed: () async {
              await _getCurrentLocation();
              if (_userLocations.isNotEmpty) {
                await _createPolylinesFromCurrentUser();
              }
            },
            backgroundColor: Colors.green.shade600,
            tooltip: 'Refresh My Location',
            child: Icon(Icons.my_location, color: Colors.white),
          ),
        ],
      ),
    );
  }
}
