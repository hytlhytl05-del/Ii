import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:shared_preferences/shared_preferences.dart';

class Ids {
  static String get banner => kReleaseMode
      ? 'ca-app-pub-8040428097634812/7208441487'
      : 'ca-app-pub-3940256099942544/6300978111';
  static String get inter => kReleaseMode
      ? 'ca-app-pub-8040428097634812/6964898901'
      : 'ca-app-pub-3940256099942544/1033173712';
  static String get reward => kReleaseMode
      ? 'ca-app-pub-8040428097634812/8915313394'
      : 'ca-app-pub-3940256099942544/5224354917';
}

class Ads {
  static InterstitialAd? _i;
  static RewardedAd? _r;
  static int _ri = 0, _rr = 0, _actions = 0;
  static DateTime _last = DateTime.now();
  static final ready = ValueNotifier<bool>(false);

  static void init() {
    MobileAds.instance.initialize();
    loadI();
    loadR();
  }

  static void _retry(VoidCallback f, int n) =>
      Future.delayed(Duration(seconds: 5 << n.clamp(0, 5)), f);

  static void loadI() {
    InterstitialAd.load(
      adUnitId: Ids.inter,
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (a) {
          _i = a;
          _ri = 0;
        },
        onAdFailedToLoad: (e) {
          _i = null;
          _retry(loadI, _ri++);
        },
      ),
    );
  }

  static void loadR() {
    RewardedAd.load(
      adUnitId: Ids.reward,
      request: const AdRequest(),
      rewardedAdLoadCallback: RewardedAdLoadCallback(
        onAdLoaded: (a) {
          _r = a;
          _rr = 0;
          ready.value = true;
        },
        onAdFailedToLoad: (e) {
          _r = null;
          ready.value = false;
          _retry(loadR, _rr++);
        },
      ),
    );
  }

  static void action() {
    _actions++;
    if (_actions % 3 != 0) return;
    if (DateTime.now().difference(_last).inSeconds < 70) return;
    final ad = _i;
    if (ad == null) return;
    _i = null;
    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (a) {
        a.dispose();
        loadI();
      },
      onAdFailedToShowFullScreenContent: (a, e) {
        a.dispose();
        loadI();
      },
    );
    _last = DateTime.now();
    ad.show();
  }

  static bool showRewarded(VoidCallback earned, VoidCallback done) {
    final ad = _r;
    if (ad == null) {
      loadR();
      return false;
    }
    _r = null;
    ready.value = false;
    bool got = false;
    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (a) {
        a.dispose();
        loadR();
        if (got) done();
      },
      onAdFailedToShowFullScreenContent: (a, e) {
        a.dispose();
        loadR();
      },
    );
    ad.show(onUserEarnedReward: (a, r) {
      got = true;
      earned();
    });
    return true;
  }
}

class Game extends ChangeNotifier {
  late SharedPreferences p;
  int coins = 0, total = 0, today = 0, best = 0, skin = 0;
  bool x2 = false, auto = false;
  Set<int> owned = {0};
  String day = '';
  Timer? _t;

  int get level => total ~/ 2000 + 1;
  double get prog => (total % 2000) / 2000;

  Future<void> load() async {
    p = await SharedPreferences.getInstance();
    coins = p.getInt('c') ?? 0;
    total = p.getInt('t') ?? 0;
    today = p.getInt('d') ?? 0;
    best = p.getInt('b') ?? 0;
    skin = p.getInt('s') ?? 0;
    x2 = p.getBool('x') ?? false;
    auto = p.getBool('a') ?? false;
    day = p.getString('day') ?? '';
    owned = (p.getStringList('o') ?? ['0']).map(int.parse).toSet();
    _roll();
    _startAuto();
  }

  void _roll() {
    final n = DateTime.now().toIso8601String().substring(0, 10);
    if (day != n) {
      day = n;
      today = 0;
    }
  }

