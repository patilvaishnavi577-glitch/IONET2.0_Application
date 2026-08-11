import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/providers/auth_provider.dart';
import '../../core/providers/device_provider.dart';
import '../support/help_screen.dart';
import 'chat_screen.dart';
import 'scanner_screen.dart';
import '../support/knowledge_screen.dart';
import '../profile/settings_tab.dart';
import '../updates/updates_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentIndex = 0;
  String _selectedFilter = 'All';
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Provider.of<AuthProvider>(context, listen: false).fetchProfile();
      Provider.of<DeviceProvider>(context, listen: false).fetchDevices();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _showAddDeviceDialog() {
    final idController = TextEditingController();
    final nameController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) {
        String? idError;
        String? nameError;
        bool isAdding = false;

        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: const Text('Add Device'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: idController,
                    enabled: !isAdding,
                    decoration: InputDecoration(
                      labelText: 'Device ID',
                      errorText: idError,
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.qr_code_scanner),
                        onPressed: isAdding
                            ? null
                            : () async {
                                final scannedCode =
                                    await Navigator.push<String>(
                                      context,
                                      MaterialPageRoute(
                                        builder: (context) =>
                                            const ScannerScreen(),
                                      ),
                                    );
                                if (scannedCode != null) {
                                  String targetId = scannedCode;
                                  try {
                                    final decoded = jsonDecode(scannedCode);
                                    if (decoded is Map) {
                                      if (decoded.containsKey('device_id')) {
                                        targetId = decoded['device_id']
                                            .toString();
                                      } else if (decoded.containsKey(
                                        'deviceId',
                                      )) {
                                        targetId = decoded['deviceId']
                                            .toString();
                                      }
                                    }
                                  } catch (_) {}
                                  final cleanCode = targetId.replaceAll(
                                    RegExp(r'[^a-zA-Z0-9]'),
                                    '',
                                  );
                                  setState(() {
                                    idController.text = cleanCode;
                                    idError = null;
                                  });
                                }
                              },
                      ),
                    ),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z0-9]')),
                    ],
                    onChanged: (val) {
                      if (idError != null && val.trim().isNotEmpty) {
                        setState(() => idError = null);
                      }
                    },
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: nameController,
                    enabled: !isAdding,
                    decoration: InputDecoration(
                      labelText: 'Device Name',
                      errorText: nameError,
                    ),
                    onChanged: (val) {
                      if (nameError != null && val.trim().isNotEmpty) {
                        setState(() => nameError = null);
                      }
                    },
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: isAdding ? null : () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                isAdding
                    ? const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 16.0),
                        child: SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    : ElevatedButton(
                        onPressed: () async {
                          final idText = idController.text.trim();
                          final nameText = nameController.text.trim();

                          setState(() {
                            idError = idText.isEmpty
                                ? 'Device ID is required'
                                : null;
                            nameError = nameText.isEmpty
                                ? 'Device Name is required'
                                : null;
                          });

                          if (idError == null && nameError == null) {
                            setState(() {
                              isAdding = true;
                            });
                            try {
                              await Provider.of<DeviceProvider>(
                                context,
                                listen: false,
                              ).addDevice(idText, nameText);
                              if (context.mounted) {
                                Navigator.pop(context);
                              }
                            } catch (e) {
                              final errMsg = e.toString().replaceAll(
                                'Exception: ',
                                '',
                              );
                              if (context.mounted) {
                                setState(() {
                                  isAdding = false;
                                  if (errMsg.contains('already exists') ||
                                      errMsg.contains('already added') ||
                                      errMsg.contains('exists')) {
                                    idError =
                                        'This device is already added and cannot be added';
                                  } else {
                                    idError = errMsg;
                                  }
                                });
                              }
                            }
                          }
                        },
                        child: const Text('Submit'),
                      ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildChip(
    String label, {
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        decoration: BoxDecoration(
          color: isSelected
              ? theme.colorScheme.primary.withOpacity(0.15)
              : theme.colorScheme.surfaceVariant.withOpacity(0.2),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected
                ? theme.colorScheme.primary
                : theme.colorScheme.outlineVariant.withOpacity(0.4),
            width: 1.2,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected
                ? theme.colorScheme.primary
                : theme.colorScheme.onSurfaceVariant,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
            fontSize: 12,
          ),
        ),
      ),
    );
  }

  Widget _buildDevicesTab() {
    return Consumer<DeviceProvider>(
      builder: (context, deviceProvider, child) {
        final devices = deviceProvider.devices.where((d) {
          if (_searchQuery.isEmpty) return true;
          return d.name.toLowerCase().contains(_searchQuery.toLowerCase()) ||
              d.id.toLowerCase().contains(_searchQuery.toLowerCase());
        }).toList();

        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 16.0,
                vertical: 6.0,
              ),
              child: Container(
                decoration: BoxDecoration(
                  color: Theme.of(
                    context,
                  ).colorScheme.surfaceVariant.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: Theme.of(
                      context,
                    ).colorScheme.outlineVariant.withOpacity(0.4),
                    width: 1.2,
                  ),
                ),
                child: TextField(
                  controller: _searchController,
                  onChanged: (val) {
                    setState(() {
                      _searchQuery = val;
                    });
                  },
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: 'Search devices...',
                    hintStyle: TextStyle(
                      color: Theme.of(
                        context,
                      ).colorScheme.onSurfaceVariant.withOpacity(0.7),
                      fontSize: 13,
                    ),
                    prefixIcon: Padding(
                      padding: const EdgeInsets.only(left: 12, right: 8),
                      child: Icon(
                        Icons.search_rounded,
                        color: Theme.of(
                          context,
                        ).colorScheme.onSurfaceVariant.withOpacity(0.7),
                        size: 18,
                      ),
                    ),
                    prefixIconConstraints: const BoxConstraints(
                      minWidth: 38,
                      minHeight: 18,
                    ),
                    suffixIcon: _searchQuery.isNotEmpty
                        ? GestureDetector(
                            onTap: () {
                              _searchController.clear();
                              setState(() {
                                _searchQuery = '';
                              });
                            },
                            child: Padding(
                              padding: const EdgeInsets.only(
                                left: 8,
                                right: 12,
                              ),
                              child: Icon(
                                Icons.clear_rounded,
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant.withOpacity(0.7),
                                size: 18,
                              ),
                            ),
                          )
                        : null,
                    suffixIconConstraints: const BoxConstraints(
                      minWidth: 38,
                      minHeight: 18,
                    ),
                    border: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    errorBorder: InputBorder.none,
                    disabledBorder: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                  style: const TextStyle(fontSize: 13),
                ),
              ),
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                child: Row(
                  children: [
                    _buildChip(
                      'All',
                      isSelected: _selectedFilter == 'All',
                      onTap: () {
                        setState(() => _selectedFilter = 'All');
                        Provider.of<DeviceProvider>(
                          context,
                          listen: false,
                        ).fetchDevices();
                      },
                    ),
                    const SizedBox(width: 8),
                    _buildChip(
                      'Owned',
                      isSelected: _selectedFilter == 'Owned',
                      onTap: () {
                        setState(() => _selectedFilter = 'Owned');
                        Provider.of<DeviceProvider>(
                          context,
                          listen: false,
                        ).fetchDevices(type: 'OWNER');
                      },
                    ),
                    const SizedBox(width: 8),
                    _buildChip(
                      'Shared',
                      isSelected: _selectedFilter == 'Shared',
                      onTap: () {
                        setState(() => _selectedFilter = 'Shared');
                        Provider.of<DeviceProvider>(
                          context,
                          listen: false,
                        ).fetchDevices(type: 'SHARED');
                      },
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: RefreshIndicator(
                onRefresh: () async {
                  String? filterType;
                  if (_selectedFilter == 'Owned') {
                    filterType = 'OWNER';
                  } else if (_selectedFilter == 'Shared') {
                    filterType = 'SHARED';
                  }
                  await Future.wait([
                    Provider.of<AuthProvider>(
                      context,
                      listen: false,
                    ).fetchProfile(),
                    Provider.of<DeviceProvider>(
                      context,
                      listen: false,
                    ).fetchDevices(type: filterType),
                  ]);
                },
                child: devices.isEmpty
                    ? ListView(
                        children: [
                          SizedBox(
                            height: MediaQuery.of(context).size.height * 0.15,
                          ),
                          Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.search_off_rounded,
                                  size: 64,
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant
                                      .withOpacity(0.5),
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  'No devices found',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant
                                        .withOpacity(0.7),
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  'Try searching for another device name or ID',
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant
                                        .withOpacity(0.5),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      )
                    : ListView.builder(
                        itemCount: devices.length,
                        itemBuilder: (context, index) {
                          final device = devices[index];
                          final isOnline = deviceProvider.isDeviceOnline(
                            device.id,
                          );
                          return Card(
                            margin: const EdgeInsets.symmetric(
                              horizontal: 16.0,
                              vertical: 6.0,
                            ),
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                              side: BorderSide(
                                color: Theme.of(
                                  context,
                                ).colorScheme.outlineVariant.withOpacity(0.3),
                                width: 1,
                              ),
                            ),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(16),
                              onTap: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) =>
                                        ChatScreen(device: device),
                                  ),
                                );
                              },
                              onLongPress: () {
                                showDialog(
                                  context: context,
                                  builder: (context) {
                                    final isOwner = device.isOwner;
                                    return AlertDialog(
                                      title: Text(
                                        isOwner
                                            ? 'Delete Device'
                                            : 'Leave Device',
                                      ),
                                      content: Text(
                                        isOwner
                                            ? 'Are you sure you want to delete ${device.name}?'
                                            : 'Are you sure you want to leave ${device.name}?',
                                      ),
                                      actions: [
                                        TextButton(
                                          onPressed: () =>
                                              Navigator.pop(context),
                                          child: const Text('Cancel'),
                                        ),
                                        TextButton(
                                          onPressed: () {
                                            final authProvider =
                                                Provider.of<AuthProvider>(
                                                  context,
                                                  listen: false,
                                                );
                                            deviceProvider.deleteDevice(
                                              device.id,
                                              userId: authProvider.userId,
                                            );
                                            Navigator.pop(context);
                                          },
                                          child: Text(
                                            isOwner ? 'Delete' : 'Leave',
                                            style: const TextStyle(
                                              color: Colors.red,
                                            ),
                                          ),
                                        ),
                                      ],
                                    );
                                  },
                                );
                              },
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16.0,
                                  vertical: 12.0,
                                ),
                                child: Row(
                                  children: [
                                    Stack(
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.all(2),
                                          decoration: BoxDecoration(
                                            shape: BoxShape.circle,
                                            border: Border.all(
                                              color: isOnline
                                                  ? Colors.green.shade400
                                                  : Colors.grey.shade400,
                                              width: 2,
                                            ),
                                          ),
                                          child: CircleAvatar(
                                            radius: 22,
                                            backgroundColor: Theme.of(
                                              context,
                                            ).colorScheme.primaryContainer,
                                            backgroundImage:
                                                device
                                                    .profilePhotoUrl
                                                    .isNotEmpty
                                                ? NetworkImage(
                                                        device.profilePhotoUrl,
                                                      )
                                                      as ImageProvider
                                                : const AssetImage(
                                                    'assets/ionet_logo.png',
                                                  ),
                                          ),
                                        ),
                                        Positioned(
                                          right: 1,
                                          bottom: 1,
                                          child: Container(
                                            width: 12,
                                            height: 12,
                                            decoration: BoxDecoration(
                                              color: isOnline
                                                  ? Colors.green
                                                  : Colors.grey,
                                              shape: BoxShape.circle,
                                              border: Border.all(
                                                color: Theme.of(
                                                  context,
                                                ).scaffoldBackgroundColor,
                                                width: 2,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(width: 16),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            device.name,
                                            style: const TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 16,
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            device.lastMessage,
                                            style: TextStyle(
                                              color: Theme.of(context)
                                                  .colorScheme
                                                  .onSurfaceVariant
                                                  .withOpacity(0.7),
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      "${device.timestamp.hour.toString().padLeft(2, '0')}:${device.timestamp.minute.toString().padLeft(2, '0')}",
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Theme.of(context)
                                            .colorScheme
                                            .onSurfaceVariant
                                            .withOpacity(0.5),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBody: false,
      appBar: _currentIndex == 0
          ? AppBar(
              title: Image.asset(
                'assets/ionet_logo.png',
                height: 38,
                fit: BoxFit.contain,
              ),
              centerTitle: false,
            )
          : AppBar(
              title: Text(
                ['Devices', 'Updates', 'Support', 'Profile'][_currentIndex],
              ),
              actions: _currentIndex == 2
                  ? [
                      IconButton(
                        icon: Image.asset(
                          'assets/whatsapp_logo.png',
                          width: 24,
                          height: 24,
                        ),
                        tooltip: 'Join WhatsApp Community',
                        onPressed: () async {
                          final Uri url = Uri.parse(
                            'https://whatsapp.com/channel/0029VbBPglwATRSi0Zibax3w',
                          );
                          if (!await launchUrl(
                            url,
                            mode: LaunchMode.externalApplication,
                          )) {
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    'Could not open WhatsApp channel link',
                                  ),
                                ),
                              );
                            }
                          }
                        },
                      ),
                    ]
                  : null,
            ),
      body: _buildBody(),
      floatingActionButton: _currentIndex == 0
          ? FloatingActionButton(
              onPressed: _showAddDeviceDialog,
              child: const Icon(Icons.add),
            )
          : (_currentIndex == 2
                ? FloatingActionButton(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const HelpScreen(),
                        ),
                      );
                    },
                    child: const Icon(Icons.help_outline),
                  )
                : null),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (index) {
          setState(() => _currentIndex = index);
          if (index == 0) {
            Provider.of<AuthProvider>(context, listen: false).fetchProfile();
            Provider.of<DeviceProvider>(context, listen: false).fetchDevices();
          }
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.chat_bubble_outline_rounded),
            selectedIcon: Icon(Icons.chat_bubble_rounded),
            label: 'Devices',
          ),
          NavigationDestination(
            icon: Icon(Icons.sync_rounded),
            selectedIcon: Icon(Icons.sync_rounded),
            label: 'Updates',
          ),
          NavigationDestination(
            icon: Icon(Icons.help_outline_rounded),
            selectedIcon: Icon(Icons.help_rounded),
            label: 'Support',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline_rounded),
            selectedIcon: Icon(Icons.person_rounded),
            label: 'Profile',
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    switch (_currentIndex) {
      case 0:
        return _buildDevicesTab();
      case 1:
        return const UpdatesScreen();
      case 2:
        return KnowledgeScreen();
      case 3:
        return const SettingsTab();
      default:
        return Center(
          child: Text(
            ['Devices', 'Updates', 'Support', 'Profile'][_currentIndex],
          ),
        );
    }
  }
}
