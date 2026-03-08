import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/current_reading_recommendation.dart';
import '../models/energy_reading.dart';
import '../models/sensor_reading.dart';
import '../services/analytics_service.dart';
import '../services/energy_service.dart';
import '../services/optimization_service.dart';

/// Component-focused analytics page for occupancy, comfort, sensor health, and recommendations
/// using the provided IoT fields (pir/rcwl, temperature, humidity, rssi, uptime, timestamps).
class AnalyticsPage extends StatefulWidget {
  const AnalyticsPage({super.key});

  @override
  State<AnalyticsPage> createState() => _AnalyticsPageState();
}

class _AnalyticsPageState extends State<AnalyticsPage> {
  final AnalyticsService _analyticsService = AnalyticsService();
  final OptimizationService _optimizationService = OptimizationService();

  static const int _maxActiveRecs = 3;
  List<SensorReading> _readings = [];
  List<EnergyReading> _energyReadings = [];
  Map<String, dynamic>? _energyUsage;
  bool _loading = true;
  String? _error;
  List<_RecItem> _activeRecItems = [];
  List<_Recommendation> _backlogRecs = [];
  List<_CompletedEntry> _history = [];
  
  // Store original AI recommendations for detailed view
  Map<String, AIRecommendation> _aiRecDetailsMap = {};
  
  // Filter state
  String? _selectedLocation;
  String? _selectedModule;
  String? _selectedDeviceId;
  List<String> _availableLocations = [];
  List<String> _availableModules = [];
  List<Map<String, dynamic>> _availableDevices = [];
  bool _filtersLoading = false;

  // Page tab state
  _AnalyticsTab _selectedTab = _AnalyticsTab.environment;

  // Occupancy stats
  Map<String, dynamic>? _occupancyStats;

  // Auto-refresh timer for live updates (no full-page refresh)
  Timer? _autoRefreshTimer;
  static const Duration _autoRefreshInterval = Duration(seconds: 30);
  bool _initialLoadDone = false;
  DateTime? _lastUpdated;

  // AI Recommendations
  OptimizationResponse? _aiRecommendations;
  bool _loadingAIRecommendations = false;

  // Current energy recommendations from trained model (CSV dataset)
  List<CurrentReadingRecommendation>? _modelCurrentRecs;

  // Energy advice: refresh recommendations every N minutes (default 5), save to history
  static const List<int> _recommendationIntervalOptions = [1, 5, 10, 15, 30];
  int _recommendationIntervalMinutes = 5;
  Timer? _recommendationTimer;
  DateTime? _lastRecommendationSave;

  // Energy advice history (previous recommendations with readings)
  List<Map<String, dynamic>> _energyAdviceHistory = [];
  bool _loadingHistory = false;
  bool _historySectionExpanded = true;
  final Set<String> _selectedHistoryIds = {};
  DateTime? _historyFilterFrom;
  DateTime? _historyFilterTo;

  @override
  void initState() {
    super.initState();
    _loadFilters();
    _loadReadings();
    _startAutoRefresh();
    _startRecommendationRefresh();
  }

  @override
  void dispose() {
    _autoRefreshTimer?.cancel();
    _recommendationTimer?.cancel();
    super.dispose();
  }

  void _startAutoRefresh() {
    _autoRefreshTimer?.cancel();
    _autoRefreshTimer = Timer.periodic(_autoRefreshInterval, (timer) {
      if (mounted) {
        _loadReadings();
      }
    });
  }

  void _startRecommendationRefresh() {
    _recommendationTimer?.cancel();
    // First run after 15s so initial data is loaded; then every N minutes
    Future.delayed(const Duration(seconds: 15), () {
      if (mounted) _refreshRecommendationsAndSave();
    });
    _recommendationTimer = Timer.periodic(
      Duration(minutes: _recommendationIntervalMinutes),
      (_) => _refreshRecommendationsAndSave(),
    );
  }

  /// Refresh energy recommendations and save current batch to history.
  Future<void> _refreshRecommendationsAndSave() async {
    if (!mounted || _energyReadings.isEmpty) return;
    final latest = _energyReadings.first;
    final trend = _energyUsage?['trend'] as Map<String, dynamic>?;
    final signal = _energyUsage?['signal'] as Map<String, dynamic>?;
    List<CurrentReadingRecommendation> recs;
    try {
      final recMaps = await _analyticsService.fetchCurrentEnergyRecommendations(
        currentA: latest.currentA,
        currentMa: latest.currentMa,
        powerW: latest.currentA * 230.0,
        trendDirection: trend?['direction'] as String? ?? 'stable',
        trendPercentChange: (trend?['percent_change'] as num?)?.toDouble() ?? 0.0,
        signalQuality: signal?['quality'] as String? ?? 'unknown',
      );
      recs = recMaps.isNotEmpty
          ? recMaps.map((e) => CurrentReadingRecommendation.fromApiMap(e)).toList()
          : CurrentReadingRecommendation.fromReadingsAndStats(
              readings: _energyReadings,
              usageStats: _energyUsage,
            );
    } catch (_) {
      recs = CurrentReadingRecommendation.fromReadingsAndStats(
        readings: _energyReadings,
        usageStats: _energyUsage,
      );
    }
    if (!mounted) return;
    setState(() {
      _modelCurrentRecs = recs;
    });
    final snapshot = {
      'current_a': latest.currentA,
      'current_ma': latest.currentMa,
      'power_w': latest.currentA * 230.0,
      'trend_direction': trend?['direction'] ?? 'stable',
      'trend_percent_change': trend?['percent_change'] ?? 0.0,
      'signal_quality': signal?['quality'],
      'location': latest.location,
      'module': latest.module,
    };
    final recPayload = recs.map((r) {
      return {
        'title': r.title,
        'message': r.message,
        'severity': r.severity,
        'advice': r.advice,
        'mitigation': r.mitigation,
        'estimated_savings_kwh_per_day': r.estimatedSavingsKwhPerDay,
        'energy_wasted_kwh_per_day': r.energyWastedKwhPerDay,
      };
    }).toList();
    try {
      await _analyticsService.saveEnergyAdviceHistory(
        readingsSnapshot: snapshot,
        recommendations: recPayload,
      );
      if (mounted) setState(() => _lastRecommendationSave = DateTime.now());
    } catch (_) {}
    _loadEnergyAdviceHistory();
  }

