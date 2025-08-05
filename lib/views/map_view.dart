import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'package:geolocator/geolocator.dart';
import 'package:flutter_polyline_points/flutter_polyline_points.dart';
import '../views/coordinate_view.dart';

class MapView extends StatefulWidget {
  const MapView({super.key});

  @override
  State<MapView> createState() => _MapViewState();
}

class _MapViewState extends State<MapView> {
  late IO.Socket socket;
  late Map<MarkerId, Marker> _markers;
  late Map<PolylineId, Polyline> _polylines;
  final Completer<GoogleMapController> _controller = Completer();
  LatLng? currentLocation;
  LatLng? socketLocation;
  PolylinePoints polylinePoints = PolylinePoints();
  bool isConnected = false;

  @override
  void initState() {
    super.initState();
    _markers = <MarkerId, Marker>{};
    _polylines = <PolylineId, Polyline>{};
    _markers.clear();
    _polylines.clear();
    _getCurrentLocation();
    initSocket();
  }

  Future<void> _getCurrentLocation() async {
    try {
      // Check if location services are enabled
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        print('Location services are disabled.');
        // Use default location if service is disabled
        setState(() {
          currentLocation = LatLng(
            23.8103,
            90.4125,
          ); // Dhaka, Bangladesh default
        });
        await _addCurrentLocationMarker();
        final GoogleMapController controller = await _controller.future;
        controller.animateCamera(
          CameraUpdate.newCameraPosition(
            CameraPosition(target: currentLocation!, zoom: 15),
          ),
        );
        return;
      }

      // Check location permission
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          print('Location permissions are denied');
          // Use default location if permission is denied
          setState(() {
            currentLocation = LatLng(
              23.8103,
              90.4125,
            ); // Dhaka, Bangladesh default
          });
          await _addCurrentLocationMarker();
          final GoogleMapController controller = await _controller.future;
          controller.animateCamera(
            CameraUpdate.newCameraPosition(
              CameraPosition(target: currentLocation!, zoom: 15),
            ),
          );
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        print(
          'Location permissions are permanently denied, we cannot request permissions.',
        );
        // Use default location if permission is permanently denied
        setState(() {
          currentLocation = LatLng(
            23.8103,
            90.4125,
          ); // Dhaka, Bangladesh default
        });
        await _addCurrentLocationMarker();
        final GoogleMapController controller = await _controller.future;
        controller.animateCamera(
          CameraUpdate.newCameraPosition(
            CameraPosition(target: currentLocation!, zoom: 15),
          ),
        );
        return;
      }