  void _save() {
    p.setInt('c', coins);
    p.setInt('t', total);
    p.setInt('d', today);
    p.setInt('b', best);
    p.setInt('s', skin);
    p.setBool('x', x2);
    p.setBool('a', auto);
    p.setString('day', day);
    p.setStringList('o', owned.map((e) => '$e').toList());
  }

  void add(int n) {
    _roll();
    coins += n;
    total += n;
    today += n;
    if (today > best) best = today;
    _save();
    notifyListeners();
  }

  void tap() => add(x2 ? 2 : 1);

  bool spend(int price) {
    if (coins < price) return false;
    coins -= price;
    _save();
    notifyListeners();
    return true;
  }

  void setAuto() {
    auto = true;
    _startAuto();
    _save();
    notifyListeners();
  }

  void setX2() {
    x2 = true;
    _save();
    notifyListeners();
  }

  void useSkin(int s) {
    owned.add(s);
    skin = s;
    _save();
    notifyListeners();
  }

  void _startAuto() {
    _t?.cancel();
    if (auto) _t = Timer.periodic(const Duration(seconds: 1), (_) => tap());
  }
}

String f(int n) => n
    .toString()
    .replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (m) => ',');

const kLime = Color(0xFFB6F23A);
const kCard = Color(0xFF2B1D6B);
const kSoft = Color(0xFFB9A8FF);
const kSkins = [Color(0xFFB6F23A), Color(0xFFFFC21A), Color(0xFF39FF88)];

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  Ads.init();
  final g = Game();
  await g.load();
  runApp(MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: ThemeData.dark(useMaterial3: true),
    builder: (c, w) => Directionality(textDirection: TextDirection.rtl, child: w!),
    home: Home(g),
  ));
}

void watch(BuildContext c, Game g, int amt) {
  final ok = Ads.showRewarded(() => g.add(amt), () {
    if (c.mounted) rewardDialog(c, g, amt);
  });
  if (!ok) {
    ScaffoldMessenger.of(c).showSnackBar(
        const SnackBar(content: Text('الإعلان قيد التحميل، حاول بعد لحظات')));
  }
}

void rewardDialog(BuildContext c, Game g, int amt) {
  showDialog(
    context: c,
    builder: (d) => AlertDialog(
      backgroundColor: kCard,
      title: Text('حصلت على +${f(amt)} كبسة!',
          textAlign: TextAlign.center,
          style: const TextStyle(fontWeight: FontWeight.w900)),
      actions: [
        ValueListenableBuilder<bool>(
          valueListenable: Ads.ready,
          builder: (_, r, __) => r
              ? FilledButton(
                  style: FilledButton.styleFrom(
                      backgroundColor: kLime, foregroundColor: Colors.black),
                  onPressed: () {
                    Navigator.pop(d);
                    watch(c, g, amt);
                  },
                  child: const Text('شاهد فيديو آخر'))
              : const SizedBox(),
        ),
        TextButton(onPressed: () => Navigator.pop(d), child: const Text('لاحقاً')),
      ],
    ),
  );
}

class Home extends StatefulWidget {
  final Game g;
  const Home(this.g, {super.key});
  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> {
  int idx = 0;
  @override
  Widget build(BuildContext context) {
    final g = widget.g;
    final pages = [PressPage(g), StorePage(g), AchPage(g)];
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
            gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xFF2A1670), Color(0xFF150B3D)])),
        child: SafeArea(
          child: Column(children: [
            Expanded(
                child: ListenableBuilder(
                    listenable: g, builder: (_, __) => pages[idx])),
            const BannerBox(),
          ]),
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: idx,
        backgroundColor: const Color(0xFF1B0F52),
        onDestinationSelected: (i) {
          setState(() => idx = i);
          Ads.action();
        },
        destinations: const [
          NavigationDestination(icon: Icon(Icons.touch_app), label: 'الزر'),
          NavigationDestination(icon: Icon(Icons.shopping_cart), label: 'المتجر'),
          NavigationDestination(icon: Icon(Icons.emoji_events), label: 'الإنجازات'),
        ],
      ),
    );
  }
}

