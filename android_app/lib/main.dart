import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: Color(0xFF05070E),
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );
  runApp(const MfkVpnApp());
}

class MfkVpnApp extends StatelessWidget {
  const MfkVpnApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'mFkVpN',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF05070E),
        fontFamily: 'Roboto',
        useMaterial3: true,
      ),
      home: const VpnDashboardScreen(),
    );
  }
}

class ServerNode {
  final String name;
  final String country;
  final String flag;
  final String ip;
  final int ping;

  const ServerNode({
    required this.name,
    required this.country,
    required this.flag,
    required this.ip,
    required this.ping,
  });
}

const List<ServerNode> kDefaultNodes = [
  ServerNode(
    name: 'HEL-01',
    country: 'Finlandiya',
    flag: '🇫🇮',
    ip: '46.224.62.213.sslip.io',
    ping: 38,
  ),
  ServerNode(
    name: 'FSN-01',
    country: 'Almanya',
    flag: '🇩🇪',
    ip: '159.69.80.12',
    ping: 42,
  ),
  ServerNode(
    name: 'AMS-01',
    country: 'Hollanda',
    flag: '🇳🇱',
    ip: '188.166.45.88',
    ping: 45,
  ),
];

enum VpnState { disconnected, connecting, connected }

class VpnDashboardScreen extends StatefulWidget {
  const VpnDashboardScreen({super.key});

  @override
  State<VpnDashboardScreen> createState() => _VpnDashboardScreenState();
}

