import 'package:flutter/material.dart';

class CoordinateField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String hint;
  final double minValue;
  final double maxValue;
  final IconData icon;
  final Function(String?) onSaved;

  const CoordinateField({
    super.key,
    required this.controller,
    required this.label,
    required this.hint,
    required this.minValue,
    required this.maxValue,
    required this.icon,
    required this.onSaved,
  });

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: Icon(icon, color: Colors.green.shade600),
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: Colors.green.shade600, width: 2),
        ),
        labelStyle: TextStyle(color: Colors.green.shade700),
      ),
      keyboardType: const TextInputType.numberWithOptions(
        decimal: true,
        signed: true,
      ),
      validator: (value) {
        if (value == null || value.isEmpty) {
          return '$label is required';
        }
        final double? parsedValue = double.tryParse(value);
        if (parsedValue == null) {
          return 'Please enter a valid number';
        }
        if (parsedValue < minValue || parsedValue > maxValue) {
          return '$label must be between $minValue and $maxValue';
        }
        return null;
      },
      onSaved: onSaved,
    );
  }
}
