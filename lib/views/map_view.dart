// ignore_for_file: deprecated_member_use

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../services/location_service.dart';
import '../services/route_service.dart';
import '../services/user_location_handler.dart';
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
  bool isLoadingUserLocations = true;
  bool isLoadingRoutes = false;

  // Services
  final LocationService _locationService = LocationService();
  final RouteService _routeService = RouteService();
  final UserLocationHandler _userLocationHandler = UserLocationHandler();

  // Connection and user data
  bool _isConnected = false;
  String? _currentUserId;
  Map<String, UserLocation> _userLocations = {};
  List<String> _roomUsers = [];

  // Route display settings
  bool _showRoutes = false;

  // Stream subscriptions
  StreamSubscription<ConnectionStatus>? _connectionSubscription;
  StreamSubscription<Map<String, UserLocation>>? _allLocationsSubscription;
  StreamSubscription<UserLocation>? _locationUpdateSubscription;
  StreamSubscription<List<String>>? _roomUsersSubscription;
  StreamSubscription<String>? _errorSubscription;

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
        if (_showRoutes && _userLocationHandler.currentLocation != null) {
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
    final result = await _userLocationHandler.getCurrentLocation();

    if (mounted) {
      setState(() {
        // Location handler manages its own loading state
      });

      if (!result.isSuccess && result.error != null) {
        _showError(result.error!);
      }

      // Move camera to current location
      if (_controller.isCompleted) {
        final GoogleMapController controller = await _controller.future;
        controller.animateCamera(_userLocationHandler.focusOnCurrentLocation());
      }

      // Update user markers
      _updateUserMarkers();
    }
  }

  Future<void> _updateUserMarkers() async {
    try {
      final markers = await _userLocationHandler.generateUserMarkers(
        userLocations: _userLocations,
        currentUserId: _currentUserId,
      );

      setState(() {
        _markers = markers;
      });

      // Show all locations on map if there are multiple users
      if (_userLocations.length > 1) {
        await _showAllLocations();
      }
    } catch (e) {
      debugPrint('Error updating user markers: $e');
      _showError('Error updating markers: $e');
    }
  }

  Future<void> _updateRoutes() async {
    if (!_showRoutes ||
        _userLocationHandler.currentLocation == null ||
        _userLocations.isEmpty) {
      setState(() {
        _polylines.clear();
      });
      return;
    }

    setState(() {
      isLoadingRoutes = true;
    });

    try {
      final polylines = await _routeService.generateRoutes(
        currentLocation: _userLocationHandler.currentLocation!,
        userLocations: _userLocations,
        currentUserId: _currentUserId,
        onRouteTap: _showRouteInfo,
      );

      setState(() {
        _polylines = polylines;
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
    if (_userLocationHandler.currentLocation == null) return;

    final routeInfo = _routeService.getRouteInfo(
      userId: userId,
      userLocation: userLocation,
      currentLocation: _userLocationHandler.currentLocation!,
    );

    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: Row(
              children: [
                Icon(Icons.route, color: Colors.blue.shade600),
                SizedBox(width: 8),
                Text('Route to ${routeInfo.userId}'),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildInfoRow('Travel Mode', routeInfo.travelMode),
                _buildInfoRow('Direct Distance', routeInfo.directDistance),
                _buildInfoRow('Destination', routeInfo.destination),
                _buildInfoRow('Last Updated', routeInfo.lastUpdated),
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
    if (!_routeService.isApiKeyConfigured()) {
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
                    groupValue: _routeService.routeMode,
                    onChanged: (value) {
                      setState(() {
                        _routeService.setRouteMode(value!);
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
                  value: _routeService.selectedUsers.isEmpty,
                  onChanged: (value) {
                    setState(() {
                      if (value == true) {
                        _routeService.clearSelectedUsers();
                      } else {
                        _routeService.setSelectedUsers(
                          _userLocations.keys
                              .where((userId) => userId != _currentUserId)
                              .toList(),
                        );
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
                            _routeService.selectedUsers.isEmpty ||
                            _routeService.selectedUsers.contains(userId),
                        onChanged:
                            _routeService.selectedUsers.isEmpty
                                ? null
                                : (value) {
                                  setState(() {
                                    if (value == true) {
                                      _routeService.addSelectedUser(userId);
                                    } else {
                                      _routeService.removeSelectedUser(userId);
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

  Future<void> _focusOnUser(UserLocation userLocation) async {
    final GoogleMapController controller = await _controller.future;
    controller.animateCamera(_userLocationHandler.focusOnUser(userLocation));
  }

  Future<void> _showAllLocations() async {
    if (!_controller.isCompleted) return;
    if (_userLocations.isEmpty && _userLocationHandler.currentLocation == null)
      return;

    final GoogleMapController controller = await _controller.future;
    final cameraUpdate = _userLocationHandler.calculateBoundsForAllLocations(
      userLocations: _userLocations,
    );
    controller.animateCamera(cameraUpdate);
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

    // Dispose services
    _routeService.dispose();
    _userLocationHandler.dispose();

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
          _userLocationHandler.isLoadingLocation ||
                  _userLocationHandler.currentLocation == null
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
                      target: _userLocationHandler.currentLocation!,
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
                              _routeService.routeMode.toUpperCase(),
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
