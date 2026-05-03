/// LECO Domestic Block Tariff Calculator
/// Revised tariff effective from 12 June 2025
///
/// Block 01:   0 -  60 units  → Rs 12.75/unit
/// Block 02:  61 -  90 units  → Rs 18.50/unit
/// Block 03:  91 - 120 units  → Rs 24.00/unit
/// Block 04: 121 - 180 units  → Rs 41.00/unit
/// Block 05: 181 -1000 units  → Rs 61.00/unit

class LecoTariffService {
  static const List<_TariffBlock> _blocks = [
    _TariffBlock(60, 12.75),   // 0-60
    _TariffBlock(30, 18.50),   // 61-90
    _TariffBlock(30, 24.00),   // 91-120
    _TariffBlock(60, 41.00),   // 121-180
    _TariffBlock(820, 61.00),  // 181-1000
  ];

  /// Calculate monthly electricity bill for given kWh units.
  static LecoTariffResult calculateMonthlyBill(double monthlyUnits) {
    double remaining = monthlyUnits < 0 ? 0 : monthlyUnits;
    double totalBill = 0;
    final breakdown = <TariffBlockResult>[];
    int cumulative = 0;

    for (final block in _blocks) {
      final unitsInBlock =
          remaining > block.size ? block.size.toDouble() : remaining;
      if (unitsInBlock <= 0) break;

      final cost = unitsInBlock * block.rate;
      totalBill += cost;
      remaining -= unitsInBlock;

      breakdown.add(TariffBlockResult(
        blockRange: '${cumulative + 1}-${cumulative + block.size}',
        units: unitsInBlock,
        rate: block.rate,
        cost: cost,
      ));
      cumulative += block.size;
    }

    final effectiveRate = monthlyUnits > 0 ? totalBill / monthlyUnits : 0.0;

    return LecoTariffResult(
      monthlyUnits: monthlyUnits,
      totalBillLkr: totalBill,
      effectiveRatePerKwh: effectiveRate,
      breakdown: breakdown,
    );
  }

  /// Calculate bill from weekly kWh by projecting to monthly.
  static LecoTariffResult calculateFromWeeklyKwh(double weeklyKwh) {
    return calculateMonthlyBill(weeklyKwh * 30.0 / 7.0);
  }

  /// Get the weekly cost from monthly bill.
  static double weeklyFromMonthlyBill(double monthlyBill) {
    return monthlyBill * 7.0 / 30.0;
  }
}

class _TariffBlock {
  final int size;
  final double rate;
  const _TariffBlock(this.size, this.rate);
}

class TariffBlockResult {
  final String blockRange;
  final double units;
  final double rate;
  final double cost;

  const TariffBlockResult({
    required this.blockRange,
    required this.units,
    required this.rate,
    required this.cost,
  });
}

class LecoTariffResult {
  final double monthlyUnits;
  final double totalBillLkr;
  final double effectiveRatePerKwh;
  final List<TariffBlockResult> breakdown;

  const LecoTariffResult({
    required this.monthlyUnits,
    required this.totalBillLkr,
    required this.effectiveRatePerKwh,
    required this.breakdown,
  });
}