class BannerBox extends StatefulWidget {
  const BannerBox({super.key});
  @override
  State<BannerBox> createState() => _BannerBoxState();
}

class _BannerBoxState extends State<BannerBox> {
  BannerAd? ad;
  bool ok = false;
  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    ad = BannerAd(
      adUnitId: Ids.banner,
      size: AdSize.banner,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (_) {
          if (mounted) setState(() => ok = true);
        },
        onAdFailedToLoad: (a, e) {
          a.dispose();
          ad = null;
          if (mounted) {
            setState(() => ok = false);
            Future.delayed(const Duration(seconds: 30), () {
              if (mounted) _load();
            });
          }
        },
      ),
    )..load();
  }

  @override
  void dispose() {
    ad?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SizedBox(
      height: 50,
      child: ok && ad != null ? AdWidget(ad: ad!) : const SizedBox());
}

class WatchCard extends StatelessWidget {
  final Game g;
  final int amt;
  const WatchCard(this.g, this.amt, {super.key});
  @override
  Widget build(BuildContext context) => ValueListenableBuilder<bool>(
        valueListenable: Ads.ready,
        builder: (_, r, __) => Opacity(
          opacity: r ? 1 : .5,
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () => watch(context, g, amt),
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                  color: kCard, borderRadius: BorderRadius.circular(16)),
              child: Row(children: [
                const Icon(Icons.smart_display, color: kSoft, size: 32),
                const SizedBox(width: 12),
                Expanded(
                    child: Text('شاهد فيديو واحصل على +${f(amt)} كبسة',
                        style: const TextStyle(fontWeight: FontWeight.bold))),
              ]),
            ),
          ),
        ),
      );
}

class PressPage extends StatefulWidget {
  final Game g;
  const PressPage(this.g, {super.key});
  @override
  State<PressPage> createState() => _PressPageState();
}

class _PressPageState extends State<PressPage> {
  bool down = false;
  @override
  Widget build(BuildContext context) {
    final g = widget.g;
    return Column(children: [
      const SizedBox(height: 24),
      Text(f(g.coins),
          style: const TextStyle(
              fontSize: 64, fontWeight: FontWeight.w900, color: Colors.white)),
      const Text('كبسة', style: TextStyle(fontSize: 22, color: kSoft)),
      const Spacer(),
      GestureDetector(
        onTapDown: (_) {
          setState(() => down = true);
          g.tap();
        },
        onTapUp: (_) => setState(() => down = false),
        onTapCancel: () => setState(() => down = false),
        child: AnimatedScale(
          scale: down ? .93 : 1,
          duration: const Duration(milliseconds: 80),
          child: Container(
            width: 230,
            height: 230,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: kSkins[g.skin],
              border: Border.all(color: const Color(0xFFFF5C7A), width: 8),
              boxShadow: [
                BoxShadow(
                    color: kSkins[g.skin].withOpacity(.5),
                    blurRadius: 40,
                    spreadRadius: 4)
              ],
            ),
            child: const Text('اضغط!',
                style: TextStyle(
                    fontSize: 48, fontWeight: FontWeight.w900, color: Colors.white)),
          ),
        ),
      ),
      const Spacer(),
      WatchCard(g, 500),
      const SizedBox(height: 8),
    ]);
  }
}

class StorePage extends StatelessWidget {
  final Game g;
  const StorePage(this.g, {super.key});

