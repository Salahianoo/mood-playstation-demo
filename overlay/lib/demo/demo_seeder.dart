import 'dart:math';

import 'package:uuid/uuid.dart';

import '../core/constants/app_constants.dart';
import '../core/services/hive_service.dart';
import '../features/cafe/data/cafe_repository.dart';
import '../features/cafe/models/cafe_order_model.dart';
import '../features/cafe/models/cafe_table_model.dart';
import '../features/checkout/models/payment_method.dart';
import '../features/inventory/data/inventory_repository.dart';
import '../features/inventory/models/inventory_item_model.dart';
import '../features/pos/models/pos_item_model.dart';
import '../features/rooms/data/room_repository.dart';
import '../features/rooms/models/room_booking_model.dart';
import '../features/rooms/models/room_model.dart';
import '../features/rooms/models/session_model.dart';
import '../features/shift/data/drawer_float_repository.dart';
import '../features/shift/data/expense_repository.dart';
import '../features/shift/data/shift_archive_repository.dart';
import '../features/shift/data/shift_closure_repository.dart';
import '../features/shift/data/shift_repository.dart';
import '../features/shift/data/staff_withdrawal_repository.dart';
import '../features/shift/models/archived_shift_record.dart';
import '../features/shift/models/expense_model.dart';
import '../features/shift/models/shift_closure_record.dart';
import '../features/shift/models/shift_record_model.dart';
import '../features/shift/models/staff_withdrawal_model.dart';
import 'demo_mode.dart';

const _uuid = Uuid();

/// Fills every Hive box with a busy, believable lounge for the web
/// portfolio demo: rooms mid-session in every state, open cafe tabs, a
/// shift in progress and ~45 days of closed shifts behind it.
///
/// All timestamps are relative to the moment of seeding, so the demo is
/// re-seeded once it goes stale (a returning visitor would otherwise find
/// sessions that have been running for days) or when the page is opened
/// with `?reset`. Past history comes from a fixed-seed [Random], so every
/// visitor sees the same books.
class DemoSeeder {
  DemoSeeder._();

  static const _seededAtKey = 'demoSeededAt';
  static const _freshFor = Duration(hours: 3);
  static const _firstBillNumber = 1000;
  static const _drawerFloat = 20.0;

  static Future<void> seedIfNeeded() async {
    if (!kDemoMode) return;

    final raw = HiveService.countersBox.get(_seededAtKey) as String?;
    final seededAt = raw == null ? null : DateTime.tryParse(raw);
    final now = DateTime.now();
    final stale = seededAt == null || now.difference(seededAt) > _freshFor;
    final forced = Uri.base.queryParameters.containsKey('reset');
    if (!stale && !forced) return;

    for (final box in [
      HiveService.roomsBox,
      HiveService.historyBox,
      HiveService.inventoryBox,
      HiveService.cafeBox,
      HiveService.categoriesBox,
      HiveService.shiftArchiveBox,
      HiveService.expensesBox,
      HiveService.countersBox,
      HiveService.shiftClosuresBox,
      HiveService.drawerFloatBox,
      HiveService.staffWithdrawalsBox,
    ]) {
      await box.clear();
    }

    await _seedInventory();
    await _seedRooms(now);
    await _seedCafe(now);
    final lastBillNumber = await _seedShifts(now);

    await HiveService.countersBox.put('nextBillNumber', lastBillNumber);
    await HiveService.countersBox.put(_seededAtKey, now.toIso8601String());
  }

  // ── Catalog ──────────────────────────────────────────────────────────

