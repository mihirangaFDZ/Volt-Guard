import 'package:flutter/material.dart';
import 'package:volt_guard/screens/login_screen.dart';
import 'package:volt_guard/services/auth_service.dart';
import 'package:volt_guard/services/user_service.dart';

/// Profile page showing user information and settings
class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  final _authService = AuthService();
  final _userService = UserService();

  String? _userId;
  Map<String, dynamic>? _user;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    final userId = await _authService.getUserId();
    if (!mounted) return;

    if (userId == null || userId.isEmpty) {
      setState(() {
        _userId = null;
        _user = null;
        _loading = false;
        _error = 'Session missing user id. Please login again.';
      });
      return;
    }

    _userId = userId;
    final result = await _userService.getUserById(userId);
    if (!mounted) return;

    if (result['error'] == true) {
      setState(() {
        _user = null;
        _loading = false;
        _error = result['message']?.toString() ?? 'Failed to load profile';
      });
      return;
    }

    setState(() {
      _user = result;
      _loading = false;
      _error = null;
    });
  }

  Future<void> _logout() async {
    await _authService.logout();
    if (!mounted) return;
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (route) => false,
    );
  }

  Future<void> _editProfile() async {
    final userId = _userId;
    final user = _user;
    if (userId == null || user == null) return;

    final nameController =
        TextEditingController(text: (user['name'] ?? '').toString());
    final emailController =
        TextEditingController(text: (user['email'] ?? '').toString());
    final formKey = GlobalKey<FormState>();

    final shouldRefresh = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) {
        final bottomInset = MediaQuery.of(context).viewInsets.bottom;
        return Padding(
          padding: EdgeInsets.only(
              left: 16, right: 16, top: 8, bottom: bottomInset + 16),
          child: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Edit Profile',
                  style: Theme.of(context)
                      .textTheme
                      .titleLarge
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: nameController,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: 'Name',
                    prefixIcon: Icon(Icons.badge_outlined),
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Name is required';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: emailController,
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.done,
                  decoration: const InputDecoration(
                    labelText: 'Email',
                    prefixIcon: Icon(Icons.email_outlined),
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Email is required';
                    }
                    final emailRegex = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
                    if (!emailRegex.hasMatch(value.trim())) {
                      return 'Enter a valid email';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: () async {
                    if (!formKey.currentState!.validate()) return;

                    final result = await _userService.updateUserById(
                      userId,
                      name: nameController.text.trim(),
                      email: emailController.text.trim(),
                    );
                    if (!context.mounted) return;

                    if (result['success'] == true) {
                      Navigator.pop(context, true);
                      return;
                    }

                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                            result['message']?.toString() ?? 'Update failed'),
                        backgroundColor: Colors.red,
                      ),
                    );
                  },
                  icon: const Icon(Icons.save_outlined),
                  label: const Text('Save Changes'),
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Cancel'),
                ),
              ],
            ),
          ),
        );
      },
    );

    if (shouldRefresh == true) {
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Profile updated successfully')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = _user;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Profile'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.all(16.0),
          children: [
            if (_loading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 32),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_error != null)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        _error!,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                      const SizedBox(height: 12),
                      FilledButton.icon(
                        onPressed: _logout,
                        icon: const Icon(Icons.login_outlined),
                        label: const Text('Go to Login'),
                      ),
                    ],
                  ),
                ),
              )
            else
              Card(
                elevation: 1,
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
                        (user?['name'] ?? 'User').toString(),
                        style: const TextStyle(
                            fontSize: 24, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        (user?['email'] ?? '').toString(),
                        style: TextStyle(fontSize: 16, color: Colors.grey[600]),
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        alignment: WrapAlignment.center,
                        children: [
                          if (user?['role'] != null)
                            Chip(
                              label: Text('Role: ${user!['role']}'),
                            ),
                          if (user?['user_id'] != null)
                            Chip(
                              label: Text('ID: ${user!['user_id']}'),
                            ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      OutlinedButton.icon(
                        onPressed: _editProfile,
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
                            _logout();
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
