import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../core/network/request_transport.dart';
import 'courier_controller.dart';
import 'courier_models.dart';
import 'proof_capture.dart';

class CourierScreen extends StatefulWidget {
  const CourierScreen({super.key, required this.controller, this.capture});
  final CourierController controller;
  final ProofCapture? capture;
  @override
  State<CourierScreen> createState() => _CourierScreenState();
}

class _CourierScreenState extends State<CourierScreen> {
  bool _history = false;
  late final ProofCapture _capture = widget.capture ?? ImageProofCapture();
  late final Timer _timer;
  CourierController get c => widget.controller;
  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        unawaited(c.loadManifest());
        unawaited(_discardLost());
      }
    });
  }

  Future<void> _discardLost() async {
    try {
      await _capture.discardLost();
    } catch (_) {
      /* Platform may not support lost-data retrieval. No proof is restored. */
    }
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: c,
    builder: (context, _) => Scaffold(
      appBar: AppBar(
        title: const Text('Courier deliveries'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pushNamed(context, '/book'),
            child: const Text('Booking'),
          ),
        ],
      ),
      body: !c.authorized
          ? const Center(
              child: Text('Sign in with a Courier account to view deliveries.'),
            )
          : c.blocked
          ? const Center(
              child: Text(
                'Access has ended. Return to your account and sign in again.',
              ),
            )
          : Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1000),
                child: ListView(
                  padding: const EdgeInsets.all(20),
                  children: [
                    SegmentedButton<bool>(
                      segments: const [
                        ButtonSegment(
                          value: false,
                          label: Text('Assigned deliveries'),
                        ),
                        ButtonSegment(
                          value: true,
                          label: Text('Delivery history'),
                        ),
                      ],
                      selected: {_history},
                      onSelectionChanged: (v) {
                        setState(() => _history = v.first);
                        unawaited(
                          _history ? c.loadHistory() : c.loadManifest(),
                        );
                      },
                    ),
                    if (c.notice != null)
                      Padding(
                        padding: const EdgeInsets.all(12),
                        child: Text(
                          c.notice!,
                          semanticsLabel: 'Delivery status: ${c.notice}',
                        ),
                      ),
                    if (c.pending != null) _Pending(c: c),
                    if (_history)
                      ..._historyWidgets()
                    else
                      ..._manifestWidgets(),
                  ],
                ),
              ),
            ),
    ),
  );
  List<Widget> _manifestWidgets() => [
    const SizedBox(height: 16),
    Text(
      'Assigned deliveries',
      style: Theme.of(context).textTheme.headlineSmall,
    ),
    Text('Service date: ${c.date ?? 'Today (Asia/Colombo)'}'),
    Wrap(
      spacing: 12,
      children: [
        TextButton(
          onPressed: () async {
            final day = await showDatePicker(
              context: context,
              initialDate: DateTime.now(),
              firstDate: DateTime(2000),
              lastDate: DateTime(2100),
            );
            if (day != null && mounted) {
              c.date =
                  '${day.year.toString().padLeft(4, '0')}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}';
              c.manifestPage = 1;
              await c.loadManifest();
            }
          },
          child: const Text('Choose day'),
        ),
        TextButton(
          onPressed: () {
            c.date = null;
            c.manifestPage = 1;
            unawaited(c.loadManifest());
          },
          child: const Text('Today'),
        ),
        TextButton(onPressed: c.loadManifest, child: const Text('Refresh')),
      ],
    ),
    SwitchListTile(
      title: const Text('Include overdue'),
      value: c.includeOverdue,
      onChanged: (v) {
        c.includeOverdue = v;
        c.manifestPage = 1;
        unawaited(c.loadManifest());
      },
    ),
    if (c.manifestLoading) const Center(child: CircularProgressIndicator()),
    if (c.manifestError != null)
      _Error(message: c.manifestError!, retry: c.loadManifest),
    if (c.manifest case final page?) ...[
      if (page.items.isEmpty)
        const Text('No assigned deliveries match this day.'),
      for (final d in page.items)
        Card(
          child: ListTile(
            title: Text(d.parcel.summary.trackingNumber),
            subtitle: Text(
              '${d.parcel.summary.status}${d.isOverdue ? ' · Overdue' : ''}\n${d.parcel.recipientName} · ${d.parcel.delivery.city}\nService date ${d.serviceDate} · ${d.parcel.summary.currency} ${d.parcel.summary.total.moneyDisplay}',
            ),
            isThreeLine: true,
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute<void>(
                builder: (_) => CourierDetailScreen(
                  controller: c,
                  id: d.parcel.summary.id,
                  capture: _capture,
                ),
              ),
            ),
          ),
        ),
      _Pager(
        page: page.page,
        total: page.total,
        change: (p) {
          c.manifestPage = p;
          unawaited(c.loadManifest());
        },
      ),
    ],
  ];
  List<Widget> _historyWidgets() => [
    const SizedBox(height: 16),
    Text('Delivery history', style: Theme.of(context).textTheme.headlineSmall),
    const Text(
      'Your completed and failed deliveries. Private recipient details are available only during active assignments.',
    ),
    TextButton(onPressed: c.loadHistory, child: const Text('Refresh history')),
    if (c.historyLoading) const Center(child: CircularProgressIndicator()),
    if (c.historyError != null)
      _Error(message: c.historyError!, retry: c.loadHistory),
    if (c.history case final page?) ...[
      if (page.items.isEmpty)
        const Text('No completed or failed deliveries yet.'),
      for (final d in page.items)
        Card(
          child: ListTile(
            title: Text(d.trackingNumber),
            subtitle: Text(
              '${d.status} · ${d.currency} ${d.total.moneyDisplay}\nCreated ${d.createdAt.toLocal()}\nVersion ${d.version.plain} · Pricing ${d.pricingVersion}',
            ),
          ),
        ),
      _Pager(
        page: page.page,
        total: page.total,
        change: (p) {
          c.historyPage = p;
          unawaited(c.loadHistory());
        },
      ),
    ],
  ];
}