  /// The seeded lounge menu, with stock already drawn down by the day's
  /// trade — including one low and one sold-out product.
  static const _menu = <InventoryItemModel>[
    InventoryItemModel(id: 'inv_water', name: 'ماء', category: 'مشروبات', costPrice: 0.2, price: 0.5, stockQty: 34),
    InventoryItemModel(id: 'inv_pepsi', name: 'بيبسي', category: 'مشروبات', costPrice: 0.5, price: 1.0, stockQty: 21),
    InventoryItemModel(id: 'inv_redbull', name: 'ريد بول', category: 'مشروبات', costPrice: 1.5, price: 2.5, stockQty: 4),
    InventoryItemModel(id: 'inv_turkish_coffee', name: 'قهوة تركية', category: 'مشروبات', costPrice: 0.5, price: 1.5, stockQty: 16),
    InventoryItemModel(id: 'inv_nescafe', name: 'نسكافيه', category: 'مشروبات', costPrice: 0.6, price: 1.5, stockQty: 13),
    InventoryItemModel(id: 'inv_tea', name: 'شاي', category: 'مشروبات', costPrice: 0.3, price: 1.0, stockQty: 18),
    InventoryItemModel(id: 'inv_chips', name: 'شيبس', category: 'وجبات خفيفة', costPrice: 0.5, price: 1.0, stockQty: 19),
    InventoryItemModel(id: 'inv_chocolate', name: 'شوكولاتة', category: 'وجبات خفيفة', costPrice: 0.5, price: 1.0, stockQty: 3),
    InventoryItemModel(id: 'inv_nuts', name: 'مكسرات', category: 'وجبات خفيفة', costPrice: 0.8, price: 1.5, stockQty: 0),
    InventoryItemModel(id: 'inv_indomie', name: 'إندومي', category: 'وجبات خفيفة', costPrice: 0.4, price: 1.25, stockQty: 22),
    InventoryItemModel(id: 'inv_shisha_single', name: 'شيشة مفردة', category: 'شيشة', costPrice: 2.0, price: 4.0, stockQty: 11),
    InventoryItemModel(id: 'inv_shisha_double', name: 'شيشة مزدوجة', category: 'شيشة', costPrice: 3.5, price: 7.0, stockQty: 6),
  ];

  /// Products a random past bill can draw from — drinks weighted up,
  /// since that's most of what a lounge actually sells.
  static const _salesMix = [
    'inv_water', 'inv_water', 'inv_pepsi', 'inv_pepsi', 'inv_pepsi',
    'inv_redbull', 'inv_turkish_coffee', 'inv_nescafe', 'inv_tea', 'inv_tea',
    'inv_chips', 'inv_chips', 'inv_chocolate', 'inv_nuts', 'inv_indomie',
    'inv_shisha_single', 'inv_shisha_double',
  ];

  static const _employees = ['أحمد', 'يزن', 'محمد', 'عمر'];

  static Future<void> _seedInventory() async {
    final repo = InventoryRepository(HiveService.inventoryBox);
    for (final item in _menu) {
      await repo.save(item);
    }
  }

  static PosItemModel _line(String productId, int quantity, DateTime at) {
    final product = _menu.firstWhere((p) => p.id == productId);
    return PosItemModel(
      id: _uuid.v4(),
      name: product.name,
      price: product.price,
      quantity: quantity,
      addedAt: at,
      productId: product.id,
      costPrice: product.costPrice,
    );
  }

  // ── Live floor ───────────────────────────────────────────────────────

