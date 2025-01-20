import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:video_player/video_player.dart';

import 'package:path_provider/path_provider.dart';

void main() {
  runApp(const HostApp());
}

class HostApp extends StatelessWidget {
  const HostApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      title: 'Host App',
      home: HostScreen(),
    );
  }
}

class HostScreen extends StatefulWidget {
  const HostScreen({super.key});

  @override
  State<HostScreen> createState() => _HostScreenState();
}

class _HostScreenState extends State<HostScreen> {
  String receivedMessage = 'No message received yet';
  late WebSocket serverSocket;
  String ipAddress = ''; // Variable to hold IP address
  late List<MovableItem> stackedItems = [];

  @override
  void initState() {
    super.initState();
    startServer();
  }

  // Function to get the local IP address
  Future<String> getLocalIPAddress() async {
    try {
      final interfaces = await NetworkInterface.list();
      for (var interface in interfaces) {
        for (var addr in interface.addresses) {
          if (addr.type == InternetAddressType.IPv4 && !addr.isLoopback) {
            return addr.address; // Return the local IPv4 address
          }
        }
      }
    } catch (e) {
      print("Error getting local IP address: $e");
    }
    return 'Unable to get IP address'; // Fallback if no IP address is found
  }

  // Function to start the WebSocket server
  Future<void> startServer() async {
    ipAddress = await getLocalIPAddress();
    final server = await HttpServer.bind(InternetAddress.anyIPv4, 8080);
    print('WebSocket server is running at ws://$ipAddress:8080');
    server.listen((HttpRequest request) {
      WebSocketTransformer.upgrade(request).then((webSocket) {
        serverSocket = webSocket;
        serverSocket.listen((message) async {
          setState(() {
            receivedMessage = message;
            final List<dynamic> jsonList = jsonDecode(message);
            stackedItems = jsonList.map((json) => MovableItem.fromJson(json)).toList();
            print('stackedItems: $stackedItems');
          });
        });
      });
    });
    setState(() {}); // Update the UI after getting the IP address
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Host App')),
      body: Center(
        child: SingleChildScrollView(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              ipAddress.isEmpty
                  ? const CircularProgressIndicator()
                  : Column(
                      children: [
                        QrImageView(
                          data: 'ws://$ipAddress:8080',
                          size: 200.0,
                        ),
                        const SizedBox(height: 20),
                        const Text(
                          'Scan this QR Code from the Client App',
                          style: TextStyle(fontSize: 18),
                        ),
                      ],
                    ),
              const SizedBox(height: 20),
              const Text(
                'Received message: ',
                style: const TextStyle(fontSize: 18),
              ),
              const SizedBox(height: 20),
              stackedItems.isEmpty
                  ? const Text('No stack data received yet')
                  : ColoredBox(
                      color: Colors.grey,
                      child: SizedBox(
                        width: 200,
                        height: 300,
                        child: Stack(
                          children: stackedItems.map((item) {
                            print('stackedItems: ${item.type}');
                            return Positioned(
                              left: item.posX,
                              top: item.posY,
                              child: item.type == 'text'
                                  ? Container(
                                      width: item.width,
                                      height: item.height,
                                      alignment: Alignment.center,
                                      child: const Text(
                                        'Text',
                                        style: TextStyle(color: Colors.white, fontSize: 16),
                                      ),
                                    )
                                  : item.type == 'image'
                                      ? Container(
                                          width: item.width,
                                          height: item.height,
                                          decoration: BoxDecoration(
                                            borderRadius: BorderRadius.circular(8),
                                          ),
                                          child: Image.memory(
                                            base64Decode(item.fileBytes!), // Decode Base64 to Uint8List
                                            fit: BoxFit.fill,
                                          ),
                                        )
                                      : item.type == 'video'
                                          ? Container(
                                              width: item.width,
                                              height: item.height,
                                              child: VideoWidget(base64FileBytes: item.fileBytes!,),
                                            )
                                          : const SizedBox.shrink(),
                            );
                          }).toList(),
                        ),
                      ),
                    ),
            ],
          ),
        ),
      ),
    );
  }
}

class MovableItem {
  final String type;
  String? mediaPath;
  final String? fileBytes; // Add fileBytes
  final double width, height, posX, posY;

  MovableItem({
    required this.type,
    this.mediaPath,
    this.fileBytes,
    required this.width,
    required this.height,
    required this.posX,
    required this.posY,
  });

  factory MovableItem.fromJson(Map<String, dynamic> json) {
    return MovableItem(
      type: json['type'],
      mediaPath: json['mediaPath'],
      fileBytes: json['fileBytes'],
      width: json['width'],
      height: json['height'],
      posX: json['posX'],
      posY: json['posY'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'type': type,
      'mediaPath': mediaPath,
      'fileBytes': fileBytes,
      'width': width,
      'height': height,
      'posX': posX,
      'posY': posY,
    };
  }
}


class VideoWidget extends StatefulWidget {
  final String base64FileBytes;

  const VideoWidget({required this.base64FileBytes, super.key});

  @override
  State<VideoWidget> createState() => _VideoWidgetState();
}

class _VideoWidgetState extends State<VideoWidget> {
  late VideoPlayerController _controller;
  String? _tempFilePath;
  bool _isVideoReady = false;

  @override
  void initState() {
    super.initState();
    _prepareVideo();
  }

  Future<void> _prepareVideo() async {
    try {
      // Decode Base64 string to Uint8List
      final videoBytes = base64Decode(widget.base64FileBytes);

      // Save the video bytes to a temporary file
      final tempDir = await getTemporaryDirectory();
      final tempFile = File('${tempDir.path}/temp_video_${DateTime.now().millisecondsSinceEpoch}.mp4');
      await tempFile.writeAsBytes(videoBytes);
      _tempFilePath = tempFile.path;

      // Initialize the VideoPlayerController
      _controller = VideoPlayerController.file(tempFile)
        ..setVolume(0)
        ..initialize().then((_) {
          setState(() {
            _isVideoReady = true;
          });
          _controller.play();
          _controller.setLooping(true);
        });
    } catch (e) {
      debugPrint("Error preparing video: $e");
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    // Clean up the temporary file
    if (_tempFilePath != null) {
      File(_tempFilePath!).deleteSync();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _isVideoReady
        ? AspectRatio(
            aspectRatio: _controller.value.aspectRatio,
            child: VideoPlayer(_controller),
          )
        : const Center(child: CircularProgressIndicator());
  }
}

