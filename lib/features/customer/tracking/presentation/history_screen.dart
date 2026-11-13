import 'package:flutter/material.dart';

import '../domain/tracking_models.dart';
import 'tracking_controller.dart';
import 'tracking_screen.dart';
import 'receipt_screen.dart';

class CustomerHistoryScreen extends StatefulWidget {
  const CustomerHistoryScreen({super.key, required this.controller});

  final CustomerHistoryController controller;

  @override
  State<CustomerHistoryScreen> createState() => _CustomerHistoryScreenState();
}

class _CustomerHistoryScreenState extends State<CustomerHistoryScreen> {
  final _searchController = TextEditingController();

  static const _filters = <(String, String?)>[
    ('All', null),
    ('In Transit', 'InTransit'),
    ('Delivered', 'Delivered'),
    ('Cancelled', 'Cancelled'),
    ('Failed', 'Failed'),
  ];

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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Order History')),
      body: ListenableBuilder(
        listenable: widget.controller,
        builder: (context, _) {
          final c = widget.controller;
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: 'Search tracking # or recipient',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.arrow_forward),
                      onPressed: () => c.setSearch(_searchController.text),
                    ),
                  ),
                  onSubmitted: c.setSearch,
                ),
              ),
              SizedBox(
                height: 44,
                child: ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  scrollDirection: Axis.horizontal,
                  itemCount: _filters.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 8),
                  itemBuilder: (context, index) {
                    final (label, value) = _filters[index];
                    return FilterChip(
                      label: Text(label),
                      selected: c.statusFilter == value,
                      onSelected: (_) => c.setStatusFilter(value),
                    );
                  },
                ),
              ),
              const SizedBox(height: 8),
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
              style: TextStyle(color: Theme.of(context).colorScheme.error),
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
        return Card(
          margin: const EdgeInsets.only(bottom: 12),
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
                      ),
                    ),
                    Chip(
                      label: Text(parcelStatusLabel(item.status)),
                      visualDensity: VisualDensity.compact,
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text('${item.pickupCity} -> ${item.deliveryCity}'),
                Text(
                  'Recipient: ${item.recipientName} · ${item.priceSnapshot.currency} ${item.priceSnapshot.total.toStringAsFixed(2)}',
                  style: Theme.of(context).textTheme.bodySmall,
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
                      icon: const Icon(Icons.location_on_outlined, size: 18),
                      label: const Text('Track'),
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
                        icon: const Icon(Icons.receipt_long_outlined, size: 18),
                        label: const Text('Receipt'),
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