  /// One room per status, so the grid shows the whole state machine at a
  /// glance — and غرفة 2's prepaid hour runs out a few minutes after the
  /// visitor arrives, firing the real expiry alarm.
  static Future<void> _seedRooms(DateTime now) async {
    final repo = RoomRepository(HiveService.roomsBox);
    DateTime ago(int minutes) => now.subtract(Duration(minutes: minutes));

    RoomModel room(
      int index,
      String name, {
      double rate = AppConstants.defaultHourlyRateJod,
      SessionModel? session,
      RoomBookingModel? booking,
    }) {
      final slot = RoomRepository.gridSlotFor(index);
      return RoomModel(
        id: 'room_${index + 1}',
        name: name,
        hourlyRate: rate,
        posX: slot.posX,
        posY: slot.posY,
        width: AppConstants.floorPlanCellWidth,
        height: AppConstants.floorPlanCellHeight,
        session: session,
        booking: booking,
        sortOrder: index,
      );
    }

    final nextSlot = DateTime(now.year, now.month, now.day, now.hour)
        .add(const Duration(hours: 2));

    final rooms = [
      room(0, 'غرفة 1', session: SessionModel(
        id: _uuid.v4(),
        startTime: ago(72),
        timerStartedAt: ago(72),
        items: [_line('inv_pepsi', 2, ago(60)), _line('inv_chips', 1, ago(35))],
      )),
      room(1, 'غرفة 2', session: SessionModel(
        id: _uuid.v4(),
        startTime: ago(56),
        timerStartedAt: ago(56),
        plannedMinutes: 60,
        items: [_line('inv_water', 2, ago(50))],
      )),
      room(2, 'غرفة 3', session: SessionModel(
        id: _uuid.v4(),
        startTime: ago(7),
        items: [_line('inv_turkish_coffee', 1, ago(5))],
      )),
      room(3, 'غرفة 4', session: SessionModel(
        id: _uuid.v4(),
        startTime: ago(41),
        timerStartedAt: ago(41),
        pausedAt: ago(4),
        items: [_line('inv_tea', 2, ago(30))],
      )),
      room(4, 'غرفة 5', booking: RoomBookingModel(
        id: _uuid.v4(),
        bookedFor: nextSlot,
        customerName: 'أبو خالد',
        plannedMinutes: 120,
        createdAt: ago(90),
      )),
      room(5, 'غرفة 6'),
      // Moved here from غرفة 6 after 35 minutes, four controllers the
      // whole way: the earlier segment is frozen at 3.5 + 1.0 JOD/h.
      room(6, 'VIP 1', rate: 5.0, session: SessionModel(
        id: _uuid.v4(),
        startTime: ago(125),
        timerStartedAt: ago(90),
        controllerCount: 4,
        carriedElapsed: const Duration(minutes: 35),
        carriedTimeCost: _round3(35 / 60 * 4.5),
        items: [
          _line('inv_shisha_double', 1, ago(110)),
          _line('inv_redbull', 3, ago(70)),
        ],
      )),
      room(7, 'VIP 2', rate: 5.0),
    ];

    for (final r in rooms) {
      await repo.save(r);
    }
  }

  static Future<void> _seedCafe(DateTime now) async {
    final repo = CafeRepository(HiveService.cafeBox);
    DateTime ago(int minutes) => now.subtract(Duration(minutes: minutes));

    CafeOrderModel order(int openedMinutesAgo, List<PosItemModel> items) =>
        CafeOrderModel(id: _uuid.v4(), openedAt: ago(openedMinutesAgo), items: items);

    final tables = [
      const CafeTableModel(id: 'table_1', name: 'طاولة 1'),
      CafeTableModel(id: 'table_2', name: 'طاولة 2', order: order(26, [
        _line('inv_nescafe', 2, ago(24)),
        _line('inv_chocolate', 1, ago(15)),
      ])),
      const CafeTableModel(id: 'table_3', name: 'طاولة 3', seats: 2),
      CafeTableModel(id: 'table_4', name: 'طاولة 4', seats: 6, order: order(9, [
        _line('inv_turkish_coffee', 2, ago(8)),
      ])),
      CafeTableModel(id: 'table_5', name: 'طاولة 5', order: order(48, [
        _line('inv_shisha_single', 1, ago(45)),
        _line('inv_tea', 3, ago(40)),
        _line('inv_water', 1, ago(20)),
      ])),
      const CafeTableModel(id: 'table_6', name: 'طاولة 6', seats: 2),
    ];

    for (final t in tables) {
      await repo.save(t);
    }
  }

  // ── Books ────────────────────────────────────────────────────────────

