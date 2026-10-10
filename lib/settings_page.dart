// settings_page.dart – Lampen suchen, umbenennen, manuell anlegen, löschen

import 'package:flutter/material.dart';

import 'device_store.dart';
import 'govee_lan.dart';
import 'theme.dart';

class SettingsPage extends StatefulWidget {
  final GoveeLan lan;
  final DeviceStore store;

  const SettingsPage({super.key, required this.lan, required this.store});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  List<Lamp> _lamps = [];
  bool _scanning = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final lamps = await widget.store.load();
    if (mounted) setState(() => _lamps = lamps);
  }

  Future<void> _save() async {
    await widget.store.save(_lamps);
    if (mounted) setState(() {});
  }

  void _message(String text) {
    if (!mounted) return;

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(text),
        behavior: SnackBarBehavior.floating,
      ));
  }

  // ------------------------------------------------------------
  // Aktionen
  // ------------------------------------------------------------

  Future<void> _scan() async {
    setState(() => _scanning = true);

    try {
      final results = await widget.lan.scan();
      var added = 0;
      var updated = 0;

      for (final r in results) {
        final idx = _lamps.indexWhere((l) => l.mac == r.mac || l.ip == r.ip);

        if (idx >= 0) {
          final lamp = _lamps[idx];
          if (lamp.ip != r.ip || lamp.mac != r.mac) updated++;
          lamp.ip = r.ip;
          lamp.mac = r.mac;
          if (r.sku.isNotEmpty) lamp.sku = r.sku;
        } else {
          _lamps.add(Lamp(
            name: 'Lampe ${_lamps.length + 1}',
            ip: r.ip,
            mac: r.mac,
            sku: r.sku,
          ));
          added++;
        }
      }

      await _save();

      _message(results.isEmpty
          ? 'Keine Lampen gefunden'
          : '${results.length} gefunden, $added neu, $updated aktualisiert');
    } catch (_) {
      _message('Suche fehlgeschlagen');
    } finally {
      if (mounted) setState(() => _scanning = false);
    }
  }

  Future<void> _edit({Lamp? lamp}) async {
    final nameCtrl = TextEditingController(text: lamp?.name ?? '');
    final ipCtrl = TextEditingController(text: lamp?.ip ?? '');

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.card,
        title: Text(lamp == null ? 'Lampe hinzufügen' : 'Lampe bearbeiten'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtrl,
              autofocus: true,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(labelText: 'Name'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: ipCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'IP-Adresse',
                hintText: '192.168.178.50',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Speichern'),
          ),
        ],
      ),
    );

    // Controller nicht sofort disposen – Dialog animiert noch aus.
    final name = nameCtrl.text.trim();
    final ip = ipCtrl.text.trim();

    if (ok != true) return;

    if (name.isEmpty || !_validIp(ip)) {
      _message('Name und gültige IPv4-Adresse angeben');
      return;
    }

    if (lamp == null) {
      _lamps.add(Lamp(name: name, ip: ip, mac: ''));
    } else {
      lamp.name = name;
      lamp.ip = ip;
    }

    await _save();
  }

  bool _validIp(String ip) {
    final parts = ip.split('.');
    if (parts.length != 4) return false;
    return parts.every((p) {
      final n = int.tryParse(p);
      return n != null && n >= 0 && n <= 255;
    });
  }

  Future<void> _delete(Lamp lamp) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.card,
        title: const Text('Lampe entfernen?'),
        content: Text('„${lamp.name}“ aus der App entfernen.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.offButton,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Entfernen'),
          ),
        ],
      ),
    );

    if (ok != true) return;

    _lamps.remove(lamp);
    await _save();
  }

  Future<void> _test(Lamp lamp) async {
    try {
      final s = await widget.lan.status(lamp.ip);
      _message('${lamp.name}: ${s.on ? 'EIN' : 'AUS'}, ${s.brightness} %');
    } catch (_) {
      _message('${lamp.name}: keine Antwort von ${lamp.ip}');
    }
  }

  // ------------------------------------------------------------
  // UI
  // ------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Lampen verwalten')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _edit(),
        icon: const Icon(Icons.add),
        label: const Text('Manuell'),
      ),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(14, 8, 14, 96),
          children: [
            FilledButton.icon(
              onPressed: _scanning ? null : _scan,
              icon: _scanning
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.search),
              label: Text(_scanning ? 'Suche läuft …' : 'Im WLAN suchen'),
            ),
            const SizedBox(height: 8),
            const Text(
              'Voraussetzung: „LAN-Steuerung“ ist in der Govee-App für jede '
              'Lampe aktiviert und das Handy ist im selben WLAN.',
              style: TextStyle(color: AppColors.muted, fontSize: 13),
            ),
            const SizedBox(height: 18),
            if (_lamps.isEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 40),
                child: Center(
                  child: Text('Noch keine Lampen',
                      style: TextStyle(color: AppColors.muted)),
                ),
              ),
            ReorderableListView(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              buildDefaultDragHandles: true,
              onReorder: (oldIndex, newIndex) {
                if (newIndex > oldIndex) newIndex--;
                final lamp = _lamps.removeAt(oldIndex);
                _lamps.insert(newIndex, lamp);
                _save();
              },
              children: [
                for (final lamp in _lamps)
                  Card(
                    key: ValueKey(lamp.id),
                    margin: const EdgeInsets.only(bottom: 10),
                    child: ListTile(
                      leading: const Icon(Icons.lightbulb_outline,
                          color: AppColors.accent),
                      title: Text(lamp.name),
                      subtitle: Text(
                        [
                          lamp.ip,
                          if (lamp.sku.isNotEmpty) lamp.sku,
                        ].join(' · '),
                        style: const TextStyle(color: AppColors.muted),
                      ),
                      onTap: () => _test(lamp),
                      trailing: PopupMenuButton<String>(
                        onSelected: (v) {
                          if (v == 'edit') _edit(lamp: lamp);
                          if (v == 'delete') _delete(lamp);
                        },
                        itemBuilder: (_) => const [
                          PopupMenuItem(
                              value: 'edit', child: Text('Bearbeiten')),
                          PopupMenuItem(
                              value: 'delete', child: Text('Entfernen')),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
            if (_lamps.isNotEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 6),
                child: Text(
                  'Antippen = Verbindung testen · lange drücken = sortieren',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.info, fontSize: 12),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