  Future<void> _loadEnergyAdviceHistory() async {
    if (!mounted) return;
    setState(() => _loadingHistory = true);
    try {
      final items = await _analyticsService.fetchEnergyAdviceHistory(limit: 50);
      if (!mounted) return;
      setState(() {
        _energyAdviceHistory = items;
        _loadingHistory = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingHistory = false);
    }
  }

  List<Map<String, dynamic>> get _filteredHistory {
    if (_historyFilterFrom == null && _historyFilterTo == null) {
      return _energyAdviceHistory;
    }
    return _energyAdviceHistory.where((item) {
      final created = item['created_at'] as String?;
      if (created == null) return false;
      final dt = DateTime.tryParse(created);
      if (dt == null) return false;
      if (_historyFilterFrom != null) {
        final fromStart = DateTime(_historyFilterFrom!.year, _historyFilterFrom!.month, _historyFilterFrom!.day);
        if (dt.isBefore(fromStart)) return false;
      }
      if (_historyFilterTo != null) {
        final toEnd = DateTime(_historyFilterTo!.year, _historyFilterTo!.month, _historyFilterTo!.day, 23, 59, 59);
        if (dt.isAfter(toEnd)) return false;
      }
      return true;
    }).toList();
  }

  Future<void> _deleteSelectedHistory() async {
    if (_selectedHistoryIds.isEmpty) return;
    final ids = _selectedHistoryIds.toList();
    try {
      await _analyticsService.deleteEnergyAdviceHistory(ids);
      if (!mounted) return;
      setState(() => _selectedHistoryIds.clear());
      await _loadEnergyAdviceHistory();
    } catch (_) {}
  }

  Future<void> _reloadAllData() async {
    await _loadReadings();
  }

  Future<void> _loadFilters() async {
    try {
      final filters = await _analyticsService.fetchAvailableFilters();
      final devices = await _analyticsService.fetchDevices();
      if (!mounted) return;
      setState(() {
        _availableLocations = filters['locations'] ?? [];
        _availableModules = filters['modules'] ?? [];
        _availableDevices = devices;
      });
    } catch (e) {
      if (!mounted) return;
      // Don't show error for filters, just continue without them
    }
  }

  Future<void> _loadReadings() async {
    try {
      // Only show full-page loading on very first load; later updates are live (no refresh)
      final isInitialLoad = !_initialLoadDone;
      if (isInitialLoad) {
        setState(() {
          _loading = true;
          _error = null;
        });
      }

      // Run main analytics requests in parallel to avoid sequential timeouts (60s total)
      List<SensorReading> data = [];
      Map<String, dynamic>? occupancyStats;
      Map<String, dynamic>? energyStats;
      List<EnergyReading> energyReadings = [];

      await Future.wait([
        _analyticsService
            .fetchLatestReadings(
              limit: 50,
              location: _selectedLocation,
              module: _selectedModule,
              deviceId: _selectedDeviceId,
            )
            .then((v) {
              data = v;
              return v;
            })
            .catchError((_) {
              data = [];
              return <SensorReading>[];
            }),
        _analyticsService
            .fetchOccupancyStats(
              limit: 50,
              location: _selectedLocation,
              module: _selectedModule,
              deviceId: _selectedDeviceId,
            )
            .then((v) {
              occupancyStats = v;
              return v;
            })
            .catchError((_) {
              occupancyStats = null;
              return <String, dynamic>{};
            }),
        _analyticsService
            .fetchCurrentEnergyStats(
              limit: 120,
              location: _selectedLocation,
              module: _selectedModule,
              deviceId: _selectedDeviceId,
            )
            .then((v) {
              energyStats = v;
              if (v != null) {
                final rawReadings = v['readings'] as List<dynamic>?;
                if (rawReadings != null && rawReadings.isNotEmpty) {
                  energyReadings = rawReadings
                      .map((e) => EnergyReading.fromJson(
                          Map<String, dynamic>.from(e as Map)))
                      .toList();
                  energyReadings.sort(
                      (a, b) => b.receivedAt.compareTo(a.receivedAt));
                } else if (v['latest'] != null) {
                  energyReadings = [
                    EnergyReading.fromJson(
                        Map<String, dynamic>.from(v['latest'] as Map))
                  ];
                }
              }
              return v;
            })
            .catchError((_) {
              energyStats = null;
              energyReadings = [];
              return <String, dynamic>{};
            }),
      ]).timeout(
        const Duration(seconds: 60),
        onTimeout: () {
          // Return partial results if timeout; data may still be empty
          throw TimeoutException(
            'Analytics request took too long. Check your connection and try again.',
            const Duration(seconds: 60),
          );
        },
      );

      _DerivedStats? stats;
      if (data.isNotEmpty) {
        stats = _deriveStats(data);
      }
      if (!mounted) return;

      // Fetch AI recommendations (show loading only when we don't have any yet)
      OptimizationResponse? aiRecsResponse;
      final showAILoading = _aiRecommendations == null;
      try {
        if (showAILoading) {
          setState(() {
            _loadingAIRecommendations = true;
          });
        }
        aiRecsResponse = await _optimizationService.fetchRecommendations(
          days: 2,
          location: _selectedLocation ??
              (energyReadings.isNotEmpty
                  ? energyReadings.first.location
                  : null),
          module: _selectedModule ??
              (energyReadings.isNotEmpty
                  ? energyReadings.first.module
                  : null),
        );
      } catch (e) {
        if (!mounted) return;
        setState(() {
          _loadingAIRecommendations = false;
          _aiRecommendations = null;
        });
      } finally {
        if (!mounted) return;
        if (showAILoading) {
          setState(() {
            _loadingAIRecommendations = false;
          });
        }
      }
      
      // Convert AI recommendations to _Recommendation format
      List<_Recommendation> aiRecs = [];
      if (aiRecsResponse != null && aiRecsResponse.recommendations.isNotEmpty) {
        for (final aiRec in aiRecsResponse.recommendations) {
          // Determine color and icon based on severity
          Color recColor;
          IconData recIcon;
          switch (aiRec.severity.toLowerCase()) {
            case 'high':
              recColor = Colors.red;
              recIcon = Icons.priority_high;
              break;
            case 'medium':
              recColor = Colors.orange;
              recIcon = Icons.info;
              break;
            default:
              recColor = Colors.blue;
              recIcon = Icons.lightbulb_outline;
          }
          
          // Add savings info to detail if available
          String detail = aiRec.message;
          if (aiRec.estimatedSavings > 0) {
            detail += ' (Potential savings: ${aiRec.estimatedSavings.toStringAsFixed(2)} kWh/day)';
          }
          
          // Create a unique ID for this recommendation
          final recId = '${aiRec.type}_${aiRec.title}_${DateTime.now().millisecondsSinceEpoch}_${aiRecs.length}';
          
          // Store original AI recommendation for detailed view
          _aiRecDetailsMap[recId] = aiRec;
          
          aiRecs.add(_Recommendation(
            title: aiRec.title,
            detail: detail,
            cta: 'View Details',
            color: recColor,
            icon: recIcon,
            id: recId, // Store ID for lookup
          ));
        }
      }

      // Fetch current energy recommendations from trained model (CSV dataset)
      List<CurrentReadingRecommendation>? modelRecs;
      if (energyReadings.isNotEmpty) {
        try {
          final latest = energyReadings.first;
          final trend = energyStats?['trend'] as Map<String, dynamic>?;
          final signal = energyStats?['signal'] as Map<String, dynamic>?;
          final recMaps = await _analyticsService.fetchCurrentEnergyRecommendations(
            currentA: latest.currentA,
            currentMa: latest.currentMa,
            powerW: latest.currentA * 230.0,
            trendDirection: trend?['direction'] as String? ?? 'stable',
            trendPercentChange: (trend?['percent_change'] as num?)?.toDouble() ?? 0.0,
            signalQuality: signal?['quality'] as String? ?? 'unknown',
          );
          if (recMaps.isNotEmpty) {
            modelRecs = recMaps
                .map((e) => CurrentReadingRecommendation.fromApiMap(e))
                .toList();
          }
        } catch (_) {
          // Fall back to rule-based if model API fails
        }
      }

      if (!mounted) return;
      setState(() {
        _readings = data;
        _energyReadings = energyReadings;
        _energyUsage = energyStats;
        _occupancyStats = occupancyStats;
        _aiRecommendations = aiRecsResponse;
        _modelCurrentRecs = modelRecs;
        final recItems = aiRecs.map((r) => _RecItem(rec: r)).toList();
        _activeRecItems = recItems.take(_maxActiveRecs).toList();
        _backlogRecs = recItems.skip(_maxActiveRecs).map((item) => item.rec).toList();
        _history = [];
        _initialLoadDone = true;
        _lastUpdated = DateTime.now();
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Failed to load analytics data: $e';
      });
    } finally {
      if (!mounted) return;
      setState(() {
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Analytics & Recommendations'),
        actions: [
          if (_initialLoadDone && _lastUpdated != null)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Center(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.fiber_manual_record, size: 8, color: Colors.green[400]),
                    const SizedBox(width: 6),
                    Text(
                      'Live',
                      style: TextStyle(fontSize: 12, color: Colors.green[700]),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _reloadAllData,
        child: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    final bool hasActiveFilters = _selectedLocation != null ||
        _selectedModule != null ||
        _selectedDeviceId != null;

    if (_loading) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: const [
          SizedBox(
            height: 280,
            child: Center(child: CircularProgressIndicator()),
          ),
        ],
      );
    }

    if (_error != null) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        children: [
          _errorCard(_error!),
        ],
      );
    }

    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildFilters(),
          const SizedBox(height: 16),
          _buildAnalyticsTabs(),
          const SizedBox(height: 16),
          if (_selectedTab == _AnalyticsTab.environment)
            ..._buildEnvironmentAnalytics(hasActiveFilters)
          else
            ..._buildCurentEnergyAnalytics(hasActiveFilters),
        ],
      ),
    );
  }

  Widget _buildAnalyticsTabs() {
    return SegmentedButton<_AnalyticsTab>(
      segments: const [
        ButtonSegment<_AnalyticsTab>(
          value: _AnalyticsTab.environment,
          icon: Icon(Icons.analytics_outlined),
          label: Text('Environment'),
        ),
        ButtonSegment<_AnalyticsTab>(
          value: _AnalyticsTab.curentEnergy,
          icon: Icon(Icons.electric_bolt),
          label: Text('Curent Energy'),
        ),
      ],
      selected: <_AnalyticsTab>{_selectedTab},
      showSelectedIcon: false,
      onSelectionChanged: (selected) {
        if (selected.isEmpty) return;
        setState(() {
          _selectedTab = selected.first;
        });
      },
    );
  }

  List<Widget> _buildEnvironmentAnalytics(bool hasActiveFilters) {
    if (_readings.isEmpty) {
      return [
        _emptyState(hasActiveFilters: hasActiveFilters),
      ];
    }

    final SensorReading latest = _latestReading(_readings);
    final _DerivedStats stats = _deriveStats(_readings);

    return [
      _buildHeader(latest, stats),
      const SizedBox(height: 16),
      if (_occupancyStats != null) ...[
        _buildOccupancyStats(),
        const SizedBox(height: 16),
      ],
      _buildComfortCard(stats),
      const SizedBox(height: 16),
      _buildSensorHealth(latest, stats),
      const SizedBox(height: 16),
      _buildRecommendations(),
      const SizedBox(height: 16),
      _buildRecentReadings(_readings),
    ];
  }

  List<Widget> _buildCurentEnergyAnalytics(bool hasActiveFilters) {
    if (_energyReadings.isEmpty) {
      return [
        _curentEnergyEmptyState(hasActiveFilters: hasActiveFilters),
      ];
    }

    final _CurentEnergyStats stats = _deriveCurentEnergyStats(
      _energyReadings,
      usageResponse: _energyUsage,
      selectedLocation: _selectedLocation,
    );

    // Use trained model recommendations when available, else rule-based
    final List<CurrentReadingRecommendation> currentRecs =
        (_modelCurrentRecs != null && _modelCurrentRecs!.isNotEmpty)
            ? _modelCurrentRecs!
            : CurrentReadingRecommendation.fromReadingsAndStats(
                readings: _energyReadings,
                usageStats: _energyUsage,
              );

    if (_energyAdviceHistory.isEmpty && !_loadingHistory) {
      _loadEnergyAdviceHistory();
    }
    return [
      _buildCurentEnergyHeader(stats),
      const SizedBox(height: 16),
      _buildCurentEnergyMetrics(stats),
      const SizedBox(height: 16),
      _buildCurrentReadingRecommendations(currentRecs),
      const SizedBox(height: 16),
      _buildEnergyAdviceHistorySection(),
      const SizedBox(height: 16),
      if (_aiRecommendations != null &&
          _aiRecommendations!.recommendations.isNotEmpty) ...[
        _buildAIRecommendations(),
        const SizedBox(height: 16),
      ],
      _buildCurentEnergyReadings(_energyReadings),
    ];
  }

  Widget _buildCurrentReadingRecommendations(
      List<CurrentReadingRecommendation> recs) {
    if (recs.isEmpty) return const SizedBox.shrink();
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.energy_savings_leaf, color: Colors.green),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Energy advice & recommendations',
                    style: TextStyle(
                        fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
                DropdownButton<int>(
                  value: _recommendationIntervalMinutes,
                  isDense: true,
                  underline: const SizedBox(),
                  items: _recommendationIntervalOptions
                      .map((m) => DropdownMenuItem<int>(
                            value: m,
                            child: Text('Every $m min'),
                          ))
                      .toList(),
                  onChanged: (int? value) {
                    if (value == null) return;
                    setState(() {
                      _recommendationIntervalMinutes = value;
                      _startRecommendationRefresh();
                    });
                  },
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Use devices correctly, see how much you can save, and how to fix issues. Recommendations refresh every $_recommendationIntervalMinutes min and are saved to history.',
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context)
                    .colorScheme
                    .onSurface
                    .withOpacity(0.7),
              ),
            ),
            if (_lastRecommendationSave != null) ...[
              const SizedBox(height: 4),
              Text(
                'Last saved: ${_friendlyTime(_lastRecommendationSave!)}',
                style: TextStyle(
                  fontSize: 11,
                  color: Theme.of(context)
                      .colorScheme
                      .onSurface
                      .withOpacity(0.6),
                ),
              ),
            ],
            const SizedBox(height: 16),
            ...recs.map((r) => _buildUserFriendlyRecCard(
                  title: r.title,
                  message: r.message,
                  severity: r.severity,
                  icon: r.icon,
                  color: r.color,
                  savingsKwhPerDay: r.estimatedSavingsKwhPerDay,
                  wastedKwhPerDay: r.energyWastedKwhPerDay,
                  advice: r.advice,
                  mitigation: r.mitigation,
                )),
          ],
        ),
      ),
    );
  }

  Widget _buildEnergyAdviceHistorySection() {
    final filtered = _filteredHistory;
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            InkWell(
              onTap: () {
                setState(() {
                  _historySectionExpanded = !_historySectionExpanded;
                });
              },
              child: Row(
                children: [
                  Icon(
                    _historySectionExpanded ? Icons.expand_less : Icons.expand_more,
                    color: Colors.blue,
                    size: 28,
                  ),
                  const Icon(Icons.history, color: Colors.blue),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'Previous recommendations (history)',
                      style: TextStyle(
                          fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                  ),
                  if (_loadingHistory)
                    const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  else
                    IconButton(
                      icon: const Icon(Icons.refresh),
                      onPressed: _loadEnergyAdviceHistory,
                      tooltip: 'Refresh history',
                    ),
                ],
              ),
            ),
            if (_historySectionExpanded) ...[
              const SizedBox(height: 8),
              Text(
                'Read previous energy advice and the readings they were based on.',
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context)
                      .colorScheme
                      .onSurface
                      .withOpacity(0.7),
                ),
              ),
              const SizedBox(height: 12),
              // Date filter row
              Row(
                children: [
                  Text(
                    'Date filter:',
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context)
                          .colorScheme
                          .onSurface
                          .withOpacity(0.7),
                    ),
                  ),
                  const SizedBox(width: 8),
                  TextButton.icon(
                    onPressed: () async {
                      final date = await showDatePicker(
                        context: context,
                        initialDate: _historyFilterFrom ?? DateTime.now(),
                        firstDate: DateTime(2020),
                        lastDate: DateTime.now(),
                      );
                      if (date != null && mounted) {
                        setState(() => _historyFilterFrom = date);
                      }
                    },
                    icon: const Icon(Icons.calendar_today, size: 18),
                    label: Text(
                      _historyFilterFrom != null
                          ? '${_historyFilterFrom!.day}/${_historyFilterFrom!.month}/${_historyFilterFrom!.year}'
                          : 'From',
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: () async {
                      final date = await showDatePicker(
                        context: context,
                        initialDate: _historyFilterTo ?? DateTime.now(),
                        firstDate: DateTime(2020),
                        lastDate: DateTime.now(),
                      );
                      if (date != null && mounted) {
                        setState(() => _historyFilterTo = date);
                      }
                    },
                    icon: const Icon(Icons.calendar_today, size: 18),
                    label: Text(
                      _historyFilterTo != null
                          ? '${_historyFilterTo!.day}/${_historyFilterTo!.month}/${_historyFilterTo!.year}'
                          : 'To',
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                  TextButton(
                    onPressed: () {
                      setState(() {
                        _historyFilterFrom = null;
                        _historyFilterTo = null;
                      });
                    },
                    child: const Text('Clear'),
                  ),
                ],
              ),
              // Select all / Deselect / Delete selected
              Row(
                children: [
                  TextButton(
                    onPressed: filtered.isEmpty
                        ? null
                        : () {
                            setState(() {
                              for (final item in filtered) {
                                final id = item['id'] as String?;
                                if (id != null) _selectedHistoryIds.add(id);
                              }
                            });
                          },
                    child: const Text('Select all'),
                  ),
                  TextButton(
                    onPressed: _selectedHistoryIds.isEmpty ? null : () {
                      setState(() => _selectedHistoryIds.clear());
                    },
                    child: const Text('Deselect all'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: _selectedHistoryIds.isEmpty
                        ? null
                        : () async {
                            await _deleteSelectedHistory();
                          },
                    icon: const Icon(Icons.delete_outline, size: 18),
                    label: Text('Delete selected (${_selectedHistoryIds.length})'),
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.red,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if (_energyAdviceHistory.isEmpty && !_loadingHistory)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Center(
                    child: Text(
                      'No history yet. Recommendations are saved every $_recommendationIntervalMinutes min.',
                      style: TextStyle(
                        fontSize: 13,
                        color: Theme.of(context)
                            .colorScheme
                            .onSurface
                            .withOpacity(0.6),
                      ),
                    ),
                  ),
                )
              else if (filtered.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: Center(
                    child: Text('No entries match the date filter.'),
                  ),
                )
              else
                ...filtered.take(30).map((item) {
                  final id = item['id'] as String? ?? '';
                  final created = item['created_at'] as String?;
                  final snapshot = item['readings_snapshot'] as Map<String, dynamic>?;
                  final recs = item['recommendations'] as List<dynamic>? ?? [];
                  final powerW = snapshot != null
                      ? (snapshot['power_w'] as num?)?.toDouble()
                      : null;
                  final currentA = snapshot != null
                      ? (snapshot['current_a'] as num?)?.toDouble()
                      : null;
                  final trend = snapshot != null
                      ? snapshot['trend_direction'] as String?
                      : null;
                  final selected = _selectedHistoryIds.contains(id);
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Theme.of(context)
                            .colorScheme
                            .surfaceContainerHighest
                            .withOpacity(0.5),
                        borderRadius: BorderRadius.circular(10),
                        border: selected
                            ? Border.all(color: Theme.of(context).colorScheme.primary, width: 2)
                            : null,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Checkbox(
                                value: selected,
                                onChanged: (v) {
                                  setState(() {
                                    if (v == true) {
                                      _selectedHistoryIds.add(id);
                                    } else {
                                      _selectedHistoryIds.remove(id);
                                    }
                                  });
                                },
                              ),
                              Icon(Icons.schedule,
                                  size: 16,
                                  color: Theme.of(context).colorScheme.primary),
                              const SizedBox(width: 6),
                              Text(
                                created != null
                                    ? _friendlyTime(DateTime.tryParse(created) ?? DateTime.now())
                                    : '—',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                          if (snapshot != null) ...[
                            const SizedBox(height: 4),
                            Wrap(
                              spacing: 8,
                              runSpacing: 4,
                              children: [
                                if (currentA != null)
                                  _pill('${currentA.toStringAsFixed(2)} A'),
                                if (powerW != null)
                                  _pill('${powerW.toStringAsFixed(0)} W'),
                                if (trend != null) _pill('Trend: $trend'),
                              ],
                            ),
                          ],
                          const SizedBox(height: 8),
                          ...recs.take(5).map((r) {
                            final map = r as Map<String, dynamic>;
                            return Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Icon(
                                    Icons.arrow_right,
                                    size: 16,
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurface
                                        .withOpacity(0.6),
                                  ),
                                  const SizedBox(width: 4),
                                  Expanded(
                                    child: Text(
                                      map['title'] as String? ?? '',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Theme.of(context)
                                            .colorScheme
                                            .onSurface
                                            .withOpacity(0.85),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }),
                          if (recs.length > 5)
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Text(
                                '+ ${recs.length - 5} more',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurface
                                      .withOpacity(0.6),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  );
                }),
            ],
          ],
        ),
      ),
    );
  }

  /// One user-understandable recommendation block: issue, advice, savings, waste, mitigate.
  Widget _buildUserFriendlyRecCard({
    required String title,
    required String message,
    required String severity,
    required IconData icon,
    required Color color,
    double? savingsKwhPerDay,
    double? wastedKwhPerDay,
    String? advice,
    String? mitigation,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: color.withOpacity(0.06),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, color: color, size: 24),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                          color: color,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        message,
                        style: TextStyle(
                          fontSize: 13,
                          color: Theme.of(context)
                              .colorScheme
                              .onSurface
                              .withOpacity(0.85),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (advice != null && advice.isNotEmpty) ...[
              const SizedBox(height: 12),
              _recLabel(Icons.tips_and_updates, 'How to use devices correctly'),
              const SizedBox(height: 4),
              Text(
                advice,
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context)
                      .colorScheme
                      .onSurface
                      .withOpacity(0.8),
                  height: 1.35,
                ),
              ),
            ],
            if (wastedKwhPerDay != null && wastedKwhPerDay > 0) ...[
              const SizedBox(height: 10),
              _recLabel(Icons.warning_amber_rounded, 'How much your device is wasting'),
              const SizedBox(height: 4),
              Text(
                'About ${wastedKwhPerDay.toStringAsFixed(2)} kWh per day (${(wastedKwhPerDay * 30).toStringAsFixed(1)} kWh per month if this continues).',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.orange[800],
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
            if (savingsKwhPerDay != null && savingsKwhPerDay > 0) ...[
              const SizedBox(height: 10),
              _recLabel(Icons.savings, 'Energy you can save'),
              const SizedBox(height: 4),
              Text(
                'Up to ${savingsKwhPerDay.toStringAsFixed(2)} kWh per day by following the advice below.',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.green[700],
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
            if (mitigation != null && mitigation.isNotEmpty) ...[
              const SizedBox(height: 10),
              _recLabel(Icons.build_circle, 'How to fix it'),
              const SizedBox(height: 4),
              Text(
                mitigation,
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context)
                      .colorScheme
                      .onSurface
                      .withOpacity(0.8),
                  height: 1.35,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _recLabel(IconData icon, String label) {
    return Row(
      children: [
        Icon(icon, size: 16, color: Theme.of(context).colorScheme.primary),
        const SizedBox(width: 6),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: Theme.of(context).colorScheme.primary,
          ),
        ),
      ],
    );
  }

  SensorReading _latestReading(List<SensorReading> readings) {
    return readings
        .reduce((a, b) => a.receivedAt.isAfter(b.receivedAt) ? a : b);
  }

  Widget _errorCard(String message) {
    return Card(
      color: Colors.red.withOpacity(0.08),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.error, color: Colors.red),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Unable to load analytics',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  Text(message,
                      style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                          fontSize: 12)),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: _loadReadings,
              tooltip: 'Retry',
            ),
          ],
        ),
      ),
    );
  }

  Widget _emptyState({required bool hasActiveFilters}) {
    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.sensors_off, color: Colors.grey),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    hasActiveFilters
                        ? 'No analytics data found for the selected location/module.'
                        : 'No sensor readings yet. Pull to refresh or wait for devices to send data.',
                    style: const TextStyle(fontSize: 13),
                  ),
                ),
              ],
            ),
            if (hasActiveFilters) ...[
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerLeft,
                child: FilledButton.icon(
                  onPressed: () {
                    setState(() {
                      _selectedLocation = null;
                      _selectedModule = null;
                      _selectedDeviceId = null;
                    });
                    _loadReadings();
                  },
                  icon: const Icon(Icons.arrow_back),
                  label: const Text('Back to Analytics'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _curentEnergyEmptyState({required bool hasActiveFilters}) {
    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.bolt_outlined, color: Colors.grey),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    hasActiveFilters
                        ? 'No curent-energy readings found for the selected location/module.'
                        : 'No curent-energy readings yet. Wait for ESP32 energy data and refresh.',
                    style: const TextStyle(fontSize: 13),
                  ),
                ),
              ],
            ),
            if (hasActiveFilters) ...[
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerLeft,
                child: FilledButton.icon(
                  onPressed: () {
                    setState(() {
                      _selectedLocation = null;
                      _selectedModule = null;
                      _selectedDeviceId = null;
                    });
                    _loadReadings();
                  },
                  icon: const Icon(Icons.arrow_back),
                  label: const Text('Back to Analytics'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildCurentEnergyHeader(_CurentEnergyStats stats) {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.electric_bolt, color: stats.trendColor),
                const SizedBox(width: 8),
                const Text(
                  'Curent Energy Analysis',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                if (stats.latest != null)
                  Text(
                    'Last seen: ${_friendlyTime(stats.latest!.receivedAt)}',
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context)
                          .colorScheme
                          .onSurface
                          .withOpacity(0.6),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (stats.latest != null) ...[
                  _pill('${stats.latest!.location} • ${stats.latest!.module}'),
                  _pill('Sensor: ${stats.latest!.sensor}'),
                  _pill('Type: ${stats.latest!.type ?? 'curent'}'),
                ],
                _pill(
                    'Trend: ${stats.trendLabel} (${stats.deltaPercent.toStringAsFixed(1)}%)'),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCurentEnergyMetrics(_CurentEnergyStats stats) {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: const [
                Icon(Icons.insights, color: Colors.green),
                SizedBox(width: 8),
                Text(
                  'Curent Metrics',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _energyMetricTile(
                    'Latest Curent',
                    '${stats.latestCurentA.toStringAsFixed(3)} A',
                    Colors.blue),
                _energyMetricTile(
                    'Latest Curent',
                    '${stats.latestCurentMa.toStringAsFixed(0)} mA',
                    Colors.indigo),
                _energyMetricTile('Avg Curent',
                    '${stats.avgCurentA.toStringAsFixed(3)} A', Colors.teal),
                _energyMetricTile('Peak Curent',
                    '${stats.maxCurentA.toStringAsFixed(3)} A', Colors.orange),
                _energyMetricTile(
                    'Estimated Power',
                    '${stats.latestPowerW.toStringAsFixed(1)} W',
                    Colors.deepOrange),
                _energyMetricTile('Avg Power',
                    '${stats.avgPowerW.toStringAsFixed(1)} W', Colors.purple),
                _energyMetricTile('Signal', '${stats.latestRssi ?? 'n/a'} dBm',
                    stats.signalColor),
                _energyMetricTile('Energy (kWh)',
                    stats.estimatedEnergyKwh.toStringAsFixed(4), Colors.green),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              'Samples: ${stats.sampleCount} | Window: ${stats.windowMinutes} min',
              style: TextStyle(
                fontSize: 12,
                color:
                    Theme.of(context).colorScheme.onSurface.withOpacity(0.65),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCurentEnergyReadings(List<EnergyReading> readings) {
    final List<EnergyReading> sorted = List.of(readings)
      ..sort((a, b) => b.receivedAt.compareTo(a.receivedAt));
    final List<EnergyReading> latestTen = sorted.take(10).toList();

    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: const [
                Icon(Icons.tune, color: Colors.indigo),
                SizedBox(width: 8),
                Text(
                  'Latest Curent Readings',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ...latestTen.map(_energyReadingRow),
          ],
        ),
      ),
    );
  }

  Widget _energyReadingRow(EnergyReading reading) {
    final double powerW = reading.currentA * 230.0;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          const Icon(Icons.bolt, color: Colors.green),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${reading.location} • ${reading.module}',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 2),
                Text(
                  '${reading.currentA.toStringAsFixed(3)} A | ${reading.currentMa.toStringAsFixed(0)} mA | ${powerW.toStringAsFixed(1)} W',
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withOpacity(0.7),
                  ),
                ),
              ],
            ),
          ),
          Text(
            _friendlyTime(reading.receivedAt),
            style: TextStyle(
              fontSize: 11,
              color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
            ),
          ),
        ],
      ),
    );
  }

  Widget _energyMetricTile(String label, String value, Color color) {
    return Container(
      width: 155,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilters() {
    final bool hasActiveFilters = _selectedLocation != null ||
        _selectedModule != null ||
        _selectedDeviceId != null;

    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.filter_list, color: Colors.blue),
                const SizedBox(width: 8),
                const Text(
                  'Filters',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                if (hasActiveFilters)
                  TextButton.icon(
                    onPressed: () {
                      setState(() {
                        _selectedLocation = null;
                        _selectedModule = null;
                        _selectedDeviceId = null;
                      });
                      _loadReadings();
                    },
                    icon: const Icon(Icons.clear, size: 18),
                    label: const Text('Clear'),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: _selectedLocation,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Location',
                border: OutlineInputBorder(),
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                isDense: true,
              ),
              items: [
                const DropdownMenuItem<String>(
                  value: null,
                  child: Text('All Locations'),
                ),
                ..._availableLocations
                    .map((location) => DropdownMenuItem<String>(
                          value: location,
                          child:
                              Text(location, overflow: TextOverflow.ellipsis),
                        )),
              ],
              onChanged: (value) {
                setState(() {
                  _selectedLocation = value;
                });
                _loadReadings();
              },
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: _selectedModule,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Module ID',
                border: OutlineInputBorder(),
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                isDense: true,
              ),
              items: [
                const DropdownMenuItem<String>(
                  value: null,
                  child: Text('All Modules'),
                ),
                ..._availableModules.map((module) => DropdownMenuItem<String>(
                      value: module,
                      child: Text(module, overflow: TextOverflow.ellipsis),
                    )),
              ],
              onChanged: (value) {
                setState(() {
                  _selectedModule = value;
                });
                _loadReadings();
              },
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: _selectedDeviceId,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Device',
                border: OutlineInputBorder(),
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                isDense: true,
              ),
              items: [
                const DropdownMenuItem<String>(
                  value: null,
                  child: Text('All Devices'),
                ),
                ..._availableDevices.map((device) {
                  final id = (device['device_id'] ?? '').toString();
                  final name = (device['device_name'] ?? '').toString();
                  final label = name.isNotEmpty ? '$name ($id)' : id;
                  return DropdownMenuItem<String>(
                    value: id,
                    child: Text(label, overflow: TextOverflow.ellipsis),
                  );
                }),
              ],
              onChanged: (value) {
                setState(() {
                  _selectedDeviceId = value;
                });
                _loadReadings();
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(SensorReading latest, _DerivedStats stats) {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  stats.isOccupied ? Icons.sensor_occupied : Icons.sensor_door,
                  color: stats.isOccupied ? Colors.green : Colors.amber,
                ),
                const SizedBox(width: 8),
                Text(
                  stats.isOccupied ? 'Occupied' : 'Vacant',
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                Text(
                  'Last seen: ${_friendlyTime(latest.receivedAt)}',
                  style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context)
                          .colorScheme
                          .onSurface
                          .withOpacity(0.6)),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _pill('${latest.location} • ${latest.module}'),
                _pill('Vacancy: ${stats.vacancyMinutes} min'),
                _pill('Avg temp: ${stats.avgTemp.toStringAsFixed(1)}°C'),
                _pill('Avg humidity: ${stats.avgHumidity.toStringAsFixed(0)}%'),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOccupancyStats() {
    if (_occupancyStats == null) {
      return const SizedBox.shrink();
    }

    final stats = _occupancyStats!;
    final isOccupied = stats['is_currently_occupied'] as bool? ?? false;
    final totalReadings = stats['total_readings'] as int? ?? 0;
    final occupiedCount = stats['occupied_count'] as int? ?? 0;
    final vacantCount = stats['vacant_count'] as int? ?? 0;
    final occupiedPercentage = stats['occupied_percentage'] as double? ?? 0.0;
    final vacantPercentage = stats['vacant_percentage'] as double? ?? 0.0;

    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  isOccupied ? Icons.sensor_occupied : Icons.sensor_door,
                  color: isOccupied ? Colors.green : Colors.orange,
                ),
                const SizedBox(width: 8),
                const Text(
                  'Occupancy Statistics',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: isOccupied
                        ? Colors.green.withOpacity(0.1)
                        : Colors.orange.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Text(
                    isOccupied ? 'Curently Occupied' : 'Curently Vacant',
                    style: TextStyle(
                      color:
                          isOccupied ? Colors.green[700] : Colors.orange[700],
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _statTile(
                    'Occupied',
                    '$occupiedCount',
                    '${occupiedPercentage.toStringAsFixed(1)}%',
                    Colors.green,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _statTile(
                    'Vacant',
                    '$vacantCount',
                    '${vacantPercentage.toStringAsFixed(1)}%',
                    Colors.orange,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: LinearProgressIndicator(
                    value: occupiedPercentage / 100,
                    backgroundColor:
                        Theme.of(context).colorScheme.surfaceContainerHighest,
                    valueColor:
                        const AlwaysStoppedAnimation<Color>(Colors.green),
                    minHeight: 8,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: LinearProgressIndicator(
                    value: vacantPercentage / 100,
                    backgroundColor:
                        Theme.of(context).colorScheme.surfaceContainerHighest,
                    valueColor:
                        const AlwaysStoppedAnimation<Color>(Colors.orange),
                    minHeight: 8,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Based on last $totalReadings readings',
              style: TextStyle(
                  fontSize: 12,
                  color:
                      Theme.of(context).colorScheme.onSurface.withOpacity(0.6)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _statTile(String label, String count, String percentage, Color color) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
                fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 4),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                count,
                style: TextStyle(
                    fontSize: 24, fontWeight: FontWeight.bold, color: color),
              ),
              const SizedBox(width: 4),
              Text(
                percentage,
                style: TextStyle(
                    fontSize: 14, color: color, fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildComfortCard(_DerivedStats stats) {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: const [
                Icon(Icons.thermostat, color: Colors.deepOrange),
                SizedBox(width: 8),
                Text('Comfort & Drift',
                    style:
                        TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                _valueTile('Temp', '${stats.latestTemp.toStringAsFixed(1)}°C',
                    stats.tempStatusColor),
                const SizedBox(width: 10),
                _valueTile(
                    'Humidity',
                    '${stats.latestHumidity.toStringAsFixed(0)}%',
                    stats.humidityStatusColor),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(stats.comfortNote,
                          style: const TextStyle(
                              fontSize: 12, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 6),
                      LinearProgressIndicator(
                        value: stats.tempBandProgress,
                        minHeight: 8,
                        backgroundColor: Theme.of(context)
                            .colorScheme
                            .surfaceContainerHighest,
                        valueColor: AlwaysStoppedAnimation<Color>(
                            stats.tempStatusColor),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSensorHealth(SensorReading latest, _DerivedStats stats) {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: const [
                Icon(Icons.wifi_tethering, color: Colors.blueGrey),
                SizedBox(width: 8),
                Text('Sensor Health',
                    style:
                        TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _healthTile('RSSI', '${latest.rssi ?? -80} dBm',
                    stats.signalColor, stats.signalLabel),
                _healthTile(
                    'Uptime',
                    latest.uptime != null ? '${latest.uptime}s' : 'n/a',
                    Colors.indigo,
                    'since boot'),
                _healthTile(
                    'Heap',
                    latest.heap != null ? '${latest.heap} B' : 'n/a',
                    Colors.teal,
                    'free mem'),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRecommendations() {
    final List<_RecItem> recs = _activeRecItems;
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: const [
                Icon(Icons.lightbulb, color: Colors.amber),
                SizedBox(width: 8),
                Text('Actionable Recommendations',
                    style:
                        TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 12),
            if (recs.isEmpty)
              Text('No recommendations right now.',
                  style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context)
                          .colorScheme
                          .onSurface
                          .withOpacity(0.7)))
            else
              ...List.generate(
                  recs.length,
                  (index) =>
                      _recTile(recs[index], () => _handleRecAction(index))),
            if (_history.isNotEmpty) ...[
              const SizedBox(height: 12),
              Divider(color: Theme.of(context).colorScheme.outlineVariant),
              const SizedBox(height: 8),
              Text('History',
                  style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: Theme.of(context)
                          .colorScheme
                          .onSurface
                          .withOpacity(0.8))),
              const SizedBox(height: 8),
              ..._history.take(5).map((entry) => _historyTile(entry)).toList(),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildAIRecommendations() {
    if (_loadingAIRecommendations) {
      return Card(
        elevation: 2,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(width: 16),
              Text(
                'Loading AI recommendations...',
                style: TextStyle(color: Colors.grey[600], fontSize: 14),
              ),
            ],
          ),
        ),
      );
    }

    if (_aiRecommendations == null || _aiRecommendations!.recommendations.isEmpty) {
      return const SizedBox.shrink(); // Hide if no recommendations
    }

    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: const [
                Icon(Icons.psychology, color: Colors.purple),
                SizedBox(width: 8),
                Text(
                  'AI energy advice (trained model)',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'Recommendations from the trained model: how to use devices, how much you waste, and how to fix it.',
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context)
                    .colorScheme
                    .onSurface
                    .withOpacity(0.7),
              ),
            ),
            if (_aiRecommendations!.potentialSavingsKwhPerDay > 0) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.green[50],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.green[200]!),
                ),
                child: Row(
                  children: [
                    Icon(Icons.savings, color: Colors.green[700], size: 24),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Potential Savings',
                            style: TextStyle(
                              color: Colors.green[700],
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${_aiRecommendations!.potentialSavingsKwhPerDay.toStringAsFixed(2)} kWh/day',
                            style: TextStyle(
                              color: Colors.green[700],
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (_aiRecommendations!.currentEnergyWatts != null)
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            'Curent',
                            style: TextStyle(
                              color: Colors.grey[600],
                              fontSize: 11,
                            ),
                          ),
                          Text(
                            '${_aiRecommendations!.currentEnergyWatts!.toStringAsFixed(0)} W',
                            style: TextStyle(
                              color: Colors.grey[700],
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 12),
            ..._aiRecommendations!.recommendations.map((rec) => _buildAIRecommendationTile(rec)),
          ],
        ),
      ),
    );
  }

  Widget _buildAIRecommendationTile(AIRecommendation rec) {
    Color severityColor;
    IconData iconData;
    switch (rec.severity.toLowerCase()) {
      case 'high':
        severityColor = Colors.red;
        iconData = Icons.priority_high;
        break;
      case 'medium':
        severityColor = Colors.orange;
        iconData = Icons.info;
        break;
      default:
        severityColor = Colors.blue;
        iconData = Icons.lightbulb_outline;
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: _buildUserFriendlyRecCard(
        title: rec.title,
        message: rec.message,
        severity: rec.severity,
        icon: iconData,
        color: severityColor,
        savingsKwhPerDay: rec.estimatedSavings > 0 ? rec.estimatedSavings : null,
        wastedKwhPerDay: rec.energyWastedKwhPerDay,
        advice: rec.advice,
        mitigation: rec.mitigation,
      ),
    );
  }

  Widget _buildRecentReadings(List<SensorReading> readings) {
    final List<SensorReading> latestFive = List.of(readings)
      ..sort((a, b) => b.receivedAt.compareTo(a.receivedAt));
    final List<SensorReading> topFive = latestFive.take(5).toList();
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: const [
                Icon(Icons.list_alt, color: Colors.indigo),
                SizedBox(width: 8),
                Text('Recent Readings',
                    style:
                        TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 12),
            ...topFive.map((r) => _readingRow(r)).toList(),
          ],
        ),
      ),
    );
  }

  Widget _recTile(_RecItem item, VoidCallback onPressed) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(item.rec.icon, color: item.rec.color),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.rec.title,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      decoration: item.completed
                          ? TextDecoration.lineThrough
                          : TextDecoration.none,
                    )),
                const SizedBox(height: 4),
                Text(item.rec.detail,
                    style: TextStyle(
                      fontSize: 12,
                      color: item.completed
                          ? Theme.of(context)
                              .colorScheme
                              .onSurface
                              .withOpacity(0.5)
                          : Theme.of(context)
                              .colorScheme
                              .onSurface
                              .withOpacity(0.7),
                    )),
                if (item.completed)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Row(
                      children: const [
                        Icon(Icons.check_circle, color: Colors.green, size: 16),
                        SizedBox(width: 6),
                        Text('Completed',
                            style:
                                TextStyle(color: Colors.green, fontSize: 12)),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          TextButton(
            style: TextButton.styleFrom(
              foregroundColor: item.completed ? Colors.grey : item.rec.color,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              minimumSize: const Size(64, 36),
            ),
            onPressed: item.completed ? null : onPressed,
            child: Text(item.completed ? 'Done' : item.rec.cta,
                style:
                    const TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  Widget _historyTile(_CompletedEntry entry) {
    final _RecItem item = entry.item;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.check_circle, color: Colors.green, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.rec.title,
                    style: const TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text(item.rec.detail,
                    style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context)
                            .colorScheme
                            .onSurface
                            .withOpacity(0.7))),
                Text(_friendlyTime(entry.completedAt),
                    style: TextStyle(
                        fontSize: 11,
                        color: Theme.of(context)
                            .colorScheme
                            .onSurface
                            .withOpacity(0.6))),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _handleRecAction(int index) {
    if (index < 0 || index >= _activeRecItems.length) return;
    final _RecItem item = _activeRecItems[index];
    if (item.completed) return;

    // If this recommendation has an ID, show detailed view
    if (item.rec.id != null && _aiRecDetailsMap.containsKey(item.rec.id)) {
      _showRecommendationDetails(item.rec.id!);
      return;
    }

    // Otherwise, mark as completed (legacy behavior)
    // Sri Lankan timezone (UTC+5:30)
    const Duration sriLankaOffset = Duration(hours: 5, minutes: 30);
    final DateTime nowSriLanka = DateTime.now().toUtc().add(sriLankaOffset);

    setState(() {
      item.completed = true;
      _history.insert(0, _CompletedEntry(item: item, completedAt: nowSriLanka));
      _activeRecItems.removeAt(index);
      _appendNextRecLocked();
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Completed: ${item.rec.title}')),
    );
  }

  void _showRecommendationDetails(String recId) {
    final aiRec = _aiRecDetailsMap[recId];
    if (aiRec == null) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) {
        return DraggableScrollableSheet(
          initialChildSize: 0.7,
          minChildSize: 0.5,
          maxChildSize: 0.95,
          expand: false,
          builder: (context, scrollController) {
            return SingleChildScrollView(
              controller: scrollController,
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: _getSeverityColor(aiRec.severity).withOpacity(0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          _getSeverityIcon(aiRec.severity),
                          color: _getSeverityColor(aiRec.severity),
                          size: 28,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              aiRec.title,
                              style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: _getSeverityColor(aiRec.severity).withOpacity(0.2),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                aiRec.severity.toUpperCase(),
                                style: TextStyle(
                                  color: _getSeverityColor(aiRec.severity),
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  
                  // Message
                  Text(
                    aiRec.message,
                    style: const TextStyle(
                      fontSize: 16,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 24),
                  
                  // Estimated Savings
                  if (aiRec.estimatedSavings > 0) ...[
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.green[50],
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.green[200]!),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.savings, color: Colors.green[700], size: 32),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Potential Savings',
                                  style: TextStyle(
                                    color: Colors.green[700],
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  '${aiRec.estimatedSavings.toStringAsFixed(2)} kWh/day',
                                  style: TextStyle(
                                    color: Colors.green[700],
                                    fontSize: 24,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                  ],
                  
                  // Detailed Information
                  const Text(
                    'Detailed Information',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),
                  
                  // Location and Module
                  if (aiRec.location != null || aiRec.module != null) ...[
                    _buildDetailRow('Location', aiRec.location ?? 'Unknown'),
                    _buildDetailRow('Module', aiRec.module ?? 'Unknown'),
                    const SizedBox(height: 8),
                  ],
                  
                  // Energy Information
                  if (aiRec.currentEnergyWatts != null)
                    _buildDetailRow('Curent Energy', '${aiRec.currentEnergyWatts!.toStringAsFixed(2)} W'),
                  
                  // Occupancy Information
                  const Divider(),
                  const Text(
                    'Occupancy Status',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey,
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (aiRec.isOccupied != null)
                    _buildDetailRow(
                      'Status',
                      aiRec.isOccupied! ? 'Occupied' : 'Vacant',
                      valueColor: aiRec.isOccupied! ? Colors.green : Colors.orange,
                    ),
                  if (aiRec.vacancyDurationMinutes != null && (aiRec.isOccupied == false))
                    _buildDetailRow(
                      'Vacancy Duration',
                      _formatDuration(aiRec.vacancyDurationMinutes!),
                    ),
                  if (aiRec.pir != null)
                    _buildDetailRow('PIR Sensor', aiRec.pir == 1 ? 'Motion Detected' : 'No Motion'),
                  if (aiRec.rcwl != null)
                    _buildDetailRow('RCWL Sensor', aiRec.rcwl == 1 ? 'Motion Detected' : 'No Motion'),
                  
                  // Environmental Information
                  if (aiRec.currentTemperature != null || aiRec.currentHumidity != null) ...[
                    const SizedBox(height: 8),
                    const Divider(),
                    const Text(
                      'Environmental Conditions',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey,
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                  if (aiRec.currentTemperature != null)
                    _buildDetailRow(
                      'Temperature',
                      '${aiRec.currentTemperature!.toStringAsFixed(1)}°C',
                      valueColor: _getTempColor(aiRec.currentTemperature!),
                    ),
                  if (aiRec.currentHumidity != null)
                    _buildDetailRow(
                      'Humidity',
                      '${aiRec.currentHumidity!.toStringAsFixed(0)}%',
                      valueColor: _getHumidityColor(aiRec.currentHumidity!),
                    ),
                  
                  const SizedBox(height: 24),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildDetailRow(String label, String value, {Color? valueColor}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 140,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[700],
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: valueColor ?? Colors.grey[900],
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatDuration(int minutes) {
    if (minutes < 60) {
      return '$minutes minutes';
    } else if (minutes < 1440) {
      final hours = minutes ~/ 60;
      final mins = minutes % 60;
      return mins > 0 ? '$hours hours $mins minutes' : '$hours hours';
    } else {
      final days = minutes ~/ 1440;
      final hours = (minutes % 1440) ~/ 60;
      return hours > 0 ? '$days days $hours hours' : '$days days';
    }
  }

  Color _getSeverityColor(String severity) {
    switch (severity.toLowerCase()) {
      case 'high':
        return Colors.red;
      case 'medium':
        return Colors.orange;
      default:
        return Colors.blue;
    }
  }

  IconData _getSeverityIcon(String severity) {
    switch (severity.toLowerCase()) {
      case 'high':
        return Icons.priority_high;
      case 'medium':
        return Icons.info;
      default:
        return Icons.lightbulb_outline;
    }
  }

  Color _getTempColor(double temp) {
    if (temp > 30) return Colors.red;
    if (temp >= 27) return Colors.orange;
    return Colors.green;
  }

  Color _getHumidityColor(double humidity) {
    if (humidity > 70) return Colors.orange;
    if (humidity < 40) return Colors.amber;
    return Colors.green;
  }

  Widget _readingRow(SensorReading reading) {
    final bool occupied = reading.occupied;
    final Color color = occupied ? Colors.green : Colors.orange;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () => _showReadingDetails(reading),
        child: Row(
          children: [
            Icon(occupied ? Icons.sensor_occupied : Icons.sensor_door,
                color: color),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                      '${reading.location} • ${_friendlyTime(reading.receivedAt)}',
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Text(
                    'Temp ${reading.temperature.toStringAsFixed(1)}\u00b0C, Hum ${reading.humidity.toStringAsFixed(0)}%, PIR ${reading.pir}, RCWL ${reading.rcwl}',
                    style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context)
                            .colorScheme
                            .onSurface
                            .withOpacity(0.7)),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(6)),
              child: Text(occupied ? 'Occupied' : 'Vacant',
                  style: TextStyle(
                      color: color, fontSize: 11, fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      ),
    );
  }

  void _showReadingDetails(SensorReading reading) {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${reading.location} • ${reading.module}',
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              Text('Seen ${_friendlyTime(reading.receivedAt)}'),
              const SizedBox(height: 12),
              Text('PIR: ${reading.pir}, RCWL: ${reading.rcwl}'),
              Text(
                  'Temp: ${reading.temperature.toStringAsFixed(1)}°C, Hum: ${reading.humidity.toStringAsFixed(0)}%'),
              Text(
                  'RSSI: ${reading.rssi ?? 'n/a'} dBm, Uptime: ${reading.uptime ?? 0}s'),
              if (reading.heap != null) Text('Heap: ${reading.heap} B'),
              if (reading.ip != null) Text('IP: ${reading.ip}'),
              if (reading.mac != null) Text('MAC: ${reading.mac}'),
              if (reading.source != null) Text('Source: ${reading.source}'),
            ],
          ),
        );
      },
    );
  }

  Widget _pill(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(18)),
      child: Text(text,
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
    );
  }

  Widget _valueTile(String label, String value, Color color) {
    return Container(
      width: 100,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
          color: color.withOpacity(0.08),
          borderRadius: BorderRadius.circular(8)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context)
                      .colorScheme
                      .onSurface
                      .withOpacity(0.7))),
          const SizedBox(height: 6),
          Text(value,
              style: TextStyle(
                  fontSize: 18, fontWeight: FontWeight.bold, color: color)),
        ],
      ),
    );
  }

  Widget _healthTile(String label, String value, Color color, String hint) {
    return Container(
      width: 150,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
          color: color.withOpacity(0.08),
          borderRadius: BorderRadius.circular(8)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context)
                      .colorScheme
                      .onSurface
                      .withOpacity(0.7))),
          const SizedBox(height: 4),
          Text(value,
              style: TextStyle(
                  fontSize: 16, fontWeight: FontWeight.bold, color: color)),
          const SizedBox(height: 2),
          Text(hint,
              style: TextStyle(
                  fontSize: 10,
                  color: Theme.of(context)
                      .colorScheme
                      .onSurface
                      .withOpacity(0.6))),
          if (label == 'IP' && value != 'n/a')
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () => _handleCopy(value),
                child: const Text('Copy', style: TextStyle(fontSize: 11)),
              ),
            ),
        ],
      ),
    );
  }

  /// Sri Lankan timezone (UTC+5:30). Used for Curent Energy "Last seen".
  static const Duration _sriLankaOffset = Duration(hours: 5, minutes: 30);

  /// Formats [time] as clock time in Sri Lankan timezone (e.g. "8 Mar 2026, 9:18 PM").
  String _formatTimeInSriLanka(DateTime time) {
    final DateTime utc = time.isUtc
        ? time
        : DateTime.utc(
            time.year, time.month, time.day, time.hour, time.minute,
            time.second, time.millisecond,
          );
    final DateTime sl = utc.add(_sriLankaOffset);
    final int h = sl.hour;
    final int m = sl.minute;
    final String ampm = h >= 12 ? 'PM' : 'AM';
    final int h12 = h > 12 ? h - 12 : (h == 0 ? 12 : h);
    const List<String> months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${sl.day} ${months[sl.month - 1]} ${sl.year}, '
        '${h12.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')} $ampm';
  }

  String _friendlyTime(DateTime time) {
    final DateTime nowSriLanka = DateTime.now().toUtc().add(_sriLankaOffset);
    final DateTime timeSriLanka =
        time.isUtc ? time.add(_sriLankaOffset) : time;
    final Duration diff = nowSriLanka.difference(timeSriLanka);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }

  void _handleCopy(String value) {
    Clipboard.setData(ClipboardData(text: value));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Copied: $value')),
    );
  }

  void _appendNextRecLocked() {
    if (_backlogRecs.isEmpty) return;

    while (_activeRecItems.length < _maxActiveRecs && _backlogRecs.isNotEmpty) {
      final _Recommendation next = _backlogRecs.removeAt(0);
      _activeRecItems.add(_RecItem(rec: next));
    }
  }
}

