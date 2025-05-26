import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;

class MapView extends StatefulWidget {
  const MapView({super.key});

  @override
  _MapViewState createState() => _MapViewState();
}

class _MapViewState extends State<MapView> {
  late IO.Socket socket;
  late Map<MarkerId, Marker> _markers;
  Completer<GoogleMapController> _controller = Completer();
  static final CameraPosition _cameraPosition = CameraPosition(
    target: LatLng(37.42, -122.085),
    zoom: 13,
  );

  @override
  void initState() {
    super.initState();
    _markers = <MarkerId, Marker>{};
    _markers.clear();
    initSocket();
  }

  Future<void> initSocket() async {
    try {
      socket = IO.io("http://127.0.0.1:3700", <String, dynamic>{
        'transports': ['websockets'],
        'autoConnect': true,
      });
      socket.connect();
      socket.on("position-change", (data) => {});
    } catch (e) {
      print(e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: GoogleMap(
        initialCameraPosition: _cameraPosition,
        mapType: MapType.normal,
        onMapCreated: (GoogleMapController controller) {
          _controller.complete(controller);
        },
        markers: Set<Marker>.of(_markers.values),
      ),
    );
  }
}