class _Pager extends StatelessWidget {
  const _Pager({required this.page, required this.total, required this.change});
  final int page, total;
  final ValueChanged<int> change;
  @override
  Widget build(BuildContext context) => Wrap(
    crossAxisAlignment: WrapCrossAlignment.center,
    children: [
      TextButton(
        onPressed: page > 1 ? () => change(page - 1) : null,
        child: const Text('Previous'),
      ),
      Text('Page $page · $total deliveries'),
      TextButton(
        onPressed: page * 20 < total ? () => change(page + 1) : null,
        child: const Text('Next'),
      ),
    ],
  );
}

class _Error extends StatelessWidget {
  const _Error({required this.message, required this.retry});
  final String message;
  final VoidCallback retry;
  @override
  Widget build(BuildContext context) => Column(
    children: [
      Text(message),
      TextButton(onPressed: retry, child: const Text('Reload')),
    ],
  );
}

class _Pending extends StatelessWidget {
  const _Pending({required this.c});
  final CourierController c;
  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          const Text(
            'The original request is retained in this open session. Other actions are paused until its outcome is confirmed.',
          ),
          if (c.busy) ...[
            LinearProgressIndicator(value: c.uploadProgress),
            Text(
              c.uploadProgress == null
                  ? 'Waiting for backend confirmation…'
                  : c.uploadProgress! >= 1
                  ? 'Upload sent. Waiting for backend confirmation…'
                  : 'Uploading ${(c.uploadProgress! * 100).floor()}%',
            ),
          ],
          FilledButton(
            onPressed: c.canRetry ? c.retry : null,
            child: const Text('Retry original request'),
          ),
        ],
      ),
    ),
  );
}

class CourierDetailScreen extends StatefulWidget {
  const CourierDetailScreen({
    super.key,
    required this.controller,
    required this.id,
    required this.capture,
  });
  final CourierController controller;
  final String id;
  final ProofCapture capture;
  @override
  State<CourierDetailScreen> createState() => _CourierDetailScreenState();
}