enum _AnalyticsTab {
  environment,
  curentEnergy,
}

class _CurentEnergyStats {
  _CurentEnergyStats({
    required this.latest,
    required this.latestCurentA,
    required this.latestCurentMa,
    required this.avgCurentA,
    required this.minCurentA,
    required this.maxCurentA,
    required this.latestPowerW,
    required this.avgPowerW,
    required this.sampleCount,
    required this.windowMinutes,
    required this.deltaPercent,
    required this.trendLabel,
    required this.trendColor,
    required this.latestRssi,
    required this.signalColor,
    required this.estimatedEnergyKwh,
  });

  final EnergyReading? latest;
  final double latestCurentA;
  final double latestCurentMa;
  final double avgCurentA;
  final double minCurentA;
  final double maxCurentA;
  final double latestPowerW;
  final double avgPowerW;
  final int sampleCount;
  final int windowMinutes;
  final double deltaPercent;
  final String trendLabel;
  final Color trendColor;
  final int? latestRssi;
  final Color signalColor;
  final double estimatedEnergyKwh;
}

class _DerivedStats {
  _DerivedStats({
    required this.avgTemp,
    required this.avgHumidity,
    required this.latestTemp,
    required this.latestHumidity,
    required this.isOccupied,
    required this.vacancyMinutes,
    required this.signalLabel,
    required this.signalColor,
    required this.tempStatusColor,
    required this.humidityStatusColor,
    required this.comfortNote,
    required this.tempBandProgress,
  });

