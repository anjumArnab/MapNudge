import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_polyline_points/flutter_polyline_points.dart';
import '../views/coordinate_view.dart';

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
  LatLng? sampleLocation;
  PolylinePoints polylinePoints = PolylinePoints();
  bool isLoadingLocation = true;

  @override
  void initState() {
    super.initState();
    _markers = <MarkerId, Marker>{};
    _polylines = <PolylineId, Polyline>{};
    _markers.clear();
    _polylines.clear();
    _getCurrentLocation();
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

  Future<void> _addSampleLocation() async {
    if (currentLocation == null) return;

    // Add a sample location marker about 1km away from current location
    double offsetLat = 0.009; // roughly 1km north
    double offsetLng = 0.009; // roughly 1km east

    sampleLocation = LatLng(
      currentLocation!.latitude + offsetLat,
      currentLocation!.longitude + offsetLng,
    );

    // Create marker for sample location
    var sampleLocationIcon = await BitmapDescriptor.defaultMarkerWithHue(
      BitmapDescriptor.hueRed,
    );
    Marker marker = Marker(
      markerId: MarkerId("sample_location"),
      icon: sampleLocationIcon,
      position: sampleLocation!,
      infoWindow: InfoWindow(
        title: "Sample Location",
        snippet:
            "Lat: ${sampleLocation!.latitude.toStringAsFixed(6)}, Lng: ${sampleLocation!.longitude.toStringAsFixed(6)}",
      ),
    );

    setState(() {
      _markers[MarkerId("sample_location")] = marker;
    });

    // Show both locations on map
    await _showBothLocations();

    // Create polyline between current location and sample location
    await _createPolyline();

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Sample location added!\nLat: ${sampleLocation!.latitude.toStringAsFixed(6)}, '
          'Lng: ${sampleLocation!.longitude.toStringAsFixed(6)}',
        ),
        backgroundColor: Colors.green.shade600,
        behavior: SnackBarBehavior.floating,
        duration: Duration(seconds: 3),
      ),
    );
  }

  Future<void> _showBothLocations() async {
    if (currentLocation == null || sampleLocation == null) return;

    final GoogleMapController controller = await _controller.future;

    // Calculate bounds to show both markers
    double minLat =
        currentLocation!.latitude < sampleLocation!.latitude
            ? currentLocation!.latitude
            : sampleLocation!.latitude;
    double maxLat =
        currentLocation!.latitude > sampleLocation!.latitude
            ? currentLocation!.latitude
            : sampleLocation!.latitude;
    double minLng =
        currentLocation!.longitude < sampleLocation!.longitude
            ? currentLocation!.longitude
            : sampleLocation!.longitude;
    double maxLng =
        currentLocation!.longitude > sampleLocation!.longitude
            ? currentLocation!.longitude
            : sampleLocation!.longitude;

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
  }

  Future<void> _createPolyline() async {
    if (currentLocation == null || sampleLocation == null) return;

    List<LatLng> polylineCoordinates = [];

    try {
      // For now, we'll use a simple straight line
      polylineCoordinates.add(currentLocation!);
      polylineCoordinates.add(sampleLocation!);

      /* Uncomment this section when you have a Google Maps API key
      PolylineResult result = await polylinePoints.getRouteBetweenCoordinates(
        googleApiKey: "YOUR_GOOGLE_MAPS_API_KEY", // Replace with your actual API key
        request: PolylineRequest(
          origin: PointLatLng(
            currentLocation!.latitude,
            currentLocation!.longitude,
          ),
          destination: PointLatLng(
            sampleLocation!.latitude,
            sampleLocation!.longitude,
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
        polylineCoordinates.add(sampleLocation!);
      }
      */
    } catch (e) {
      print('Error creating polyline: $e');
      // Fallback to straight line
      polylineCoordinates.clear();
      polylineCoordinates.add(currentLocation!);
      polylineCoordinates.add(sampleLocation!);
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

  void _clearMarkers() {
    setState(() {
      // Remove sample location marker and polyline, keep current location
      _markers.removeWhere((key, value) => key.value == "sample_location");
      _polylines.clear();
      sampleLocation = null;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Sample markers cleared'),
        backgroundColor: Colors.orange.shade600,
        behavior: SnackBarBehavior.floating,
        duration: Duration(seconds: 2),
      ),
    );
  }

  void _refreshCurrentLocation() async {
    await _getCurrentLocation();
    if (sampleLocation != null) {
      await _createPolyline();
    }
  }

  @override
  void dispose() {
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
            tooltip: 'Refresh My Location',
            child: Icon(Icons.my_location, color: Colors.white, size: 20),
          ),
          SizedBox(height: 10),
          // Add sample location button
          FloatingActionButton(
            heroTag: "add_sample_location",
            onPressed: _addSampleLocation,
            backgroundColor: Colors.green.shade600,
            tooltip: 'Add Sample Location',
            child: Icon(Icons.add_location, color: Colors.white),
          ),
        ],
      ),
    );
  }
}
