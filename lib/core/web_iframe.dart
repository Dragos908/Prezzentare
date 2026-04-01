// lib/core/web_iframe.dart

import 'package:flutter/material.dart';
import 'dart:html' as html;
import 'dart:ui_web' as ui;

class WebIframeWidget extends StatefulWidget {
  final String url;
  final VoidCallback? onLoad;
  const WebIframeWidget({required this.url, this.onLoad, super.key});

  @override
  State<WebIframeWidget> createState() => _WebIframeWidgetState();
}

class _WebIframeWidgetState extends State<WebIframeWidget> {
  static int _idCounter = 0;

  late final String _viewType;
  html.IFrameElement? _iframe;

  @override
  void initState() {
    super.initState();
    final id = _idCounter++;
    _viewType = 'prez-iframe-$id';

    _iframe = html.IFrameElement()
      ..src = widget.url
      ..style.border = 'none'
      ..style.width = '100%'
      ..style.height = '100%'
      ..setAttribute('allowfullscreen', 'true')
      ..setAttribute('allow',
          'autoplay; fullscreen; encrypted-media; picture-in-picture');

    if (widget.onLoad != null) {
      _iframe!.onLoad.listen((_) => widget.onLoad!());
    }

    // Se înregistrează o singură dată per id unic
    ui.platformViewRegistry.registerViewFactory(_viewType, (_) => _iframe!);
  }

  @override
  void didUpdateWidget(WebIframeWidget old) {
    super.didUpdateWidget(old);
    // Dacă URL-ul s-a schimbat (ex: iframePageIndex a avansat), actualizăm src.
    if (old.url != widget.url && _iframe != null) {
      _iframe!.src = widget.url;
    }
  }

  @override
  Widget build(BuildContext context) {
    return HtmlElementView(viewType: _viewType);
  }
}