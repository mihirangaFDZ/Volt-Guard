import 'package:flutter/material.dart';
import 'package:volt_guard/pages/zone_details_page.dart';
import 'package:volt_guard/services/zones_service.dart';

/// Smart Zone Energy Manager - Main page for zone management
/// Perfect for managing multiple rooms/spaces in an institution
class ZonesPage extends StatefulWidget {
  const ZonesPage({super.key});

  @override
  State<ZonesPage> createState() => _ZonesPageState();
}

class _ZonesPageState extends State<ZonesPage> {
  // Mock data - replace with actual API calls
  late List<ZoneData> zones;
  bool _isLoading = false;
  bool _showAddZone = false;
  String _search = "";
  bool _onlyAlerts = false;
  bool _onlyOccupied = false;
  bool _onlyNonCompliant = false;
  String _sort = "efficiency";
  final ZonesService _zonesService = ZonesService();

  @override
  void initState() {
    super.initState();
    zones = [];
    _loadZones();
  }

  Future<void> _loadZones() async {
    setState(() => _isLoading = true);
    try {
      final list = await _zonesService.fetchZoneSummaries();
      zones = list.map((e) => ZoneData.fromApi(e)).toList();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load zones: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  double get totalPowerUsage => zones.fold(0, (sum, zone) => sum + zone.currentPower);
  double get totalMonthlyCost => zones.fold(0, (sum, zone) => sum + zone.monthlyCost);
  double get totalMonthlyBudget => zones.fold(0, (sum, zone) => sum + (zone.monthlyBudget ?? 0));
  int get occupiedZones => zones.where((z) => z.occupancy == "occupied").length;
  List<ZoneData> get _bestZones => [...zones]..sort((a, b) => b.efficiencyScore.compareTo(a.efficiencyScore));
  List<ZoneData> get _attentionZones => [...zones]..sort((a, b) => a.efficiencyScore.compareTo(b.efficiencyScore));
  List<ZoneData> get _wasteLeaders => [...zones]
    ..sort((a, b) => b.wasteBreakdown.fold<double>(0, (s, w) => s + w.wastedKwh).compareTo(
          a.wasteBreakdown.fold<double>(0, (s, w) => s + w.wastedKwh),
        ));
  double get totalAvoidedKwh => zones.fold(0, (sum, z) => sum + z.avoidedKwh);
  double get totalAvoidedCost => zones.fold(0, (sum, z) => sum + z.avoidedCost);
  double get totalCarbonSaved => zones.fold(0, (sum, z) => sum + z.carbonSavedKg);

  List<ZoneData> get _filteredZones {
    final query = _search.toLowerCase();
    final list = zones.where((z) {
      final matchesSearch = query.isEmpty || z.name.toLowerCase().contains(query) || z.type.toLowerCase().contains(query);
      final matchesAlerts = !_onlyAlerts || z.alerts.isNotEmpty;
      final matchesOccupied = !_onlyOccupied || z.occupancy == "occupied";
      final matchesCompliance = !_onlyNonCompliant || z.recommendationCompliance < 0.8;
      return matchesSearch && matchesAlerts && matchesOccupied && matchesCompliance;
    }).toList();

    list.sort((a, b) {
      switch (_sort) {
        case "efficiency":
          return b.efficiencyScore.compareTo(a.efficiencyScore);
        case "waste":
          final wa = a.wasteBreakdown.fold<double>(0, (s, w) => s + w.wastedKwh);
          final wb = b.wasteBreakdown.fold<double>(0, (s, w) => s + w.wastedKwh);
          return wb.compareTo(wa);
        case "peak":
          return b.peakDemandKw.compareTo(a.peakDemandKw);
        default:
          return a.name.compareTo(b.name);
      }
    });
    return list;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F9F9),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: const Text("Zone Manager", style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_circle_outline),
            color: const Color(0xFF4A90E2),
            onPressed: () => _showAddZoneDialog(),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadZones,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                child: zones.isEmpty
                    ? _buildEmptyState()
                    : Column(
                        children: [
                          _buildSummarySection(),
                          const SizedBox(height: 24),
                          _buildQuickActionsSection(),
                          const SizedBox(height: 24),
                          _buildHighlightsSection(),
                          const SizedBox(height: 24),
                          _buildPerformanceSection(),
                          const SizedBox(height: 24),
                          _buildControlBar(),
                          const SizedBox(height: 16),
                          _buildZonesListSection(),
                        ],
                      ),
              ),
            ),
    );
  }

  Widget _buildEmptyState() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 80),
      alignment: Alignment.center,
      child: Column(
        children: const [
          Icon(Icons.meeting_room, size: 48, color: Colors.grey),
          SizedBox(height: 12),
          Text("No zones found", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          SizedBox(height: 6),
          Text("Pull to refresh or add a zone", style: TextStyle(color: Colors.grey)),
        ],
      ),
    );
  }

  Widget _buildSummarySection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          "Energy Overview",
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _buildStatCard(
                icon: Icons.bolt,
                title: "Total Power",
                value: "${(totalPowerUsage / 1000).toStringAsFixed(2)} kW",
                color: const Color(0xFFFBBF24),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildStatCard(
                icon: Icons.attach_money,
                title: "Monthly Cost",
                value: "₹${totalMonthlyCost.toStringAsFixed(0)}",
                color: const Color(0xFF00C853),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _buildStatCard(
                icon: Icons.people,
                title: "Occupied Zones",
                value: "$occupiedZones/${zones.length}",
                color: const Color(0xFF4A90E2),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildStatCard(
                icon: Icons.devices,
                title: "Total Devices",
                value: "${zones.fold<int>(0, (sum, z) => sum + z.deviceCount)}",
                color: const Color(0xFFE91E63),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildStatCard({
    required IconData icon,
    required String title,
    required String value,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(height: 8),
          Text(
            title,
            style: TextStyle(fontSize: 12, color: Colors.grey[600]),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickActionsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          "Quick Actions",
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _buildActionButton(
                icon: Icons.power_settings_new,
                label: "All Off",
                color: const Color(0xFFEF5350),
                onPressed: () => _showActionSnackbar("All devices turned OFF"),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildActionButton(
                icon: Icons.power,
                label: "All On",
                color: const Color(0xFF4CAF50),
                onPressed: () => _showActionSnackbar("All devices turned ON"),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildActionButton(
                icon: Icons.eco,
                label: "Power Saver",
                color: const Color(0xFF2196F3),
                onPressed: () => _showActionSnackbar("Power Saver mode activated"),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onPressed,
  }) {
    return ElevatedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 18),
      label: Text(label, style: const TextStyle(fontSize: 12)),
      style: ElevatedButton.styleFrom(
        backgroundColor: color,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }

  Widget _buildControlBar() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          decoration: InputDecoration(
            hintText: "Search rooms or types",
            prefixIcon: const Icon(Icons.search),
            filled: true,
            fillColor: Colors.white,
            contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 12),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
          ),
          onChanged: (v) => setState(() => _search = v),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            FilterChip(
              label: const Text("Has alerts"),
              selected: _onlyAlerts,
              onSelected: (v) => setState(() => _onlyAlerts = v),
            ),
            FilterChip(
              label: const Text("Occupied"),
              selected: _onlyOccupied,
              onSelected: (v) => setState(() => _onlyOccupied = v),
            ),
            FilterChip(
              label: const Text("Non-compliant"),
              selected: _onlyNonCompliant,
              onSelected: (v) => setState(() => _onlyNonCompliant = v),
            ),
            DropdownButton<String>(
              value: _sort,
              items: const [
                DropdownMenuItem(value: "efficiency", child: Text("Sort: Efficiency")),
                DropdownMenuItem(value: "waste", child: Text("Sort: Waste")),
                DropdownMenuItem(value: "peak", child: Text("Sort: Peak")),
                DropdownMenuItem(value: "name", child: Text("Sort: Name")),
              ],
              onChanged: (v) => setState(() => _sort = v ?? "efficiency"),
              underline: const SizedBox.shrink(),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildHighlightsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          "Advanced Performance Analytics",
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 16),
        // Top performers ranked view
        _buildPerformanceRanking(),
        const SizedBox(height: 20),
        // Efficiency distribution
        _buildEfficiencyDistribution(),
      ],
    );
  }

  Widget _buildPerformanceRanking() {
    final ranked = [...zones]..sort((a, b) => b.efficiencyScore.compareTo(a.efficiencyScore));
    
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text("Efficiency Ranking", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
          const SizedBox(height: 12),
          ...List.generate(
            ranked.length,
            (idx) => _buildRankingRow(ranked[idx], idx + 1),
          ),
        ],
      ),
    );
  }

  Widget _buildRankingRow(ZoneData zone, int rank) {
    final color = rank == 1
        ? const Color(0xFFFFD700)
        : rank == 2
            ? const Color(0xFFC0C0C0)
            : rank == 3
                ? const Color(0xFFCD7F32)
                : Colors.grey[300];

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            child: Center(
              child: Text(
                "#$rank",
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(zone.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                Text("${zone.type} • Floor ${zone.floor}", style: TextStyle(fontSize: 11, color: Colors.grey[600])),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text("${zone.efficiencyScore.toStringAsFixed(0)}", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
              Text("efficiency", style: TextStyle(fontSize: 10, color: Colors.grey[600])),
            ],
          ),
          const SizedBox(width: 16),
          Container(
            width: 60,
            height: 6,
            decoration: BoxDecoration(
              color: Colors.grey[200],
              borderRadius: BorderRadius.circular(3),
            ),
            child: Stack(
              children: [
                Container(
                  width: 60 * (zone.efficiencyScore / 100),
                  height: 6,
                  decoration: BoxDecoration(
                    color: zone.efficiencyScore >= 80
                        ? const Color(0xFF4CAF50)
                        : zone.efficiencyScore >= 60
                            ? const Color(0xFFFBBF24)
                            : const Color(0xFFEF5350),
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEfficiencyDistribution() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text("Performance Distribution", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildDistributionMetric(
                label: "Excellent (80+)",
                count: zones.where((z) => z.efficiencyScore >= 80).length,
                color: const Color(0xFF4CAF50),
              ),
              _buildDistributionMetric(
                label: "Good (60-79)",
                count: zones.where((z) => z.efficiencyScore >= 60 && z.efficiencyScore < 80).length,
                color: const Color(0xFFFBBF24),
              ),
              _buildDistributionMetric(
                label: "Fair (40-59)",
                count: zones.where((z) => z.efficiencyScore >= 40 && z.efficiencyScore < 60).length,
                color: const Color(0xFFF97316),
              ),
              _buildDistributionMetric(
                label: "Poor (<40)",
                count: zones.where((z) => z.efficiencyScore < 40).length,
                color: const Color(0xFFEF5350),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDistributionMetric({
    required String label,
    required int count,
    required Color color,
  }) {
    return Column(
      children: [
        Container(
          width: 50,
          height: 50,
          decoration: BoxDecoration(color: color.withOpacity(0.2), shape: BoxShape.circle),
          child: Center(
            child: Text(
              count.toString(),
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: color),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(label, style: TextStyle(fontSize: 11, color: Colors.grey[700]), textAlign: TextAlign.center),
      ],
    );
  }



  Widget _buildPerformanceSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          "Detailed Room Performance Analysis",
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 16),
        // What happened - key events and changes
        _buildWhatHappened(),
        const SizedBox(height: 20),
        // Why it happened - root cause analysis
        _buildWhyItHappened(),
        const SizedBox(height: 20),
        // Energy waste breakdown
        _buildWasteBreakdown(),
        const SizedBox(height: 20),
        // Recommendations
        _buildDetailedRecommendations(),
      ],
    );
  }

  Widget _buildWhatHappened() {
    final topSaver = _bestZones.first;
    final topWaste = _wasteLeaders.first;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFFE3F2FD),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.history, color: Color(0xFF2196F3), size: 20),
              ),
              const SizedBox(width: 10),
              const Text("What Happened (Today's Summary)", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
            ],
          ),
          const SizedBox(height: 14),
          _buildEventCard(
            "✓ Best Performer",
            "${topSaver.name} achieved ${topSaver.efficiencyScore.toStringAsFixed(0)} efficiency with ${topSaver.avoidedKwh.toStringAsFixed(1)} kWh saved",
            const Color(0xFF4CAF50),
          ),
          const SizedBox(height: 10),
          _buildEventCard(
            "⚠ Highest Waste",
            "${topWaste.name} recorded ${topWaste.wasteBreakdown.fold<double>(0, (s, w) => s + w.wastedKwh).toStringAsFixed(1)} kWh wasted - main issue: ${topWaste.wasteBreakdown.isNotEmpty ? topWaste.wasteBreakdown.first.cause : 'untracked'}",
            const Color(0xFFEF5350),
          ),
          const SizedBox(height: 10),
          _buildEventCard(
            "📊 System Total",
            "${zones.length} rooms monitored • ${(totalPowerUsage / 1000).toStringAsFixed(2)} kW current load • ₹${totalMonthlyCost.toStringAsFixed(0)} monthly cost",
            const Color(0xFF9C27B0),
          ),
        ],
      ),
    );
  }

  Widget _buildEventCard(String title, String detail, Color color) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 3,
            height: 60,
            decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: TextStyle(fontWeight: FontWeight.bold, color: color, fontSize: 12)),
                const SizedBox(height: 4),
                Text(detail, style: TextStyle(fontSize: 12, color: Colors.grey[700])),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWhyItHappened() {
    final topWaste = _wasteLeaders.first;
    final nonCompliant = zones.where((z) => z.recommendationCompliance < 0.8).toList();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF8E1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.lightbulb, color: Color(0xFFF9A825), size: 20),
              ),
              const SizedBox(width: 10),
              const Text("Why It Happened (Root Causes)", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
            ],
          ),
          const SizedBox(height: 14),
          if (topWaste.wasteReasons.isNotEmpty)
            _buildCauseItem(
              "Equipment Waste",
              topWaste.wasteReasons.join(" • "),
              Icons.warning_amber,
              const Color(0xFFE53935),
            ),
          if (nonCompliant.isNotEmpty) ...[
            const SizedBox(height: 10),
            _buildCauseItem(
              "Non-Compliance Issues",
              "${nonCompliant.length} rooms not following energy playbooks - occupancy sensors not linked",
              Icons.rule_folder,
              const Color(0xFFF9A825),
            ),
          ],
          const SizedBox(height: 10),
          _buildCauseItem(
            "Peak Demand Spikes",
            "High concentration of load between 12:00-15:00; AC + computers running simultaneously",
            Icons.trending_up,
            const Color(0xFF2196F3),
          ),
        ],
      ),
    );
  }

  Widget _buildCauseItem(String title, String description, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: TextStyle(fontWeight: FontWeight.bold, color: color, fontSize: 12)),
                const SizedBox(height: 4),
                Text(description, style: TextStyle(fontSize: 12, color: Colors.grey[700])),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWasteBreakdown() {
    final topWaste = _wasteLeaders.first;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFEBEE),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.warning, color: Color(0xFFE53935), size: 20),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text("Energy Waste Breakdown", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                    Text("Analyzing ${topWaste.name}", style: TextStyle(fontSize: 11, color: Colors.grey[600])),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (topWaste.wasteBreakdown.isEmpty)
            Text("No waste data available", style: TextStyle(color: Colors.grey[600], fontSize: 12))
          else
            Column(
              children: List.generate(
                topWaste.wasteBreakdown.length,
                (idx) {
                  final waste = topWaste.wasteBreakdown[idx];
                  final totalWaste =
                      topWaste.wasteBreakdown.fold<double>(0, (s, w) => s + w.wastedKwh);
                  final percentage = totalWaste > 0 ? (waste.wastedKwh / totalWaste * 100) : 0.0;

                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(waste.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                                  Text(waste.cause, style: TextStyle(fontSize: 11, color: Colors.grey[600])),
                                ],
                              ),
                            ),
                            Text("${waste.wastedKwh.toStringAsFixed(2)} kWh",
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Expanded(
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(4),
                                child: LinearProgressIndicator(
                                  value: percentage / 100,
                                  minHeight: 8,
                                  backgroundColor: Colors.grey[200],
                                  valueColor: AlwaysStoppedAnimation(
                                    Color.lerp(const Color(0xFF4CAF50), const Color(0xFFEF5350),
                                        percentage / 100)!,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text("${percentage.toStringAsFixed(0)}%", style: const TextStyle(fontSize: 11)),
                          ],
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildDetailedRecommendations() {
    final topSaver = _bestZones.first;
    final topWaste = _wasteLeaders.first;
    final peakRoom = [...zones]..sort((a, b) => b.peakDemandKw.compareTo(a.peakDemandKw));
    final peak = peakRoom.first;

    final wasteEquipment = topWaste.wasteBreakdown.isNotEmpty ? topWaste.wasteBreakdown.first.name : 'equipment';
    final wasteCause = topWaste.wasteBreakdown.isNotEmpty ? topWaste.wasteBreakdown.first.cause : 'Configure auto-off timers';
    final wasteImpact = topWaste.wasteBreakdown.fold<double>(0, (s, w) => s + w.wastedKwh);

    final recommendations = [
      {
        'priority': 'CRITICAL',
        'room': topWaste.name,
        'action': 'Fix $wasteEquipment',
        'detail': wasteCause,
        'impact': '${wasteImpact.toStringAsFixed(1)} kWh/month to save',
        'color': const Color(0xFFE53935),
      },
      {
        'priority': 'HIGH',
        'room': peak.name,
        'action': 'Reduce peak demand',
        'detail': 'Pre-cool 30 mins before peak; stagger load with other rooms',
        'impact': 'Peak load: ${peak.peakDemandKw.toStringAsFixed(1)} kW',
        'color': const Color(0xFFF9A825),
      },
      {
        'priority': 'MEDIUM',
        'room': topSaver.name,
        'action': 'Copy best practices',
        'detail': '${(topSaver.recommendationCompliance * 100).toStringAsFixed(0)}% compliance - replicate schedules to other rooms',
        'impact': '${topSaver.avoidedKwh.toStringAsFixed(1)} kWh already saved',
        'color': const Color(0xFF4CAF50),
      },
    ];

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFFE8F5E9),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.check_circle, color: Color(0xFF4CAF50), size: 20),
              ),
              const SizedBox(width: 10),
              const Text("Actionable Recommendations", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
            ],
          ),
          const SizedBox(height: 14),
          Column(
            children: List.generate(
              recommendations.length,
              (idx) {
                final rec = recommendations[idx];
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _buildRecommendationCard(
                    priority: rec['priority'] as String,
                    room: rec['room'] as String,
                    action: rec['action'] as String,
                    detail: rec['detail'] as String,
                    impact: rec['impact'] as String,
                    color: rec['color'] as Color,
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRecommendationCard({
    required String priority,
    required String room,
    required String action,
    required String detail,
    required String impact,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  priority,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 10, color: Colors.white),
                ),
              ),
              Text(room, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
            ],
          ),
          const SizedBox(height: 8),
          Text(action, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
          const SizedBox(height: 4),
          Text(detail, style: TextStyle(fontSize: 11, color: Colors.grey[700])),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: color.withOpacity(0.2),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(impact, style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }





  Widget _buildZonesListSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          "Zones",
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        _buildRoomTableHeader(),
        const SizedBox(height: 8),
        ListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: _filteredZones.length,
          itemBuilder: (context, index) => _buildRoomRow(_filteredZones[index]),
        ),
      ],
    );
  }

  Widget _buildRoomTableHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.grey[100],
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: const [
          Expanded(flex: 2, child: Text("Room", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
          Expanded(child: Text("Eff.", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
          Expanded(child: Text("Waste", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
          Expanded(child: Text("Peak", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
          Expanded(child: Text("Status", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
        ],
      ),
    );
  }

  Widget _buildRoomRow(ZoneData zone) {
    final wasteKwh = zone.wasteBreakdown.fold<double>(0, (s, w) => s + w.wastedKwh);
    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => ZoneDetailsPage(zone: zone)),
      ),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.grey[200]!),
        ),
        child: Row(
          children: [
            Expanded(
              flex: 2,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(zone.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                      const SizedBox(width: 6),
                      if (zone.alerts.isNotEmpty)
                        Icon(Icons.notification_important, color: Colors.red[400], size: 14),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text("${zone.type} • Floor ${zone.floor}", style: TextStyle(fontSize: 11, color: Colors.grey[600])),
                ],
              ),
            ),
            Expanded(
              child: _buildMiniStat("${zone.efficiencyScore.toStringAsFixed(0)}", "eff."),
            ),
            Expanded(
              child: _buildMiniStat("${wasteKwh.toStringAsFixed(1)} kWh", "waste"),
            ),
            Expanded(
              child: _buildMiniStat("${zone.peakDemandKw.toStringAsFixed(1)} kW", "peak"),
            ),
            Expanded(
              child: _buildStatusChips(zone),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMiniStat(String value, String label) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(value, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
        const SizedBox(height: 2),
        Text(label, style: TextStyle(fontSize: 11, color: Colors.grey[600])),
      ],
    );
  }

  Widget _buildStatusChips(ZoneData zone) {
    final chips = <String>[];
    if (zone.occupancy == "occupied") chips.add("Occupied");
    if (zone.recommendationCompliance < 0.8) chips.add("Needs compliance");
    if (zone.alerts.isNotEmpty) chips.add("Alerts");
    if (chips.isEmpty) chips.add("OK");

    return Wrap(
      spacing: 4,
      runSpacing: 2,
      children: chips
          .map(
            (c) => Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(c, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600)),
            ),
          )
          .toList(),
    );
  }

  Widget _buildZoneCard(ZoneData zone) {
    final budgetPercentage = zone.monthlyBudget != null
        ? (zone.monthlyCost / zone.monthlyBudget! * 100)
        : 0.0;
    final budgetColor = budgetPercentage > 90
        ? const Color(0xFFEF5350)
        : budgetPercentage > 75
            ? const Color(0xFFFBBF24)
            : const Color(0xFF4CAF50);

    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => ZoneDetailsPage(zone: zone),
        ),
      ),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey[200]!),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Zone Header
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      zone.name,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      "${zone.type} • Floor ${zone.floor}",
                      style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                    ),
                  ],
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: zone.occupancy == "occupied"
                        ? const Color(0xFFE8F5E9)
                        : const Color(0xFFF5F5F5),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    zone.occupancy == "occupied" ? "Occupied" : "Empty",
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: zone.occupancy == "occupied"
                          ? const Color(0xFF2E7D32)
                          : Colors.grey[600],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Energy Metrics
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _buildMetric("Power", "${(zone.currentPower / 1000).toStringAsFixed(1)} kW"),
                _buildMetric("Consumption", "${zone.monthlyConsumption.toStringAsFixed(0)} kWh"),
                _buildMetric("Cost", "₹${zone.monthlyCost.toStringAsFixed(0)}"),
                _buildMetric("Devices", "${zone.deviceCount}"),
              ],
            ),
            const SizedBox(height: 12),

            // Budget Progress
            if (zone.monthlyBudget != null)
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        "Budget: ₹${zone.monthlyBudget!.toStringAsFixed(0)}",
                        style: const TextStyle(fontSize: 12),
                      ),
                      Text(
                        "${budgetPercentage.toStringAsFixed(0)}%",
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: budgetColor,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: budgetPercentage / 100,
                      minHeight: 6,
                      backgroundColor: Colors.grey[200],
                      valueColor: AlwaysStoppedAnimation(budgetColor),
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildMetric(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          value,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: TextStyle(fontSize: 10, color: Colors.grey[600]),
        ),
      ],
    );
  }

  void _showActionSnackbar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: const Color(0xFF4A90E2),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _showAddZoneDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Add New Zone"),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                decoration: InputDecoration(
                  labelText: "Zone Name",
                  hintText: "e.g., Classroom C",
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                decoration: InputDecoration(
                  labelText: "Zone Type",
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                items: ["Classroom", "Lab", "Office", "Corridor", "Other"]
                    .map((type) => DropdownMenuItem(
                          value: type,
                          child: Text(type),
                        ))
                    .toList(),
                onChanged: (value) {},
              ),
              const SizedBox(height: 12),
              TextField(
                decoration: InputDecoration(
                  labelText: "Monthly Budget (₹)",
                  hintText: "e.g., 2000",
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                keyboardType: TextInputType.number,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            onPressed: () {
              _showActionSnackbar("Zone added successfully!");
              Navigator.pop(context);
            },
            child: const Text("Add Zone"),
          ),
        ],
      ),
    );
  }
}

