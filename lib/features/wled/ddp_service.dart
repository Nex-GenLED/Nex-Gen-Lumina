import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexgen_command/app_providers.dart';
import 'package:nexgen_command/features/discovery/device_discovery.dart';

/// Distributed Display Protocol (DDP) sender for ultra-low-latency LED updates.
///
/// This implementation uses a UDP socket to send frames to the Dig-Octa/WLED
/// compatible controller on port 4048. The header format follows the user
/// specification with magic bytes [0x41, 0x4C, 0x56, 0x01] ("ALV\x01"), then a
/// DDP-like sequence/flags/len/offset layout.
class DdpService {
  final InternetAddress target;
  final int port;
  RawDatagramSocket? _socket;
  bool _running = false;
  int _sequence = 0;

  DdpService(String ip, {this.port = 4048}) : target = InternetAddress(ip);

  bool get isRunning => _running;

  Future<void> start() async {
    if (_running) return;
    if (kSimulationMode) {
      _running = true;
      debugPrint('DDP(sim): started');
      return;
    }
    try {
      _socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      _socket!.writeEventsEnabled = true;
      _running = true;
      debugPrint('DDP: socket bound ${_socket!.address.address}:${_socket!.port}');
    } catch (e) {
      debugPrint('DDP start failed: $e');
      rethrow;
    }
  }

  void stop() {
    _running = false;
    try {
      _socket?.close();
    } catch (_) {}
    _socket = null;
    debugPrint('DDP: stopped');
  }

  /// Sends one frame of channel data. data must be tightly packed RGB or RGBW bytes.
  /// [channelOffset] controls start channel (usually 0). If [rgbw] is true, each pixel is 4 bytes.
  void sendFrame(Uint8List data, {int channelOffset = 0, bool rgbw = false}) {
    if (!_running) return;
    if (kSimulationMode) {
      // In simulation, just trace minimal stats
      if ((_sequence % 30) == 0) debugPrint('DDP(sim): frame seq=$_sequence bytes=${data.length} rgbw=$rgbw');
      _sequence = (_sequence + 1) & 0xFF;
      return;
    }
    final header = _buildHeader(length: data.length, offset: channelOffset, rgbw: rgbw);
    final packet = Uint8List(header.length + data.length);
    packet.setRange(0, header.length, header);
    packet.setRange(header.length, header.length + data.length, data);
    _socket?.send(packet, target, port);
    _sequence = (_sequence + 1) & 0xFF;
  }

  /// Fetches LED count from /json/info on the target. Returns null on failure.
  Future<int?> getLedCount() async {
    if (kSimulationMode) return 150;
    try {
      final httpClient = HttpClient()..connectionTimeout = const Duration(seconds: 3);
      final uri = Uri.parse('http://${target.address}/json/info');
      final req = await httpClient.getUrl(uri);
      req.headers.set(HttpHeaders.acceptHeader, 'application/json');
      final res = await req.close().timeout(const Duration(seconds: 3));
      final body = await res.transform(utf8.decoder).join();
      httpClient.close(force: true);
      if (res.statusCode >= 200 && res.statusCode < 300) {
        final map = jsonDecode(body) as Map<String, dynamic>;
        final leds = map['leds'];
        if (leds is Map) {
          final cnt = leds['count'];
          if (cnt is num) return cnt.toInt();
        }
      }
    } catch (e) {
      debugPrint('DDP getLedCount error: $e');
    }
    return null;
  }

  Uint8List _buildHeader({required int length, required int offset, required bool rgbw}) {
    // Header layout (12 bytes):
    // 0..3: magic 'A','L','V',0x01
    // 4: flags (bit 0 set for data; bit 4 indicates RGBW)
    // 5: sequence (0..255)
    // 6..7: data length (big-endian)
    // 8..11: channel offset (big-endian)
    final bytes = Uint8List(12);
    bytes[0] = 0x41; // 'A'
    bytes[1] = 0x4C; // 'L'
    bytes[2] = 0x56; // 'V'
    bytes[3] = 0x01; // version
    int flags = 0x01; // data present
    if (rgbw) flags |= 0x10; // custom bit to indicate RGBW pixel packing
    bytes[4] = flags;
    bytes[5] = _sequence;
    bytes[6] = (length >> 8) & 0xFF;
    bytes[7] = length & 0xFF;
    bytes[8] = (offset >> 24) & 0xFF;
    bytes[9] = (offset >> 16) & 0xFF;
    bytes[10] = (offset >> 8) & 0xFF;
    bytes[11] = offset & 0xFF;
    return bytes;
  }
}

