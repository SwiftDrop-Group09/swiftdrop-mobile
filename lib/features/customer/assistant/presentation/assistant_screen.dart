import 'package:flutter/material.dart';

import '../../tracking/data/tracking_api.dart';
import '../../tracking/presentation/tracking_controller.dart';
import '../../tracking/presentation/tracking_screen.dart';
import '../domain/assistant_models.dart';
import 'assistant_bottom_sheet.dart';
import 'assistant_cards.dart';
import 'assistant_controller.dart';

class AssistantScreen extends StatefulWidget {
  const AssistantScreen({super.key, required this.controller});

  final AssistantController controller;

  @override
  State<AssistantScreen> createState() => _AssistantScreenState();
}

class _AssistantScreenState extends State<AssistantScreen> {
  final _textController = TextEditingController();
  final _scrollController = ScrollController();
  final _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onControllerUpdate);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerUpdate);
    _textController.dispose();
    _scrollController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onControllerUpdate() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _handleSend([String? preset]) {
    final text = preset ?? _textController.text;
    if (text.trim().isEmpty) return;
    if (preset == null) _textController.clear();
    widget.controller.sendMessage(text);
  }

  void _openTrackingFor(String trackingNumber, [String? parcelId]) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => CustomerTrackingScreen(
          controller: CustomerParcelDetailController(
            api: TrackingApi(widget.controller.api.transport),
            parcelId: parcelId ?? trackingNumber,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Delivery assistant',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            Text(
              widget.controller.sessions.value.signedIn
                  ? 'Authenticated Customer · MCP Grounded'
                  : 'Public Delivery Assistant · Rates & Tracking',
              style: theme.textTheme.bodySmall?.copyWith(fontSize: 11),
            ),
          ],
        ),
        actions: [
          ListenableBuilder(
            listenable: widget.controller,
            builder: (context, _) {
              if (widget.controller.messages.isEmpty) {
                return const SizedBox.shrink();
              }
              return IconButton(
                icon: const Icon(Icons.refresh_rounded),
                tooltip: 'Clear chat',
                onPressed: widget.controller.clearChat,
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.terminal_outlined),
            tooltip: 'MCP Inspector',
            onPressed: () {
              McpInspectorBottomSheet.show(
                context,
                api: widget.controller.api,
                onRunTestPrompt: _handleSend,
              );
            },
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Message stream or Welcome state
            Expanded(
              child: ListenableBuilder(
                listenable: widget.controller,
                builder: (context, _) {
                  final c = widget.controller;
                  if (c.messages.isEmpty && !c.loading) {
                    return _buildWelcomeState(context);
                  }

                  return ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    itemCount: c.messages.length + (c.loading ? 1 : 0),
                    itemBuilder: (context, index) {
                      if (index == c.messages.length) {
                        return _buildLoadingBubble(context);
                      }
                      final msg = c.messages[index];
                      return _buildMessageRow(context, msg);
                    },
                  );
                },
              ),
            ),

            // Docked Suggestions row
            ListenableBuilder(
              listenable: widget.controller,
              builder: (context, _) {
                final prompts = widget.controller.suggestedPrompts;
                if (prompts.isEmpty) return const SizedBox.shrink();

                return Container(
                  height: 40,
                  margin: const EdgeInsets.only(bottom: 6),
                  child: ListView.separated(
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    scrollDirection: Axis.horizontal,
                    itemCount: prompts.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 6),
                    itemBuilder: (context, i) {
                      return ActionChip(
                        label: Text(
                          prompts[i],
                          style: TextStyle(
                            fontSize: 12,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        onPressed: () => _handleSend(prompts[i]),
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                          side: BorderSide(
                            color: theme.colorScheme.outlineVariant.withOpacity(0.6),
                          ),
                        ),
                      );
                    },
                  ),
                );
              },
            ),

            // Bottom Composer
            Container(
              padding: const EdgeInsets.fromLTRB(14, 4, 14, 10),
              decoration: BoxDecoration(
                color: theme.scaffoldBackgroundColor,
                border: Border(
                  top: BorderSide(
                    color: theme.colorScheme.outlineVariant.withOpacity(0.4),
                  ),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _textController,
                      focusNode: _focusNode,
                      decoration: InputDecoration(
                        hintText: 'Ask about a parcel or delivery rate...',
                        hintStyle: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.outline,
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        filled: true,
                        fillColor: theme.colorScheme.surfaceContainerHighest.withOpacity(0.3),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: BorderSide(
                            color: theme.colorScheme.outlineVariant.withOpacity(0.6),
                          ),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: BorderSide(
                            color: theme.colorScheme.outlineVariant.withOpacity(0.6),
                          ),
                        ),
                      ),
                      onSubmitted: (_) => _handleSend(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: () => _handleSend(),
                    style: FilledButton.styleFrom(
                      shape: const CircleBorder(),
                      padding: const EdgeInsets.all(12),
                    ),
                    child: const Icon(Icons.arrow_upward_rounded, size: 20),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWelcomeState(BuildContext context) {
    final theme = Theme.of(context);

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const SizedBox(height: 16),
        Center(
          child: Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: theme.colorScheme.primary.withOpacity(0.1),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: theme.colorScheme.primary.withOpacity(0.2),
              ),
            ),
            child: Icon(
              Icons.auto_awesome_outlined,
              size: 28,
              color: theme.colorScheme.primary,
            ),
          ),
        ),
        const SizedBox(height: 14),
        Text(
          'How can I help with your deliveries?',
          textAlign: TextAlign.center,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Track an active booking, estimate shipping rates across Sri Lanka, or check coverage zones.',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodySmall?.copyWith(fontSize: 12),
        ),
        const SizedBox(height: 24),

        // 4 Starter Action Cards
        _StarterCard(
          icon: Icons.inventory_2_outlined,
          title: 'Where is my parcel?',
          subtitle: 'Check live status and milestones for your active bookings',
          onTap: () => _handleSend('Where is my parcel?'),
        ),
        const SizedBox(height: 10),
        _StarterCard(
          icon: Icons.calculate_outlined,
          title: 'Estimate delivery fee',
          subtitle: 'How much to send 2 kg to Kandy?',
          onTap: () => _handleSend('How much to send 2 kg to Kandy?'),
        ),
        const SizedBox(height: 10),
        _StarterCard(
          icon: Icons.place_outlined,
          title: 'Service zones & coverage',
          subtitle: 'What delivery zones do you cover?',
          onTap: () => _handleSend('What delivery zones do you cover?'),
        ),
        const SizedBox(height: 10),
        _StarterCard(
          icon: Icons.schedule_outlined,
          title: 'My recent deliveries',
          subtitle: 'List my recent deliveries',
          onTap: () => _handleSend('List my recent deliveries'),
        ),
      ],
    );
  }

  Widget _buildMessageRow(BuildContext context, AssistantMessageItem msg) {
    final theme = Theme.of(context);

    if (msg.isUser) {
      return Align(
        alignment: Alignment.centerRight,
        child: Container(
          margin: const EdgeInsets.only(left: 48, bottom: 12),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: theme.colorScheme.primary,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(16),
              topRight: Radius.circular(16),
              bottomLeft: Radius.circular(16),
              bottomRight: Radius.circular(4),
            ),
          ),
          child: Text(
            msg.content,
            style: TextStyle(
              color: theme.colorScheme.onPrimary,
              fontSize: 14,
            ),
          ),
        ),
      );
    }

    final hasCards = msg.cards != null &&
        (msg.cards!.tracking != null ||
            msg.cards!.quote != null ||
            msg.cards!.parcelList != null ||
            msg.cards!.zones != null);

    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(right: 32, bottom: 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Message text bubble
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.35),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(16),
                  topRight: Radius.circular(16),
                  bottomRight: Radius.circular(16),
                  bottomLeft: Radius.circular(4),
                ),
                border: Border.all(
                  color: theme.colorScheme.outlineVariant.withOpacity(0.5),
                ),
              ),
              child: FormattedAssistantText(
                text: msg.content,
                hasRichCards: hasCards,
              ),
            ),

            // Collapsible Tool execution trace pills
            ...msg.toolCalls.map((trace) => McpToolTracePill(trace: trace)),

            // Rich Result Cards
            if (msg.cards?.tracking != null)
              MobileTrackingResultCard(
                tracking: msg.cards!.tracking!,
                onOpenTracker: () => _openTrackingFor(
                  msg.cards!.tracking!.trackingNumber,
                  msg.cards!.tracking!.parcelId,
                ),
              ),

            if (msg.cards?.quote != null)
              MobileQuoteResultCard(
                quote: msg.cards!.quote!,
                onBook: () {
                  Navigator.of(context).pushNamed('/book');
                },
              ),

            if (msg.cards?.parcelList != null)
              MobileParcelListResultCard(
                parcelList: msg.cards!.parcelList!,
                onAskAboutParcel: (trk) => _handleSend('Track $trk'),
                onTrackParcel: (trk, id) => _openTrackingFor(trk, id),
              ),

            if (msg.cards?.zones != null)
              MobileZonesResultCard(
                zones: msg.cards!.zones!,
                onSelectCity: (city) => _handleSend('How much to send 2 kg to $city?'),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildLoadingBubble(BuildContext context) {
    final theme = Theme.of(context);

    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(right: 48, bottom: 12),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.35),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: theme.colorScheme.outlineVariant.withOpacity(0.5),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: theme.colorScheme.primary,
              ),
            ),
            const SizedBox(width: 10),
            Text(
              'Assistant is consulting delivery tools...',
              style: theme.textTheme.bodySmall?.copyWith(fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}

class _StarterCard extends StatelessWidget {
  const _StarterCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: theme.colorScheme.outlineVariant.withOpacity(0.6),
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: theme.colorScheme.primary.withOpacity(0.15),
                  ),
                ),
                child: Icon(icon, size: 20, color: theme.colorScheme.primary),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: theme.textTheme.bodySmall?.copyWith(fontSize: 11),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.arrow_forward_ios,
                size: 14,
                color: theme.colorScheme.outline,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