class ZoneData {
  final String id;
  final String name;
  final String type;
  final int floor;
  final double area;
  final int capacity;
  final double currentPower;
  final double monthlyConsumption;
  final double monthlyCost;
  final double? monthlyBudget;
  final String occupancy;
  final int deviceCount;
  final bool isActive;
  final double efficiencyScore;
  final double recommendationCompliance;
  final List<String> savingsPlays;
  final List<String> wasteReasons;
  final List<EquipmentWasteData> wasteBreakdown;
  final double baselineKwh;
  final double actualKwh;
  final double avoidedKwh;
  final double avoidedCost;
  final double carbonSavedKg;
  final double peakDemandKw;
  final double comfortScore;
  final List<String> alerts;

  factory ZoneData.fromApi(Map<String, dynamic> json) {
    final loc = json['location']?.toString() ?? 'Unknown Zone';
    final occupancyBool = json['occupancy'] == true;
    final currentPower = (json['power_w'] is num) ? (json['power_w'] as num).toDouble() : 0.0;
    final currentKw = currentPower / 1000.0;

    return ZoneData(
      id: json['module'] != null ? '${json['module']}_$loc' : loc,
      name: loc,
      type: json['module']?.toString() ?? 'Room',
      floor: 0,
      area: 0,
      capacity: 0,
      currentPower: currentPower,
      monthlyConsumption: 0,
      monthlyCost: 0,
      monthlyBudget: null,
      occupancy: occupancyBool ? "occupied" : "empty",
      deviceCount: 0,
      isActive: true,
      efficiencyScore: occupancyBool ? 80 : 70,
      recommendationCompliance: 0.85,
      savingsPlays: const [],
      wasteReasons: const [],
      wasteBreakdown: const [],
      baselineKwh: 0,
      actualKwh: 0,
      avoidedKwh: 0,
      avoidedCost: 0,
      carbonSavedKg: 0,
      peakDemandKw: currentKw,
      comfortScore: 0,
      alerts: const [],
    );
  }

  ZoneData({
    required this.id,
    required this.name,
    required this.type,
    required this.floor,
    required this.area,
    required this.capacity,
    required this.currentPower,
    required this.monthlyConsumption,
    required this.monthlyCost,
    required this.monthlyBudget,
    required this.occupancy,
    required this.deviceCount,
    required this.isActive,
    required this.efficiencyScore,
    required this.recommendationCompliance,
    required this.savingsPlays,
    required this.wasteReasons,
    required this.wasteBreakdown,
    required this.baselineKwh,
    required this.actualKwh,
    required this.avoidedKwh,
    required this.avoidedCost,
    required this.carbonSavedKg,
    required this.peakDemandKw,
    required this.comfortScore,
    required this.alerts,
  });
}

class EquipmentWasteData {
  final String name;
  final double wastedKwh;
  final String cause;

  const EquipmentWasteData({
    required this.name,
    required this.wastedKwh,
    required this.cause,
  });
}