  final double avgTemp;
  final double avgHumidity;
  final double latestTemp;
  final double latestHumidity;
  final bool isOccupied;
  final int vacancyMinutes;
  final String signalLabel;
  final Color signalColor;
  final Color tempStatusColor;
  final Color humidityStatusColor;
  final String comfortNote;
  final double tempBandProgress;
}

class _Recommendation {
  _Recommendation({
    required this.title,
    required this.detail,
    required this.cta,
    required this.color,
    required this.icon,
    this.id,
  });

  final String title;
  final String detail;
  final String cta;
  final Color color;
  final IconData icon;
  final String? id; // ID to lookup detailed AI recommendation
}

class _RecItem {
  _RecItem({required this.rec});

  final _Recommendation rec;
  bool completed = false;
}

class _CompletedEntry {
  _CompletedEntry({required this.item, required this.completedAt});

  final _RecItem item;
  final DateTime completedAt;
}

_CurentEnergyStats _deriveCurentEnergyStats(
  List<EnergyReading> readings, {
  Map<String, dynamic>? usageResponse,
  String? selectedLocation,
}) {
  // If we have backend stats, use them directly
  if (usageResponse != null && usageResponse.containsKey('current_a')) {
    final currentAData =
        usageResponse['current_a'] as Map<String, dynamic>? ?? {};
    final currentMaData =
        usageResponse['current_ma'] as Map<String, dynamic>? ?? {};
    final powerWData = usageResponse['power_w'] as Map<String, dynamic>? ?? {};
    final trendData = usageResponse['trend'] as Map<String, dynamic>? ?? {};
    final signalData = usageResponse['signal'] as Map<String, dynamic>? ?? {};

    final double latestCurentA =
        (currentAData['latest'] as num?)?.toDouble() ?? 0;
    final double latestCurentMa =
        (currentMaData['latest'] as num?)?.toDouble() ?? 0;
    final double avgCurentA = (currentAData['avg'] as num?)?.toDouble() ?? 0;
    final double minCurentA = (currentAData['min'] as num?)?.toDouble() ?? 0;
    final double maxCurentA = (currentAData['max'] as num?)?.toDouble() ?? 0;

    final double latestPowerW = (powerWData['latest'] as num?)?.toDouble() ?? 0;
    final double avgPowerW = (powerWData['avg'] as num?)?.toDouble() ?? 0;

    final double deltaPercent =
        (trendData['percent_change'] as num?)?.toDouble() ?? 0;
    final String trendDirection =
        trendData['direction']?.toString() ?? 'stable';

    final String trendLabel;
    final Color trendColor;
    if (trendDirection == 'stable') {
      trendLabel = 'Stable';
      trendColor = Colors.blue;
    } else if (trendDirection == 'rising') {
      trendLabel = 'Rising';
      trendColor = Colors.orange;
    } else {
      trendLabel = 'Falling';
      trendColor = Colors.green;
    }

    final int? latestRssi = signalData['latest_rssi'] as int?;
    final String signalQuality = signalData['quality']?.toString() ?? 'unknown';

    final Color signalColor;
    if (signalQuality == 'strong') {
      signalColor = Colors.green;
    } else if (signalQuality == 'fair') {
      signalColor = Colors.orange;
    } else if (signalQuality == 'weak') {
      signalColor = Colors.red;
    } else {
      signalColor = Colors.grey;
    }

    final double estimatedEnergyKwh =
        (usageResponse['estimated_energy_kwh'] as num?)?.toDouble() ?? 0;
    final int sampleCount = usageResponse['total_readings'] as int? ?? 0;
    final int windowMinutes = usageResponse['time_window_minutes'] as int? ?? 0;

    // Parse the latest reading if available
    EnergyReading? latest;
    if (usageResponse['latest'] != null) {
      try {
        latest = EnergyReading.fromJson(
            Map<String, dynamic>.from(usageResponse['latest'] as Map));
      } catch (_) {
        // Use first reading as fallback
        latest = readings.isNotEmpty ? readings.first : null;
      }
    } else {
      latest = readings.isNotEmpty ? readings.first : null;
    }

    return _CurentEnergyStats(
      latest: latest,
      latestCurentA: latestCurentA,
      latestCurentMa: latestCurentMa,
      avgCurentA: avgCurentA,
      minCurentA: minCurentA,
      maxCurentA: maxCurentA,
      latestPowerW: latestPowerW,
      avgPowerW: avgPowerW,
      sampleCount: sampleCount,
      windowMinutes: windowMinutes,
      deltaPercent: deltaPercent,
      trendLabel: trendLabel,
      trendColor: trendColor,
      latestRssi: latestRssi,
      signalColor: signalColor,
      estimatedEnergyKwh: estimatedEnergyKwh,
    );
  }

  // Fallback to client-side computation if backend data not available
  if (readings.isEmpty) {
    return _CurentEnergyStats(
      latest: null,
      latestCurentA: 0,
      latestCurentMa: 0,
      avgCurentA: 0,
      minCurentA: 0,
      maxCurentA: 0,
      latestPowerW: 0,
      avgPowerW: 0,
      sampleCount: 0,
      windowMinutes: 0,
      deltaPercent: 0,
      trendLabel: 'Stable',
      trendColor: Colors.blue,
      latestRssi: null,
      signalColor: Colors.grey,
      estimatedEnergyKwh: 0,
    );
  }

  final List<EnergyReading> sorted = List.of(readings)
    ..sort((a, b) => a.receivedAt.compareTo(b.receivedAt));

  final EnergyReading latest = sorted.last;
  final List<double> currentValues =
      sorted.map((r) => r.currentA).where((v) => v >= 0).toList();

  final double avgCurentA = currentValues.isEmpty
      ? 0
      : currentValues.reduce((a, b) => a + b) / currentValues.length;
  final double minCurentA =
      currentValues.isEmpty ? 0 : currentValues.reduce((a, b) => a < b ? a : b);
  final double maxCurentA =
      currentValues.isEmpty ? 0 : currentValues.reduce((a, b) => a > b ? a : b);

  final double latestPowerW = latest.currentA * 230.0;
  final double avgPowerW = avgCurentA * 230.0;

  final List<EnergyReading> recentSlice =
      sorted.length >= 6 ? sorted.sublist(sorted.length - 3) : sorted;
  final List<EnergyReading> baselineSlice = sorted.length >= 6
      ? sorted.sublist(sorted.length - 6, sorted.length - 3)
      : sorted;

  final double recentAvg = recentSlice.isEmpty
      ? 0
      : recentSlice.map((r) => r.currentA).reduce((a, b) => a + b) /
          recentSlice.length;
  final double baselineAvg = baselineSlice.isEmpty
      ? 0
      : baselineSlice.map((r) => r.currentA).reduce((a, b) => a + b) /
          baselineSlice.length;

  final double deltaPercent =
      baselineAvg == 0 ? 0 : ((recentAvg - baselineAvg) / baselineAvg) * 100;

  final String trendLabel;
  final Color trendColor;
  if (deltaPercent.abs() < 5) {
    trendLabel = 'Stable';
    trendColor = Colors.blue;
  } else if (deltaPercent > 0) {
    trendLabel = 'Rising';
    trendColor = Colors.orange;
  } else {
    trendLabel = 'Falling';
    trendColor = Colors.green;
  }

  final int? latestRssi = latest.wifiRssi;
  final Color signalColor;
  if (latestRssi == null) {
    signalColor = Colors.grey;
  } else if (latestRssi >= -60) {
    signalColor = Colors.green;
  } else if (latestRssi >= -75) {
    signalColor = Colors.orange;
  } else {
    signalColor = Colors.red;
  }

  double estimatedEnergyKwh = 0;
  final dynamic usageList = usageResponse?['usage'];
  if (usageList is List) {
    final Iterable<Map<String, dynamic>> rows =
        usageList.whereType<Map>().map((e) => Map<String, dynamic>.from(e));
    for (final row in rows) {
      final String rowLocation = (row['location'] ?? '').toString();
      if (selectedLocation != null &&
          selectedLocation.isNotEmpty &&
          rowLocation != selectedLocation) {
        continue;
      }
      final double kwh = (row['energy_kwh'] as num?)?.toDouble() ?? 0;
      estimatedEnergyKwh += kwh;
    }
  }

  final DateTime firstTime = sorted.first.receivedAt;
  final DateTime lastTime = sorted.last.receivedAt;
  final int windowMinutes =
      lastTime.difference(firstTime).inMinutes.clamp(0, 1 << 16).toInt();

  return _CurentEnergyStats(
    latest: latest,
    latestCurentA: latest.currentA,
    latestCurentMa: latest.currentMa,
    avgCurentA: avgCurentA,
    minCurentA: minCurentA,
    maxCurentA: maxCurentA,
    latestPowerW: latestPowerW,
    avgPowerW: avgPowerW,
    sampleCount: sorted.length,
    windowMinutes: windowMinutes,
    deltaPercent: deltaPercent,
    trendLabel: trendLabel,
    trendColor: trendColor,
    latestRssi: latestRssi,
    signalColor: signalColor,
    estimatedEnergyKwh: estimatedEnergyKwh,
  );
}

