// lib/features/scanner/presentation/scanner_screen.dart
import 'dart:async';
import 'dart:io';


import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';


import 'package:one_piece_card_scanner/app/app.dart';
import 'package:one_piece_card_scanner/core/database/card_database.dart';
import 'package:one_piece_card_scanner/core/services/card_api_service.dart';


class ScannerScreen extends StatefulWidget {
  const ScannerScreen({super.key});


  @override
  State<ScannerScreen> createState() => _ScannerScreenState();
}


class _ScannerScreenState extends State<ScannerScreen>
    with WidgetsBindingObserver {
  CameraController? _cameraController;
  Future<void>? _initFuture;
  CameraDescription? _selectedCamera;


  final _textRecognizer = TextRecognizer(script: TextRecognitionScript.latin);
  final _apiService = CardApiService();


  String? _detectedCode;
  CardLookupResult? _lookupResult;
  CardData? _selectedCard;
  XFile? _capturedImage;


  bool _isScanning = false;
  bool _isLooking = false;
  bool _isSaving = false;
  bool _liveEnabled = true;


  String? _errorMessage;
  String? _successMessage;


  Timer? _liveTimer;


  int _quantity = 1;
  Folder? _selectedFolder;
  List<Folder> _allFolders = [];
  bool _loadingFolders = false;


  // FIX: suscripción al stream de cambios de carpetas
  StreamSubscription<void>? _foldersSub;


  // NUEVO: toggle para arte alternativa
  bool _isAlternateArt = false;


  // NUEVO: carta efectiva para UI + guardado
  CardData? get _effectiveCard {
    final result = _lookupResult;
    if (result == null) return _selectedCard;


    if (_isAlternateArt && result.alternateVersions.isNotEmpty) {
      return result.alternateVersions.first;
    }


    return _selectedCard ?? result.card;
  }


  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _setupCamera();
    _loadFoldersForScanner();


    // FIX: recarga la lista de carpetas automáticamente cuando se crea,
    // edita o elimina una carpeta desde FoldersScreen
    _foldersSub = AppEvents.onFoldersChanged.listen((_) {
      _loadFoldersForScanner();
    });
  }


  Future<void> _loadFoldersForScanner() async {
    setState(() => _loadingFolders = true);
    final folders = await CardDatabase.instance.getAllFolders();
    if (!mounted) return;
    setState(() {
      _allFolders = folders;
      final stillExists =
          _selectedFolder != null &&
          folders.any((f) => f.id == _selectedFolder!.id);
      if (!stillExists) {
        _selectedFolder = null;
      }
      _loadingFolders = false;
    });
  }


  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final c = _cameraController;
    if (c == null || !c.value.isInitialized) return;
    if (state == AppLifecycleState.inactive) {
      _stopLive();
      c.dispose();
    } else if (state == AppLifecycleState.resumed && _selectedCamera != null) {
      _initCamera(_selectedCamera!);
    }
  }


  Future<void> _setupCamera() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        setState(() => _errorMessage = 'No se encontraron cámaras.');
        return;
      }
      _selectedCamera = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );
      await _initCamera(_selectedCamera!);
    } catch (e) {
      setState(() => _errorMessage = 'Error al inicializar cámara: $e');
    }
  }


  Future<void> _initCamera(CameraDescription camera) async {
    final prev = _cameraController;
    _stopLive();
    final controller = CameraController(
      camera,
      ResolutionPreset.high,
      enableAudio: false,
    );
    final future = controller.initialize();
    setState(() {
      _cameraController = controller;
      _initFuture = future;
      _errorMessage = null;
    });
    await prev?.dispose();
    try {
      await future;
      try {
        await controller.setFocusMode(FocusMode.auto);
      } catch (_) {}
      if (!mounted) return;
      setState(() {});
      _startLive();
    } catch (e) {
      setState(() => _errorMessage = 'Error de cámara: $e');
    }
  }


  void _startLive() {
    _liveTimer?.cancel();
    _liveTimer = Timer.periodic(const Duration(milliseconds: 1800), (_) {
      if (_liveEnabled && !_isScanning && !_isLooking) _detectCodeLive();
    });
  }


  void _stopLive() {
    _liveTimer?.cancel();
    _liveTimer = null;
  }


  Future<void> _detectCodeLive() async {
    final c = _cameraController;
    if (c == null || !c.value.isInitialized) return;
    try {
      final image = await c.takePicture();
      final input = InputImage.fromFilePath(image.path);
      final result = await _textRecognizer.processImage(input);
      final code = _extractCode(result.text);
      if (code == null || !mounted) {
        try {
          await File(image.path).delete();
        } catch (_) {}
        return;
      }
      if (code != _detectedCode) {
        setState(() => _detectedCode = code);
        await _lookupAndShow(code, image);
      } else {
        try {
          await File(image.path).delete();
        } catch (_) {}
      }
    } catch (_) {}
  }


  Future<void> _lookupAndShow(String code, XFile image) async {
    setState(() {
      _isLooking = true;
      _capturedImage = image;
      _successMessage = null;
      _errorMessage = null;
      _isAlternateArt = false;
    });
    try {
      final result = await _apiService.lookupCard(code);
      if (!mounted) return;
      if (result == null) {
        setState(() {
          _errorMessage = 'Carta "$code" no encontrada.';
          _lookupResult = null;
          _selectedCard = null;
        });
        return;
      }
      setState(() {
        _lookupResult = result;
        _detectedCode = code;
        _selectedCard = result.card; // siempre estándar
      });
      if (result.hasVariants && mounted) await _showVariantDialog(result);
    } catch (e) {
      if (!mounted) return;
      setState(() => _errorMessage = 'Error al consultar el servidor.');
    } finally {
      if (mounted) setState(() => _isLooking = false);
    }
  }


  Future<void> _showVariantDialog(CardLookupResult result) async {
    final all = [result.card, ...result.alternateVersions];
    await showDialog<CardData>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: kSurface,
        title: const Text('¿Cuál versión tienes?', style: TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: all
              .map(
                (card) => ListTile(
                  leading: _rarityBadge(card.rarity),
                  title: Text(
                    card.isAlternate
                        ? (card.name.contains('Parallel')
                              ? 'Parallel'
                              : 'Alternate Art')
                        : 'Arte estándar',
                    style: const TextStyle(color: Colors.white),
                  ),
                  subtitle: Text(card.rarityLabel,
                      style: const TextStyle(color: Color(0xFF888888))),
                  onTap: () {
                    // Solo activa/desactiva el toggle según lo que eligió
                    setState(() => _isAlternateArt = card.isAlternate);
                    Navigator.pop(ctx);
                  },
                ),
              )
              .toList(),
        ),
      ),
    );
    // _selectedCard siempre es result.card (estándar)
    if (mounted) setState(() => _selectedCard = result.card);
  }


  Widget _rarityBadge(String rarity) {
    Color color;
    switch (rarity.toUpperCase()) {
      case 'SEC':
        color = Colors.purple;
        break;
      case 'L':
        color = Colors.amber;
        break;
      case 'SR':
        color = Colors.orange;
        break;
      case 'R':
        color = Colors.blue;
        break;
      case 'UC':
        color = Colors.teal;
        break;
      default:
        color = Colors.grey;
    }
    return CircleAvatar(
      backgroundColor: color.withOpacity(0.18),
      child: Text(
        rarity,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.bold,
          fontSize: 12,
        ),
      ),
    );
  }


  Future<void> _saveToCollection() async {
    final card = _effectiveCard ?? _selectedCard ?? _lookupResult?.card;
    final image = _capturedImage;
    if (card == null || image == null || _quantity <= 0) return;


    setState(() {
      _isSaving = true;
      _successMessage = null;
      _errorMessage = null;
    });


    try {
      // Busca si ya existe este código para no duplicar
      final allCards = await CardDatabase.instance.getAllCards();
      ScannedCard? existing;
      for (final c in allCards) {
        if (c.setCode == card.id) {
          existing = c;
          break;
        }
      }


      final int cardDbId;


      if (existing != null) {
        cardDbId = existing.id!;


        // ── OPTIMIZACIÓN: si ya tenía URL del servidor guardada antes
        //    pero la imagen local sigue existiendo, la borramos ahora.
        if (existing.hasServerImage) {
          await CardDatabase.instance.deleteLocalImageSafely(
            existing.localImagePath,
          );
        }
      } else {
        // Carta nueva: guarda imagen local temporalmente
        final permanentPath = await CardDatabase.persistImage(image.path);


        final saved = await CardDatabase.instance.insertCard(
          ScannedCard(
            name: card.cleanName,
            cardClass: card.cardType,
            faction: card.faction ?? '',
            setCode: card.id,
            ability: card.effect ?? '',
            trigger: card.trigger ?? '',
            localImagePath: permanentPath,
            serverImageUrl: card.imageUrl, // puede ser null
          ),
        );
        cardDbId = saved.id!;


        // ── OPTIMIZACIÓN: si el servidor ya devolvió la URL en este escaneo,
        //    borramos la imagen local inmediatamente (no la necesitamos).
        if (card.imageUrl != null && card.imageUrl!.isNotEmpty) {
          await CardDatabase.instance.updateServerUrl(
            cardDbId,
            card.imageUrl!,
            deleteLocalImage: true, // borra el archivo local
          );
        }
      }


      await CardDatabase.instance.database; // asegura inicialización
      final targetFolderId =
          _selectedFolder?.id ?? CardDatabase.collectionFolderId;


      if (targetFolderId != null) {
        await CardDatabase.instance.addCardToFolder(
          folderId: targetFolderId,
          cardId: cardDbId,
          quantity: _quantity,
        );
      }


      AppEvents.notifyCollectionChanged();
      if (!mounted) return;


      final qty = _quantity;
      final folderName = _selectedFolder?.name ?? 'Colección';
      setState(() {
        _successMessage = 'x$qty ${card.cleanName} → $folderName';
      });
    } catch (e) {
      setState(() => _errorMessage = 'Error al guardar: $e');
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }


  String? _extractCode(String text) {
    final n = text
        .toUpperCase()
        .replaceAll('\n', ' ')
        .replaceAll('\r', ' ')
        .replaceAll('–', '-')
        .replaceAll('—', '-')
        .replaceAll('_', '-')
        .replaceAll('0P', 'OP')
        .replaceAll('0B', 'OB');
    for (final p in [
      RegExp(r'\b(OP\d{2}-\d{3})\b'),
      RegExp(r'\b(ST\d{2}-\d{3})\b'),
      RegExp(r'\b(EB\d{2}-\d{3})\b'),
      RegExp(r'\b(P-\d{3})\b'),
    ]) {
      final m = p.firstMatch(n);
      if (m != null) return m.group(1);
    }
    return null;
  }


  void _resetCardView() {
    setState(() {
      _lookupResult = null;
      _selectedCard = null;
      _detectedCode = null;
      _capturedImage = null;
      _errorMessage = null;
      _successMessage = null;
      _quantity = 1;
      _isAlternateArt = false;
    });
  }


  String _costText(CardData card) =>
      card.cost == null ? '' : card.cost.toString();


  String _attributeText(CardData card) =>
      card.attribute == null ? '' : card.attribute.toString();


  @override
  void dispose() {
    _foldersSub?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _stopLive();
    _textRecognizer.close();
    _cameraController?.dispose();
    super.dispose();
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBlack,
      appBar: AppBar(
        backgroundColor: kBlack,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: const Text(
          'Scanner',
          style: TextStyle(
            color: kGold,
            fontWeight: FontWeight.w800,
            fontSize: 28,
          ),
        ),
        actions: [
          IconButton(
            onPressed: _resetCardView,
            icon: const Icon(Icons.center_focus_strong_rounded),
            color: const Color(0xFF888888),
          ),
        ],
      ),
      body: FutureBuilder<void>(
        future: _initFuture,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator(color: kGold));
          }
          final controller = _cameraController;
          if (controller == null || !controller.value.isInitialized) {
            return _ErrorView(
              message: _errorMessage ?? 'Error de cámara',
              onRetry: _setupCamera,
            );
          }
          return SafeArea(
            top: false,
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
              child: Column(
                children: [
                  _buildCameraCard(controller),
                  const SizedBox(height: 14),
                  _buildInfoCard(context),
                ],
              ),
            ),
          );
        },
      ),
    );
  }


  Widget _buildCameraCard(CameraController controller) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(26),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.40),
            blurRadius: 22,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(26),
        child: AspectRatio(
          aspectRatio: 0.92,
          child: Stack(
            fit: StackFit.expand,
            children: [
              _CameraPreviewFit(controller: controller),
              if (_isLooking)
                Container(
                  color: Colors.black26,
                  child: const Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircularProgressIndicator(color: Colors.white),
                        SizedBox(height: 10),
                        Text(
                          'Buscando carta...',
                          style: TextStyle(color: Colors.white),
                        ),
                      ],
                    ),
                  ),
                ),
              if (_detectedCode != null)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 18,
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.72),
                        borderRadius: BorderRadius.circular(28),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.check_circle,
                            color: Color(0xFF4BE39A),
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            _detectedCode!,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                              fontSize: 18,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }


  Widget _buildInfoCard(BuildContext context) {
    final card = _effectiveCard ?? _selectedCard ?? _lookupResult?.card;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: kSurface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: kBorder),
      ),
      child: card == null ? _buildEmptyInfo() : _buildCardInfo(context, card),
    );
  }


  Widget _buildEmptyInfo() => const Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        'Escanea una carta',
        style: TextStyle(
          fontSize: 24,
          fontWeight: FontWeight.w700,
          color: kGold,
        ),
      ),
      SizedBox(height: 10),
      Text(
        'Apunta la cámara al código inferior derecho de la carta.',
        style: TextStyle(fontSize: 16, height: 1.45, color: Color(0xFF888888)),
      ),
    ],
  );


  Widget _buildCardInfo(BuildContext context, CardData card) {
    final costText = _costText(card);
    final attributeText = _attributeText(card);
    final hasVariants = _lookupResult?.hasVariants ?? false;


    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(
                card.cleanName,
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
            ),
            const SizedBox(width: 12),
            _rarityPill(card.rarity),
          ],
        ),
        const SizedBox(height: 12),
        const Divider(height: 1, color: kBorder),
        const SizedBox(height: 16),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            _metaChip('Código', card.id),
            _metaChip('Tipo', card.cardType),
            _metaChip('Color', card.color),
            if (costText.isNotEmpty) _metaChip('Costo', costText),
            if (attributeText.isNotEmpty) _metaChip('Atributo', attributeText),
          ],
        ),
        const SizedBox(height: 12),
        if ((card.faction ?? '').isNotEmpty) _softLine('Tipo: ${card.faction}'),
        const SizedBox(height: 18),
        const Text(
          'Efecto',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          (card.effect?.isNotEmpty ?? false)
              ? card.effect!
              : 'Sin efecto registrado.',
          style: const TextStyle(
            fontSize: 16,
            height: 1.45,
            color: Colors.white70,
          ),
        ),
        const SizedBox(height: 18),
        _folderSelector(context),
        const SizedBox(height: 12),
        _quantitySelector(),
        if (hasVariants) ...[const SizedBox(height: 12), _alternateArtToggle()],
        const SizedBox(height: 14),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: _isSaving ? null : _saveToCollection,
            style: FilledButton.styleFrom(
              backgroundColor: kGold,
              foregroundColor: kBlack,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
              ),
            ),
            icon: _isSaving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: kBlack,
                    ),
                  )
                : const Icon(Icons.add_circle_outline),
            label: Text(
              _selectedFolder == null
                  ? 'Agregar carta (x$_quantity)'
                  : 'Agregar a ${_selectedFolder!.name} (x$_quantity)',
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
        if (_successMessage != null) ...[
          const SizedBox(height: 12),
          _feedbackBox(
            _successMessage!,
            const Color(0xFF0D2A1A),
            Colors.green,
          ),
        ],
        if (_errorMessage != null) ...[
          const SizedBox(height: 12),
          _feedbackBox(
            _errorMessage!,
            const Color(0xFF2A1010),
            const Color(0xFFEF9A9A),
          ),
        ],
      ],
    );
  }


  Widget _alternateArtToggle() => InkWell(
    borderRadius: BorderRadius.circular(18),
    onTap: () => setState(() => _isAlternateArt = !_isAlternateArt),
    child: Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      decoration: BoxDecoration(
        color: _isAlternateArt
            ? kGold.withOpacity(0.10)
            : kSurface2,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: _isAlternateArt
              ? kGold.withOpacity(0.6)
              : kBorder,
          width: _isAlternateArt ? 1.5 : 1,
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.auto_awesome,
            color: _isAlternateArt
                ? kGold
                : const Color(0xFF666666),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Arte alternativa (Parallel)',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: _isAlternateArt
                        ? kGold
                        : Colors.white,
                  ),
                ),
                Text(
                  _isAlternateArt
                      ? 'Usando imagen parallel del servidor'
                      : 'Activar si tienes la versión parallel',
                  style: TextStyle(
                    fontSize: 13,
                    color: _isAlternateArt
                        ? kGold
                        : const Color(0xFF666666),
                  ),
                ),
              ],
            ),
          ),
          Switch.adaptive(
            value: _isAlternateArt,
            onChanged: (v) => setState(() => _isAlternateArt = v),
            activeColor: kGold,
          ),
        ],
      ),
    ),
  );


  Widget _rarityPill(String rarity) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(999),
      border: Border.all(color: kGold.withOpacity(0.6), width: 1.5),
      color: kGold.withOpacity(0.10),
    ),
    child: Text(
      rarity,
      style: const TextStyle(
        color: kGold,
        fontWeight: FontWeight.w700,
        fontSize: 16,
      ),
    ),
  );


  Widget _metaChip(String label, String value) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    decoration: BoxDecoration(
      color: kSurface2,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: kBorder),
    ),
    child: RichText(
      text: TextSpan(
        style: const TextStyle(fontSize: 16, color: Colors.white),
        children: [
          TextSpan(
            text: '$label: ',
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          TextSpan(text: value),
        ],
      ),
    ),
  );


  Widget _softLine(String text) => Container(
    width: double.infinity,
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
    decoration: BoxDecoration(
      color: kSurface2,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: kBorder),
    ),
    child: Text(
      text,
      style: const TextStyle(fontSize: 16, color: Colors.white),
    ),
  );


  Widget _feedbackBox(String text, Color bg, Color fg) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: bg,
      borderRadius: BorderRadius.circular(14),
    ),
    child: Text(
      text,
      style: TextStyle(color: fg, fontWeight: FontWeight.w600),
    ),
  );


  Widget _folderSelector(BuildContext context) => InkWell(
    borderRadius: BorderRadius.circular(18),
    onTap: _loadingFolders
        ? null
        : () async {
            final result = await showDialog<Object>(
              context: context,
              builder: (ctx) => SimpleDialog(
                backgroundColor: kSurface,
                title: const Text('Elegir carpeta',
                    style: TextStyle(color: Colors.white)),
                children: [
                  SimpleDialogOption(
                    onPressed: () => Navigator.pop(ctx, 'none'),
                    child: const Row(
                      children: [
                        Icon(Icons.folder_off_outlined, color: Colors.grey),
                        SizedBox(width: 10),
                        Text(
                          'Sin carpeta',
                          style: TextStyle(color: Colors.grey),
                        ),
                      ],
                    ),
                  ),
                  if (_allFolders.isNotEmpty) const Divider(height: 1, color: kBorder),
                  ..._allFolders.map(
                    (f) => SimpleDialogOption(
                      onPressed: () => Navigator.pop(ctx, f),
                      child: Row(
                        children: [
                          const Icon(Icons.folder_outlined, color: Color(0xFF888888)),
                          const SizedBox(width: 10),
                          Expanded(child: Text(f.name,
                              style: const TextStyle(color: Colors.white))),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            );


            if (result == 'none') {
              setState(() => _selectedFolder = null);
            } else if (result is Folder) {
              setState(() => _selectedFolder = result);
            }
          },
    child: Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
      decoration: BoxDecoration(
        color: kSurface2,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: kBorder),
      ),
      child: Row(
        children: [
          Icon(
            _selectedFolder == null
                ? Icons.folder_off_outlined
                : Icons.folder_outlined,
            color: const Color(0xFF888888),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _loadingFolders
                  ? 'Cargando carpetas...'
                  : _selectedFolder?.name ?? 'Sin carpeta',
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: _selectedFolder == null
                    ? Colors.grey
                    : Colors.white,
              ),
            ),
          ),
          const Icon(
            Icons.keyboard_arrow_down_rounded,
            color: Color(0xFF888888),
          ),
        ],
      ),
    ),
  );


  Widget _quantitySelector() => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
    decoration: BoxDecoration(
      color: kSurface2,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: kBorder),
    ),
    child: Row(
      children: [
        const Text(
          'Cantidad',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: Colors.white,
          ),
        ),
        const Spacer(),
        _roundQtyButton(
          icon: Icons.remove,
          onTap: _quantity > 1 ? () => setState(() => _quantity--) : null,
        ),
        SizedBox(
          width: 48,
          child: Center(
            child: Text(
              '$_quantity',
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
          ),
        ),
        _roundQtyButton(
          icon: Icons.add,
          onTap: () => setState(() => _quantity++),
        ),
      ],
    ),
  );


  Widget _roundQtyButton({
    required IconData icon,
    required VoidCallback? onTap,
  }) => InkWell(
    borderRadius: BorderRadius.circular(14),
    onTap: onTap,
    child: Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: onTap != null
            ? kGold
            : const Color(0xFF333333),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Icon(icon, color: onTap != null ? kBlack : Colors.white54, size: 20),
    ),
  );
}


class _CameraPreviewFit extends StatelessWidget {
  const _CameraPreviewFit({required this.controller});
  final CameraController controller;


  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final previewSize = controller.value.previewSize;
        final previewAspect = previewSize == null
            ? controller.value.aspectRatio
            : previewSize.height / previewSize.width;
        return ClipRect(
          child: OverflowBox(
            maxWidth: double.infinity,
            maxHeight: double.infinity,
            child: FittedBox(
              fit: BoxFit.cover,
              child: SizedBox(
                width: constraints.maxHeight * previewAspect,
                height: constraints.maxHeight,
                child: CameraPreview(controller),
              ),
            ),
          ),
        );
      },
    );
  }
}


class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;


  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.camera_alt_outlined, size: 64, color: Colors.grey),
          const SizedBox(height: 16),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.grey),
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: onRetry,
            style: FilledButton.styleFrom(
              backgroundColor: kGold,
              foregroundColor: kBlack,
            ),
            icon: const Icon(Icons.refresh),
            label: const Text('Reintentar'),
          ),
        ],
      ),
    ),
  );
}