import 'package:flutter/material.dart';

class ActionButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color backgroundColor;
  final Color foregroundColor;
  final double height;
  final double borderRadius;
  final VoidCallback? onPressed;
  final bool isLoading;

  const ActionButton({
    super.key,
    required this.label,
    required this.icon,
    required this.backgroundColor,
    required this.foregroundColor,
    this.height = 60,
    this.borderRadius = 12,
    this.onPressed,
    this.isLoading = false,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: height,
      child: ElevatedButton.icon(
        onPressed: onPressed,
        icon:
            isLoading
                ? SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(foregroundColor),
                  ),
                )
                : Icon(icon),
        label: Text(label, style: TextStyle(fontSize: 16)),
        style: ElevatedButton.styleFrom(
          backgroundColor: backgroundColor,
          foregroundColor: foregroundColor,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(borderRadius),
          ),
        ),
      ),
    );
  }
}