class _CourierDetailScreenState extends State<CourierDetailScreen> {
  late final Timer _timer;
  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(widget.controller.loadDetail(widget.id));
    });
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    return AnimatedBuilder(
      animation: c,
      builder: (context, _) => Scaffold(
        appBar: AppBar(title: const Text('Delivery details')),
        body: !c.authorized || c.blocked
            ? const Center(
                child: Text('A current Courier session is required.'),
              )
            : Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 800),
                  child: ListView(
                    padding: const EdgeInsets.all(20),
                    children: [
                      if (c.notice != null) Text(c.notice!),
                      if (c.pending != null) _Pending(c: c),
                      if (c.receipt case final receipt?)
                        if (receipt.id == widget.id && !receipt.active) ...[
                          Text('${receipt.status} confirmed by Delivery.'),
                          Text(receipt.trackingNumber),
                        ],
                      if (c.detailLoading)
                        const Center(child: CircularProgressIndicator()),
                      if (c.detailError != null)
                        _Error(
                          message: c.detailError!,
                          retry: () => unawaited(c.loadDetail(widget.id)),
                        ),
                      if (c.detail case final d?)
                        if (d.summary.id == widget.id) ...[
                          Text(
                            d.summary.trackingNumber,
                            style: Theme.of(context).textTheme.headlineSmall,
                          ),
                          Text(
                            '${d.summary.status} · Version ${d.summary.version.plain}',
                          ),
                          Text(
                            '${d.summary.currency} ${d.summary.total.moneyDisplay}',
                          ),
                          TextButton(
                            onPressed: c.locked
                                ? null
                                : () => unawaited(c.loadDetail(widget.id)),
                            child: const Text('Refresh parcel'),
                          ),
                          const Text('Pickup'),
                          Text(d.parcel.pickup.display),
                          const SizedBox(height: 16),
                          const Text('Delivery'),
                          Text(d.parcel.delivery.display),
                          Text('${d.parcel.recipientName}\n${d.parcel.phone}'),
                          Text(
                            'Package: ${d.parcel.size} · ${d.parcel.weight.plain} kg',
                          ),
                          if (d.serviceDate != null)
                            Text('Service date ${d.serviceDate}'),
                          _Actions(
                            key: ValueKey(
                              '${c.scope}:${d.summary.id}:${d.summary.version.plain}',
                            ),
                            c: c,
                            d: d,
                            capture: widget.capture,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'Status history',
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          for (final h in d.history)
                            ListTile(
                              title: Text(
                                '${h.from == null ? '' : '${h.from} → '}${h.to}',
                              ),
                              subtitle: Text(
                                '${h.timestamp.toLocal()}${h.reason == null ? '' : '\nReason: ${h.reason}'}${h.note == null ? '' : '\n${h.note}'}',
                              ),
                            ),
                        ],
                    ],
                  ),
                ),
              ),
      ),
    );
  }
}

class _Actions extends StatefulWidget {
  const _Actions({
    super.key,
    required this.c,
    required this.d,
    required this.capture,
  });
  final CourierController c;
  final ParcelDetail d;
  final ProofCapture capture;
  @override
  State<_Actions> createState() => _ActionsState();
}

class _ActionsState extends State<_Actions> {
  final _notes = TextEditingController(), _name = TextEditingController();
  String? _reason, _error;
  UploadPart? _photo, _signature;
  bool _capturing = false;
  @override
  void dispose() {
    _notes.dispose();
    _name.dispose();
    _photo = null;
    _signature = null;
    super.dispose();
  }

