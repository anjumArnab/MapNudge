import 'package:flutter/material.dart';

class AppTextField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String hint;
  final IconData icon;
  final String? helperText;
  final bool enabled;
  final TextInputType keyboardType;
  final int? maxLength;
  final double? minValue;
  final double? maxValue;
  final FormFieldSetter<String>? onSaved;
  final FormFieldValidator<String>? validator;

  const AppTextField({
    super.key,
    required this.controller,
    required this.label,
    required this.hint,
    required this.icon,
    this.helperText,
    this.enabled = true,
    this.keyboardType = TextInputType.text,
    this.maxLength,
    this.minValue,
    this.maxValue,
    this.onSaved,
    this.validator,
  });

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      enabled: enabled,
      keyboardType: keyboardType,
      maxLength: maxLength,
      onSaved: onSaved,
      validator:
          validator ??
          (minValue != null && maxValue != null
              ? (value) {
                if (value == null || value.isEmpty) {
                  return '$label is required';
                }
                final double? parsedValue = double.tryParse(value);
                if (parsedValue == null) {
                  return 'Please enter a valid number';
                }
                if (parsedValue < minValue! || parsedValue > maxValue!) {
                  return '$label must be between $minValue and $maxValue';
                }
                return null;
              }
              : null),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: Icon(icon),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        helperText: helperText,
      ),
    );
  }
}
