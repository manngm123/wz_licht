// home_page.dart – Hauptansicht mit "Alle Lampen" + Einzelsteuerung

import 'dart:async';

import 'package:flutter/material.dart';

import 'device_store.dart';
import 'govee_lan.dart';
import 'settings_page.dart';
import 'theme.dart';

class LampState {
  DeviceStatus? status;
  bool loading = true;
  bool reachable = true;
  bool dragging = false;
  double slider = 50;
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with WidgetsBindingObserver {
  final GoveeLan _lan = GoveeLan();
  final DeviceStore _store = DeviceStore();

  List<Lamp> _lamps = [];
  final Map<String, LampState> _states = {};

  double _allSlider = 50;
  bool _initialized = false;
  bool _scanning = false;
  bool _refreshing = false;
  Timer? _timer;

  // ------------------------------------------------------------
  // Lifecycle
  // ------------------------------------------------------------

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _init();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stopPolling();
    _lan.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Kein Polling im Hintergrund
    if (state == AppLifecycleState.resumed) {
      _startPolling();
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      _stopPolling();
    }
  }

  Future<void> _init() async {
    _lamps = await _store.load();
    _syncStates();

    try {
      await _lan.start();
    } catch (e) {
      _showMessage('UDP-Port 4002 nicht verfügbar');
    }

    if (mounted) setState(() => _initialized = true);

    if (_lamps.isEmpty) {
      await _scan();
    } else {
      // IPs im Hintergrund aktualisieren (DHCP)
      unawaited(_scan(silent: true));
    }

    _startPolling();
  }

  void _syncStates() {
    for (final lamp in _lamps) {
      _states.putIfAbsent(lamp.id, () => LampState());
    }
    _states.removeWhere((id, _) => !_lamps.any((l) => l.id == id));
  }

  LampState _state(Lamp lamp) =>
      _states.putIfAbsent(lamp.id, () => LampState());

  // ------------------------------------------------------------
  // Scan
  // ------------------------------------------------------------

  Future<void> _scan({bool silent = false}) async {
    if (_scanning) return;
    if (mounted) setState(() => _scanning = true);

    try {
      final results = await _lan.scan();
      var changed = false;

      for (final r in results) {
        final existing = _lamps.where((l) => l.mac == r.mac).toList();

        if (existing.isNotEmpty) {
          if (existing.first.ip != r.ip) {
            existing.first.ip = r.ip;
            changed = true;
          }
        } else if (!silent) {
          _lamps.add(Lamp(
            name: 'Lampe ${_lamps.length + 1}',
            ip: r.ip,
            mac: r.mac,
            sku: r.sku,
          ));
          changed = true;
        }
      }

      if (changed) {
        await _store.save(_lamps);
        _syncStates();
      }

      if (!silent && results.isEmpty) {
        _showMessage('Keine Lampen gefunden');
      }
    } catch (_) {
      if (!silent) _showMessage('Suche fehlgeschlagen');
    } finally {
      if (mounted) setState(() => _scanning = false);
    }

    await _refreshAll();
  }

  // ------------------------------------------------------------
  // Status / Polling
  // ------------------------------------------------------------

  void _startPolling() {
    if (_timer != null || !_initialized) return;

    _refreshAll();

    // Alle 10 Sekunden echten Zustand aktualisieren
    _timer = Timer.periodic(
      const Duration(seconds: 10),
      (_) => _refreshAll(),
    );
  }

  void _stopPolling() {
    _timer?.cancel();
    _timer = null;
  }

  Future<void> _refreshAll() async {
    if (_refreshing) return;
    _refreshing = true;

    try {
      // nacheinander – eine Antwort pro Lampe auf Port 4002
      for (final lamp in List<Lamp>.of(_lamps)) {
        await _loadStatus(lamp);
        await Future.delayed(const Duration(milliseconds: 150));
      }
    } finally {
      _refreshing = false;
    }
  }

  Future<void> _loadStatus(Lamp lamp) async {
    final state = _state(lamp);

    try {
      final status = await _lan.status(lamp.ip);

      state.status = status;
      state.reachable = true;

      if (!state.dragging) {
        state.slider = status.brightness.clamp(1, 100).toDouble();
      }
    } catch (_) {
      state.reachable = false;
    } finally {
      state.loading = false;
      if (mounted) setState(() {});
    }
  }

  // ------------------------------------------------------------
  // Einzelne Lampe
  // ------------------------------------------------------------

  Future<void> _switch(Lamp lamp, bool on) async {
    try {
      await _lan.turn(lamp.ip, on);

      // Govee kurz Zeit geben
      await Future.delayed(const Duration(milliseconds: 250));

      await _loadStatus(lamp);
    } catch (_) {
      _showMessage('Fehler beim Senden');
    }
  }

