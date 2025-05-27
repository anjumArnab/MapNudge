import 'package:flutter/material.dart';
import 'package:map_nudge/views/map_view.dart';
import 'package:map_nudge/widgets/custom_coordinate_fields.dart';
import 'package:map_nudge/widgets/send_location_button.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;

class CoordinateView extends StatefulWidget {
  const CoordinateView({super.key});

  @override
  _CoordinateViewState createState() => _CoordinateViewState();
}

class _CoordinateViewState extends State<CoordinateView> {
  late IO.Socket socket;
  double? latitude;
  double? longitude;
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _latitudeController = TextEditingController();
  final TextEditingController _longitudeController = TextEditingController();

  @override
  void initState() {
    super.initState();
    initSocket(context);
  }

  void _navToMapView(BuildContext context) {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (context) => MapView()));
  }

  Future<void> initSocket(BuildContext context) async {
    try {
      socket = IO.io("http://192.168.1.2:3200", <String, dynamic>{
        'transports': ['websocket'],
        'autoConnect': true,
      });

      socket.connect();

      socket.onConnect((data) {
        print('Connect: ${socket.id}');
        _navToMapView(context);
      });
    } catch (e) {
      print(e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.green.shade50,
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
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
              const SizedBox(height: 40),
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

              const SizedBox(height: 20),
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

              const SizedBox(height: 30),
              SendLocationButton(
                onPressed: () {
                  if (validateAndSave()) {
                    var coords = {"lat": latitude, "lng": longitude};
                    socket.emit('position-change', coords);

                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: const Text('Location sent successfully!'),
                        backgroundColor: Colors.green.shade600,
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  }
                },
              ),
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
    socket.dispose();
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
