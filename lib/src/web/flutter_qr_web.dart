import 'dart:async';
import 'dart:core';
import 'dart:html';
import 'dart:ui' as ui;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';

import '../../qr_code_scanner.dart';
import '../qr_code_scanner.dart';
import '../types/camera.dart';

class WebQrView extends StatefulWidget {
  final QRViewCreatedCallback onPlatformViewCreated;
  final CameraFacing? cameraFacing;

  const WebQrView({
    Key? key,
    required this.onPlatformViewCreated,
    this.cameraFacing = CameraFacing.front,
  }) : super(key: key);

  @override
  _WebQrViewState createState() => _WebQrViewState();

  static Future<bool> cameraAvailable() async {
    final sources = await window.navigator.mediaDevices!.enumerateDevices();
    var hasCam = false;
    for (final e in sources) {
      if (e.kind == 'videoinput') {
        hasCam = true;
      }
    }
    return hasCam;
  }
}

class _WebQrViewState extends State<WebQrView> {
  late BarcodeDetector _barcodeDetector;
  late VideoElement _video;
  late QRViewControllerWeb _controller;
  final StreamController<Barcode> _scanUpdateController =
      StreamController<Barcode>();

  bool _currentlyProcessing = false;
  final Size _size = Size(1280, 720);
  String? code;
  String? _errorMsg;
  String viewID = 'QRVIEW-' + DateTime.now().millisecondsSinceEpoch.toString();

  late CameraFacing facing;

  @override
  void initState() {
    super.initState();
    _controller = QRViewControllerWeb(this);
    _barcodeDetector = BarcodeDetector();
    facing = widget.cameraFacing ?? CameraFacing.front;
    _video = VideoElement()
      ..style.width = '${_size.width}px'
      ..style.height = '${_size.height}px'
      ..autoplay = true
      ..muted = true;
    _video.setAttribute('playsinline', 'true');

    // ignore: UNDEFINED_PREFIXED_NAME
    ui.platformViewRegistry.registerViewFactory(viewID, (int id) => _video);

    loadVideoStream().then((_) => startCapture());
  }

  Future<void> loadVideoStream() async {
    try {
      if (window.location.protocol.contains('https')) {
        var options = {
          'audio': false,
          'video': {
            'facingMode': facing == CameraFacing.front ? 'user' : 'environment',
            'width': {'ideal': _size.width.toInt()},
            'height': {'ideal': _size.height.toInt()},
            'frameRate': {'ideal': 15},
          },
        };
        _video.srcObject =
            await window.navigator.mediaDevices?.getUserMedia(options);
      } else {
        _video.srcObject =
            await window.navigator.getUserMedia(audio: false, video: true);
      }
    } catch (err) {
      setState(() {
        _errorMsg = err.toString();
      });
    }
  }

  Future<void> startCapture() async {
    await Future.delayed(Duration(milliseconds: 250));
    widget.onPlatformViewCreated(_controller);
    await _video.play();

    setState(() {
      _currentlyProcessing = true;
    });

    await capture();
  }

  Future capture() async {
    if (_currentlyProcessing && _video.srcObject != null) {
      try {
        var barcodes = await _barcodeDetector.detect(_video);
        if (barcodes.isNotEmpty) {
          barcodes.forEach((code) {
            _scanUpdateController.add(Barcode(
                code.rawValue, BarcodeFormat.qrcode, code.rawValue.codeUnits));
          });
        }
      } catch (err) {
        print(err);
      } finally {
        window.requestAnimationFrame((n) => capture());
      }
    }
  }

  void cancel() {
    if (_currentlyProcessing) {
      _stopStream();
    }
  }

  @override
  void dispose() {
    cancel();
    super.dispose();
  }

  // Platform messages are asynchronous, so we initialize in an async method.
  Future<void> _stopStream() async {
    setState(() {
      _currentlyProcessing = false;
    });

    try {
      _video.pause();
      _video.srcObject?.getTracks().forEach((track) {
        track.stop();
        track.enabled = false;
      });
      _video.srcObject = null;
      // ignore: empty_catches
    } catch (e) {}
  }

  @override
  Widget build(BuildContext context) {
    if (_errorMsg != null) {
      return Center(child: Text(_errorMsg!));
    }
    if (_video.srcObject == null) {
      return Center(child: CircularProgressIndicator());
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        var zoom = 1.0;

        if (_size.height != 0) zoom = constraints.maxHeight / _size.height;

        if (_size.width != 0) {
          final horizontalZoom = constraints.maxWidth / _size.width;
          if (horizontalZoom > zoom) {
            zoom = horizontalZoom;
          }
        }

        return SizedBox(
          width: constraints.maxWidth,
          height: constraints.maxHeight,
          child: Center(
            child: SizedBox.fromSize(
              size: _size,
              child: Transform.scale(
                alignment: Alignment.center,
                scale: zoom,
                child: HtmlElementView(key: UniqueKey(), viewType: viewID),
              ),
            ),
          ),
        );
      },
    );
  }
}

class QRViewControllerWeb implements QRViewController {
  final _WebQrViewState _state;

  QRViewControllerWeb(this._state);

  @override
  Stream<Barcode> get scannedDataStream => _state._scanUpdateController.stream;

  @override
  // TODO: implement hasPermissions. Blocking: WebQrView.cameraAvailable() returns a Future<bool> whereas a bool is required
  bool get hasPermissions => throw UnimplementedError();

  @override
  Future<CameraFacing> getCameraInfo() async {
    return _state.facing;
  }

  @override
  Future<CameraFacing> flipCamera() async {
    // TODO: improve error handling
    _state.facing = _state.facing == CameraFacing.front
        ? CameraFacing.back
        : CameraFacing.front;
    await _state.loadVideoStream();
    return _state.facing;
  }

  @override
  Future<bool?> getFlashStatus() async {
    // TODO: flash is simply not supported by JavaScipt. To avoid issuing applications, we always return it to be off.
    return false;
  }

  @override
  void dispose() => _state.cancel();

  @override
  Future<SystemFeatures> getSystemFeatures() {
    // TODO: implement getSystemFeatures
    throw UnimplementedError();
  }

  @override
  Future<void> pauseCamera() async {
    _state._video.pause();
  }

  @override
  Future<void> resumeCamera() async {
    await _state._video.play();
  }

  @override
  Future<void> stopCamera() {
    // TODO: implement stopCamera
    throw UnimplementedError();
  }

  @override
  Future<void> toggleFlash() async {
    // TODO: flash is simply not supported by JavaScipt
    return;
  }
}

Widget createWebQrView({onPlatformViewCreated, CameraFacing? cameraFacing}) =>
    WebQrView(
      onPlatformViewCreated: onPlatformViewCreated,
      cameraFacing: cameraFacing,
    );