  /// Writes ~45 closed shifts (one a day), the current open shift, and
  /// the 48-hour archive. Returns the last bill number handed out, so the
  /// live app's own numbering carries straight on from it.
  static Future<int> _seedShifts(DateTime now) async {
    final rng = Random(2023);
    final currentShiftStart =
        now.subtract(const Duration(hours: 6, minutes: 10));
    var billNumber = _firstBillNumber;

    final closures = ShiftClosureRepository(HiveService.shiftClosuresBox);
    final archive = ShiftArchiveRepository(HiveService.shiftArchiveBox);
    final withdrawals = StaffWithdrawalRepository(HiveService.staffWithdrawalsBox);

    // Oldest first, so bill numbers climb forward through time.
    for (var daysBack = 44; daysBack >= 0; daysBack--) {
      final closedAt = currentShiftStart.subtract(Duration(days: daysBack));
      final opened = closedAt.subtract(const Duration(hours: 13));
      // Thursday and Friday nights are the busy ones.
      final weekend = closedAt.weekday == DateTime.thursday ||
          closedAt.weekday == DateTime.friday;
      final count = 14 + rng.nextInt(12) + (weekend ? 8 : 0);

      final bills = _numbered(
        [for (var i = 0; i < count; i++) _randomBill(rng, opened, closedAt)],
        billNumber,
      );
      billNumber += bills.length;

      var withdrawalsTotal = 0.0;
      if (rng.nextDouble() < 0.35) {
        final amount = (1 + rng.nextInt(2)) * 5.0;
        withdrawalsTotal = amount;
        await withdrawals.add(StaffWithdrawalModel(
          id: _uuid.v4(),
          employeeName: _employees[rng.nextInt(_employees.length)],
          amount: amount,
          note: 'سلفة',
          withdrawnAt: opened.add(Duration(hours: 2 + rng.nextInt(9))),
        ));
      }

      final expensesTotal = _round3(rng.nextInt(5) * 0.75);
      final billsTotal = bills.fold(0.0, (sum, b) => sum + b.total);
      final cogs = bills.fold(0.0, (sum, b) => sum + b.itemsCogs);
      final totalCash = billsTotal + _drawerFloat - withdrawalsTotal;

      await closures.add(ShiftClosureRecord(
        id: _uuid.v4(),
        closedAt: closedAt,
        totalCash: _round3(max(0, totalCash)),
        expensesTotal: expensesTotal,
        netProfit: _round3(billsTotal - withdrawalsTotal - cogs - expensesTotal),
        sessionsCount: bills.length,
        drawerFloat: _drawerFloat,
        withdrawalsTotal: withdrawalsTotal,
        bills: bills,
      ));

      // The last two closes are still inside the 48-hour lookback.
      if (daysBack <= 1) {
        await archive.addAll(
          bills.map((b) => ArchivedShiftRecord(record: b, archivedAt: closedAt)),
        );
      }
    }

    // The shift that's open right now.
    const methods = [
      PaymentMethod.cash, PaymentMethod.visa, PaymentMethod.cash,
      PaymentMethod.cliq, PaymentMethod.cash, PaymentMethod.cash,
      PaymentMethod.visa, PaymentMethod.cash, PaymentMethod.cliq,
    ];
    final liveEnd = now.subtract(const Duration(minutes: 6));
    final current = _numbered(
      [
        for (final method in methods)
          _randomBill(rng, currentShiftStart, liveEnd, paymentMethod: method),
      ],
      billNumber,
    );
    billNumber += current.length;

    final shift = ShiftRepository(HiveService.historyBox);
    for (final bill in current) {
      await shift.add(bill);
    }

    final expenses = ExpenseRepository(HiveService.expensesBox);
    await expenses.add(ExpenseModel(
      id: _uuid.v4(),
      description: 'صابون ومعقم',
      amount: 1.25,
      addedAt: now.subtract(const Duration(hours: 4)),
    ));
    await expenses.add(ExpenseModel(
      id: _uuid.v4(),
      description: 'ورق تواليت',
      amount: 2.0,
      addedAt: now.subtract(const Duration(hours: 2)),
    ));

    await DrawerFloatRepository(HiveService.drawerFloatBox).set(_drawerFloat);

    await withdrawals.add(StaffWithdrawalModel(
      id: _uuid.v4(),
      employeeName: 'أحمد',
      amount: 5.0,
      note: 'سلفة',
      withdrawnAt: now.subtract(const Duration(hours: 3)),
    ));

    return billNumber - 1;
  }

