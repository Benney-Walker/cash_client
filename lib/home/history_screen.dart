import 'package:flutter/material.dart';

/// The collector's transaction history. Until the backend can list a
/// collector's records, it shows an empty state.
class HistoryScreen extends StatelessWidget {
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(title: const Text('History')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.history, size: 40, color: scheme.onSurfaceVariant),
              const SizedBox(height: 12),
              Text(
                'No records yet',
                key: const Key('history.empty'),
                style: textTheme.titleMedium,
              ),
              const SizedBox(height: 4),
              Text(
                'Your deposits, share payments and withdrawal requests will '
                'show here.',
                textAlign: TextAlign.center,
                style: textTheme.bodyMedium
                    ?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
