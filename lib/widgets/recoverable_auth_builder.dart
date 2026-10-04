import 'package:flutter/material.dart';

/// Re-subscribes to authentication only after a failed check, on explicit retry
/// or app resume. A fresh subscription receives Firebase's current user again.
class RecoverableAuthBuilder<T> extends StatefulWidget {
  const RecoverableAuthBuilder({
    super.key,
    required this.streamFactory,
    required this.builder,
  });

  final Stream<T> Function() streamFactory;
  final Widget Function(BuildContext, AsyncSnapshot<T>, VoidCallback) builder;

  @override
  State<RecoverableAuthBuilder<T>> createState() =>
      _RecoverableAuthBuilderState<T>();
}

class _RecoverableAuthBuilderState<T> extends State<RecoverableAuthBuilder<T>>
    with WidgetsBindingObserver {
  late Stream<T> _stream;
  int _attempt = 0;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _stream = widget.streamFactory();
  }

  void _retry() {
    if (!_failed || !mounted) return;
    setState(() {
      _failed = false;
      _attempt++;
      _stream = widget.streamFactory();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _retry();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => StreamBuilder<T>(
        key: ValueKey(_attempt),
        stream: _stream,
        builder: (context, snapshot) {
          _failed = snapshot.hasError;
          return widget.builder(context, snapshot, _retry);
        },
      );
}