      // Get current position
      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: Duration(seconds: 10),
      );

      setState(() {
        currentLocation = LatLng(position.latitude, position.longitude);
      });

      // Add marker for current location
      await _addCurrentLocationMarker();

      // Move camera to current location
      final GoogleMapController controller = await _controller.future;
      controller.animateCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(target: currentLocation!, zoom: 15),
        ),
      );
    } catch (e) {
      print('Error getting current location: $e');
      // Use default location if any error occurs
      setState(() {
        currentLocation = LatLng(23.8103, 90.4125); // Dhaka, Bangladesh default
      });
      await _addCurrentLocationMarker();
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
      infoWindow: InfoWindow(title: "Your Location"),
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
      PolylineResult result = await polylinePoints.getRouteBetweenCoordinates(
        googleApiKey:
            "YOUR_GOOGLE_MAPS_API_KEY", // Replace with your actual API key
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
    } catch (e) {
      print('Error creating polyline: $e');
      // Fallback to straight line
      polylineCoordinates.add(currentLocation!);
      polylineCoordinates.add(socketLocation!);
    }

    PolylineId id = PolylineId("route");
    Polyline polyline = Polyline(
      polylineId: id,
      color: Colors.red,
      points: polylineCoordinates,
      width: 3,
      patterns: [],
    );

    setState(() {
      _polylines[id] = polyline;
    });
  }

  Future<void> initSocket() async {
    try {
      // Fixed: Use localhost for Flutter Web
      socket = IO.io("http://localhost:3200", <String, dynamic>{
        'transports': [
          'websocket',
          'polling',
        ], // Fixed: correct transport names
        'autoConnect': true,
      });

      socket.connect();

      socket.onConnect((data) {
        print('Connected: ${socket.id}');
        setState(() {
          isConnected = true;
        });

        // NEW: Identify this client as a map viewer
        socket.emit('identify', {
          'role': 'map-viewer',
          'roomId': 'default-room', // Should match the coordinate sender's room
        });
      });

      // NEW: Handle identification response
      socket.on('identified', (data) {
        print('Map view identified successfully: $data');
        // Request current position from coordinate senders
        socket.emit('request-position');
      });

      // Handle position changes from coordinate senders
      socket.on("position-change", (data) async {
        print('Received position data: $data');

        try {
          Map<String, dynamic> latLng;

          // Handle both string and object data
          if (data is String) {
            latLng = jsonDecode(data);
          } else {
            latLng = data;
          }

          final GoogleMapController controller = await _controller.future;

          // Update socket location
          socketLocation = LatLng(
            latLng["lat"].toDouble(),
            latLng["lng"].toDouble(),
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

            // Add some padding to the bounds
            double latPadding = (maxLat - minLat) * 0.1;
            double lngPadding = (maxLng - minLng) * 0.1;

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
                CameraPosition(target: socketLocation!, zoom: 13),
              ),
            );
          }

          var image = await BitmapDescriptor.defaultMarkerWithHue(
            BitmapDescriptor.hueRed,
          );
          Marker marker = Marker(
            markerId: MarkerId("socket_location"),
            icon: image,
            position: socketLocation!,
            infoWindow: InfoWindow(
              title: "Received Location",
              snippet: "Lat: ${latLng["lat"]}, Lng: ${latLng["lng"]}",
            ),
          );

          setState(() {
            _markers[MarkerId("socket_location")] = marker;
          });

          // Create polyline between current location and socket location
          await _createPolyline();
        } catch (e) {
          print('Error processing position data: $e');
        }
      });

      // NEW: Handle position requests
      socket.on('position-request', (data) {
        print('Position requested by: ${data['requesterId']}');
        // This would be handled by coordinate senders, not map viewers
      });

      // NEW: Handle client join/leave events
      socket.on('client-joined', (data) {
        print('Client joined: $data');
      });

      socket.on('client-left', (data) {
        print('Client left: $data');
      });

      // NEW: Handle errors from backend
      socket.on('error', (data) {
        print('Socket error: $data');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: ${data['message'] ?? 'Unknown error'}'),
            backgroundColor: Colors.red.shade600,
            behavior: SnackBarBehavior.floating,
          ),
        );
      });

      socket.onDisconnect((data) {
        print('Disconnected: $data');
        setState(() {
          isConnected = false;
        });
      });
    } catch (e) {
      print('Socket initialization error: ${e.toString()}');
    }
  }

  @override
  void dispose() {
    socket.disconnect();
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
                  isConnected ? 'Connected' : 'Offline',
                  style: TextStyle(fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
      body:
          currentLocation == null
              ? Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircularProgressIndicator(color: Colors.green.shade600),
                    SizedBox(height: 16),
                    Text(
                      'Loading map...',
                      style: TextStyle(
                        color: Colors.green.shade600,
                        fontSize: 16,
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
                  _controller.complete(controller);
                },
                markers: Set<Marker>.of(_markers.values),
                polylines: Set<Polyline>.of(_polylines.values),
                myLocationEnabled: true,
                myLocationButtonEnabled: true,
              ),
      floatingActionButton: FloatingActionButton(
        heroTag: "refresh_position",
        shape: const CircleBorder(),
        onPressed:
            isConnected
                ? () {
                  // Request current position from coordinate senders
                  socket.emit('request-position');
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Requesting current position...'),
                      backgroundColor: Colors.green.shade600,
                      behavior: SnackBarBehavior.floating,
                      duration: Duration(seconds: 2),
                    ),
                  );
                }
                : null,
        backgroundColor: isConnected ? Colors.green.shade600 : Colors.grey,
        child: Icon(Icons.refresh, color: Colors.white),
      ),
    );
  }
}
