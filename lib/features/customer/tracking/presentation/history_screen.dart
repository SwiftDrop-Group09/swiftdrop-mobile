import 'package:flutter/material.dart';

import '../domain/tracking_models.dart';
import 'receipt_screen.dart';
import 'status_badge.dart';
import 'tracking_controller.dart';
import 'tracking_screen.dart';

class CustomerHistoryScreen extends StatefulWidget {
  const CustomerHistoryScreen({super.key, required this.controller});

  final CustomerHistoryController controller;

  @override
  State<CustomerHistoryScreen> createState() => _CustomerHistoryScreenState();
}

class _CustomerHistoryScreenState extends State<CustomerHistoryScreen> {
  final _searchController = TextEditingController();

  static const _filters = <(String, String?)>[
    ('All statuses', null),
    ('Booked', 'Created'),
    ('Assigned', 'Assigned'),
    ('Collected', 'PickedUp'),
    ('In transit', 'InTransit'),
    ('Out for delivery', 'OutForDelivery'),
    ('Delivered', 'Delivered'),
    ('Delivery unsuccessful', 'Failed'),
    ('Cancelled', 'Cancelled'),
  ];

  DateTimeRange? _selectedDateRange;
  String? _downloadingParcelId;

  @override
  void initState() {
    super.initState();
    widget.controller.load(refresh: true);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _pickDateRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(now.year + 2),
      initialDateRange: _selectedDateRange,
    );

    if (picked != null) {
      setState(() => _selectedDateRange = picked);
      await widget.controller.setDateRange(picked.start, picked.end);
    }
  }

  Future<void> _clearDateRange() async {
    setState(() => _selectedDateRange = null);
    await widget.controller.setDateRange(null, null);
  }

  Future<void> _handleDownloadPdf(String parcelId) async {
    setState(() => _downloadingParcelId = parcelId);
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
      if (mounted) setState(() => _downloadingParcelId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Order History'),
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
          return Column(
            children: [
              // Search input
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
                child: TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: 'Search tracking # or recipient',
                    prefixIcon: const Icon(Icons.search, size: 20),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.arrow_forward, size: 20),
                      onPressed: () => c.setSearch(_searchController.text),
                    ),
                  ),
                  onSubmitted: c.setSearch,
                ),
              ),

              // Date Range Filter Bar
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: Row(
                  children: [
                    OutlinedButton.icon(
                      onPressed: _pickDateRange,
                      style: OutlinedButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      icon: const Icon(Icons.date_range_outlined, size: 16),
                      label: Text(
                        _selectedDateRange != null
                            ? '${_selectedDateRange!.start.month}/${_selectedDateRange!.start.day} - ${_selectedDateRange!.end.month}/${_selectedDateRange!.end.day}'
                            : 'Filter by date',
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                    if (_selectedDateRange != null) ...[
                      const SizedBox(width: 6),
                      IconButton(
                        icon: const Icon(Icons.close, size: 16),
                        tooltip: 'Clear date filter',
                        onPressed: _clearDateRange,
                        visualDensity: VisualDensity.compact,
                      ),
                    ],
                  ],
                ),
              ),

              // 9 Lifecycle Status Filter Chips
              SizedBox(
                height: 40,
                child: ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  scrollDirection: Axis.horizontal,
                  itemCount: _filters.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 6),
                  itemBuilder: (context, index) {
                    final (label, value) = _filters[index];
                    return FilterChip(
                      label: Text(label, style: const TextStyle(fontSize: 12)),
                      selected: c.statusFilter == value,
                      onSelected: (_) => c.setStatusFilter(value),
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                    );
                  },
                ),
              ),
              const SizedBox(height: 6),

              // List of parcels
              Expanded(
                child: RefreshIndicator(
                  onRefresh: () => c.load(refresh: true),
                  child: _buildList(context, c),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildList(BuildContext context, CustomerHistoryController c) {
    final theme = Theme.of(context);

    if (c.loading && c.items.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (c.error != null && c.items.isEmpty) {
      return ListView(
        children: [
          Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              c.error!,
              textAlign: TextAlign.center,
              style: TextStyle(color: theme.colorScheme.error),
            ),
          ),
        ],
      );
    }
    if (c.items.isEmpty) {
      return ListView(
        children: const [
          Padding(
            padding: EdgeInsets.all(32),
            child: Column(
              children: [
                Icon(Icons.inventory_2_outlined, size: 48),
                SizedBox(height: 12),
                Text('No deliveries found', style: TextStyle(fontSize: 16)),
              ],
            ),
          ),
        ],
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: c.items.length + (c.hasMore ? 1 : 0),
      itemBuilder: (context, index) {
        if (index == c.items.length) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Center(
              child: OutlinedButton(
                onPressed: c.loading ? null : c.loadNextPage,
                child: const Text('Load more'),
              ),
            ),
          );
        }
        final item = c.items[index];
        final isDownloadingThisPdf = _downloadingParcelId == item.id;

        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(
              color: theme.colorScheme.outlineVariant.withOpacity(0.6),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      item.trackingNumber,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontFamily: 'monospace',
                        fontSize: 13,
                      ),
                    ),
                    StatusBadge(status: item.status, useCompact: true),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  '${item.pickupCity} → ${item.deliveryCity}',
                  style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13),
                ),
                const SizedBox(height: 2),
                Text(
                  'Recipient: ${item.recipientName} · ${item.priceSnapshot.currency} ${item.priceSnapshot.total.toStringAsFixed(2)}',
                  style: theme.textTheme.bodySmall?.copyWith(fontSize: 11),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    FilledButton.tonalIcon(
                      onPressed: () {
                        Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => CustomerTrackingScreen(
                              controller: CustomerParcelDetailController(
                                api: widget.controller.api,
                                parcelId: item.id,
                              ),
                            ),
                          ),
                        );
                      },
                      style: FilledButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      icon: const Icon(Icons.location_on_outlined, size: 16),
                      label: const Text('Track', style: TextStyle(fontSize: 12)),
                    ),
                    if (item.status == 'Delivered') ...[
                      const SizedBox(width: 8),
                      OutlinedButton.icon(
                        onPressed: () {
                          Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => CustomerReceiptScreen(
                                api: widget.controller.api,
                                parcelId: item.id,
                              ),
                            ),
                          );
                        },
                        style: OutlinedButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        icon: const Icon(Icons.receipt_long_outlined, size: 16),
                        label: const Text('Receipt', style: TextStyle(fontSize: 12)),
                      ),
                      const SizedBox(width: 6),
                      IconButton(
                        icon: isDownloadingThisPdf
                            ? const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.download_outlined, size: 18),
                        tooltip: 'Download PDF Receipt',
                        onPressed: isDownloadingThisPdf
                            ? null
                            : () => _handleDownloadPdf(item.id),
                        visualDensity: VisualDensity.compact,
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
