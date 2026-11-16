import 'package:flutter/material.dart';

import '../domain/tracking_models.dart';
import 'receipt_screen.dart';
import 'status_badge.dart';
import 'tracking_controller.dart';

class CustomerTrackingScreen extends StatefulWidget {
  const CustomerTrackingScreen({super.key, required this.controller});

  final CustomerParcelDetailController controller;

  @override
  State<CustomerTrackingScreen> createState() => _CustomerTrackingScreenState();
}

class _CustomerTrackingScreenState extends State<CustomerTrackingScreen> {
  static const _steps = [
    'Created',
    'Assigned',
    'PickedUp',
    'InTransit',
    'OutForDelivery',
    'Delivered',
  ];

  bool _downloadingPdf = false;

  @override
  void initState() {
    super.initState();
    widget.controller.load();
  }

  @override
  void dispose() {
    widget.controller.dispose();
    super.dispose();
  }

  Future<void> _handleDownloadPdf(String parcelId) async {
    setState(() => _downloadingPdf = true);
    try {
      final bytes = await widget.controller.api.downloadReceiptPdf(parcelId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.check_circle_outline, color: Colors.white, size: 20),
              const SizedBox(width: 8),
              Text('PDF Receipt downloaded (${bytes.length} bytes).'),
            ],
          ),
          backgroundColor: const Color(0xFF047857),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Failed to download PDF receipt.'),
          backgroundColor: Color(0xFFB91C1C),
        ),
      );
    } finally {
      if (mounted) setState(() => _downloadingPdf = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Live Parcel Tracking'),
        actions: [
          IconButton(
            icon: const Icon(Icons.auto_awesome_outlined),
            tooltip: 'Delivery Assistant',
            onPressed: () {
              Navigator.of(context).pushNamed('/assistant');
            },
          ),
        ],
      ),
      body: ListenableBuilder(
        listenable: widget.controller,
        builder: (context, _) {
          final c = widget.controller;
          if (c.loading && c.parcel == null) {
            return const Center(child: CircularProgressIndicator());
          }
          if (c.error != null && c.parcel == null) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  c.error!,
                  style: TextStyle(color: theme.colorScheme.error),
                ),
              ),
            );
          }
          final parcel = c.parcel;
          if (parcel == null) return const SizedBox.shrink();

          final rawStepIndex = _steps.indexOf(parcel.status);
          final activeStep = rawStepIndex >= 0 ? rawStepIndex : 0;
          final milestoneNum = rawStepIndex >= 0 ? rawStepIndex + 1 : 1;
          final milestoneProgress = (milestoneNum / 6).clamp(0.0, 1.0);

          return RefreshIndicator(
            onRefresh: () => c.load(startLivePolling: false),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // Live Polling Banner if active
                if (c.isLivePollingActive)
                  Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: const Color(0xFFECFDF5),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: const Color(0xFFA7F3D0)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: const BoxDecoration(
                            color: Color(0xFF047857),
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 8),
                        const Text(
                          'Live updates (4s)',
                          style: TextStyle(
                            color: Color(0xFF047857),
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),

                // Parcel Header Card
                Card(
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                    side: BorderSide(
                      color: theme.colorScheme.outlineVariant.withOpacity(0.6),
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              parcel.trackingNumber,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                fontFamily: 'monospace',
                              ),
                            ),
                            StatusBadge(status: parcel.status),
                          ],
                        ),
                        const SizedBox(height: 12),
                        // Route Card
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.25),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 36,
                                height: 36,
                                decoration: BoxDecoration(
                                  color: theme.colorScheme.primary.withOpacity(0.08),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                    color: theme.colorScheme.primary.withOpacity(0.15),
                                  ),
                                ),
                                child: Icon(
                                  Icons.place_outlined,
                                  size: 20,
                                  color: theme.colorScheme.primary,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      '${parcel.pickupAddress.city} → ${parcel.deliveryAddress.city}',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                        fontSize: 14,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      'Recipient: ${parcel.recipient.name} (${parcel.recipient.phoneNumber})',
                                      style: theme.textTheme.bodySmall?.copyWith(fontSize: 11),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 14),

                // 6-Stage Milestone Progress + Stepper
                Card(
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                    side: BorderSide(
                      color: theme.colorScheme.outlineVariant.withOpacity(0.6),
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              'Delivery Progress',
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                            ),
                            if (parcel.status != 'Failed' && parcel.status != 'Cancelled')
                              Text(
                                'Milestone $milestoneNum of 6',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        if (parcel.status == 'Failed' || parcel.status == 'Cancelled') ...[
                          Text(
                            parcelStatusLabel(parcel.status),
                            style: TextStyle(
                              color: theme.colorScheme.error,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ] else ...[
                          ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: LinearProgressIndicator(
                              value: milestoneProgress,
                              minHeight: 6,
                              backgroundColor: theme.colorScheme.outlineVariant.withOpacity(0.3),
                              valueColor: AlwaysStoppedAnimation(
                                parcel.status == 'Delivered'
                                    ? const Color(0xFF047857)
                                    : theme.colorScheme.primary,
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          ...List.generate(_steps.length, (i) {
                            final done = i <= activeStep;
                            final isCurrent = i == activeStep;
                            return ListTile(
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                              leading: Icon(
                                done ? Icons.check_circle : Icons.radio_button_unchecked,
                                color: done
                                    ? (parcel.status == 'Delivered'
                                        ? const Color(0xFF047857)
                                        : theme.colorScheme.primary)
                                    : Colors.grey,
                                size: 20,
                              ),
                              title: Text(
                                parcelStatusLabel(_steps[i]),
                                style: TextStyle(
                                  fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
                                  fontSize: 13,
                                ),
                              ),
                            );
                          }),
                        ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 14),

                // Documents & Receipt Section
                Card(
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                    side: BorderSide(
                      color: theme.colorScheme.outlineVariant.withOpacity(0.6),
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Documents & Proof',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                        ),
                        const SizedBox(height: 10),
                        if (parcel.status == 'Delivered') ...[
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: () {
                                    Navigator.of(context).push(
                                      MaterialPageRoute<void>(
                                        builder: (_) => CustomerReceiptScreen(
                                          api: c.api,
                                          parcelId: parcel.id,
                                        ),
                                      ),
                                    );
                                  },
                                  icon: const Icon(Icons.receipt_long_outlined, size: 18),
                                  label: const Text('View Receipt'),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: FilledButton.tonalIcon(
                                  onPressed: _downloadingPdf
                                      ? null
                                      : () => _handleDownloadPdf(parcel.id),
                                  icon: _downloadingPdf
                                      ? const SizedBox(
                                          width: 16,
                                          height: 16,
                                          child: CircularProgressIndicator(strokeWidth: 2),
                                        )
                                      : const Icon(Icons.download_outlined, size: 18),
                                  label: const Text('PDF Receipt'),
                                ),
                              ),
                            ],
                          ),
                          if (c.proof != null) ...[
                            const SizedBox(height: 10),
                            ListTile(
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                              leading: const Icon(
                                Icons.verified_outlined,
                                color: Color(0xFF047857),
                              ),
                              title: const Text('Proof of Delivery Confirmed'),
                              subtitle: Text(
                                '${c.proof!.proofType} · Received by ${c.proof!.recipientName}',
                              ),
                            ),
                          ],
                        ] else ...[
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.info_outline,
                                  size: 18,
                                  color: theme.colorScheme.outline,
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    'Documents available after delivery — Once your parcel is delivered, return here for its receipt and any proof of delivery.',
                                    style: theme.textTheme.bodySmall?.copyWith(fontSize: 12),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 14),

                // Event History Timeline
                Card(
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                    side: BorderSide(
                      color: theme.colorScheme.outlineVariant.withOpacity(0.6),
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Event History Timeline',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                        ),
                        const SizedBox(height: 10),
                        if (parcel.history.isEmpty)
                          Text(
                            'No timeline events recorded yet.',
                            style: theme.textTheme.bodySmall,
                          )
                        else
                          ...parcel.history.map(
                            (entry) => ListTile(
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                              leading: Icon(
                                Icons.circle,
                                size: 8,
                                color: theme.colorScheme.primary,
                              ),
                              title: Text(
                                parcelStatusLabel(entry.toStatus),
                                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                              ),
                              subtitle: Text(
                                entry.changeReason ??
                                    entry.timestamp.toLocal().toString().substring(0, 16),
                                style: theme.textTheme.bodySmall?.copyWith(fontSize: 11),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