_DerivedStats _deriveStats(List<SensorReading> readings) {
  final List<SensorReading> sorted = List.of(readings)
    ..sort((a, b) => a.receivedAt.compareTo(b.receivedAt));
  final SensorReading latest = sorted.last;

  final double avgTemp =
      sorted.map((r) => r.temperature).reduce((a, b) => a + b) / sorted.length;
  final double avgHumidity =
      sorted.map((r) => r.humidity).reduce((a, b) => a + b) / sorted.length;

  final SensorReading lastOccupied =
      sorted.reversed.firstWhere((r) => r.occupied, orElse: () => latest);
  final int vacancyMinutes = lastOccupied == latest
      ? 0
      : latest.receivedAt
          .difference(lastOccupied.receivedAt)
          .inMinutes
          .clamp(0, 1 << 16)
          .toInt();

  final int rssi = latest.rssi ?? -80;
  final String signalLabel;
  final Color signalColor;
  if (rssi >= -60) {
    signalLabel = 'Strong';
    signalColor = Colors.green;
  } else if (rssi >= -75) {
    signalLabel = 'Fair';
    signalColor = Colors.amber;
  } else {
    signalLabel = 'Weak';
    signalColor = Colors.red;
  }

  final double tempBandProgress =
      (((latest.temperature - 20) / 10).clamp(0, 1)).toDouble();
  final Color tempColor = latest.temperature > 30
      ? Colors.red
      : (latest.temperature >= 27 ? Colors.orange : Colors.green);
  final Color humidityColor = latest.humidity > 70
      ? Colors.orange
      : (latest.humidity < 40 ? Colors.amber : Colors.green);
  final String comfortNote = latest.temperature > 30
      ? 'Hot drift: lower setpoint or turn off if vacant.'
      : latest.temperature < 23
          ? 'Cooler than typical. Check setpoint.'
          : 'Within comfort band.';

  return _DerivedStats(
    avgTemp: avgTemp,
    avgHumidity: avgHumidity,
    latestTemp: latest.temperature,
    latestHumidity: latest.humidity,
    isOccupied: latest.occupied,
    vacancyMinutes: vacancyMinutes,
    signalLabel: signalLabel,
    signalColor: signalColor,
    tempStatusColor: tempColor,
    humidityStatusColor: humidityColor,
    comfortNote: comfortNote,
    tempBandProgress: tempBandProgress,
  );
}

