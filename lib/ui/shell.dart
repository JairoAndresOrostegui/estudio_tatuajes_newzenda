import 'dart:async';
import 'dart:convert';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../data/api.dart';
import '../data/exports.dart';
import '../domain/format.dart';
import 'forms.dart';
import 'theme.dart';
import 'import_page.dart';

class Nav {
  final String key, title;
  final IconData icon;
  const Nav(this.key, this.title, this.icon);
}

const navs = [
  Nav('home', 'Vista general', Icons.space_dashboard_outlined),
  Nav('appointments', 'Agenda', Icons.calendar_month_outlined),
  Nav('sales', 'Ventas y CxC', Icons.point_of_sale_outlined),
  Nav('payables', 'Gastos y compras', Icons.receipt_long_outlined),
  Nav('deposits', 'Anticipos', Icons.savings_outlined),
  Nav('catalog', 'Catálogo e inventario', Icons.inventory_2_outlined),
  Nav('movements', 'Kardex', Icons.swap_vert),
  Nav('artists', 'Artistas', Icons.brush_outlined),
  Nav('beds', 'Camillas', Icons.weekend_outlined),
  Nav('accruals', 'Participaciones', Icons.pie_chart_outline),
  Nav('settlements', 'Liquidaciones', Icons.payments_outlined),
  Nav('report', 'Caja y reportes', Icons.bar_chart),
  Nav('imports', 'Importación', Icons.file_upload_outlined),
  Nav('members', 'Usuarios', Icons.group_outlined),
  Nav('audit', 'Bitácora', Icons.history),
  Nav('settings', 'Configuración', Icons.tune),
];