  Future<void> _pick(bool camera) async {
    if (widget.c.locked) return;
    setState(() {
      _capturing = true;
      _error = null;
    });
    final scope = widget.c.scope;
    try {
      final file = await widget.capture.pick(camera: camera);
      if (mounted && scope == widget.c.scope) setState(() => _photo = file);
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = 'Photo capture failed. Choose a JPEG/PNG up to 5 MiB or use a signature.',
        );
      }
    } finally {
      if (mounted) setState(() => _capturing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.d, c = widget.c;
    if (!d.summary.active) {
      return const Text('No actions are available for this state.');
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 20),
        Text('Delivery actions', style: Theme.of(context).textTheme.titleLarge),
        if (_error != null) Text(_error!),
        AbsorbPointer(
          absorbing: c.locked || _capturing,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _notes,
                maxLength: 500,
                maxLines: 3,
                decoration: InputDecoration(
                  labelText: d.summary.status == 'OutForDelivery'
                      ? 'Private failure note (optional)'
                      : 'Private delivery note',
                ),
              ),
              if (nextStages[d.summary.status] case final next?)
                FilledButton(
                  onPressed: c.locked
                      ? null
                      : () => c.status(next, _notes.text),
                  child: Text('Mark $next'),
                ),
              DropdownButtonFormField<String>(
                initialValue: _reason,
                decoration: const InputDecoration(labelText: 'Failure reason'),
                items: [
                  for (final r in failureReasons)
                    DropdownMenuItem(value: r, child: Text(r)),
                ],
                onChanged: (r) => setState(() => _reason = r),
              ),
              OutlinedButton(
                onPressed: c.locked
                    ? null
                    : () => c.status('Failed', _notes.text, reason: _reason),
                child: const Text('Report failed delivery'),
              ),
              if (d.summary.status == 'OutForDelivery') ...[
                const SizedBox(height: 20),
                Text(
                  'Proof of delivery',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const Text(
                  'Provide a JPEG/PNG photo or drawn signature (both accepted), up to 5 MiB each. Completion requires backend confirmation.',
                ),
                TextField(
                  controller: _name,
                  maxLength: 120,
                  decoration: const InputDecoration(
                    labelText: 'Recipient name',
                  ),
                ),
                Wrap(
                  children: [
                    TextButton(
                      onPressed: () => _pick(true),
                      child: const Text('Take photo'),
                    ),
                    TextButton(
                      onPressed: () => _pick(false),
                      child: const Text('Choose photo'),
                    ),
                  ],
                ),
                if (_capturing) const LinearProgressIndicator(),
                if (_photo != null) ...[
                  Text(
                    'Photo selected (${(_photo!.bytes.length / 1024).ceil()} KiB)',
                  ),
                  TextButton(
                    onPressed: () => setState(() => _photo = null),
                    child: const Text('Remove photo'),
                  ),
                ],
                _Signature(
                  onChange: (file) => setState(() => _signature = file),
                ),
                FilledButton(
                  onPressed: c.locked
                      ? null
                      : () async {
                          await c.proof(
                            _name.text,
                            photo: _photo,
                            signature: _signature,
                          );
                          if (mounted && c.pending == null) {
                            setState(() {
                              _photo = null;
                              _signature = null;
                            });
                          }
                        },
                  child: const Text('Submit proof and complete delivery'),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _Signature extends StatefulWidget {
  const _Signature({required this.onChange});
  final ValueChanged<UploadPart?> onChange;
  @override
  State<_Signature> createState() => _SignatureState();
}

class _SignatureState extends State<_Signature> {
  final List<List<Offset>> _strokes = [];
  String _notice = '';
  int _generation = 0;
  Future<void> _save() async {
    if (!_strokes.any((s) => s.length > 1)) {
      setState(() => _notice = 'Draw a signature first.');
      return;
    }
    final generation = ++_generation;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawColor(Colors.white, BlendMode.src);
    _SignaturePainter(_strokes).paint(canvas, const Size(560, 180));
    final picture = recorder.endRecording();
    final image = await picture.toImage(560, 180);
    picture.dispose();
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    if (mounted && generation == _generation && data != null) {
      widget.onChange(
        UploadPart('signature', 'image/png', data.buffer.asUint8List()),
      );
      setState(() => _notice = 'Signature selected.');
    }
  }

  @override
  void dispose() {
    _generation++;
    _strokes.clear();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
    children: [
      const Text(
        'Optional recipient signature. Draw below, then use the signature.',
      ),
      LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          Offset scale(Offset p) => Offset(p.dx * 560 / width, p.dy);
          return Semantics(
            label: 'Draw recipient signature',
            child: GestureDetector(
              onPanStart: (d) {
                _generation++;
                widget.onChange(null);
                setState(() {
                  _strokes.add([scale(d.localPosition)]);
                  _notice = '';
                });
              },
              onPanUpdate: (d) =>
                  setState(() => _strokes.last.add(scale(d.localPosition))),
              child: Container(
                height: 180,
                width: width,
                decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border.all(),
                ),
                child: CustomPaint(
                  painter: _SignaturePainter(_strokes, scale: width / 560),
                ),
              ),
            ),
          );
        },
      ),
      Wrap(
        children: [
          TextButton(onPressed: _save, child: const Text('Use signature')),
          TextButton(
            onPressed: () {
              _generation++;
              setState(() {
                _strokes.clear();
                _notice = '';
              });
              widget.onChange(null);
            },
            child: const Text('Clear signature'),
          ),
        ],
      ),
      Text(_notice),
    ],
  );
}

class _SignaturePainter extends CustomPainter {
  _SignaturePainter(this.strokes, {this.scale = 1});
  final List<List<Offset>> strokes;
  final double scale;
  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(scale, 1);
    final pen = Paint()
      ..color = Colors.black
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    for (final s in strokes) {
      for (var i = 1; i < s.length; i++) {
        canvas.drawLine(s[i - 1], s[i], pen);
      }
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _SignaturePainter oldDelegate) => true;
}
