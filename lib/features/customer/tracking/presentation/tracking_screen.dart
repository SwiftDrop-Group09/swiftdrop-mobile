import 'package:flutter/material.dart';

import '../domain/tracking_models.dart';
import 'receipt_screen.dart';
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Live Parcel Tracking')),
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
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            );
          }
          final parcel = c.parcel;
          if (parcel == null) return const SizedBox.shrink();

          final activeStep = _steps.indexOf(parcel.status);

          return RefreshIndicator(
            onRefresh: () => c.load(startLivePolling: false),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Card(
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
                            Chip(label: Text(parcelStatusLabel(parcel.status))),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '${parcel.pickupAddress.city} -> ${parcel.deliveryAddress.city}',
                        ),
                        Text(
                          'Recipient: ${parcel.recipient.name} (${parcel.recipient.phoneNumber})',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Delivery Progress',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 12),
                        if (parcel.status == 'Failed' ||
                            parcel.status == 'Cancelled')
                          Text(
                            parcelStatusLabel(parcel.status),
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                              fontWeight: FontWeight.w600,
                            ),
                          )
                        else
                          ...List.generate(_steps.length, (i) {
                            final done = i <= activeStep;
                            return ListTile(
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                              leading: Icon(
                                done
                                    ? Icons.check_circle
                                    : Icons.radio_button_unchecked,
                                color: done
                                    ? Theme.of(context).colorScheme.primary
                                    : Colors.grey,
                              ),
                              title: Text(parcelStatusLabel(_steps[i])),
                            );
                          }),
                      ],
                    ),
                  ),
                ),
                if (c.proof != null) ...[
                  const SizedBox(height: 12),
                  Card(
                    child: ListTile(
                      leading: const Icon(Icons.verified_outlined),
                      title: const Text('Proof of Delivery'),
                      subtitle: Text(
                        '${c.proof!.proofType} · Received by ${c.proof!.recipientName}',
                      ),
                    ),
                  ),
                ],
                if (parcel.status == 'Delivered') ...[
                  const SizedBox(height: 12),
                  FilledButton.icon(
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
                    icon: const Icon(Icons.receipt_long),
                    label: const Text('View Digital Receipt'),
                  ),
                ],
                const SizedBox(height: 16),
                const Text(
                  'Event History',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                ...parcel.history.map(
                  (entry) => Card(
                    child: ListTile(
                      title: Text(parcelStatusLabel(entry.toStatus)),
                      subtitle: Text(
                        entry.changeReason ??
                            entry.timestamp.toLocal().toString(),
                      ),
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
