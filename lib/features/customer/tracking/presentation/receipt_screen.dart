import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/tracking_api.dart';
import '../domain/tracking_models.dart';

class CustomerReceiptScreen extends StatefulWidget {
  const CustomerReceiptScreen({
    super.key,
    required this.api,
    required this.parcelId,
  });

  final TrackingApi api;
  final String parcelId;

  @override
  State<CustomerReceiptScreen> createState() => _CustomerReceiptScreenState();
}

class _CustomerReceiptScreenState extends State<CustomerReceiptScreen> {
  ParcelReceiptModel? _receipt;
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await widget.api.getReceipt(widget.parcelId);
      if (!mounted) return;
      setState(() {
        _receipt = result;
        _loading = false;
      });
    } on TrackingApiFailure catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message ?? 'Receipt unavailable (${e.code}).';
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Unable to load receipt.';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Digital Receipt')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null || _receipt == null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  _error ?? 'Receipt unavailable.',
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            )
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'SwiftDrop Receipt',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(height: 4),
                        Text(_receipt!.receiptNumber),
                        Text(
                          'Tracking: ${_receipt!.trackingNumber}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        const Divider(height: 24),
                        Text(
                          'Pickup: ${_receipt!.pickupAddress.street}, ${_receipt!.pickupAddress.city}',
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Delivery: ${_receipt!.deliveryAddress.street}, ${_receipt!.deliveryAddress.city}',
                        ),
                        const SizedBox(height: 4),
                        Text('Recipient: ${_receipt!.recipient.name}'),
                        const Divider(height: 24),
                        _FeeRow(
                          'Base Delivery Fee',
                          '${_receipt!.currency} ${_receipt!.baseFee.toStringAsFixed(2)}',
                        ),
                        const SizedBox(height: 6),
                        _FeeRow(
                          'Weight Surcharge',
                          '${_receipt!.currency} ${_receipt!.weightFee.toStringAsFixed(2)}',
                        ),
                        const Divider(height: 20),
                        _FeeRow(
                          'Total Charged',
                          '${_receipt!.currency} ${_receipt!.total.toStringAsFixed(2)}',
                          bold: true,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: () async {
                    await Clipboard.setData(
                      ClipboardData(text: _receipt!.toShareableText()),
                    );
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Receipt copied to clipboard.'),
                      ),
                    );
                  },
                  icon: const Icon(Icons.copy_all_outlined),
                  label: const Text('Copy / Share Receipt'),
                ),
              ],
            ),
    );
  }
}

class _FeeRow extends StatelessWidget {
  const _FeeRow(this.label, this.value, {this.bold = false});
  final String label;
  final String value;
  final bool bold;

  @override
  Widget build(BuildContext context) {
    final style = bold
        ? const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)
        : null;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: style),
        Text(value, style: style),
      ],
    );
  }
}
