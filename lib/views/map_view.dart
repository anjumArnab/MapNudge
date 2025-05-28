import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'package:location/location.dart';
import 'package:flutter_polyline_points/flutter_polyline_points.dart';

class MapView extends StatefulWidget {
  const MapView({super.key});

  @override
  _MapViewState createState() => _MapViewState();
}

class _MapViewState extends State<MapView> {
  late IO.Socket socket;
  late Map<MarkerId, Marker> _markers;
  late Map<PolylineId, Polyline> _polylines;
  Completer<GoogleMapController> _controller = Completer();
  Location location = Location();
  LatLng? currentLocation;
  LatLng? socketLocation;
  PolylinePoints polylinePoints = PolylinePoints();

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
    bool serviceEnabled;
    PermissionStatus permissionGranted;
    LocationData locationData;

    // Check if location service is enabled
    serviceEnabled = await location.serviceEnabled();
    if (!serviceEnabled) {
      serviceEnabled = await location.requestService();
      if (!serviceEnabled) {
        return;
      }
    }

    // Check location permission
    permissionGranted = await location.hasPermission();
    if (permissionGranted == PermissionStatus.denied) {
      permissionGranted = await location.requestPermission();
      if (permissionGranted != PermissionStatus.granted) {
        return;
      }
    }

    try {
      locationData = await location.getLocation();
      if (locationData.latitude != null && locationData.longitude != null) {
        setState(() {
          currentLocation = LatLng(
            locationData.latitude!,
            locationData.longitude!,
          );
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
      }
    } catch (e) {
      print('Error getting current location: $e');
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
        "YOUR_GOOGLE_MAPS_API_KEY",
        PointLatLng(currentLocation!.latitude, currentLocation!.longitude),
        PointLatLng(socketLocation!.latitude, socketLocation!.longitude),
        travelMode: TravelMode.driving,
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
      socket = IO.io("http://127.0.0.1:3700", <String, dynamic>{
        'transports': ['websockets'],
        'autoConnect': true,
      });
      socket.connect();
      socket.on("position-change", (data) async {
        var latLng = jsonDecode(data);
        final GoogleMapController controller = await _controller.future;

        // Update socket location
        socketLocation = LatLng(latLng["lat"], latLng["lng"]);

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

          controller.animateCamera(
            CameraUpdate.newLatLngBounds(
              LatLngBounds(
                southwest: LatLng(minLat, minLng),
                northeast: LatLng(maxLat, maxLng),
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
          infoWindow: InfoWindow(title: "Socket Location"),
        );

        setState(() {
          _markers[MarkerId("socket_location")] = marker;
        });

        // Create polyline between current location and socket location
        await _createPolyline();
      });
    } catch (e) {
      print(e.toString());
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
      body:
          currentLocation == null
              ? Center(child: CircularProgressIndicator())
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
    );
  }
}