  /// A plausible closed bill ending somewhere inside [from]..[to]: about
  /// two thirds PS5 sessions (some VIP, some with extra controllers), the
  /// rest cafe tabs.
  static ShiftRecordModel _randomBill(
    Random rng,
    DateTime from,
    DateTime to, {
    PaymentMethod? paymentMethod,
  }) {
    final span = to.difference(from).inMinutes;
    final end = from.add(Duration(minutes: 20 + rng.nextInt(max(1, span - 20))));
    final gaming = rng.nextDouble() < 0.66;

    final int minutes;
    final double timeCost;
    final String name;
    final List<PosItemModel> items;
    if (gaming) {
      final vip = rng.nextDouble() < 0.22;
      final controllers = rng.nextDouble() < 0.18 ? 3 + rng.nextInt(2) : 2;
      final rate = (vip ? 5.0 : AppConstants.defaultHourlyRateJod) +
          (controllers - 2) * 0.5;
      minutes = 40 + rng.nextInt(170);
      timeCost = _round3(minutes / 60 * rate);
      name = vip ? 'VIP ${1 + rng.nextInt(2)}' : 'غرفة ${1 + rng.nextInt(6)}';
      items = _randomItems(rng, end, rng.nextInt(4));
    } else {
      minutes = 15 + rng.nextInt(80);
      timeCost = 0;
      name = 'طاولة ${1 + rng.nextInt(6)}';
      items = _randomItems(rng, end, 1 + rng.nextInt(4));
    }

    final itemsCost = _round3(items.fold(0.0, (sum, i) => sum + i.subtotal));
    final discount = rng.nextDouble() < 0.08
        ? _round3((timeCost + itemsCost) * 0.1)
        : 0.0;
    final roll = rng.nextDouble();

    return ShiftRecordModel(
      id: _uuid.v4(),
      billNumber: 0,
      roomName: name,
      startTime: end.subtract(Duration(minutes: minutes)),
      endTime: end,
      timeCost: timeCost,
      itemsCost: itemsCost,
      itemsCogs: _round3(items.fold(0.0, (sum, i) => sum + i.costSubtotal)),
      discountAmount: discount,
      source: gaming ? ShiftSource.gaming : ShiftSource.cafe,
      items: items,
      paymentMethod: paymentMethod ??
          (roll < 0.58
              ? PaymentMethod.cash
              : roll < 0.83
                  ? PaymentMethod.visa
                  : PaymentMethod.cliq),
    );
  }

  static List<PosItemModel> _randomItems(Random rng, DateTime at, int lines) {
    final picked = <String>{};
    while (picked.length < lines) {
      picked.add(_salesMix[rng.nextInt(_salesMix.length)]);
    }
    return [
      for (final id in picked)
        _line(id, id.startsWith('inv_shisha') ? 1 : 1 + rng.nextInt(3), at),
    ];
  }

  /// Orders bills by when they ended and numbers them from [first] — the
  /// same order the live [BillNumberSequence] would have issued them in.
  static List<ShiftRecordModel> _numbered(
    List<ShiftRecordModel> bills,
    int first,
  ) {
    bills.sort((a, b) => a.endTime.compareTo(b.endTime));
    return [
      for (var i = 0; i < bills.length; i++)
        ShiftRecordModel.fromMap({...bills[i].toMap(), 'billNumber': first + i}),
    ];
  }

  static double _round3(num value) => double.parse(value.toStringAsFixed(3));
}
