// Same sums as the web dashboard's summary.

const Map<String, String> kChannels = {'talabat': 'طلبات', 'snoonu': 'سنونو', 'khedmah': 'خدمة'};

double numOf(dynamic v) => v is num ? v.toDouble() : double.tryParse('${v ?? ''}') ?? 0;

class Method {
  Method(this.key, this.name, this.isApp, this.gross, this.comm, this.n);
  final String key;
  final String name;
  final bool isApp;
  final double gross;
  final double comm;
  final int n;
  double get net => gross - comm;
}

class Stats {
  Stats(Map<String, dynamic> data, List<DateTime> days) {
    final orders = (data['orders'] as List? ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    final apps = (data['apps'] as List? ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    final exps = (data['exps'] as List? ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();

    final valid = orders.where((o) => o['status'] != 'cancelled').toList();
    bool isApp(Map o) => o['source'] == 'pos' && kChannels.containsKey(o['payment']);
    final web = valid.where((o) => o['source'] != 'pos').toList();
    final shopO = valid.where((o) => o['source'] == 'pos' && !kChannels.containsKey(o['payment'])).toList();
    final appO = valid.where(isApp).toList();

    double sumT(List<Map<String, dynamic>> l) => l.fold(0.0, (s, o) => s + numOf(o['total']));
    int cnt(List<Map<String, dynamic>> l) => l.fold(0, (s, o) => s + (o['n_orders'] is num ? (o['n_orders'] as num).toInt() : 1));
    int cups(List<Map<String, dynamic>> l) =>
        l.fold(0, (s, o) => s + ((o['items'] as List?) ?? []).fold<int>(0, (a, i) => a + ((i as Map)['qty'] as num).toInt()));

    site = sumT(web);
    shop = sumT(shopO);
    siteOrders = cnt(web);
    siteCups = cups(web);
    shopOrders = cnt(shopO);
    shopCups = cups(shopO);

    Method mk(String k, String name, List<Map<String, dynamic>> list, List<Map<String, dynamic>> manual, bool app) {
      final gross = sumT(list) + manual.fold(0.0, (s, r) => s + numOf(r['gross']));
      final comm = list.fold(0.0, (s, o) => s + numOf(o['commission'])) + manual.fold(0.0, (s, r) => s + numOf(r['commission']));
      final n = cnt(list) + manual.fold(0, (s, r) => s + (r['orders_count'] is num ? (r['orders_count'] as num).toInt() : 0));
      return Method(k, name, app, gross, comm, n);
    }

    methods = [
      mk('cash', 'نقد', valid.where((o) => o['payment'] == 'cash').toList(), [], false),
      mk('card', 'بطاقة', valid.where((o) => o['payment'] == 'card').toList(), [], false),
      for (final e in kChannels.entries)
        mk(e.key, e.value, appO.where((o) => o['payment'] == e.key).toList(), apps.where((r) => r['channel'] == e.key).toList(), true),
    ];
    final unpaid = web.where((o) => o['payment'] == null || o['payment'] == '').toList();
    unpaidTotal = sumT(unpaid);
    unpaidCount = unpaid.length;

    appGross = methods.where((m) => m.isApp).fold(0.0, (s, m) => s + m.gross);
    comm = methods.fold(0.0, (s, m) => s + m.comm);
    exp = exps.fold(0.0, (s, r) => s + numOf(r['amount']));
    expCount = exps.length;
    final manualGross = apps.fold(0.0, (s, r) => s + numOf(r['gross']));
    sales = sumT(valid) + manualGross;
    net = sales - comm - exp;
    orderCount = cnt(valid) + apps.fold(0, (s, r) => s + (r['orders_count'] is num ? (r['orders_count'] as num).toInt() : 0));

    final prod = <String, int>{};
    for (final o in valid) {
      for (final i in (o['items'] as List? ?? [])) {
        final m = i as Map;
        final name = '${m['name_ar'] ?? m['name_en'] ?? ''}';
        prod[name] = (prod[name] ?? 0) + (m['qty'] as num).toInt();
      }
    }
    products = prod.entries.toList()..sort((a, b) => b.value.compareTo(a.value));

    String d10(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    daily = [
      for (final d in days)
        MapEntry(
          d,
          valid.where((o) => '${o['created_at']}'.startsWith(d10(d))).fold(0.0, (s, o) => s + numOf(o['total'])) +
              apps.where((r) => r['sale_date'] == d10(d)).fold(0.0, (s, r) => s + numOf(r['gross'])),
        ),
    ];
  }

  late final double site, shop, appGross, comm, exp, sales, net, unpaidTotal;
  late final int siteOrders, siteCups, shopOrders, shopCups, unpaidCount, expCount, orderCount;
  late final List<Method> methods;
  late final List<MapEntry<String, int>> products;
  late final List<MapEntry<DateTime, double>> daily;

  double get avg => orderCount > 0 ? sales / orderCount : 0;
  int pct(double v) => sales > 0 ? (v / sales * 100).round().clamp(0, 100).toInt() : 0;
}