  Future<void> _sendBrightness(Lamp lamp) async {
    final state = _state(lamp);

    try {
      await _lan.brightness(lamp.ip, state.slider.round());

      await Future.delayed(const Duration(milliseconds: 200));

      await _loadStatus(lamp);
    } catch (_) {
      _showMessage('Fehler beim Einstellen');
    }
  }

  void _stepBrightness(Lamp lamp, int amount) {
    final state = _state(lamp);

    setState(() {
      state.slider = (state.slider + amount).clamp(1, 100).toDouble();
    });

    _sendBrightness(lamp);
  }

  // ------------------------------------------------------------
  // Alle
  // ------------------------------------------------------------

  Future<void> _switchAll(bool on) async {
    try {
      // absichtlich nacheinander
      for (final lamp in _lamps) {
        await _lan.turn(lamp.ip, on);
        await Future.delayed(const Duration(milliseconds: 100));
      }

      await Future.delayed(const Duration(milliseconds: 250));
      await _refreshAll();
    } catch (_) {
      _showMessage('Fehler beim Senden');
    }
  }

  Future<void> _brightnessAll() async {
    final value = _allSlider.round();

    try {
      for (final lamp in _lamps) {
        await _lan.brightness(lamp.ip, value);
        await Future.delayed(const Duration(milliseconds: 100));
      }

      await Future.delayed(const Duration(milliseconds: 200));
      await _refreshAll();
    } catch (_) {
      _showMessage('Fehler beim Einstellen');
    }
  }

  void _stepAll(int amount) {
    setState(() {
      _allSlider = (_allSlider + amount).clamp(1, 100).toDouble();
    });

    _brightnessAll();
  }

  // ------------------------------------------------------------
  // Sonstiges
  // ------------------------------------------------------------

  void _showMessage(String text) {
    if (!mounted) return;

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(text),
        duration: const Duration(milliseconds: 2500),
        behavior: SnackBarBehavior.floating,
      ));
  }

  Future<void> _openSettings() async {
    _stopPolling();

    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => SettingsPage(lan: _lan, store: _store),
    ));

    _lamps = await _store.load();
    _syncStates();
    if (mounted) setState(() {});

    _startPolling();
  }

  // ------------------------------------------------------------
  // UI
  // ------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 52,
        title: const Text(
          '💡 Wohnzimmer',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            tooltip: 'Lampen verwalten',
            onPressed: _openSettings,
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: RefreshIndicator(
          onRefresh: _refreshAll,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 650),
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 16),
                children: _buildContent(),
              ),
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _buildContent() {
    if (!_initialized || (_scanning && _lamps.isEmpty)) {
      return const [
        SizedBox(height: 120),
        Center(child: CircularProgressIndicator(color: AppColors.accent)),
        SizedBox(height: 16),
        Center(
          child: Text('Suche Lampen …',
              style: TextStyle(color: AppColors.muted)),
        ),
      ];
    }

    if (_lamps.isEmpty) {
      return [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                const Text(
                  'Keine Lampen gefunden',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 10),
                const Text(
                  'Handy im selben WLAN? „LAN-Steuerung“ in der Govee-App '
                  'für jede Lampe aktiviert?',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.muted),
                ),
                const SizedBox(height: 18),
                FilledButton.icon(
                  onPressed: () => _scan(),
                  icon: const Icon(Icons.search),
                  label: const Text('Erneut suchen'),
                ),
                TextButton(
                  onPressed: _openSettings,
                  child: const Text('Manuell per IP hinzufügen'),
                ),
              ],
            ),
          ),
        ),
      ];
    }

    return [
      if (_lamps.length > 1)
        ControlCard(
          title: 'Alle Lampen',
          stateText: 'gemeinsam',
          stateColor: AppColors.muted,
          highlighted: true,
          sliderValue: _allSlider,
          valueText: '${_allSlider.round()} %',
          onOn: () => _switchAll(true),
          onOff: () => _switchAll(false),
          onMinus: () => _stepAll(-5),
          onPlus: () => _stepAll(5),
          onSliderChanged: (v) => setState(() => _allSlider = v),
          onSliderChangeEnd: (_) => _brightnessAll(),
        ),
      for (final lamp in _lamps) _buildLampCard(lamp),
    ];
  }

  Widget _buildLampCard(Lamp lamp) {
    final state = _state(lamp);
    final status = state.status;

    String stateText;
    Color stateColor;

    if (state.loading) {
      stateText = 'lade …';
      stateColor = AppColors.muted;
    } else if (!state.reachable) {
      stateText = 'nicht erreichbar';
      stateColor = AppColors.stateOff;
    } else if (status?.on ?? false) {
      stateText = '● EIN';
      stateColor = AppColors.stateOn;
    } else {
      stateText = '● AUS';
      stateColor = AppColors.stateOff;
    }

    final valueText = state.dragging || status != null
        ? '${state.slider.round()} %'
        : '-- %';

    return ControlCard(
      title: lamp.name,
      stateText: stateText,
      stateColor: stateColor,
      sliderValue: state.slider,
      valueText: valueText,
      info: status?.kelvin != null ? '${status!.kelvin} K' : null,
      onOn: () => _switch(lamp, true),
      onOff: () => _switch(lamp, false),
      onMinus: () => _stepBrightness(lamp, -5),
      onPlus: () => _stepBrightness(lamp, 5),
      onSliderChangeStart: (_) => state.dragging = true,
      onSliderChanged: (v) => setState(() => state.slider = v),
      onSliderChangeEnd: (_) {
        state.dragging = false;
        _sendBrightness(lamp);
      },
    );
  }
}

