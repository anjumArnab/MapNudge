import 'package:flutter/material.dart';
import 'package:map_nudge/views/coordinate_view.dart';
import 'package:google_fonts/google_fonts.dart';

void main() {
  runApp(const MapNudge());
}

class MapNudge extends StatelessWidget {
  const MapNudge({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'MapNudge',
      theme: ThemeData(textTheme: GoogleFonts.poppinsTextTheme()),
      home: CoordinateView(),
    );
  }
}
