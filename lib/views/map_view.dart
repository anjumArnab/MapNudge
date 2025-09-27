// ignore_for_file: deprecated_member_use

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_polyline_points/flutter_polyline_points.dart';
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
  bool isLoadingLocation = true;
  bool isLoadingUserLocations = true;
  bool isLoadingRoutes = false;

  // Google API Key
  static const String googleApiKey = "YOUR_GOOGLE_API_KEY_HERE";

  // Services
  final LocationService _locationService = LocationService();
  final PolylinePoints _polylinePoints = PolylinePoints();

  // Connection and user data
  bool _isConnected = false;
  String? _currentUserId;
  Map<String, UserLocation> _userLocations = {};
  List<String> _roomUsers = [];

  // Route display settings
  bool _showRoutes = false;
  String _routeMode = 'driving'; // driving, walking, transit
  List<String> _selectedUsers = []; // Empty means show routes to all users

  // Stream subscriptions
  StreamSubscription<ConnectionStatus>? _connectionSubscription;
  StreamSubscription<Map<String, UserLocation>>? _allLocationsSubscription;
  StreamSubscription<UserLocation>? _locationUpdateSubscription;
  StreamSubscription<List<String>>? _roomUsersSubscription;
  StreamSubscription<String>? _errorSubscription;

  // Color scheme for different users and routes
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

  final List<Color> _polylineColors = [
    Colors.red,
    Colors.blue,
    Colors.green,
    Colors.orange,
    Colors.purple,
    Colors.cyan,
    Colors.pink,
    Colors.indigo,
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

        // Update routes if they're currently shown
        if (_showRoutes && currentLocation != null) {
          _updateRoutes();
        }
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
        debugPrint('Location services are disabled.');
        _showError('Location services are disabled. Using default location.');
        await _setDefaultLocation();
        return;
      }

      // Check location permission
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          debugPrint('Location permissions are denied');
          _showError('Location permission denied. Using default location.');
          await _setDefaultLocation();
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        debugPrint('Location permissions are permanently denied.');
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

      // Update user markers
      _updateUserMarkers();

      debugPrint(
        'Current location obtained: ${currentLocation!.latitude}, ${currentLocation!.longitude}',
      );
    } catch (e) {
      debugPrint('Error getting current location: $e');
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

  // Get polyline points between two locations
  Future<List<LatLng>> _getPolylinePoints(
    LatLng origin,
    LatLng destination,
  ) async {
    List<LatLng> polylineCoordinates = [];

    try {
      PolylineRequest request = PolylineRequest(
        origin: PointLatLng(origin.latitude, origin.longitude),
        destination: PointLatLng(destination.latitude, destination.longitude),
        mode: _getTravelMode(),
      );

      PolylineResult result = await _polylinePoints.getRouteBetweenCoordinates(
        googleApiKey: googleApiKey,
        request: request,
      );

      if (result.points.isNotEmpty) {
        result.points.forEach((PointLatLng point) {
          polylineCoordinates.add(LatLng(point.latitude, point.longitude));
        });
      } else {
        debugPrint('No route found between $origin and $destination');
        // Fallback to direct line
        polylineCoordinates = [origin, destination];
      }
    } catch (e) {
      debugPrint('Error getting polyline points: $e');
      // Fallback to direct line
      polylineCoordinates = [origin, destination];
    }

    return polylineCoordinates;
  }

  TravelMode _getTravelMode() {
    switch (_routeMode) {
      case 'walking':
        return TravelMode.walking;
      case 'transit':
        return TravelMode.transit;
      case 'driving':
      default:
        return TravelMode.driving;
    }
  }

  // Update routes between current location and other users
  Future<void> _updateRoutes() async {
    if (!_showRoutes || currentLocation == null || _userLocations.isEmpty) {
      setState(() {
        _polylines.clear();
      });
      return;
    }

    setState(() {
      isLoadingRoutes = true;
    });

    Map<PolylineId, Polyline> newPolylines = {};
    int colorIndex = 0;

    try {
      // Create routes from current location to selected users (or all users if none selected)
      List<String> targetUsers =
          _selectedUsers.isEmpty
              ? _userLocations.keys
                  .where((userId) => userId != _currentUserId)
                  .toList()
              : _selectedUsers;

      for (String userId in targetUsers) {
        UserLocation? userLocation = _userLocations[userId];
        if (userLocation == null || userId == _currentUserId) continue;

        LatLng destination = LatLng(
          userLocation.latitude,
          userLocation.longitude,
        );

        List<LatLng> polylineCoordinates = await _getPolylinePoints(
          currentLocation!,
          destination,
        );

        if (polylineCoordinates.isNotEmpty) {
          PolylineId polylineId = PolylineId("route_to_$userId");
          Polyline polyline = Polyline(
            polylineId: polylineId,
            points: polylineCoordinates,
            color: _polylineColors[colorIndex % _polylineColors.length],
            width: 4,
            patterns:
                _routeMode == 'walking'
                    ? [PatternItem.dash(10), PatternItem.gap(10)]
                    : [],
            onTap: () => _showRouteInfo(userId, userLocation),
          );

          newPolylines[polylineId] = polyline;
        }

        colorIndex++;
      }

      setState(() {
        _polylines = newPolylines;
        isLoadingRoutes = false;
      });
    } catch (e) {
      debugPrint('Error updating routes: $e');
      setState(() {
        isLoadingRoutes = false;
      });
      _showError('Error loading routes: $e');
    }
  }

  void _showRouteInfo(String userId, UserLocation userLocation) {
    double distance = _calculateDistance(
      currentLocation!,
      LatLng(userLocation.latitude, userLocation.longitude),
    );

    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: Row(
              children: [
                Icon(Icons.route, color: Colors.blue.shade600),
                SizedBox(width: 8),
                Text('Route to $userId'),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildInfoRow('Travel Mode', _routeMode.toUpperCase()),
                _buildInfoRow(
                  'Direct Distance',
                  '${distance.toStringAsFixed(2)} km',
                ),
                _buildInfoRow(
                  'Destination',
                  '${userLocation.latitude.toStringAsFixed(6)}, ${userLocation.longitude.toStringAsFixed(6)}',
                ),
                _buildInfoRow(
                  'Last Updated',
                  _formatTimestamp(userLocation.timestamp),
                ),
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

  void _toggleRoutes() {
    if (googleApiKey == "YOUR_GOOGLE_API_KEY_HERE") {
      _showError('Please add your Google API key to use route features');
      return;
    }

    setState(() {
      _showRoutes = !_showRoutes;
    });

    if (_showRoutes) {
      _updateRoutes();
    } else {
      setState(() {
        _polylines.clear();
      });
    }
  }

  void _showRoutesSettings() {
    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: Text('Route Settings'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Travel Mode:',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                SizedBox(height: 8),
                ...['driving', 'walking', 'transit'].map(
                  (mode) => RadioListTile<String>(
                    title: Text(mode.toUpperCase()),
                    value: mode,
                    groupValue: _routeMode,
                    onChanged: (value) {
                      setState(() {
                        _routeMode = value!;
                      });
                      if (_showRoutes) {
                        _updateRoutes();
                      }
                    },
                  ),
                ),
                SizedBox(height: 16),
                Text(
                  'Show Routes To:',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                SizedBox(height: 8),
                CheckboxListTile(
                  title: Text('All Users'),
                  value: _selectedUsers.isEmpty,
                  onChanged: (value) {
                    setState(() {
                      if (value == true) {
                        _selectedUsers.clear();
                      } else {
                        _selectedUsers =
                            _userLocations.keys
                                .where((userId) => userId != _currentUserId)
                                .toList();
                      }
                    });
                    if (_showRoutes) {
                      _updateRoutes();
                    }
                  },
                ),
                ..._userLocations.keys
                    .where((userId) => userId != _currentUserId)
                    .map(
                      (userId) => CheckboxListTile(
                        title: Text(userId),
                        value:
                            _selectedUsers.isEmpty ||
                            _selectedUsers.contains(userId),
                        onChanged:
                            _selectedUsers.isEmpty
                                ? null
                                : (value) {
                                  setState(() {
                                    if (value == true) {
                                      if (!_selectedUsers.contains(userId)) {
                                        _selectedUsers.add(userId);
                                      }
                                    } else {
                                      _selectedUsers.remove(userId);
                                    }
                                  });
                                  if (_showRoutes) {
                                    _updateRoutes();
                                  }
                                },
                      ),
                    ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text('Done'),
              ),
            ],
          ),
    );
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
          // Routes toggle button
          IconButton(
            onPressed: _userLocations.isNotEmpty ? _toggleRoutes : null,
            icon: Icon(_showRoutes ? Icons.route : Icons.route_outlined),
            tooltip: _showRoutes ? 'Hide Routes' : 'Show Routes',
          ),
          // Routes settings
          if (_showRoutes)
            IconButton(
              onPressed: _showRoutesSettings,
              icon: Icon(Icons.settings),
              tooltip: 'Route Settings',
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
                              '${_userLocations.length + 1}',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Colors.green.shade600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  // Routes loading indicator
                  if (isLoadingRoutes)
                    Positioned(
                      top: 16,
                      left: 16,
                      child: Container(
                        padding: EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(8),
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
                            SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.blue.shade600,
                              ),
                            ),
                            SizedBox(width: 8),
                            Text(
                              'Loading Routes...',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.blue.shade600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  // Route info overlay
                  if (_showRoutes && _polylines.isNotEmpty)
                    Positioned(
                      bottom: 100,
                      right: 16,
                      child: Container(
                        padding: EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(8),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.1),
                              blurRadius: 4,
                              offset: Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.route,
                                  size: 16,
                                  color: Colors.blue.shade600,
                                ),
                                SizedBox(width: 4),
                                Text(
                                  '${_polylines.length} Routes',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.blue.shade600,
                                  ),
                                ),
                              ],
                            ),
                            Text(
                              _routeMode.toUpperCase(),
                              style: TextStyle(
                                fontSize: 10,
                                color: Colors.grey.shade600,
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
            onPressed: _getCurrentLocation,
            backgroundColor: Colors.green.shade600,
            tooltip: 'Refresh My Location',
            child: Icon(Icons.my_location, color: Colors.white),
          ),
        ],
      ),
    );
  }
}
