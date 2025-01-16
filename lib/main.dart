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

          // Handle received files
          for (var item in stackedItems) {
            if (item.fileBytes != null && item.mediaPath != null) {
              final savedPath = await saveReceivedFile(item.fileBytes!, item.mediaPath!);
              setState(() {
                item.mediaPath = savedPath; // Update mediaPath to the saved file path
              });
              print('savedfile $savedPath');
              print('mediaPath ${item.mediaPath}');
            }
          }
        });
      });
    });
    setState(() {}); // Update the UI after getting the IP address
  }

  // Save received file to a permanent location
  Future<String> saveReceivedFile(Uint8List fileBytes, String fileName) async {
    final directory = await getApplicationDocumentsDirectory(); // Use getApplicationDocumentsDirectory
    final filePath = '${directory.path}/$fileName';
    final file = File(filePath);
    await file.writeAsBytes(fileBytes);
    print('File saved to $filePath');
    return filePath; // Return the saved file path
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
                                            image: DecorationImage(
                                              image: FileImage(File(item.mediaPath!)),
                                              fit: BoxFit.cover,
                                            ),
                                          ),
                                        )
                                      : item.type == 'video'
                                          ? Container(
                                              width: item.width,
                                              height: item.height,
                                              child: VideoWidget(filePath: item.mediaPath!),
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
  final Uint8List? fileBytes; // Add fileBytes
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
      fileBytes: json['fileBytes'] != null ? base64Decode(json['fileBytes']) : null,
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
      'fileBytes': fileBytes != null ? base64Encode(fileBytes!) : null,
      'width': width,
      'height': height,
      'posX': posX,
      'posY': posY,
    };
  }
}

class VideoWidget extends StatefulWidget {
  final String filePath;

  const VideoWidget({required this.filePath, super.key});

  @override
  State<VideoWidget> createState() => _VideoWidgetState();
}

class _VideoWidgetState extends State<VideoWidget> {
  late VideoPlayerController _controller;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.file(File(widget.filePath))
      ..setVolume(0)
      ..initialize().then((_) {
        setState(() {});
        _controller.play();
        _controller.setLooping(true);
      });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _controller.value.isInitialized
        ? AspectRatio(
            aspectRatio: _controller.value.aspectRatio,
            child: VideoPlayer(
              _controller,
            ),
          )
        : const Center(child: CircularProgressIndicator());
  }
}
