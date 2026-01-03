import 'package:flutter/material.dart';
import '../screens/welcome_screen.dart';
import 'profile_edit_page.dart';

/// Profile page showing user information and settings with goals and preferences
class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  String _name = 'Sakya Institute';
  String _email = 'sakya@example.com';
  final TextEditingController _billAmountController =
    TextEditingController(text: '1850');
  DateTime _selectedMonth =
      DateTime(DateTime.now().year, DateTime.now().month, 1);
  final List<_BillEntry> _billHistory = [
    _BillEntry(
        month: DateTime(DateTime.now().year, DateTime.now().month - 1, 1),
        amount: 2200),
    _BillEntry(
        month: DateTime(DateTime.now().year, DateTime.now().month, 1),
        amount: 1850),
  ];
  double _comfortTemp = 24;
  bool _preferLightingSavings = true;
  bool _preferHvacSavings = true;
  bool _quietHoursEnabled = true;
  TimeOfDay _quietStart = const TimeOfDay(hour: 22, minute: 0);
  TimeOfDay _quietEnd = const TimeOfDay(hour: 6, minute: 0);

  @override
  void dispose() {
    _billAmountController.dispose();
    super.dispose();
  }

  Future<void> _pickTime(bool isStart) async {
    final initial = isStart ? _quietStart : _quietEnd;
    final picked = await showTimePicker(
      context: context,
      initialTime: initial,
    );
    if (picked != null) {
      setState(() {
        if (isStart) {
          _quietStart = picked;
        } else {
          _quietEnd = picked;
        }
      });
    }
  }

  void _savePreferences() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Preferences saved (local only for now)')),
    );
  }

  Future<void> _openEditProfile() async {
    final result = await Navigator.push<Map<String, String>>(
      context,
      MaterialPageRoute(
        builder: (context) => ProfileEditPage(
          initialName: _name,
          initialEmail: _email,
        ),
      ),
    );

    if (result != null) {
      setState(() {
        _name = result['name'] ?? _name;
        _email = result['email'] ?? _email;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Profile saved for $_name ($_email)')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Profile'),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            onPressed: _openEditProfile,
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            // Profile Header
            Card(
              elevation: 2,
              child: Padding(
                padding: const EdgeInsets.all(20.0),
                child: Column(
                  children: [
                    CircleAvatar(
                      radius: 50,
                      backgroundColor:
                          Theme.of(context).colorScheme.primaryContainer,
                      child: Icon(
                        Icons.person,
                        size: 50,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      _name,
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _email,
                      style: TextStyle(
                        fontSize: 16,
                        color: Colors.grey[600],
                      ),
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: _openEditProfile,
                      icon: const Icon(Icons.edit_outlined),
                      label: const Text('Edit Profile'),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            _buildGoalsCard(context),
            const SizedBox(height: 16),
            _buildPreferencesCard(context),
            const SizedBox(height: 16),
            _buildQuietHoursCard(context),
            const SizedBox(height: 24),
            // Logout
            SizedBox(
              width: double.infinity,
              height: 48,
              child: OutlinedButton.icon(
                onPressed: () {
                  showDialog(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: const Text('Logout'),
                      content: const Text('Are you sure you want to logout?'),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('Cancel'),
                        ),
                        ElevatedButton(
                          onPressed: () {
                            Navigator.pop(context);
                            Navigator.pushAndRemoveUntil(
                              context,
                              MaterialPageRoute(
                                builder: (context) => const WelcomeScreen(),
                              ),
                              (route) => false,
                            );
                          },
                          child: const Text('Logout'),
                        ),
                      ],
                    ),
                  );
                },
                icon: const Icon(Icons.logout),
                label: const Text('Logout'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.red,
                  side: const BorderSide(color: Colors.red),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Version 1.0.0',
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[600],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGoalsCard(BuildContext context) {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: const [
                Icon(Icons.receipt_long_outlined),
                SizedBox(width: 8),
                Text(
                  'Bills (LKR)',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _pickMonth,
                    icon: const Icon(Icons.calendar_today_outlined),
                    label: Text(_formatMonth(_selectedMonth)),
                  ),
                ),
                const SizedBox(width: 12),
                SizedBox(
                  width: 140,
                  child: TextField(
                    controller: _billAmountController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Bill (LKR)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                ElevatedButton(
                  onPressed: _addBillEntry,
                  child: const Text('Save'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _buildBillDelta(),
            const SizedBox(height: 12),
            _buildBillHistory(),
          ],
        ),
      ),
    );
  }

  Widget _buildBillDelta() {
    if (_billHistory.length < 2) {
      return const Text('Add at least two months to see change');
    }

    final sorted = [..._billHistory]
      ..sort((a, b) => a.month.compareTo(b.month));
    final last = sorted[sorted.length - 2].amount;
    final current = sorted.last.amount;
    final delta = current - last;
    final pct = last > 0 ? (delta / last) * 100 : 0;
    final isUp = delta > 0;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isUp ? Colors.red[50] : Colors.green[50],
        borderRadius: BorderRadius.circular(12),
        border:
            Border.all(color: (isUp ? Colors.red[200] : Colors.green[200])!),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Change vs last month',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 4),
              Text(
                '${isUp ? '▲' : '▼'} LKR ${delta.abs().toStringAsFixed(0)}',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: isUp ? Colors.red[700] : Colors.green[700],
                ),
              ),
            ],
          ),
          Text(
            '${pct.abs().toStringAsFixed(1)}% ${isUp ? 'higher' : 'lower'}',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: isUp ? Colors.red[700] : Colors.green[700],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBillHistory() {
    final sorted = [..._billHistory]
      ..sort((a, b) => b.month.compareTo(a.month));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'History',
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        ...sorted.take(6).map(
              (entry) => ListTile(
                dense: true,
                leading: const Icon(Icons.calendar_today, size: 20),
                title: Text(_formatMonth(entry.month)),
                trailing: Text('LKR ${entry.amount.toStringAsFixed(0)}'),
              ),
            ),
      ],
    );
  }

  Future<void> _pickMonth() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedMonth,
      firstDate: DateTime(now.year - 2, 1),
      lastDate: DateTime(now.year + 1, 12),
      helpText: 'Select bill month',
    );

    if (picked != null) {
      setState(() {
        _selectedMonth = DateTime(picked.year, picked.month, 1);
      });
    }
  }

  void _addBillEntry() {
    final amount = double.tryParse(_billAmountController.text);
    if (amount == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a valid bill amount in LKR')),
      );
      return;
    }

    // Replace existing entry for the month or add new
    final existingIndex = _billHistory.indexWhere((e) =>
        e.month.year == _selectedMonth.year &&
        e.month.month == _selectedMonth.month);
    if (existingIndex >= 0) {
      _billHistory[existingIndex] =
          _BillEntry(month: _selectedMonth, amount: amount);
    } else {
      _billHistory.add(_BillEntry(month: _selectedMonth, amount: amount));
    }

    setState(() {
      // re-render with updated history
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Saved ${_formatMonth(_selectedMonth)} bill')),
    );
  }

  String _formatMonth(DateTime dt) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec'
    ];
    return '${months[dt.month - 1]} ${dt.year}';
  }

  Widget _buildPreferencesCard(BuildContext context) {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: const [
                Icon(Icons.tune),
                SizedBox(width: 8),
                Text(
                  'Recommendation Preferences',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Comfort temperature (°C)'),
                Text('${_comfortTemp.toStringAsFixed(0)}°'),
              ],
            ),
            Slider(
              value: _comfortTemp,
              min: 18,
              max: 28,
              divisions: 10,
              label: '${_comfortTemp.toStringAsFixed(0)}°C',
              onChanged: (v) => setState(() => _comfortTemp = v),
            ),
            SwitchListTile(
              title: const Text('Prioritize lighting savings'),
              value: _preferLightingSavings,
              onChanged: (v) => setState(() => _preferLightingSavings = v),
            ),
            SwitchListTile(
              title: const Text('Prioritize HVAC savings'),
              value: _preferHvacSavings,
              onChanged: (v) => setState(() => _preferHvacSavings = v),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuietHoursCard(BuildContext context) {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: const [
                Icon(Icons.nights_stay_outlined),
                SizedBox(width: 8),
                Text(
                  'Quiet Hours / Alerts',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
              ],
            ),
            const SizedBox(height: 12),
            SwitchListTile(
              title: const Text('Silence non-critical alerts'),
              value: _quietHoursEnabled,
              onChanged: (v) => setState(() => _quietHoursEnabled = v),
            ),
            if (_quietHoursEnabled) ...[
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Start: ${_quietStart.format(context)}'),
                  TextButton(
                    onPressed: () => _pickTime(true),
                    child: const Text('Change'),
                  ),
                ],
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('End: ${_quietEnd.format(context)}'),
                  TextButton(
                    onPressed: () => _pickTime(false),
                    child: const Text('Change'),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _BillEntry {
  final DateTime month;
  final double amount;

  _BillEntry({required this.month, required this.amount});
}
