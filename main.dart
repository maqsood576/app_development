import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:open_file/open_file.dart';
import 'package:path/path.dart' as p;
import 'package:http/http.dart' as http;
import 'package:mime/mime.dart';
import 'package:http_parser/http_parser.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Hive.initFlutter();
  await Hive.openBox('messages');
  runApp(const MaterialApp(home: ChatScreen()));
}

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _textController = TextEditingController();
  late final Box _messageBox;
  File? _file;
  bool _uploading = false;

  @override
  void initState() {
    super.initState();
    _messageBox = Hive.box('messages');
    _syncPendingUploads();
  }

  /// Try uploading any unsynced messages to API
  Future<void> _syncPendingUploads() async {
    final messages = _messageBox.values.toList().cast<Map>();
    for (int i = 0; i < messages.length; i++) {
      final msg = messages[i];
      if (msg['uploaded'] != true) {
        final success = await _uploadMessageToApi(msg);
        if (success) {
          await _messageBox.putAt(i, {...msg, 'uploaded': true});
          setState(() {});
        }
      }
    }
  }

  /// Upload message with optional file to your API
  Future<bool> _uploadMessageToApi(Map msg) async {
    try {
      final uri = Uri.parse("https://maqsoodah.pythonanywhere.com/api/api/msg/");

      var request = http.MultipartRequest('POST', uri);
      request.fields['text'] = msg['text'] ?? '';

      if (msg['file'] != null) {
        final file = File(msg['file']);
        if (await file.exists()) {
          final mimeType = lookupMimeType(file.path) ?? 'application/octet-stream';
          final mimeSplit = mimeType.split('/');
          request.files.add(await http.MultipartFile.fromPath(
            'file',
            file.path,
            contentType: MediaType(mimeSplit[0], mimeSplit[1]),
          ));
        }
      }

      final response = await request.send();
      if (response.statusCode == 201 || response.statusCode == 200) {
        return true;
      } else {
        debugPrint('Upload failed with status: ${response.statusCode}');
        return false;
      }
    } catch (e) {
      debugPrint('Upload exception: $e');
      return false;
    }
  }

  Future<void> _upload() async {
    final message = _textController.text.trim();
    if (message.isEmpty && _file == null) return;

    setState(() => _uploading = true);

    final timestamp = DateTime.now().toIso8601String();
    final messageData = {
      'text': message,
      'file': _file?.path,
      'timestamp': timestamp,
      'uploaded': false,
    };

    // Save locally first
    final index = await _messageBox.add(messageData);

    // Try upload to API now
    final uploaded = await _uploadMessageToApi(messageData);

    // Update uploaded flag in Hive
    await _messageBox.putAt(index, {...messageData, 'uploaded': uploaded});

    setState(() {
      _textController.clear();
      _file = null;
      _uploading = false;
    });
  }

  void _editMessage(int index) {
    final message = _messageBox.getAt(index) as Map?;
    if (message != null) {
      _textController.text = message['text'] ?? '';
      _file = message['file'] != null ? File(message['file']) : null;
      _messageBox.deleteAt(index);
      setState(() {});
    }
  }

  void _deleteMessage(int index) {
    _messageBox.deleteAt(index);
    setState(() {});
  }

  void _copyMessage(String text) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Message copied')),
    );
  }

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles();
    if (result != null) {
      final path = result.files.single.path;
      if (path != null) {
        setState(() {
          _file = File(path);
        });
      }
    }
  }

  Widget _buildMessageBubble(Map message, int index) {
    final timestamp = DateTime.tryParse(message['timestamp'] ?? '') ?? DateTime.now();
    final timeString = '${timestamp.hour}:${timestamp.minute.toString().padLeft(2, '0')}';
    final uploaded = message['uploaded'] == true;

    return Align(
      alignment: Alignment.centerRight,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
        padding: const EdgeInsets.all(12),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
        decoration: BoxDecoration(
          color: uploaded ? Colors.lightBlue.shade100 : Colors.orange.shade100,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(16),
            topRight: Radius.circular(16),
            bottomLeft: Radius.circular(16),
          ),
          boxShadow: [
            BoxShadow(color: Colors.grey.withOpacity(0.3), spreadRadius: 1, blurRadius: 5),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if ((message['text'] ?? '').isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(message['text'], style: const TextStyle(fontSize: 16)),
              ),
            if (message['file'] != null)
              InkWell(
                onTap: () async {
                  final file = File(message['file']);
                  if (await file.exists()) {
                    await OpenFile.open(file.path);
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('File not found')),
                    );
                  }
                },
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.insert_drive_file, size: 18, color: Colors.blueGrey),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        p.basename(message['file']),
                        style: const TextStyle(
                          color: Colors.blue,
                          fontSize: 14,
                          decoration: TextDecoration.underline,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(timeString, style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.cloud_done, color: uploaded ? Colors.green : Colors.redAccent, size: 16),
                    const SizedBox(width: 4),
                    IconButton(icon: const Icon(Icons.edit, size: 18), onPressed: () => _editMessage(index)),
                    IconButton(icon: const Icon(Icons.delete_outline, size: 18), onPressed: () => _deleteMessage(index)),
                    IconButton(icon: const Icon(Icons.copy, size: 18), onPressed: () => _copyMessage(message['text'] ?? '')),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final messages = _messageBox.values.toList().cast<Map>();

    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: const Text('Chatbot', style: TextStyle(fontWeight: FontWeight.w600)),
        backgroundColor: Colors.blueAccent,
        elevation: 4,
      ),
      body: Column(
        children: [
          Expanded(
            child: messages.isEmpty
                ? const Center(child: Text("No messages yet"))
                : ListView.builder(
                    reverse: true,
                    padding: const EdgeInsets.only(top: 8, bottom: 8),
                    itemCount: messages.length,
                    itemBuilder: (context, index) {
                      final message = messages[messages.length - 1 - index];
                      return _buildMessageBubble(message, messages.length - 1 - index);
                    },
                  ),
          ),
          const Divider(height: 1, thickness: 1),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            color: Colors.white,
            child: Row(
              children: [
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      color: Colors.grey[200],
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: TextField(
                      controller: _textController,
                      decoration: const InputDecoration(
                        hintText: 'Type a message',
                        border: InputBorder.none,
                      ),
                      enabled: !_uploading,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                IconButton(
                  icon: const Icon(Icons.attach_file, color: Colors.blueAccent),
                  onPressed: _uploading ? null : _pickFile,
                ),
                IconButton(
                  icon: const Icon(Icons.send, color: Colors.blueAccent),
                  onPressed: _uploading ? null : _upload,
                ),
              ],
            ),
          ),
          if (_uploading) const LinearProgressIndicator(minHeight: 2),
          if (_file != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              child: Row(
                children: [
                  const Icon(Icons.insert_drive_file, color: Colors.blueAccent),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      p.basename(_file!.path),
                      style: const TextStyle(color: Colors.blueAccent, fontWeight: FontWeight.w600),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.redAccent),
                    onPressed: () => setState(() => _file = null),
                  )
                ],
              ),
            ),
        ],
      ),
    );
  }
}
