import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_polyline_points/flutter_polyline_points.dart';
import '../views/coordinate_view.dart';
import '../services/socket_service.dart'; // Import the socket service

class MapView extends StatefulWidget {
  const MapView({super.key});

  @override
  State<MapView> createState() => _MapViewState();
}

class _MapViewState extends State<MapView> {
  final SocketService _socketService = SocketService();
  late Map<MarkerId, Marker> _markers;
  late Map<PolylineId, Polyline> _polylines;
  final Completer<GoogleMapController> _controller = Completer();
  LatLng? currentLocation;
  LatLng? socketLocation;
  PolylinePoints polylinePoints = PolylinePoints();
  bool isConnected = false;
  bool isLoadingLocation = true;

  // Stream subscriptions
  StreamSubscription<bool>? _connectionSubscription;
  StreamSubscription<Map<String, dynamic>>? _positionChangeSubscription;
  StreamSubscription<Map<String, dynamic>>? _identifiedSubscription;
  StreamSubscription<Map<String, dynamic>>? _errorSubscription;
  StreamSubscription<Map<String, dynamic>>? _clientJoinedSubscription;
  StreamSubscription<Map<String, dynamic>>? _clientLeftSubscription;
  StreamSubscription<Map<String, dynamic>>? _positionRequestSubscription;