/// A simple, local effect generator that produces smooth frames from a color palette.
/// This is used to demonstrate AI-driven patterns in real time without relying on
/// device-side HTTP effects.
class PaletteFlowGenerator {
  final List<List<int>> palette; // list of [r,g,b,(w?)]
  final bool rgbw;
  final int pixelCount;
  final double speed; // cycles per second
  final double spread; // spatial frequency

  double _t = 0;

  PaletteFlowGenerator({
    required this.palette,
    required this.pixelCount,
    this.rgbw = false,
    this.speed = 0.2,
    this.spread = 0.08,
  });

  /// Advances time by [dt] seconds and returns the next packed frame.
  Uint8List nextFrame(double dt) {
    _t += dt * speed * 2 * pi;
    final bytesPerPixel = rgbw ? 4 : 3;
    final out = Uint8List(pixelCount * bytesPerPixel);
    if (palette.isEmpty) return out;
    for (int i = 0; i < pixelCount; i++) {
      final x = i * spread;
      final phase = (_t + x) % (2 * pi);
      final mix = (sin(phase) * 0.5 + 0.5); // 0..1
      // Blend between two palette colors cycling over time
      final a = palette[(i ~/ max(1, (1 / spread)).toInt()) % palette.length];
      final b = palette[(i + 1) % palette.length];
      final r = (a[0] * (1 - mix) + b[0] * mix).clamp(0, 255).toInt();
      final g = (a[1] * (1 - mix) + b[1] * mix).clamp(0, 255).toInt();
      final bl = (a[2] * (1 - mix) + b[2] * mix).clamp(0, 255).toInt();
      int w = 0;
      if (rgbw) {
        final aw = a.length >= 4 ? a[3] : 0;
        final bw = b.length >= 4 ? b[3] : 0;
        w = (aw * (1 - mix) + bw * mix).clamp(0, 255).toInt();
      }
      final base = i * bytesPerPixel;
      out[base] = r;
      out[base + 1] = g;
      out[base + 2] = bl;
      if (rgbw) out[base + 3] = w;
    }
    return out;
  }
}

/// Riverpod: exposes the DDP service for the currently selected device.
final ddpServiceProvider = Provider<DdpService?>((ref) {
  final ip = ref.watch(selectedDeviceIpProvider);
  if (ip == null) return null;
  return DdpService(ip);
});

/// Tracks whether a DDP stream is active. When true, HTTP updates should pause.
final ddpStreamingProvider = StateProvider<bool>((ref) => false);

/// Manages a 60 FPS streaming loop using a generator.
class DdpStreamController {
  final DdpService service;
  Timer? _timer;
  late int _lastTickMs;
  PaletteFlowGenerator? _generator;
  bool _rgbw = false;

  DdpStreamController(this.service);

  Future<void> start(PaletteFlowGenerator generator, {bool rgbw = false}) async {
    _generator = generator;
    _rgbw = rgbw;
    await service.start();
    const frameMs = 1000 ~/ 60; // ~16ms
    _lastTickMs = DateTime.now().millisecondsSinceEpoch;
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(milliseconds: frameMs), (_) {
      final now = DateTime.now().millisecondsSinceEpoch;
      final dt = (now - _lastTickMs) / 1000.0;
      _lastTickMs = now;
      final gen = _generator;
      if (gen != null) {
        final frame = gen.nextFrame(dt);
        service.sendFrame(frame, channelOffset: 0, rgbw: _rgbw);
      }
    });
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
    service.stop();
  }
}
