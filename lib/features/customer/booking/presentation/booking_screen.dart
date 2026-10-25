import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/network/exact_json.dart';
import '../domain/booking_models.dart';
import 'booking_controller.dart';

class BookingScreen extends StatefulWidget {
  const BookingScreen({super.key, required this.controller});
  final BookingController controller;
  @override
  State<BookingScreen> createState() => _BookingScreenState();
}

class _BookingScreenState extends State<BookingScreen> {
  GlobalKey<FormState> _form = GlobalKey<FormState>();
  final _fields = <String, TextEditingController>{
    for (final name in [
      'pickupStreet',
      'pickupCity',
      'pickupPostalCode',
      'deliveryStreet',
      'deliveryCity',
      'deliveryPostalCode',
      'recipientName',
      'recipientPhone',
      'weight',
    ])
      name: TextEditingController(),
  };
  String? _pickupZone;
  String? _deliveryZone;
  String? _size;
  BookingDraft? _displayedDraft;
  late final Timer _timer;
  late int _sessionRevision;
  BookingController get controller => widget.controller;

  @override
  void initState() {
    super.initState();
    _sessionRevision = controller.sessionRevision;
    _restoreQuotedDraft();
    controller.addListener(_controllerChanged);
    _timer = Timer.periodic(
      const Duration(seconds: 1),
      (_) => controller.refreshTime(),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(controller.loadZones());
    });
  }

  void _controllerChanged() {
    if (_sessionRevision != controller.sessionRevision) {
      _sessionRevision = controller.sessionRevision;
      _displayedDraft = null;
      for (final field in _fields.values) {
        field.clear();
      }
      _pickupZone = null;
      _deliveryZone = null;
      _size = null;
      if (mounted) {
        setState(() => _form = GlobalKey<FormState>());
        unawaited(controller.loadZones());
      }
    } else if (_restoreQuotedDraft() && mounted) {
      setState(() => _form = GlobalKey<FormState>());
    }
  }

  bool _restoreQuotedDraft() {
    final draft = controller.quotedDraft;
    if (draft == null || identical(draft, _displayedDraft)) return false;
    _displayedDraft = draft;
    final values = {
      'pickupStreet': draft.pickup.street,
      'pickupCity': draft.pickup.city,
      'pickupPostalCode': draft.pickup.postalCode,
      'deliveryStreet': draft.delivery.street,
      'deliveryCity': draft.delivery.city,
      'deliveryPostalCode': draft.delivery.postalCode,
      'recipientName': draft.recipientName,
      'recipientPhone': draft.recipientPhone,
      'weight': draft.weight,
    };
    for (final entry in values.entries) {
      _fields[entry.key]!.text = entry.value;
    }
    _pickupZone = draft.pickup.zoneId;
    _deliveryZone = draft.delivery.zoneId;
    _size = draft.size;
    return true;
  }

  @override
  void dispose() {
    _timer.cancel();
    controller.removeListener(_controllerChanged);
    for (final field in _fields.values) {
      field.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder: (context, _) => PopScope(
      canPop: !controller.locked,
      child: Scaffold(
        appBar: AppBar(title: const Text('Book a delivery')),
        body: !controller.canBook
            ? const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.lock_outline, size: 40),
                      SizedBox(height: 16),
                      Text(
                        'Sign in with a Customer account to book a delivery.',
                      ),
                    ],
                  ),
                ),
              )
            : SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 680),
                    child: controller.stage == BookingStage.success
                        ? _result()
                        : _bookingForm(),
                  ),
                ),
              ),
      ),
    ),
  );

  Widget _bookingForm() => Form(
    key: _form,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Delivery details',
          style: TextStyle(fontSize: 26, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        const Text(
          'Get a delivery fee first. Your parcel is booked only after you confirm.',
        ),
        const SizedBox(height: 20),
        if (controller.zonesLoading) const LinearProgressIndicator(),
        if (!controller.zonesLoading && controller.zones.isEmpty)
          OutlinedButton(
            onPressed: controller.loadZones,
            child: const Text('Reload address coverage'),
          ),
        _address(
          'Pickup',
          'pickup',
          _pickupZone,
          (value) => _pickupZone = value,
        ),
        const SizedBox(height: 20),
        _address(
          'Delivery',
          'delivery',
          _deliveryZone,
          (value) => _deliveryZone = value,
        ),
        const SizedBox(height: 20),
        _heading('Recipient'),
        _text('recipientName', 'Recipient name', serverField: 'recipient.name'),
        _text(
          'recipientPhone',
          'Recipient phone number',
          serverField: 'recipient.phoneNumber',
          keyboard: TextInputType.phone,
        ),
        const SizedBox(height: 20),
        _heading('Parcel'),
        DropdownButtonFormField<String>(
          key: const Key('size'),
          initialValue: _size,
          decoration: InputDecoration(
            labelText: 'Parcel size',
            errorText: controller.fieldErrors['packageDetails.size'],
          ),
          items: const ['Small', 'Medium', 'Large']
              .map((size) => DropdownMenuItem(value: size, child: Text(size)))
              .toList(),
          onChanged: controller.locked
              ? null
              : (value) {
                  _size = value;
                  controller.inputChanged();
                },
          validator: (value) => value == null ? 'Choose a parcel size.' : null,
        ),
        _text(
          'weight',
          'Weight (kg)',
          keyboard: const TextInputType.numberWithOptions(decimal: true),
          validator: (value) =>
              ExactNumber.tryParse(value ?? '')?.isWeight == true
              ? null
              : 'Enter an exact weight greater than 0 and at most 30 kg.',
          serverField: 'packageDetails.weightKg',
        ),
        const SizedBox(height: 20),
        if (controller.error != null)
          Semantics(
            liveRegion: true,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Text(
                controller.error!,
                key: const Key('bookingError'),
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          ),
        if (controller.quote != null) _preview(),
        if (controller.stage == BookingStage.confirming) ...[
          const LinearProgressIndicator(),
          const SizedBox(height: 12),
          const Text(
            'Confirming your booking…',
            semanticsLabel: 'Confirming your booking',
          ),
        ],
        if (controller.stage == BookingStage.uncertain) ...[
          const Text(
            'Your confirmation may already have been received. Recover the same attempt before starting another booking.',
          ),
          const SizedBox(height: 12),
          FilledButton(
            key: const Key('retryConfirmation'),
            onPressed: controller.canRetry ? controller.confirm : null,
            child: const Text('Retry this confirmation'),
          ),
        ],
        if (controller.attempt == null)
          FilledButton(
            key: const Key('estimateFee'),
            onPressed:
                controller.stage == BookingStage.estimating ||
                    controller.zones.isEmpty
                ? null
                : _estimate,
            child: Text(
              controller.stage == BookingStage.estimating
                  ? 'Estimating…'
                  : 'Estimate delivery fee',
            ),
          ),
      ],
    ),
  );

  Widget _address(
    String title,
    String prefix,
    String? value,
    ValueChanged<String?> changed,
  ) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _heading('$title address'),
      _text(
        '${prefix}Street',
        '$title street',
        serverField: '${prefix}Address.street',
      ),
      _text(
        '${prefix}City',
        '$title city',
        serverField: '${prefix}Address.city',
      ),
      _text(
        '${prefix}PostalCode',
        '$title postal code',
        serverField: '${prefix}Address.postalCode',
      ),
      DropdownButtonFormField<String>(
        key: Key('${prefix}Zone'),
        initialValue: value,
        decoration: InputDecoration(
          labelText: '$title service zone',
          errorText: controller.fieldErrors['${prefix}Address.zoneId'],
        ),
        items: controller.zones
            .map(
              (zone) =>
                  DropdownMenuItem(value: zone.id, child: Text(zone.name)),
            )
            .toList(),
        onChanged: controller.locked
            ? null
            : (selected) {
                changed(selected);
                controller.inputChanged();
              },
        validator: (selected) =>
            selected == null ? 'Choose a service zone.' : null,
      ),
    ],
  );

  Widget _heading(String value) => Padding(
    padding: const EdgeInsets.only(bottom: 4),
    child: Text(
      value,
      style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
    ),
  );

  Widget _text(
    String key,
    String label, {
    TextInputType? keyboard,
    String? Function(String?)? validator,
    String? serverField,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: TextFormField(
      key: Key(key),
      controller: _fields[key],
      enabled: !controller.locked,
      decoration: InputDecoration(
        labelText: label,
        errorText: controller.fieldErrors[serverField],
      ),
      keyboardType: keyboard,
      validator: validator ?? requiredText,
      onChanged: (_) => controller.inputChanged(),
    ),
  );

  void _estimate() {
    if (!_form.currentState!.validate()) return;
    unawaited(
      controller.estimate(
        BookingDraft(
          pickup: BookingAddress(
            street: _fields['pickupStreet']!.text,
            city: _fields['pickupCity']!.text,
            postalCode: _fields['pickupPostalCode']!.text,
            zoneId: _pickupZone!,
          ),
          delivery: BookingAddress(
            street: _fields['deliveryStreet']!.text,
            city: _fields['deliveryCity']!.text,
            postalCode: _fields['deliveryPostalCode']!.text,
            zoneId: _deliveryZone!,
          ),
          recipientName: _fields['recipientName']!.text,
          recipientPhone: _fields['recipientPhone']!.text,
          weight: _fields['weight']!.text,
          size: _size!,
        ),
      ),
    );
  }

  Widget _preview() {
    final quote = controller.quote!;
    return Card(
      margin: const EdgeInsets.only(bottom: 20),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Delivery fee',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
            Text(
              '${quote.currency} ${quote.total.moneyDisplay}',
              key: const Key('quoteTotal'),
              style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w700),
            ),
            Text(
              controller.quoteExpired
                  ? 'Quote expired — request a new fee before a first confirmation.'
                  : 'Valid until ${quote.expiresAt.toLocal()}',
            ),
            if (controller.attempt == null) ...[
              const SizedBox(height: 12),
              FilledButton(
                key: const Key('confirmBooking'),
                onPressed: controller.isBusy || controller.quoteExpired
                    ? null
                    : controller.confirm,
                child: const Text('Accept fee and confirm booking'),
              ),
              TextButton(
                key: const Key('declineQuote'),
                onPressed: controller.isBusy ? null : controller.decline,
                child: const Text('Decline quote'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _result() {
    final receipt = controller.receipt!;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Icon(Icons.check_circle_outline, size: 48),
            const SizedBox(height: 16),
            const Text(
              'Booking confirmed',
              style: TextStyle(fontSize: 28, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            const Text('Tracking number'),
            Semantics(
              container: true,
              excludeSemantics: true,
              label: 'Tracking number: ${receipt.trackingNumber}',
              child: SelectableText(
                receipt.trackingNumber,
                key: const Key('trackingNumber'),
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            TextButton.icon(
              onPressed: () async {
                await Clipboard.setData(
                  ClipboardData(text: receipt.trackingNumber),
                );
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Tracking number copied.')),
                  );
                }
              },
              icon: const Icon(Icons.content_copy),
              label: const Text('Copy tracking number'),
            ),
            const SizedBox(height: 12),
            Text(
              '${receipt.currency} ${receipt.total.moneyDisplay} • ${receipt.status}',
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: controller.startAnother,
              child: const Text('Book another delivery'),
            ),
          ],
        ),
      ),
    );
  }
}
