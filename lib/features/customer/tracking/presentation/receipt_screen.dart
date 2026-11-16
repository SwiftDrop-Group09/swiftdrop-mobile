import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/tracking_api.dart';
import '../domain/tracking_models.dart';
import 'status_badge.dart';

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
  bool _downloadingPdf = false;

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

  Future<void> _handleDownloadPdf() async {
    if (_receipt == null) return;
    setState(() => _downloadingPdf = true);
    try {
      final bytes = await widget.api.downloadReceiptPdf(widget.parcelId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.check_circle_outline, color: Colors.white, size: 20),
              const SizedBox(width: 8),
              Text('Official PDF Receipt downloaded (${bytes.length} bytes).'),
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
      appBar: AppBar(title: const Text('Digital Receipt')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null || _receipt == null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      _error ?? 'Receipt unavailable.',
                      style: TextStyle(color: theme.colorScheme.error),
                    ),
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
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
                            // Header
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'SwiftDrop Official Receipt',
                                      style: theme.textTheme.titleMedium?.copyWith(
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      _receipt!.receiptNumber,
                                      style: const TextStyle(
                                        fontFamily: 'monospace',
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                                StatusBadge(status: _receipt!.status),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Tracking: ${_receipt!.trackingNumber}',
                              style: theme.textTheme.bodySmall?.copyWith(
                                fontFamily: 'monospace',
                                fontSize: 11,
                              ),
                            ),
                            const Divider(height: 24),

                            // Route & Addresses
                            Text(
                              'PICKUP LOCATION',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: theme.colorScheme.primary,
                                letterSpacing: 0.6,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '${_receipt!.pickupAddress.street}, ${_receipt!.pickupAddress.city} (${_receipt!.pickupAddress.postalCode})',
                              style: const TextStyle(fontSize: 13),
                            ),
                            const SizedBox(height: 10),
                            Text(
                              'DELIVERY LOCATION',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: theme.colorScheme.primary,
                                letterSpacing: 0.6,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '${_receipt!.deliveryAddress.street}, ${_receipt!.deliveryAddress.city} (${_receipt!.deliveryAddress.postalCode})',
                              style: const TextStyle(fontSize: 13),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'Recipient: ${_receipt!.recipient.name} (${_receipt!.recipient.phoneNumber})',
                              style: theme.textTheme.bodySmall?.copyWith(fontSize: 12),
                            ),
                            const Divider(height: 24),

                            // Package specs & Tariff
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  'Package Details',
                                  style: theme.textTheme.bodySmall?.copyWith(fontSize: 12),
                                ),
                                Text(
                                  '${_receipt!.packageDetails.weightKg.toStringAsFixed(1)} kg · ${_receipt!.packageDetails.size}',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                            if (_receipt!.pricingVersion.isNotEmpty) ...[
                              const SizedBox(height: 4),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    'Tariff Version',
                                    style: theme.textTheme.bodySmall?.copyWith(fontSize: 12),
                                  ),
                                  Text(
                                    _receipt!.pricingVersion,
                                    style: const TextStyle(
                                      fontFamily: 'monospace',
                                      fontSize: 11,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                            const Divider(height: 24),

                            // Itemized Breakdown
                            _FeeRow(
                              'Base Delivery Fee',
                              '${_receipt!.currency} ${_receipt!.baseFee.toStringAsFixed(2)}',
                            ),
                            const SizedBox(height: 8),
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

                    // Primary Download PDF Button
                    FilledButton.icon(
                      onPressed: _downloadingPdf ? null : _handleDownloadPdf,
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      icon: _downloadingPdf
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.download_outlined),
                      label: Text(
                        _downloadingPdf ? 'Downloading PDF...' : 'Download PDF Receipt',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                    const SizedBox(height: 10),

                    // Copy / Share Text Button
                    OutlinedButton.icon(
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
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      icon: const Icon(Icons.copy_all_outlined),
                      label: const Text('Copy / Share Receipt Text'),
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
        ? const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)
        : const TextStyle(fontSize: 13);
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: style),
        Text(value, style: style),
      ],
    );
  }
}
