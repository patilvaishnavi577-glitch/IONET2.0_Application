import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/providers/auth_provider.dart';
import '../../core/providers/device_provider.dart';
import '../../core/providers/theme_provider.dart';
import 'chat_screen.dart';
import '../auth/login_screen.dart';
import 'scanner_screen.dart';
import '../profile/profile_screen.dart';
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
        return AlertDialog(
          title: const Text('Add Device'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: idController,
                decoration: InputDecoration(
                  labelText: 'Device ID',
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.qr_code_scanner),
                    onPressed: () async {
                      final scannedCode = await Navigator.push<String>(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const ScannerScreen(),
                        ),
                      );
                      if (scannedCode != null) {
                        idController.text = scannedCode;
                      }
                    },
                  ),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: nameController,
                decoration: const InputDecoration(labelText: 'Device Name'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                if (idController.text.isNotEmpty && nameController.text.isNotEmpty) {
                  Provider.of<DeviceProvider>(context, listen: false)
                      .addDevice(idController.text, nameController.text);
                  Navigator.pop(context);
                }
              },
              child: const Text('Submit'),
            ),
          ],
        );
      },
    );
  }

  Widget _buildChip(String label, {required bool isSelected, required VoidCallback onTap}) {
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
            color: isSelected ? theme.colorScheme.primary : theme.colorScheme.onSurfaceVariant,
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
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 6.0),
              child: Container(
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: Theme.of(context).colorScheme.outlineVariant.withOpacity(0.4),
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
                      color: Theme.of(context).colorScheme.onSurfaceVariant.withOpacity(0.7),
                      fontSize: 13,
                    ),
                    prefixIcon: Padding(
                      padding: const EdgeInsets.only(left: 12, right: 8),
                      child: Icon(
                        Icons.search_rounded,
                        color: Theme.of(context).colorScheme.onSurfaceVariant.withOpacity(0.7),
                        size: 18,
                      ),
                    ),
                    prefixIconConstraints: const BoxConstraints(minWidth: 38, minHeight: 18),
                    suffixIcon: _searchQuery.isNotEmpty
                        ? GestureDetector(
                            onTap: () {
                              _searchController.clear();
                              setState(() {
                                _searchQuery = '';
                              });
                            },
                            child: Padding(
                              padding: const EdgeInsets.only(left: 8, right: 12),
                              child: Icon(
                                Icons.clear_rounded,
                                color: Theme.of(context).colorScheme.onSurfaceVariant.withOpacity(0.7),
                                size: 18,
                              ),
                            ),
                          )
                        : null,
                    suffixIconConstraints: const BoxConstraints(minWidth: 38, minHeight: 18),
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
                        Provider.of<DeviceProvider>(context, listen: false).fetchDevices();
                      },
                    ),
                    const SizedBox(width: 8),
                    _buildChip(
                      'Owner',
                      isSelected: _selectedFilter == 'Owner',
                      onTap: () {
                        setState(() => _selectedFilter = 'Owner');
                        Provider.of<DeviceProvider>(context, listen: false).fetchDevices(type: 'OWNER');
                      },
                    ),
                    const SizedBox(width: 8),
                    _buildChip(
                      'Shared',
                      isSelected: _selectedFilter == 'Shared',
                      onTap: () {
                        setState(() => _selectedFilter = 'Shared');
                        Provider.of<DeviceProvider>(context, listen: false).fetchDevices(type: 'SHARED');
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
                  await Future.wait([
                    Provider.of<AuthProvider>(context, listen: false).fetchProfile(),
                    Provider.of<DeviceProvider>(context, listen: false).fetchDevices(),
                  ]);
                },
                child: devices.isEmpty
                    ? ListView(
                        children: [
                          SizedBox(height: MediaQuery.of(context).size.height * 0.15),
                          Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.search_off_rounded,
                                  size: 64,
                                  color: Theme.of(context).colorScheme.onSurfaceVariant.withOpacity(0.5),
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  'No devices found',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    color: Theme.of(context).colorScheme.onSurfaceVariant.withOpacity(0.7),
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  'Try searching for another device name or ID',
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: Theme.of(context).colorScheme.onSurfaceVariant.withOpacity(0.5),
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
                          final isOnline = deviceProvider.isDeviceOnline(device.id);
                          return Card(
                            margin: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 6.0),
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
                                    builder: (context) => ChatScreen(device: device),
                                  ),
                                );
                              },
                              onLongPress: () {
                                showDialog(
                                  context: context,
                                  builder: (context) {
                                    final isOwner = device.isOwner;
                                    return AlertDialog(
                                      title: Text(isOwner ? 'Delete Device' : 'Remove Shared Device'),
                                      content: Text(isOwner
                                          ? 'Are you sure you want to delete ${device.name}?'
                                          : 'Are you sure you want to remove ${device.name} from your shared devices?'),
                                      actions: [
                                        TextButton(
                                          onPressed: () => Navigator.pop(context),
                                          child: const Text('Cancel'),
                                        ),
                                        TextButton(
                                          onPressed: () {
                                            deviceProvider.deleteDevice(device.id);
                                            Navigator.pop(context);
                                          },
                                          child: Text(isOwner ? 'Delete' : 'Remove', style: const TextStyle(color: Colors.red)),
                                        ),
                                      ],
                                    );
                                  },
                                );
                              },
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
                                child: Row(
                                  children: [
                                    Stack(
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.all(2),
                                          decoration: BoxDecoration(
                                            shape: BoxShape.circle,
                                            border: Border.all(
                                              color: isOnline ? Colors.green.shade400 : Colors.grey.shade400,
                                              width: 2,
                                            ),
                                          ),
                                          child: CircleAvatar(
                                            radius: 22,
                                            backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                                            backgroundImage: device.profilePhotoUrl.isNotEmpty
                                                ? NetworkImage(device.profilePhotoUrl) as ImageProvider
                                                : const AssetImage('assets/ionet_logo.png'),
                                          ),
                                        ),
                                        Positioned(
                                          right: 1,
                                          bottom: 1,
                                          child: Container(
                                            width: 12,
                                            height: 12,
                                            decoration: BoxDecoration(
                                              color: isOnline ? Colors.green : Colors.grey,
                                              shape: BoxShape.circle,
                                              border: Border.all(color: Theme.of(context).scaffoldBackgroundColor, width: 2),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(width: 16),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(device.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                                          const SizedBox(height: 4),
                                          Text(
                                            device.lastMessage,
                                            style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant.withOpacity(0.7)),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      "${device.timestamp.hour.toString().padLeft(2, '0')}:${device.timestamp.minute.toString().padLeft(2, '0')}",
                                      style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant.withOpacity(0.5)),
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
              actions: [
                Center(
                  child: Consumer<AuthProvider>(
                    builder: (context, auth, _) {
                      return Container(
                        margin: const EdgeInsets.only(right: 8),
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.primaryContainer,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.monetization_on, size: 14, color: Theme.of(context).colorScheme.onPrimaryContainer),
                            const SizedBox(width: 4),
                            Text(
                              '${auth.credits}',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: Theme.of(context).colorScheme.onPrimaryContainer,
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ],
            )
          : AppBar(
              title: Text(['Devices', 'Updates', 'Support', 'Profile'][_currentIndex]),
            ),
      body: _buildBody(),
      floatingActionButton: _currentIndex == 0
          ? FloatingActionButton(
              onPressed: _showAddDeviceDialog,
              child: const Icon(Icons.add),
            )
          : null,
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
            icon: Icon(Icons.notifications_none_rounded),
            selectedIcon: Icon(Icons.notifications_rounded),
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
        return Center(child: Text(['Devices', 'Updates', 'Support', 'Profile'][_currentIndex]));
    }
  }
}