// ------------------------------------------------------------
// Karte (kompakt)
// ------------------------------------------------------------

class ControlCard extends StatelessWidget {
  final String title;
  final String stateText;
  final Color stateColor;
  final bool highlighted;
  final double sliderValue;
  final String valueText;
  final String? info;

  final VoidCallback onOn;
  final VoidCallback onOff;
  final VoidCallback onMinus;
  final VoidCallback onPlus;
  final ValueChanged<double>? onSliderChangeStart;
  final ValueChanged<double> onSliderChanged;
  final ValueChanged<double> onSliderChangeEnd;

  const ControlCard({
    super.key,
    required this.title,
    required this.stateText,
    required this.stateColor,
    required this.sliderValue,
    required this.valueText,
    required this.onOn,
    required this.onOff,
    required this.onMinus,
    required this.onPlus,
    required this.onSliderChanged,
    required this.onSliderChangeEnd,
    this.onSliderChangeStart,
    this.highlighted = false,
    this.info,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: highlighted
            ? const BorderSide(color: AppColors.border)
            : BorderSide.none,
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 10, 4),
        child: Column(
          children: [
            // Name + Status | EIN / AUS
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(
                              text: stateText,
                              style: TextStyle(color: stateColor),
                            ),
                            if (info != null)
                              TextSpan(
                                text: '  ·  $info',
                                style: const TextStyle(color: AppColors.info),
                              ),
                          ],
                        ),
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                _PowerButton(
                  label: 'EIN',
                  background: AppColors.onButton,
                  foreground: AppColors.onButtonText,
                  onPressed: onOn,
                ),
                const SizedBox(width: 8),
                _PowerButton(
                  label: 'AUS',
                  background: AppColors.offButton,
                  foreground: Colors.white,
                  onPressed: onOff,
                ),
              ],
            ),

            // − Slider Wert +
            Row(
              children: [
                _StepButton(label: '−', onPressed: onMinus),
                Expanded(
                  child: SizedBox(
                    height: 40,
                    child: Slider(
                      min: 1,
                      max: 100,
                      divisions: 99,
                      value: sliderValue.clamp(1, 100),
                      onChangeStart: onSliderChangeStart,
                      onChanged: onSliderChanged,
                      onChangeEnd: onSliderChangeEnd,
                    ),
                  ),
                ),
                SizedBox(
                  width: 46,
                  child: Text(
                    valueText,
                    textAlign: TextAlign.right,
                    style: const TextStyle(
                      fontSize: 14,
                      color: AppColors.value,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                _StepButton(label: '+', onPressed: onPlus),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _PowerButton extends StatelessWidget {
  final String label;
  final Color background;
  final Color foreground;
  final VoidCallback onPressed;

  const _PowerButton({
    required this.label,
    required this.background,
    required this.foreground,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return FilledButton(
      onPressed: onPressed,
      style: FilledButton.styleFrom(
        backgroundColor: background,
        foregroundColor: foreground,
        minimumSize: const Size(62, 38),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
        textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
      ),
      child: Text(label),
    );
  }
}

class _StepButton extends StatelessWidget {
  final String label;
  final VoidCallback onPressed;

  const _StepButton({required this.label, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 36,
      height: 32,
      child: FilledButton(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.stepButton,
          foregroundColor: Colors.white,
          padding: EdgeInsets.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          textStyle: const TextStyle(fontSize: 18),
        ),
        child: Text(label),
      ),
    );
  }
}
