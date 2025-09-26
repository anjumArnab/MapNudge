import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../views/homepage.dart';

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
      theme: ThemeData(
        scaffoldBackgroundColor: Color(0XFFF5F5F5),
        textTheme: GoogleFonts.poppinsTextTheme(),
      ),
      home: Homepage(),
    );
  }
}