List<_Recommendation> _buildRecList(_DerivedStats stats) {
  final List<_Recommendation> recs = [];
  if (!stats.isOccupied &&
      stats.latestTemp > 31 &&
      stats.vacancyMinutes >= 30) {
    recs.add(_Recommendation(
      title: 'Turn off AC in vacant room',
      detail:
          'Vacant for ${stats.vacancyMinutes} min at ${stats.latestTemp.toStringAsFixed(1)}°C.',
      cta: 'Send Alert',
      color: Colors.red,
      icon: Icons.ac_unit,
    ));
  }
  recs.add(_Recommendation(
    title: 'Align motion sensing',
    detail:
        'RCWL often 1 while PIR 0. Reposition sensor to reduce false motion.',
    cta: 'Inspect',
    color: Colors.indigo,
    icon: Icons.sensors,
  ));
  recs.add(_Recommendation(
    title: 'Check link quality',
    detail: 'RSSI ${stats.signalLabel}. Move gateway or adjust antenna.',
    cta: 'Check Link',
    color: stats.signalColor,
    icon: Icons.network_check,
  ));
  recs.add(_Recommendation(
    title: 'Comfort guardrails',
    detail: 'Keep 24-27°C occupied; allow 29-30°C when vacant to save energy.',
    cta: 'Apply',
    color: Colors.teal,
    icon: Icons.rule,
  ));
  return recs;
}
