import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../../core/api_config.dart';
import 'knowledge_device_model.dart';
import 'knowledge_channel_screen.dart';

class KnowledgeScreen extends StatefulWidget {
  const KnowledgeScreen({super.key});

  @override
  State<KnowledgeScreen> createState() => _KnowledgeScreenState();
}

class _KnowledgeScreenState extends State<KnowledgeScreen> {
  List<KnowledgeDevice> _devices = [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _fetchChannels();
  }

  Future<void> _fetchChannels() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final url = Uri.parse('${ApiConfig.baseUrl}/api/v1/channels');
      debugPrint('--> [API REQUEST] GET $url');

      final response = await http.get(url, headers: {'Content-Type': 'application/json'});

      debugPrint('<-- [API RESPONSE] ${response.statusCode} GET $url');
      debugPrint('Response Body: ${response.body}');

      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        List<dynamic> list = [];
        if (decoded is List) {
          list = decoded;
        } else if (decoded is Map && decoded['data'] is List) {
          list = decoded['data'];
        }

        setState(() {
          _devices = list.map((json) => KnowledgeDevice.fromJson(json)).toList();
          _isLoading = false;
        });
      } else {
        setState(() {
          _error = 'Failed to load channels: ${response.statusCode}';
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error fetching channels: $e');
      setState(() {
        _error = 'Error connecting to server';
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(_error!, style: const TextStyle(color: Colors.red)),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _fetchChannels,
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16.0),
      itemCount: _devices.length + 1,
      itemBuilder: (context, index) {
        if (index == 0) {
          return const Padding(
            padding: EdgeInsets.only(bottom: 16.0),
            child: Text(
              'Channels',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
          );
        }
        final device = _devices[index - 1];
        return _buildChannelTile(device);
      },
    );
  }

  Widget _buildChannelTile(KnowledgeDevice device) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12.0),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: Theme.of(context).colorScheme.outlineVariant.withOpacity(0.3),
          width: 1,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => KnowledgeChannelScreen(channel: device),
            ),
          );
        },
        child: Padding(
          padding: const EdgeInsets.all(12.0),
          child: Row(
            children: [
              CircleAvatar(
                radius: 26,
                backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                child: Icon(
                  Icons.memory_rounded, 
                  size: 26, 
                  color: Theme.of(context).colorScheme.onPrimaryContainer,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      device.name, 
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${device.followers} followers', 
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant.withOpacity(0.7),
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right_rounded, 
                color: Theme.of(context).colorScheme.onSurfaceVariant.withOpacity(0.4),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