class _VpnDashboardScreenState extends State<VpnDashboardScreen>
    with SingleTickerProviderStateMixin {
  VpnState _vpnState = VpnState.disconnected;
  ServerNode _selectedNode = kDefaultNodes[0];
  String _selectedProtocol = 'IKEv2'; // 'IKEv2' or 'WireGuard'

  Timer? _statTimer;
  int _connectedSeconds = 0;
  double _rxMegaBytes = 0.0;
  double _txMegaBytes = 0.0;

  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _statTimer?.cancel();
    _pulseController.dispose();
    super.dispose();
  }

  void _toggleVpn() {
    HapticFeedback.mediumImpact();
    if (_vpnState == VpnState.connected) {
      // Disconnect
      setState(() {
        _vpnState = VpnState.disconnected;
      });
      _statTimer?.cancel();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: Color(0xFFF43F5E),
          content: Text(
            'mFkVpN Bağlantısı Kesildi. Normal ağa dönüldü.',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          duration: Duration(seconds: 2),
        ),
      );
    } else if (_vpnState == VpnState.disconnected) {
      // Connect
      setState(() {
        _vpnState = VpnState.connecting;
      });

      Timer(const Duration(milliseconds: 1400), () {
        if (!mounted) return;
        setState(() {
          _vpnState = VpnState.connected;
          _connectedSeconds = 0;
          _rxMegaBytes = 0.4;
          _txMegaBytes = 0.1;
        });

        _statTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
          if (!mounted) return;
          setState(() {
            _connectedSeconds++;
            _rxMegaBytes += 0.05 + (Random().nextDouble() * 0.15);
            _txMegaBytes += 0.02 + (Random().nextDouble() * 0.05);
          });
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: const Color(0xFF10B981),
            content: Text(
              '${_selectedNode.flag} ${_selectedNode.name} tüneline başarıyla bağlanıldı!',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            duration: const Duration(seconds: 2),
          ),
        );
      });
    }
  }

  String _formatDuration(int seconds) {
    final m = (seconds ~/ 60).toString().padLeft(2, '0');
    final s = (seconds % 60).toString().padLeft(2, '0');
    final h = (seconds ~/ 3600).toString().padLeft(2, '0');
    return h == '00' ? '$m:$s' : '$h:$m:$s';
  }

  void _showServerPicker() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF0A0F1D),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Sunucu Seçimi',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFFF8FAFC),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(ctx),
                    icon: const Icon(Icons.close, color: Colors.white54),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              ...kDefaultNodes.map((node) {
                final isSelected = node.name == _selectedNode.name;
                return Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? const Color(0xFF06B6D4).withValues(alpha: 0.12)
                        : Colors.white.withValues(alpha: 0.03),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: isSelected
                          ? const Color(0xFF06B6D4).withValues(alpha: 0.4)
                          : Colors.white.withValues(alpha: 0.06),
                    ),
                  ),
                  child: ListTile(
                    leading: Text(node.flag, style: const TextStyle(fontSize: 26)),
                    title: Text(
                      '${node.name} • ${node.country}',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: isSelected ? const Color(0xFF06B6D4) : Colors.white,
                      ),
                    ),
                    subtitle: Text(
                      '${node.ip} • ⚡ ${node.ping} ms',
                      style: const TextStyle(color: Colors.white54, fontSize: 12),
                    ),
                    trailing: isSelected
                        ? const Icon(Icons.check_circle, color: Color(0xFF06B6D4))
                        : null,
                    onTap: () {
                      setState(() {
                        _selectedNode = node;
                      });
                      Navigator.pop(ctx);
                      HapticFeedback.lightImpact();
                    },
                  ),
                );
              }),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final isConnected = _vpnState == VpnState.connected;
    final isConnecting = _vpnState == VpnState.connecting;

    final primaryGlow = isConnected
        ? const Color(0xFF10B981) // Emerald
        : (isConnecting ? const Color(0xFFF59E0B) : const Color(0xFF06B6D4));

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child: Column(
            children: [
              // ÜST HEADER
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFFF59E0B).withValues(alpha: 0.25),
                              blurRadius: 12,
                            ),
                          ],
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: Image.asset(
                            'assets/logo.png',
                            fit: BoxFit.cover,
                            errorBuilder: (c, e, s) => Container(
                              color: const Color(0xFF10192C),
                              child: const Icon(Icons.shield, color: Color(0xFFF59E0B)),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'mFkVpN',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 1.1,
                              color: Color(0xFFF8FAFC),
                            ),
                          ),
                          Row(
                            children: [
                              Container(
                                width: 8,
                                height: 8,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: isConnected
                                      ? const Color(0xFF10B981)
                                      : const Color(0xFF64748B),
                                ),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                isConnected
                                    ? 'SAVUNMA AKTİF'
                                    : (isConnecting ? 'BAĞLANILIYOR...' : 'BEKLEMEDE'),
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: isConnected
                                      ? const Color(0xFF10B981)
                                      : Colors.white54,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ],
                  ),
                  // Protokol Seçici Chip
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: _selectedProtocol,
                        dropdownColor: const Color(0xFF0A0F1D),
                        icon: const Icon(Icons.arrow_drop_down, color: Colors.white70, size: 18),
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF38BDF8),
                        ),
                        onChanged: isConnected
                            ? null
                            : (val) {
                                if (val != null) {
                                  setState(() => _selectedProtocol = val);
                                }
                              },
                        items: const [
                          DropdownMenuItem(value: 'IKEv2', child: Text('⚡ IKEv2')),
                          DropdownMenuItem(value: 'WireGuard', child: Text('🛡️ WG')),
                        ],
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 24),

              // SUNUCU KARTI (DÜĞÜM SEÇİCİ)
              InkWell(
                onTap: isConnected ? null : _showServerPicker,
                borderRadius: BorderRadius.circular(16),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0A0F1D).withValues(alpha: 0.85),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                  ),
                  child: Row(
                    children: [
                      Text(_selectedNode.flag, style: const TextStyle(fontSize: 26)),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${_selectedNode.name} • ${_selectedNode.country}',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                                color: Colors.white,
                              ),
                            ),
                            Text(
                              '${_selectedNode.ip} • ⚡ ${_selectedNode.ping} ms',
                              style: const TextStyle(
                                fontSize: 11,
                                color: Color(0xFF94A3B8),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Icon(Icons.swap_vert, color: Color(0xFF06B6D4)),
                    ],
                  ),
                ),
              ),

              const Spacer(),

              // DEVASA DİJİTAL GÜÇ DÜĞMESİ (BAĞLAN / KOPAR)
              AnimatedBuilder(
                animation: _pulseController,
                builder: (context, child) {
                  final pulseScale = isConnected
                      ? (1.0 + (_pulseController.value * 0.05))
                      : (isConnecting ? (1.0 + (_pulseController.value * 0.08)) : 1.0);

                  return Transform.scale(
                    scale: pulseScale,
                    child: Container(
                      width: 210,
                      height: 210,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: primaryGlow.withValues(alpha: isConnected ? 0.35 : 0.15),
                            blurRadius: 40,
                            spreadRadius: 4,
                          ),
                        ],
                        border: Border.all(
                          color: primaryGlow.withValues(alpha: 0.5),
                          width: 2.5,
                        ),
                        gradient: RadialGradient(
                          colors: [
                            primaryGlow.withValues(alpha: 0.18),
                            const Color(0xFF0A0F1D),
                          ],
                        ),
                      ),
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          customBorder: const CircleBorder(),
                          onTap: _toggleVpn,
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                isConnected
                                    ? Icons.shield
                                    : (isConnecting
                                        ? Icons.hourglass_top
                                        : Icons.power_settings_new),
                                size: 54,
                                color: primaryGlow,
                              ),
                              const SizedBox(height: 12),
                              Text(
                                isConnected
                                    ? 'BAĞLANTIYI KES'
                                    : (isConnecting ? 'BAĞLANILIYOR' : 'BAĞLAN'),
                                style: TextStyle(
                                  fontWeight: FontWeight.w900,
                                  fontSize: 14,
                                  letterSpacing: 1.2,
                                  color: primaryGlow,
                                ),
                              ),
                              if (isConnected) ...[
                                const SizedBox(height: 4),
                                Text(
                                  _formatDuration(_connectedSeconds),
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontFamily: 'monospace',
                                    color: Colors.white70,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),

              const Spacer(),

              // CANLI VERİ KARTI (TRAFİK & GİZLİLİK)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                decoration: BoxDecoration(
                  color: const Color(0xFF0A0F1D).withValues(alpha: 0.85),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    Column(
                      children: [
                        const Row(
                          children: [
                            Icon(Icons.arrow_downward, color: Color(0xFF10B981), size: 14),
                            SizedBox(width: 4),
                            Text('İNDİRME', style: TextStyle(fontSize: 11, color: Colors.white54)),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${_rxMegaBytes.toStringAsFixed(1)} MB',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                        ),
                      ],
                    ),
                    Container(width: 1, height: 28, color: Colors.white10),
                    Column(
                      children: [
                        const Row(
                          children: [
                            Icon(Icons.arrow_upward, color: Color(0xFF38BDF8), size: 14),
                            SizedBox(width: 4),
                            Text('YÜKLEME', style: TextStyle(fontSize: 11, color: Colors.white54)),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${_txMegaBytes.toStringAsFixed(1)} MB',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                        ),
                      ],
                    ),
                    Container(width: 1, height: 28, color: Colors.white10),
                    Column(
                      children: [
                        const Row(
                          children: [
                            Icon(Icons.lock, color: Color(0xFFF59E0B), size: 14),
                            SizedBox(width: 4),
                            Text('PROTOKOL', style: TextStyle(fontSize: 11, color: Colors.white54)),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _selectedProtocol,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                            color: Color(0xFFF59E0B),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 14),

              // ALT BİLGİ
              const Text(
                'mFk Games Zero-Knowledge Stealth Network • Helsinki Node',
                style: TextStyle(fontSize: 10, color: Colors.white30),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
