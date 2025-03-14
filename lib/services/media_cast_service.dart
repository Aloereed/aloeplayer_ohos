import 'dart:async';
import 'dart:io';
import 'package:castscreen/castscreen.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import '../models/cast_device.dart';

class MediaCastService {
  static final MediaCastService _instance = MediaCastService._internal();
  factory MediaCastService() => _instance;
  
  MediaCastService._internal() {
    dio = Dio();
    // Don't initialize the server in the constructor
  }
  
  Dio dio = Dio();
  HttpServer? _httpServer; // Store the actual server instance
  List<CastDevice> devices = [];
  CastDevice? activeDevice;
  String? currentMediaPath;
  StreamController<List<CastDevice>> devicesStreamController = StreamController<List<CastDevice>>.broadcast();
  
  Stream<List<CastDevice>> get devicesStream => devicesStreamController.stream;

  Future<void> startDiscovery() async {
    devices.clear();
    
    try {
      final discoveredDevices = await CastScreen.discoverDevice(
        timeout: const Duration(seconds: 5),
        onError: (e) => debugPrint('Discovery error: $e'),
      );
      if (discoveredDevices.isEmpty) {
       print("[Cast] No devices found"); 
      }
      
      devices = discoveredDevices
          .map((device) => CastDevice(device: device))
          .toList();
      
      devicesStreamController.add(devices);
    } catch (e) {
      debugPrint('Error discovering devices: $e');
    }
  }

  Future<String> startLocalServer(String filePath) async {
    // Close previous server if it exists
    if (_httpServer != null) {
      await _httpServer!.close(force: true);
      _httpServer = null;
    }
    
    print("[cast] start local server");
    final file = File(filePath);
    final localIp = await _getLocalIpAddress();
    
    // Create a new server each time
    _httpServer = await HttpServer.bind(InternetAddress.anyIPv4, 0);
    final serverPort = _httpServer!.port;
    
    print("[cast] local ip: $localIp, port: $serverPort");
    _httpServer!.listen((request) {
      if (request.uri.path == '/media') {
        request.response.headers.contentType = ContentType.parse(
          _getContentType(filePath),
        );
        request.response.headers.add('Access-Control-Allow-Origin', '*');
        
        file.openRead().pipe(request.response).catchError((e) {
          debugPrint('Error serving file: $e');
        });
      } else {
        request.response.statusCode = HttpStatus.notFound;
        request.response.close();
      }
    });
    
    print("[cast] local server started with port: $serverPort");
    return 'http://$localIp:$serverPort/media';
  }
  
  Future<String> _getLocalIpAddress() async {
    final interfaces = await NetworkInterface.list(
      type: InternetAddressType.IPv4,
      includeLinkLocal: false,
    );
    
    // Filter out loopback and get first available interface
    return interfaces
        .where((interface) => 
            !interface.addresses.first.address.startsWith('127.'))
        .first
        .addresses
        .first
        .address;
  }
  
  String _getContentType(String path) {
    final ext = path.split('.').last.toLowerCase();
    switch (ext) {
      case 'mp4':
        return 'video/mp4';
      case 'mp3':
        return 'audio/mpeg';
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'png':
        return 'image/png';
      default:
        return 'application/octet-stream';
    }
  }

  Future<bool> connectToDevice(CastDevice device) async {
    try {
      final isAlive = await device.device.alive();
      if (!isAlive) {
        debugPrint('Device is not alive');
        print(device.device.spec.URLBase);
        return false;
      }
      
      // Disconnect from current device if any
      if (activeDevice != null) {
        await disconnectFromDevice();
      }
      
      device.isConnected = true;
      activeDevice = device;
      devicesStreamController.add(devices);
      return true;
    } catch (e) {
      debugPrint('Error connecting to device: $e');
      return false;
    }
  }

  Future<bool> disconnectFromDevice() async {
    if (activeDevice == null) return true;
    
    try {
      await stopMedia();
      activeDevice!.isConnected = false;
      activeDevice!.isPlaying = false;
      activeDevice = null;
      devicesStreamController.add(devices);
      return true;
    } catch (e) {
      debugPrint('Error disconnecting from device: $e');
      return false;
    }
  }

  Future<bool> castMedia(String mediaPath) async {
    if (activeDevice == null) return false;
    
    try {
      currentMediaPath = mediaPath;
      final mediaUrl = await startLocalServer(mediaPath);
      
      final device = activeDevice!.device;
      
      // SetAVTransportURI action to set the media
      await device.setAVTransportURI(
        SetAVTransportURIInput(mediaUrl),
      );
      
      // Play action to start playback
      await device.play(PlayInput());
      
      activeDevice!.isPlaying = true;
      devicesStreamController.add(devices);
      return true;
    } catch (e) {
      debugPrint('Error casting media: $e');
      return false;
    }
  }

  Future<bool> pauseMedia() async {
    if (activeDevice == null || !activeDevice!.isPlaying) return false;
    
    try {
      await activeDevice!.device.pause(PauseInput());
      activeDevice!.isPlaying = false;
      devicesStreamController.add(devices);
      return true;
    } catch (e) {
      debugPrint('Error pausing media: $e');
      return false;
    }
  }

  Future<bool> resumeMedia() async {
    if (activeDevice == null || activeDevice!.isPlaying) return false;
    
    try {
      await activeDevice!.device.play(PlayInput());
      activeDevice!.isPlaying = true;
      devicesStreamController.add(devices);
      return true;
    } catch (e) {
      debugPrint('Error resuming media: $e');
      return false;
    }
  }

  Future<bool> stopMedia() async {
    if (activeDevice == null) return false;
    
    try {
      await activeDevice!.device.stop(StopInput());
      activeDevice!.isPlaying = false;
      devicesStreamController.add(devices);
      return true;
    } catch (e) {
      debugPrint('Error stopping media: $e');
      return false;
    }
  }

  void dispose() {
    // Close the server gracefully
    if (_httpServer != null) {
      _httpServer!.close(force: true);
      _httpServer = null;
    }
    // Uncomment this if you want to close the stream controller
    // devicesStreamController.close();
  }
}