class AppShell extends StatefulWidget {
  final Api api;
  final Json member;
  const AppShell({super.key, required this.api, required this.member});
  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  String page = 'home',
      search = '',
      agendaDay = today(),
      artistFilter = '',
      bedFilter = '';
  final look = Lookups();
  bool ready = false, loading = false;
  String? error, cursor;
  List<Json> rows = [];
  Json? report;
  String from = '${today().substring(0, 7)}-01',
      to = today(),
      dimension = 'all';
  Timer? refreshTimer;
  int request = 0;
  String get role => widget.member['role'];
  bool get canWrite => role == 'admin' || role == 'reception';
  List<Nav> get navigation => navs.where((n) {
    if (role == 'artist') {
      return [
        'home',
        'appointments',
        'accruals',
        'settlements',
        'report',
      ].contains(n.key);
    }
    if (role == 'auditor') return n.key == 'report';
    if (role == 'reception') {
      return !['imports', 'members', 'audit', 'settings'].contains(n.key);
    }
    return true;
  }).toList();
  @override
  void initState() {
    super.initState();
    if (role == 'auditor') page = 'report';
    if (role == 'artist') dimension = 'artist_${widget.member['artistId']}';
    boot();
    refreshTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted && ready && page == 'appointments' && !loading) load();
    });
  }

  @override
  void dispose() {
    refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> boot() async {
    try {
      await look.load(widget.api, role);
      if (mounted) setState(() => ready = true);
      await load();
    } catch (e) {
      if (mounted) setState(() => error = readableError(e));
    }
  }

  Future<void> load({bool more = false}) async {
    final token = ++request;
    setState(() {
      loading = true;
      error = null;
    });
    try {
      if (page == 'home' || page == 'report') {
        final r = await widget.api.report(from, to, dimension: dimension);
        if (token != request || !mounted) return;
        report = r;
        if (page == 'home') {
          final a = await widget.api.query(
            'appointments',
            filters: {'day': today()},
          );
          if (token != request || !mounted) return;
          rows = asRows(a['rows']);
          final previousDay = DateTime.parse(today())
              .subtract(const Duration(days: 1))
              .toIso8601String()
              .substring(0, 10);
          final previous = await widget.api.query(
            'appointments',
            filters: {'day': previousDay},
          );
          if (token != request || !mounted) return;
          final midnight = DateTime.parse(
            '${today()}T00:00:00-05:00',
          ).toUtc().toIso8601String();
          rows.addAll(
            asRows(
              previous['rows'],
            ).where((r) => (r['end'] as String).compareTo(midnight) > 0),
          );
        }
      } else if (page != 'settings' && page != 'imports') {
        final result = await widget.api.query(
          page,
          cursor: more ? cursor : null,
          filters: {
            if (page == 'appointments') ...{
              if (agendaDay.isNotEmpty) 'day': agendaDay,
              if (artistFilter.isNotEmpty) 'artistId': artistFilter,
              if (bedFilter.isNotEmpty) 'bedId': bedFilter,
            },
          },
        );
        if (token != request || !mounted) return;
        rows = more
            ? [...rows, ...asRows(result['rows'])]
            : asRows(result['rows']);
        cursor = result['nextCursor'];
      }
    } catch (e) {
      if (token == request && mounted) error = readableError(e);
    } finally {
      if (token == request && mounted) setState(() => loading = false);
    }
  }

  void navigate(String key) {
    setState(() {
      page = key;
      search = '';
      rows = [];
      cursor = null;
    });
    load();
  }

  Future<void> op(
    String action,
    String title, {
    Json initial = const {},
  }) async {
    final ok = await operationDialog(
      context,
      widget.api,
      look,
      action,
      title,
      initial: initial,
    );
    if (ok == true && mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Operación guardada.')));
      await boot();
    }
  }

  Widget button(String text, String action, {Json initial = const {}}) =>
      FilledButton.icon(
        onPressed: () => op(action, text, initial: initial),
        icon: const Icon(Icons.add, size: 18),
        label: Text(text),
      );
  List<Widget> actions() => switch (page) {
    'appointments' when canWrite => [button('Nueva cita', 'reserve')],
    'sales' when canWrite => [button('Nueva venta', 'sale')],
    'payables' when canWrite => [
      button('Registrar gasto', 'expense'),
      button('Recibir compra', 'purchase'),
    ],
    'deposits' when canWrite => [button('Registrar anticipo', 'deposit')],
    'catalog' when role == 'admin' => [
      button('Crear artículo', 'saveCatalog'),
      button('Consumo / ajuste', 'movement'),
    ],
    'catalog' when canWrite => [button('Consumo / ajuste', 'movement')],
    'movements' when canWrite => [button('Consumo / ajuste', 'movement')],
    'artists' when role == 'admin' => [button('Nuevo artista', 'saveArtist')],
    'beds' when role == 'admin' => [button('Nueva camilla', 'saveBed')],
    'settlements' when canWrite => [
      button('Pagar participación', 'settlement'),
    ],
    'members' when role == 'admin' => [
      button('Autorizar correo', 'invite'),
      button('Crear cuenta con contraseña', 'createUser'),
    ],
    _ => [],
  };
  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 1050;
    final selected = navigation.firstWhere((n) => n.key == page);
    final sidebar = Container(
      width: 244,
      color: Colors.white,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(26, 30, 26, 24),
              child: Brand(),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 28, vertical: 10),
              child: Text(
                'TU ESTUDIO',
                style: TextStyle(
                  fontSize: 10,
                  letterSpacing: 2,
                  color: Color(0xff849080),
                ),
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                children: [
                  for (final n in navigation)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 3),
                      child: ListTile(
                        dense: true,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        selected: page == n.key,
                        selectedTileColor: accent.withValues(alpha: .5),
                        selectedColor: ink,
                        leading: Icon(n.icon, size: 21),
                        title: Text(
                          n.title,
                          style: TextStyle(
                            fontWeight: page == n.key
                                ? FontWeight.w700
                                : FontWeight.w400,
                          ),
                        ),
                        onTap: () {
                          if (!wide) Navigator.pop(context);
                          navigate(n.key);
                        },
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Divider(),
                  const SizedBox(height: 12),
                  Text(
                    label(role),
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  Text(
                    widget.member['email'] ?? '',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 11),
                  ),
                  TextButton.icon(
                    onPressed: () => FirebaseAuth.instance.signOut(),
                    icon: const Icon(Icons.logout, size: 16),
                    label: const Text('Cerrar sesión'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
    return Scaffold(
      drawer: wide ? null : Drawer(child: sidebar),
      appBar: wide
          ? null
          : AppBar(
              title: const Brand(),
              actions: [
                IconButton(
                  tooltip: 'Actualizar',
                  onPressed: load,
                  icon: const Icon(Icons.refresh),
                ),
              ],
            ),
      body: Row(
        children: [
          if (wide) sidebar,
          Expanded(
            child: SafeArea(
              child: Column(
                children: [
                  Padding(
                    padding: EdgeInsets.fromLTRB(
                      wide ? 36 : 20,
                      wide ? 24 : 8,
                      wide ? 36 : 20,
                      14,
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            'FINDINK HOUSE  /  ${selected.title.toUpperCase()}',
                            style: const TextStyle(
                              fontSize: 10,
                              letterSpacing: 1.5,
                              color: Color(0xff788579),
                            ),
                          ),
                        ),
                        const Chip(
                          avatar: Icon(Icons.science_outlined, size: 15),
                          label: Text('QA', style: TextStyle(fontSize: 11)),
                        ),
                        if (wide)
                          IconButton(
                            tooltip: 'Actualizar',
                            onPressed: loading ? null : () => boot(),
                            icon: const Icon(Icons.refresh),
                          ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: !ready && error == null
                        ? const Center(child: CircularProgressIndicator())
                        : SingleChildScrollView(
                            padding: EdgeInsets.fromLTRB(
                              wide ? 36 : 20,
                              8,
                              wide ? 36 : 20,
                              36,
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  page == 'home'
                                      ? 'El pulso de tu estudio'
                                      : selected.title,
                                  style: Theme.of(
                                    context,
                                  ).textTheme.headlineLarge,
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  subtitle(),
                                  style: const TextStyle(
                                    color: Color(0xff6a786d),
                                    fontSize: 15,
                                  ),
                                ),
                                const SizedBox(height: 24),
                                if (error != null)
                                  Card(
                                    child: Padding(
                                      padding: const EdgeInsets.all(20),
                                      child: Row(
                                        children: [
                                          const Icon(Icons.error_outline),
                                          const SizedBox(width: 12),
                                          Expanded(child: Text(error!)),
                                          TextButton(
                                            onPressed: boot,
                                            child: const Text('Reintentar'),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                if (loading)
                                  const LinearProgressIndicator(minHeight: 2),
                                if (ready) ...[
                                  if (actions().isNotEmpty)
                                    Padding(
                                      padding: const EdgeInsets.only(
                                        bottom: 20,
                                      ),
                                      child: Wrap(
                                        spacing: 12,
                                        runSpacing: 12,
                                        children: actions(),
                                      ),
                                    ),
                                  if (page == 'home')
                                    dashboard()
                                  else if (page == 'report')
                                    reportPage()
                                  else if (page == 'settings')
                                    settingsPage()
                                  else if (page == 'imports')
                                    ImportPage(api: widget.api, look: look)
                                  else
                                    recordsPage(),
                                ],
                              ],
                            ),
                          ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  String subtitle() => switch (page) {
    'home' => 'Agenda, finanzas y equipo, conectados. ${dateLabel(today())}.',
    'appointments' =>
      'Horarios en Bogotá · Completo comprende AM y PM · Actualización cada 30 segundos.',
    'sales' => 'Cada venta conserva precios, costos, pagos y saldos.',
    'payables' =>
      'Recibe compras y paga obligaciones sin duplicar el inventario.',
    'catalog' =>
      'Servicios, productos vendibles e insumos en un solo catálogo.',
    'report' =>
      'Ingresos devengados y efectivo: dos perspectivas para decidir.',
    'imports' => 'Revisa, concilia y aprueba cada fila antes de cargarla.',
    'artists' => 'La tasa del estudio y la parte complementaria del artista.',
    'settings' =>
      'Valores de QA. Confirma las reglas del estudio antes de producción.',
    _ => 'Consulta el historial y gestiona las operaciones de tu estudio.',
  };
  Widget metric(
    String title,
    dynamic value, {
    bool highlight = false,
    String? caption,
  }) => Container(
    width: MediaQuery.sizeOf(context).width < 600
        ? MediaQuery.sizeOf(context).width - 40
        : 240,
    padding: const EdgeInsets.all(22),
    decoration: BoxDecoration(
      color: highlight ? ink : Colors.white,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: const Color(0xffe4e7dd)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            color: highlight
                ? const Color(0xffc4d0c7)
                : const Color(0xff69786c),
            fontSize: 12,
          ),
        ),
        const SizedBox(height: 16),
        Text(
          value is String ? value : money(value),
          style: TextStyle(
            fontSize: 27,
            fontWeight: FontWeight.w600,
            letterSpacing: -.8,
            color: highlight ? accent : ink,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          caption ?? 'Período seleccionado',
          style: TextStyle(
            fontSize: 10,
            color: highlight
                ? const Color(0xffc4d0c7)
                : const Color(0xff899287),
          ),
        ),
      ],
    ),
  );
  Widget dashboard() {
    final totals = asJson(report?['totals'] ?? {});
    final now = isoNow();
    final occupied = rows
        .where(
          (r) =>
              ['reserved', 'arrived'].contains(r['status']) &&
              (r['start'] as String).compareTo(now) <= 0 &&
              (r['end'] as String).compareTo(now) > 0,
        )
        .map((r) => r['bedId'])
        .toSet();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 16,
          runSpacing: 16,
          children: [
            metric(
              'Ingreso del estudio',
              totals['studio'] ?? 0,
              highlight: true,
            ),
            metric('Ingresos devengados', totals['gross'] ?? 0),
            metric('Flujo neto de caja', totals['cash'] ?? 0),
            metric(
              'Camillas en uso',
              '${occupied.length} / ${look.beds.where((r) => r['active'] == true).length}',
              caption: 'Ocupación actual',
            ),
          ],
        ),
        const SizedBox(height: 26),
        if (role != 'artist')
          Padding(
            padding: const EdgeInsets.only(bottom: 20),
            child: Wrap(
              spacing: 16,
              runSpacing: 16,
              children: [
                metric(
                  'Valor actual del inventario',
                  report?['inventoryValue'] ?? 0,
                  caption: 'Valoración de existencias, todas las fechas',
                ),
                metric(
                  'Mayor producción de servicios',
                  report?['topArtist'] == null
                      ? 'Sin actividad'
                      : nameOf(look.artists, report!['topArtist']['id']),
                  caption: report?['topArtist'] == null
                      ? 'Período seleccionado'
                      : money(report!['topArtist']['gross']),
                ),
              ],
            ),
          ),
        if (canWrite)
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: accent.withValues(alpha: .45),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Wrap(
              spacing: 24,
              runSpacing: 16,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Dale espacio a la próxima idea.',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text('Organiza una cita o registra lo que acaba de pasar.'),
                  ],
                ),
                button('Nueva cita', 'reserve'),
                button('Nueva venta', 'sale'),
              ],
            ),
          ),
        const SizedBox(height: 28),
        Row(
          children: [
            const Expanded(
              child: Text(
                'En la agenda de hoy',
                style: TextStyle(fontSize: 21, fontWeight: FontWeight.w600),
              ),
            ),
            TextButton(
              onPressed: () => navigate('appointments'),
              child: const Text('Ver agenda →'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (rows.isEmpty)
          empty(
            'Tu agenda de hoy está libre.',
            'Las nuevas reservas aparecerán aquí.',
          )
        else
          ...rows.take(6).map((r) => record(r, 'appointments')),
        if (role != 'artist') ...[
          const SizedBox(height: 24),
          const Text(
            'Inventario por reponer',
            style: TextStyle(fontSize: 21, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 12),
          if (look.catalog
              .where(
                (r) =>
                    r['active'] == true &&
                    r['kind'] != 'service' &&
                    (r['stock'] as num) <= (r['minimum'] as num),
              )
              .isEmpty)
            empty(
              'Existencias al día',
              'No hay artículos por debajo del mínimo.',
            )
          else
            ...look.catalog
                .where(
                  (r) =>
                      r['active'] == true &&
                      r['kind'] != 'service' &&
                      (r['stock'] as num) <= (r['minimum'] as num),
                )
                .map((r) => record(r, 'catalog')),
        ],
      ],
    );
  }

  Widget empty(String title, String text) => Card(
    child: Padding(
      padding: const EdgeInsets.all(28),
      child: Row(
        children: [
          const Icon(Icons.spa_outlined, size: 32, color: Color(0xff839978)),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 16,
                  ),
                ),
                Text(text, style: const TextStyle(color: Color(0xff75806f))),
              ],
            ),
          ),
        ],
      ),
    ),
  );
  Widget recordsPage() {
    final filtered = rows
        .where(
          (r) => jsonEncode(r).toLowerCase().contains(search.toLowerCase()),
        )
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (page == 'appointments') ...[
          calendarStrip(),
          const SizedBox(height: 16),
        ],
        Wrap(
          spacing: 16,
          runSpacing: 12,
          children: [
            SizedBox(
              width: 280,
              child: TextField(
                decoration: const InputDecoration(
                  hintText: 'Buscar en registros cargados',
                  prefixIcon: Icon(Icons.search),
                ),
                onChanged: (v) => setState(() => search = v),
              ),
            ),
            if (page == 'appointments') ...[
              SizedBox(
                width: 220,
                child: DropdownButtonFormField<String>(
                  initialValue: bedFilter,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Camilla'),
                  items: [
                    const DropdownMenuItem(
                      value: '',
                      child: Text('Todas las camillas'),
                    ),
                    for (final bed in look.beds)
                      DropdownMenuItem(
                        value: bed['id'],
                        child: Text(bed['name']),
                      ),
                  ],
                  onChanged: (v) {
                    bedFilter = v ?? '';
                    load();
                  },
                ),
              ),
              SizedBox(
                width: 190,
                child: TextFormField(
                  initialValue: agendaDay,
                  decoration: const InputDecoration(
                    labelText: 'Fecha AAAA-MM-DD',
                  ),
                  onFieldSubmitted: (v) {
                    agendaDay = v;
                    load();
                  },
                ),
              ),
              SizedBox(
                width: 240,
                child: DropdownButtonFormField<String>(
                  initialValue: artistFilter,
                  decoration: const InputDecoration(labelText: 'Artista'),
                  items: [
                    const DropdownMenuItem(
                      value: '',
                      child: Text('Todos los permitidos'),
                    ),
                    for (final a in look.artists)
                      DropdownMenuItem(
                        value: a['id'],
                        child: Text(a['name'], overflow: TextOverflow.ellipsis),
                      ),
                  ],
                  isExpanded: true,
                  onChanged: (v) {
                    artistFilter = v ?? '';
                    load();
                  },
                ),
              ),
              TextButton(
                onPressed: () {
                  agendaDay = '';
                  load();
                },
                child: const Text('Ver historial'),
              ),
            ],
            OutlinedButton.icon(
              onPressed: filtered.isEmpty
                  ? null
                  : () => saveWorkbook(
                      'findink-$page.xlsx',
                      [
                        'Referencia',
                        'Descripción',
                        'Fecha',
                        'Estado',
                        'Monto COP',
                        'Saldo COP',
                      ],
                      [
                        for (final r in filtered)
                          [
                            r['id'],
                            recordTitle(r, page),
                            r['eventAt'] ?? r['day'] ?? r['createdAt'],
                            r['status'] ?? '',
                            r['total'] ?? r['amount'] ?? '',
                            r['balance'] ?? '',
                          ],
                      ],
                    ),
              icon: const Icon(Icons.download, size: 17),
              label: const Text('Exportar vista XLSX'),
            ),
          ],
        ),
        const SizedBox(height: 20),
        if (filtered.isEmpty && !loading)
          empty(
            'Aún no hay registros',
            'Las operaciones guardadas aparecerán aquí.',
          ),
        for (final r in filtered) record(r, page),
        if (cursor != null)
          Padding(
            padding: const EdgeInsets.all(16),
            child: OutlinedButton(
              onPressed: loading ? null : () => load(more: true),
              child: const Text('Cargar siguientes 50 registros'),
            ),
          ),
      ],
    );
  }

  String nameOf(List<Json> list, dynamic id) =>
      list.where((r) => r['id'] == id).firstOrNull?['name'] ??
      id?.toString() ??
      '—';
  String recordTitle(Json r, String type) => switch (type) {
    'appointments' => '${label(r['mode'])} · ${nameOf(look.beds, r['bedId'])}',
    'sales' =>
      r['clientName'] == ''
          ? 'Venta · ${r['id'].toString().substring(0, 8)}'
          : r['clientName'] ?? 'Venta',
    'payables' => r['description'] ?? 'Compra · ${r['supplier'] ?? ''}',
    'movements' =>
      '${label(r['reason'])} · ${nameOf(look.catalog, r['itemId'])}',
    'accruals' || 'settlements' => nameOf(look.artists, r['artistId']),
    'members' => r['email'] ?? r['id'],
    'audit' => '${r['action']} · ${r['entityId'] ?? ''}',
    _ => r['name'] ?? r['clientName'] ?? r['id'] ?? 'Registro',
  };
  Widget record(Json r, String type) {
    final amount = r['total'] ?? r['amount'];
    final sub = switch (type) {
      'appointments' =>
        '${nameOf(look.artists, r['artistId'])} · ${dateLabel(r['day'])} · ${r['clientName'] ?? ''}',
      'catalog' =>
        '${label(r['kind'])} · SKU ${r['sku']} · ${r['kind'] == 'service' ? money(r['price']) : 'Stock ${r['stock']} ${r['unit']} · mínimo ${r['minimum']}'}',
      'artists' =>
        '${r['styles']} · Estudio ${asJson(r['rule'] ?? {})['baseBps'] != null ? (r['rule']['baseBps'] / 100).toString() : ''}%',
      'members' => label(r['role']),
      'movements' =>
        '${r['quantity']} unidades · saldo ${r['stockAfter']} · ${dateLabel(r['eventAt'])}',
      _ =>
        '${dateLabel(r['eventAt'] ?? r['createdAt'])}${r['balance'] != null ? ' · Pendiente ${money(r['balance'])}' : ''}',
    };
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () => detail(r, type),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: paper,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  type == 'appointments'
                      ? Icons.schedule
                      : type == 'catalog'
                      ? Icons.inventory_2_outlined
                      : Icons.receipt_long_outlined,
                  color: ink,
                  size: 21,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      recordTitle(r, type),
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      sub,
                      style: const TextStyle(
                        color: Color(0xff73806e),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (amount != null)
                    Text(
                      money(amount),
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  if (r['status'] != null)
                    Text(
                      label(r['status']),
                      style: TextStyle(
                        fontSize: 11,
                        color: r['status'] == 'void'
                            ? Colors.red
                            : const Color(0xff628448),
                      ),
                    ),
                ],
              ),
              const SizedBox(width: 8),
              const Icon(Icons.chevron_right, size: 18),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> detail(Json r, String type) async {
    final ops = <String, String>{};
    if (role == 'admin') {
      if (type == 'catalog') ops['saveCatalog'] = 'Editar artículo';
      if (type == 'artists') ops['saveArtist'] = 'Editar artista y regla';
      if (type == 'beds') ops['saveBed'] = 'Editar camilla';
      if (type == 'members') ops['member'] = 'Editar acceso';
    }
    if (canWrite) {
      if (type == 'appointments' &&
          ['reserved', 'arrived'].contains(r['status'])) {
        ops['appointmentStatus'] = 'Cambiar estado';
      }
      if (type == 'sales' && r['status'] == 'confirmed') {
        if ((r['balance'] ?? 0) > 0) ops['salePayment'] = 'Registrar cobro';
        ops['saleVoid'] = 'Anular y devolver';
      }
      if (type == 'payables' && r['status'] == 'confirmed') {
        if ((r['balance'] ?? 0) > 0) ops['payablePayment'] = 'Registrar pago';
        ops['payableVoid'] = 'Anular y devolver';
      }
      if (type == 'deposits' && r['status'] == 'available') {
        ops['depositRefund'] = 'Devolver anticipo';
      }
    }
    final action = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(recordTitle(r, type)),
        content: SizedBox(
          width: 600,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SelectableText('Referencia: ${r['id']}'),
                const Divider(),
                ...humanDetails(r),
              ],
            ),
          ),
        ),
        actions: [
          for (final e in ops.entries)
            TextButton(
              onPressed: () => Navigator.pop(context, e.key),
              child: Text(e.value),
            ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cerrar'),
          ),
        ],
      ),
    );
    if (action != null && mounted) await op(action, ops[action]!, initial: r);
  }

  List<Widget> humanDetails(Json r) => [
    for (final k in [
      'status',
      'eventAt',
      'day',
      'start',
      'end',
      'clientName',
      'contact',
      'design',
      'description',
      'notes',
      'supplier',
      'folio',
      'costCenter',
      'dueDate',
      'sku',
      'unit',
      'stock',
      'minimum',
      'price',
      'cost',
      'total',
      'paid',
      'balance',
      'amount',
      'quantity',
      'reason',
      'reference',
      'artistId',
      'role',
      'email',
      'createdAt',
    ])
      if (r[k] != null && r[k] != '')
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            '${{'status': 'Estado', 'eventAt': 'Fecha', 'day': 'Día', 'start': 'Inicio UTC', 'end': 'Fin UTC', 'clientName': 'Cliente', 'contact': 'Contacto', 'design': 'Diseño', 'description': 'Descripción', 'notes': 'Notas', 'supplier': 'Proveedor', 'folio': 'Folio', 'costCenter': 'Centro de costos', 'dueDate': 'Vencimiento', 'sku': 'SKU', 'unit': 'Unidad', 'stock': 'Existencias', 'minimum': 'Mínimo', 'price': 'Precio', 'cost': 'Costo', 'total': 'Total', 'paid': 'Pagado', 'balance': 'Saldo', 'amount': 'Monto', 'quantity': 'Cantidad', 'reason': 'Motivo', 'reference': 'Referencia', 'artistId': 'Artista', 'role': 'Rol', 'email': 'Correo', 'createdAt': 'Creación'}[k]}: ${['total', 'paid', 'balance', 'amount', 'price', 'cost'].contains(k) ? money(r[k]) : label(r[k])}',
          ),
        ),
    if (r['lines'] is List) ...[
      const Divider(),
      const Text(
        'Líneas y precios históricos',
        style: TextStyle(fontWeight: FontWeight.bold),
      ),
      for (final line in asRows(r['lines']))
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Text(
            '${line['name']} × ${line['quantity']} · ${money(line['total'] ?? line['cost'])}${line['artistShare'] != null ? '\nArtista: ${money(line['artistShare'])} · Estudio: ${money(line['studioShare'])}' : ''}',
          ),
        ),
    ],
    if (r['payments'] is List) ...[
      const Divider(),
      const Text(
        'Pagos registrados',
        style: TextStyle(fontWeight: FontWeight.bold),
      ),
      for (final p in asRows(r['payments']))
        Text(
          '${dateLabel(p['at'])} · ${money(p['amount'])} · ${widget.lookName(look, p['methodId'], 'methods')} · ${p['reference'] ?? ''}',
        ),
    ],
    if (r['history'] is List) ...[
      const Divider(),
      for (final h in asRows(r['history']))
        Text(
          '${label(h['status'])} · ${dateLabel(h['at'])} · ${h['reason'] ?? ''}',
        ),
    ],
    if (r['reversal'] is Map) ...[
      const Divider(),
      Text(
        'Reverso: ${r['reversal']['reason']} · ${dateLabel(r['reversal']['at'])}',
      ),
    ],
  ];
  Widget reportPage() {
    final totals = asJson(report?['totals'] ?? {});
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Wrap(
            spacing: 8,
            children: [
              for (final preset in ['Hoy', 'Semana', 'Mes', 'Año'])
                ActionChip(
                  label: Text(preset),
                  onPressed: () {
                    final d = DateTime.parse(today());
                    setState(() {
                      to = today();
                      from = switch (preset) {
                        'Hoy' => today(),
                        'Semana' =>
                          d
                              .subtract(Duration(days: d.weekday - 1))
                              .toIso8601String()
                              .substring(0, 10),
                        'Mes' => '${today().substring(0, 7)}-01',
                        _ => '${today().substring(0, 4)}-01-01',
                      };
                    });
                    load();
                  },
                ),
            ],
          ),
        ),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            SizedBox(
              width: 175,
              child: TextFormField(
                key: ValueKey('from_$from'),
                initialValue: from,
                decoration: const InputDecoration(
                  labelText: 'Desde AAAA-MM-DD',
                ),
                onChanged: (v) => from = v,
              ),
            ),
            SizedBox(
              width: 175,
              child: TextFormField(
                key: ValueKey('to_$to'),
                initialValue: to,
                decoration: const InputDecoration(
                  labelText: 'Hasta AAAA-MM-DD',
                ),
                onChanged: (v) => to = v,
              ),
            ),
            if (role != 'artist')
              SizedBox(
                width: 260,
                child: DropdownButtonFormField<String>(
                  initialValue: dimension,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Filtrar por'),
                  items: [
                    const DropdownMenuItem(
                      value: 'all',
                      child: Text('Todo el estudio'),
                    ),
                    for (final a in look.artists)
                      DropdownMenuItem(
                        value: 'artist_${a['id']}',
                        child: Text(a['name'], overflow: TextOverflow.ellipsis),
                      ),
                    for (final k in ['categories', 'methods', 'accounts'])
                      for (final a in asRows(look.settings[k]))
                        DropdownMenuItem(
                          value:
                              '${{'categories': 'category', 'methods': 'method', 'accounts': 'account'}[k]}_${a['id']}',
                          child: Text(
                            '${k == 'categories'
                                ? 'Categoría'
                                : k == 'methods'
                                ? 'Medio'
                                : 'Cuenta'}: ${a['name']}',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                  ],
                  onChanged: (v) => dimension = v ?? 'all',
                ),
              ),
            FilledButton(
              onPressed: loading ? null : load,
              child: const Text('Consultar'),
            ),
            OutlinedButton.icon(
              onPressed: report == null
                  ? null
                  : () => exportReport(report!, false),
              icon: const Icon(Icons.download),
              label: const Text('Excel'),
            ),
            OutlinedButton.icon(
              onPressed: report == null
                  ? null
                  : () => exportReport(report!, true),
              icon: const Icon(Icons.picture_as_pdf_outlined),
              label: const Text('PDF'),
            ),
          ],
        ),
        const SizedBox(height: 20),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            for (final k in [
              'gross',
              'studio',
              'artistGenerated',
              'artistPaid',
              'cogs',
              'expenses',
              'cash',
              'net',
            ])
              metric(label(k), totals[k] ?? 0, highlight: k == 'net'),
            metric(
              'Saldo actual de artistas',
              report?['artistBalance']?['pending'] ??
                  ((report?['balances']?['artistGenerated'] ?? 0) -
                      (report?['balances']?['artistPaid'] ?? 0)),
              caption: 'Generado menos pagado, todas las fechas',
            ),
          ],
        ),
        const SizedBox(height: 24),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Cómo leer estos números',
                  style: TextStyle(fontSize: 19, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 10),
                const Text(
                  'Neto operativo = ingresos devengados − parte del artista generada − costo vendido − gastos devengados. Los pagos a artistas afectan caja y no se restan otra vez del neto. Las compras de inventario se reconocen como costo al vender o consumir.',
                ),
                const SizedBox(height: 10),
                Text(
                  'Impuestos informativos: cobrados ${money(totals['taxCollected'])} · pagados ${money(totals['taxPaid'])}',
                ),
                const SizedBox(height: 10),
                Text(
                  'Saldos actuales, todas las fechas: CxC ${money(report?['balances']?['receivable'])} · CxP ${money(report?['balances']?['payable'])} · Anticipos ${money(report?['balances']?['depositLiability'])}',
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),
        const Text(
          'Detalle diario',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 12),
        for (final r in asRows(report?['rows']))
          Card(
            child: ListTile(
              title: Text(dateLabel(r['day'])),
              subtitle: Text(
                'Ingresos: ${money(r['metrics']['gross'])} · Caja: ${money(r['metrics']['cash'])}',
              ),
              trailing: Text(
                money(
                  (r['metrics']['gross'] ?? 0) -
                      (r['metrics']['artistGenerated'] ?? 0) -
                      (r['metrics']['cogs'] ?? 0) -
                      (r['metrics']['expenses'] ?? 0),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget calendarStrip() {
    final selected = DateTime.tryParse(agendaDay) ?? DateTime.parse(today());
    final monday = selected.subtract(Duration(days: selected.weekday - 1));
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                IconButton(
                  tooltip: 'Semana anterior',
                  onPressed: () {
                    agendaDay = selected
                        .subtract(const Duration(days: 7))
                        .toIso8601String()
                        .substring(0, 10);
                    load();
                  },
                  icon: const Icon(Icons.chevron_left),
                ),
                Expanded(
                  child: Text(
                    'Semana del ${dateLabel(monday.toIso8601String())}',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                IconButton(
                  tooltip: 'Elegir fecha',
                  onPressed: () async {
                    final d = await showDatePicker(
                      context: context,
                      initialDate: selected,
                      firstDate: DateTime(2000),
                      lastDate: DateTime(2100),
                    );
                    if (d != null) {
                      agendaDay = d.toIso8601String().substring(0, 10);
                      load();
                    }
                  },
                  icon: const Icon(Icons.calendar_month),
                ),
                IconButton(
                  tooltip: 'Semana siguiente',
                  onPressed: () {
                    agendaDay = selected
                        .add(const Duration(days: 7))
                        .toIso8601String()
                        .substring(0, 10);
                    load();
                  },
                  icon: const Icon(Icons.chevron_right),
                ),
              ],
            ),
            Wrap(
              spacing: 10,
              runSpacing: 8,
              children: [
                for (var i = 0; i < 7; i++)
                  ChoiceChip(
                    label: Text(
                      '${['Lun', 'Mar', 'Mié', 'Jue', 'Vie', 'Sáb', 'Dom'][i]} ${monday.add(Duration(days: i)).day}',
                    ),
                    selected:
                        agendaDay ==
                        monday
                            .add(Duration(days: i))
                            .toIso8601String()
                            .substring(0, 10),
                    onSelected: (_) {
                      agendaDay = monday
                          .add(Duration(days: i))
                          .toIso8601String()
                          .substring(0, 10);
                      load();
                    },
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget settingsPage() => Card(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Parámetros del estudio',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 16),
          const Text(
            'Moneda: COP en pesos enteros\nZona horaria: America/Bogota\nEntorno: QA con datos ficticios',
          ),
          const SizedBox(height: 16),
          for (final m in ['am', 'pm', 'night'])
            Text(
              '${label(m)}: ${look.settings['shifts']?[m]?.join(' → ') ?? 'Sin configurar'}',
            ),
          const SizedBox(height: 16),
          for (final k in ['methods', 'accounts', 'categories'])
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                '${{'methods': 'Medios', 'accounts': 'Cuentas', 'categories': 'Categorías'}[k]}: ${asRows(look.settings[k]).map((r) => r['name']).join(', ')}',
              ),
            ),
          const SizedBox(height: 16),
          button('Editar configuración', 'settings'),
        ],
      ),
    ),
  );
}

extension on AppShell {
  String lookName(Lookups look, dynamic id, String type) =>
      asRows(
        look.settings[type],
      ).where((r) => r['id'] == id).firstOrNull?['name'] ??
      id.toString();
}