  @override
  void initState() {
    super.initState();
    _markers = <MarkerId, Marker>{};
    _polylines = <PolylineId, Polyline>{};
    _markers.clear();
    _polylines.clear();
    _getCurrentLocation();
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
        // Identify as map viewer when connected
        _socketService.identify(ClientRole.mapViewer);
      }
    });

    _identifiedSubscription = _socketService.identifiedStream.listen((data) {
      print('Map view identified successfully: $data');
      // Request current position from coordinate senders
      _socketService.requestPosition();
    });

    _positionChangeSubscription = _socketService.positionChangeStream.listen((
      data,
    ) async {
      await _handlePositionChange(data);
    });

    _positionRequestSubscription = _socketService.positionRequestStream.listen((
      data,
    ) {
      print('Position requested: $data');
      // This is handled by coordinate senders, map viewers just listen
    });

    _errorSubscription = _socketService.errorStream.listen((error) {
      _showError('Socket Error: ${error['message'] ?? 'Unknown error'}');
    });

    _clientJoinedSubscription = _socketService.clientJoinedStream.listen((
      data,
    ) {
      print('Client joined: $data');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('New client connected'),
          backgroundColor: Colors.green.shade600,
          behavior: SnackBarBehavior.floating,
          duration: Duration(seconds: 2),
        ),
      );
    });

    _clientLeftSubscription = _socketService.clientLeftStream.listen((data) {
      print('Client left: $data');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Client disconnected'),
          backgroundColor: Colors.orange.shade600,
          behavior: SnackBarBehavior.floating,
          duration: Duration(seconds: 2),
        ),
      );
    });

    // Connect to the socket server (reuse existing connection if available)
    if (!_socketService.isConnected) {
      await _socketService.connect();
    } else {
      // If already connected, just identify
      _socketService.identify(ClientRole.mapViewer);
      setState(() {
        isConnected = true;
      });
    }
  }

  Future<void> _handlePositionChange(Map<String, dynamic> data) async {
    print('Received position data: $data');

    try {
      // Validate the received data
      if (!data.containsKey('lat') || !data.containsKey('lng')) {
        throw Exception('Invalid position data: missing lat or lng');
      }

      final GoogleMapController controller = await _controller.future;

      // Update socket location
      socketLocation = LatLng(data["lat"].toDouble(), data["lng"].toDouble());

      // Show success message
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Location received!\nLat: ${socketLocation!.latitude.toStringAsFixed(6)}, '
            'Lng: ${socketLocation!.longitude.toStringAsFixed(6)}',
          ),
          backgroundColor: Colors.green.shade600,
          behavior: SnackBarBehavior.floating,
          duration: Duration(seconds: 3),
        ),
      );

      // Animate camera to show both points
      if (currentLocation != null) {
        // Calculate bounds to show both markers
        double minLat =
            currentLocation!.latitude < socketLocation!.latitude
                ? currentLocation!.latitude
                : socketLocation!.latitude;
        double maxLat =
            currentLocation!.latitude > socketLocation!.latitude
                ? currentLocation!.latitude
                : socketLocation!.latitude;
        double minLng =
            currentLocation!.longitude < socketLocation!.longitude
                ? currentLocation!.longitude
                : socketLocation!.longitude;
        double maxLng =
            currentLocation!.longitude > socketLocation!.longitude
                ? currentLocation!.longitude
                : socketLocation!.longitude;

        // Add some padding to the bounds (minimum 0.01 degrees)
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
      } else {
        controller.animateCamera(
          CameraUpdate.newCameraPosition(
            CameraPosition(target: socketLocation!, zoom: 15),
          ),
        );
      }

      // Create marker for received location
      var receivedLocationIcon = await BitmapDescriptor.defaultMarkerWithHue(
        BitmapDescriptor.hueRed,
      );
      Marker marker = Marker(
        markerId: MarkerId("socket_location"),
        icon: receivedLocationIcon,
        position: socketLocation!,
        infoWindow: InfoWindow(
          title: "Received Location",
          snippet:
              "Lat: ${data["lat"].toStringAsFixed(6)}, Lng: ${data["lng"].toStringAsFixed(6)}",
        ),
      );

      setState(() {
        _markers[MarkerId("socket_location")] = marker;
      });

      // Create polyline between current location and socket location
      await _createPolyline();
    } catch (e) {
      print('Error processing position data: $e');
      _showError('Error processing received location: $e');
    }
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
        title: "Your Location",
        snippet:
            "Lat: ${currentLocation!.latitude.toStringAsFixed(6)}, "
            "Lng: ${currentLocation!.longitude.toStringAsFixed(6)}",
      ),
    );

    setState(() {
      _markers[MarkerId("current_location")] = currentMarker;
    });
  }

  Future<void> _createPolyline() async {
    if (currentLocation == null || socketLocation == null) return;

    List<LatLng> polylineCoordinates = [];

    try {
      // Get route points between current location and socket location
      // Note: Replace "YOUR_GOOGLE_MAPS_API_KEY" with your actual API key
      // For now, we'll use a simple straight line
      polylineCoordinates.add(currentLocation!);
      polylineCoordinates.add(socketLocation!);

      /* Uncomment this section when you have a Google Maps API key
      PolylineResult result = await polylinePoints.getRouteBetweenCoordinates(
        googleApiKey: "YOUR_GOOGLE_MAPS_API_KEY", // Replace with your actual API key
        request: PolylineRequest(
          origin: PointLatLng(
            currentLocation!.latitude,
            currentLocation!.longitude,
          ),
          destination: PointLatLng(
            socketLocation!.latitude,
            socketLocation!.longitude,
          ),
          mode: TravelMode.driving,
        ),
      );

      if (result.points.isNotEmpty) {
        for (var point in result.points) {
          polylineCoordinates.add(LatLng(point.latitude, point.longitude));
        }
      } else {
        // Fallback to straight line if no route found
        polylineCoordinates.add(currentLocation!);
        polylineCoordinates.add(socketLocation!);
      }
      */
    } catch (e) {
      print('Error creating polyline: $e');
      // Fallback to straight line
      polylineCoordinates.clear();
      polylineCoordinates.add(currentLocation!);
      polylineCoordinates.add(socketLocation!);
    }

    PolylineId id = PolylineId("route");
    Polyline polyline = Polyline(
      polylineId: id,
      color: Colors.red,
      points: polylineCoordinates,
      width: 4,
      patterns: [PatternItem.dash(20), PatternItem.gap(10)],
    );

    setState(() {
      _polylines[id] = polyline;
    });
  }

  void _showError(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: Colors.red.shade600,
          behavior: SnackBarBehavior.floating,
          duration: Duration(seconds: 4),
        ),
      );
    }
  }

  void _requestPosition() {
    if (!isConnected) {
      _showError("Not connected to server. Please wait for connection...");
      return;
    }

    _socketService.requestPosition();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Requesting current position from coordinate senders...'),
        backgroundColor: Colors.green.shade600,
        behavior: SnackBarBehavior.floating,
        duration: Duration(seconds: 3),
      ),
    );
  }

  void _clearMarkers() {
    setState(() {
      // Remove socket location marker and polyline, keep current location
      _markers.removeWhere((key, value) => key.value == "socket_location");
      _polylines.clear();
      socketLocation = null;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Markers cleared'),
        backgroundColor: Colors.orange.shade600,
        behavior: SnackBarBehavior.floating,
        duration: Duration(seconds: 2),
      ),
    );
  }

  void _refreshCurrentLocation() async {
    await _getCurrentLocation();
    if (socketLocation != null) {
      await _createPolyline();
    }
  }

  @override
  void dispose() {
    // Cancel stream subscriptions
    _connectionSubscription?.cancel();
    _positionChangeSubscription?.cancel();
    _identifiedSubscription?.cancel();
    _errorSubscription?.cancel();
    _clientJoinedSubscription?.cancel();
    _clientLeftSubscription?.cancel();
    _positionRequestSubscription?.cancel();

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
          // Navigation button to CoordinateView
          IconButton(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const CoordinateView()),
              );
            },
            icon: Icon(Icons.send),
            tooltip: 'Send Coordinates',
          ),
          // Clear markers button
          IconButton(
            onPressed: _clearMarkers,
            icon: Icon(Icons.clear),
            tooltip: 'Clear Markers',
          ),
          // Connection status indicator
          Padding(
            padding: EdgeInsets.only(right: 16),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  isConnected ? Icons.wifi : Icons.wifi_off,
                  color: isConnected ? Colors.white : Colors.red,
                  size: 20,
                ),
                SizedBox(width: 4),
                Text(
                  isConnected ? 'Online' : 'Offline',
                  style: TextStyle(fontSize: 12),
                ),
              ],
            ),
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
                    SizedBox(height: 8),
                    Text(
                      isConnected
                          ? 'Connected to server'
                          : 'Connecting to server...',
                      style: TextStyle(
                        color: isConnected ? Colors.green : Colors.orange,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              )
              : GoogleMap(
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
      floatingActionButton: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          // Refresh current location button
          FloatingActionButton(
            heroTag: "refresh_current_location",
            mini: true,
            onPressed: _refreshCurrentLocation,
            backgroundColor: Colors.blue.shade600,
            child: Icon(Icons.my_location, color: Colors.white, size: 20),
            tooltip: 'Refresh My Location',
          ),
          SizedBox(height: 10),
          // Request position button
          FloatingActionButton(
            heroTag: "request_position",
            onPressed: isConnected ? _requestPosition : null,
            backgroundColor: isConnected ? Colors.green.shade600 : Colors.grey,
            child: Icon(Icons.refresh, color: Colors.white),
            tooltip: 'Request Position',
          ),
        ],
      ),
    );
  }
}
