// lib/core/widgets/card_image_widget.dart
//
// Carga la imagen de una carta desde tu servidor.
// Muestra placeholder mientras carga y fallback si falla.

import 'package:flutter/material.dart';

class CardImageWidget extends StatelessWidget {
  const CardImageWidget({
    super.key,
    required this.imageUrl,
    this.width,
    this.height,
    this.fit = BoxFit.contain,
    this.borderRadius = 8.0,
    this.showShadow = false,
  });

  final String? imageUrl;
  final double? width;
  final double? height;
  final BoxFit fit;
  final double borderRadius;
  final bool showShadow;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(borderRadius),
        boxShadow: showShadow
            ? [BoxShadow(color: Colors.black26, blurRadius: 8, offset: const Offset(0, 3))]
            : null,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(borderRadius),
        child: _buildImage(context),
      ),
    );
  }

  Widget _buildImage(BuildContext context) {
    final url = imageUrl;
    if (url == null || url.isEmpty) return _placeholder(context);

    return Image.network(
      url,
      width: width,
      height: height,
      fit: fit,
      loadingBuilder: (context, child, progress) {
        if (progress == null) return child;
        return _loading(context, progress);
      },
      errorBuilder: (context, error, stack) => _placeholder(context),
    );
  }

  Widget _loading(BuildContext context, ImageChunkEvent progress) {
    final percent = progress.expectedTotalBytes != null
        ? progress.cumulativeBytesLoaded / progress.expectedTotalBytes!
        : null;
    return Container(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Center(
        child: CircularProgressIndicator(value: percent, strokeWidth: 2),
      ),
    );
  }

  Widget _placeholder(BuildContext context) {
    return Container(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: const Center(
        child: Icon(Icons.image_not_supported_outlined, color: Colors.grey, size: 32),
      ),
    );
  }
}

/// Versión pequeña para listas (thumbnail)
class CardThumbnail extends StatelessWidget {
  const CardThumbnail({super.key, required this.imageUrl});
  final String? imageUrl;

  @override
  Widget build(BuildContext context) => CardImageWidget(
        imageUrl: imageUrl,
        width: 52,
        height: 72,
        borderRadius: 6,
        fit: BoxFit.cover,
      );
}
