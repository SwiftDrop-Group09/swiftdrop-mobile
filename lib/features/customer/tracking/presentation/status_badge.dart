import 'package:flutter/material.dart';

import '../domain/tracking_models.dart';

class StatusBadge extends StatelessWidget {
  const StatusBadge({
    super.key,
    required this.status,
    this.useCompact = false,
  });

  final String status;
  final bool useCompact;

  @override
  Widget build(BuildContext context) {
    final label = parcelStatusLabel(status);
    final (bg, fg, border) = switch (status) {
      'Delivered' => (
        const Color(0xFFECFDF5),
        const Color(0xFF047857),
        const Color(0xFFA7F3D0),
      ),
      'InTransit' || 'OutForDelivery' => (
        const Color(0xFFF0F9FF),
        const Color(0xFF0369A1),
        const Color(0xFFBAE6FD),
      ),
      'Created' || 'Assigned' || 'PickedUp' => (
        const Color(0xFFFFFBEB),
        const Color(0xFFB45309),
        const Color(0xFFFDE68A),
      ),
      'Failed' || 'Cancelled' => (
        const Color(0xFFFEF2F2),
        const Color(0xFFB91C1C),
        const Color(0xFFFECACA),
      ),
      _ => (
        Colors.grey.shade100,
        Colors.grey.shade700,
        Colors.grey.shade300,
      ),
    };

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: useCompact ? 8 : 10,
        vertical: useCompact ? 2 : 4,
      ),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: border),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: fg,
          fontSize: useCompact ? 11 : 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