  Widget tile(BuildContext c, String title, IconData ic, Color col,
      String trail, VoidCallback onTap) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
            color: kCard, borderRadius: BorderRadius.circular(14)),
        child: Row(children: [
          Icon(ic, color: col, size: 30),
          const SizedBox(width: 12),
          Expanded(
              child: Text(title,
                  style: const TextStyle(fontWeight: FontWeight.bold))),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
                color: kLime, borderRadius: BorderRadius.circular(20)),
            child: Text(trail,
                style: const TextStyle(
                    color: Colors.black, fontWeight: FontWeight.bold)),
          ),
        ]),
      ),
    );
  }

  void buy(BuildContext c, int price, VoidCallback ok) {
    if (g.spend(price)) {
      ok();
      Ads.action();
    } else {
      ScaffoldMessenger.of(c).showSnackBar(
          const SnackBar(content: Text('لا تملك كبسات كافية')));
    }
  }

  @override
  Widget build(BuildContext c) {
    return ListView(children: [
      const Padding(
          padding: EdgeInsets.all(20),
          child: Text('المتجر',
              style: TextStyle(fontSize: 32, fontWeight: FontWeight.w900))),
      tile(c, 'مضاعف x2', Icons.bolt, kSoft, g.x2 ? 'مفعّل' : '5,000',
          () => g.x2 ? null : buy(c, 5000, g.setX2)),
      tile(c, 'زر ذهبي', Icons.circle, kSkins[1],
          g.owned.contains(1) ? 'استخدم' : '12,000', () {
        g.owned.contains(1) ? g.useSkin(1) : buy(c, 12000, () => g.useSkin(1));
      }),
      tile(c, 'زر نيون', Icons.circle, kSkins[2],
          g.owned.contains(2) ? 'استخدم' : '8,000', () {
        g.owned.contains(2) ? g.useSkin(2) : buy(c, 8000, () => g.useSkin(2));
      }),
      tile(c, 'كبسة تلقائية', Icons.timer, kSoft, g.auto ? 'مفعّل' : '20,000',
          () => g.auto ? null : buy(c, 20000, g.setAuto)),
      WatchCard(g, 300),
    ]);
  }
}

class AchPage extends StatelessWidget {
  final Game g;
  const AchPage(this.g, {super.key});

  Widget stat(String t, int v) => Expanded(
        child: Container(
          margin: const EdgeInsets.all(6),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
              color: kCard, borderRadius: BorderRadius.circular(14)),
          child: Column(children: [
            Text(t, style: const TextStyle(color: kSoft)),
            Text(f(v),
                style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900)),
          ]),
        ),
      );

  Widget goal(int target) {
    final done = g.total >= target;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
      padding: const EdgeInsets.all(14),
      decoration:
          BoxDecoration(color: kCard, borderRadius: BorderRadius.circular(14)),
      child: Row(children: [
        Icon(Icons.emoji_events,
            color: done ? const Color(0xFFFFC21A) : Colors.white38),
        const SizedBox(width: 12),
        Expanded(child: Text('${f(target)} كبسة')),
        Text(done ? 'مفتوح' : 'مقفل',
            style: TextStyle(color: done ? kLime : kSoft)),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListView(children: [
      const SizedBox(height: 24),
      Center(
        child: SizedBox(
          width: 190,
          height: 190,
          child: Stack(alignment: Alignment.center, children: [
            SizedBox.expand(
                child: CircularProgressIndicator(
                    value: g.prog,
                    strokeWidth: 12,
                    color: kLime,
                    backgroundColor: kCard)),
            Column(mainAxisSize: MainAxisSize.min, children: [
              Text('المستوى ${g.level}',
                  style: const TextStyle(
                      fontSize: 24, fontWeight: FontWeight.w900)),
              Text('${f(g.total % 2000)} / 2,000',
                  style: const TextStyle(color: kSoft)),
            ]),
          ]),
        ),
      ),
      const SizedBox(height: 16),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10),
        child: Row(children: [stat('الأفضل', g.best), stat('اليوم', g.today)]),
      ),
      goal(1000),
      goal(10000),
      goal(100000),
    ]);
  }
}
