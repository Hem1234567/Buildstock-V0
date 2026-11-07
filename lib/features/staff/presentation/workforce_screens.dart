import 'package:drift/drift.dart' show OrderingTerm;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:buildstock/app/theme/app_theme.dart';
import 'package:buildstock/core/database/app_database.dart';
import 'package:buildstock/core/domain/enums.dart';
import 'package:buildstock/core/utils/dates.dart';
import 'package:buildstock/core/utils/money.dart';
import 'package:buildstock/core/widgets/app_form.dart';
import 'package:buildstock/core/widgets/async_view.dart';
import 'package:buildstock/core/widgets/section_card.dart';
import 'package:buildstock/core/database/database_provider.dart';
import 'package:buildstock/features/business/data/business_repository.dart';
import 'package:buildstock/features/staff/data/salary_slip_pdf.dart';
import 'package:buildstock/features/staff/data/workforce_repository.dart';
import 'package:buildstock/core/widgets/feedback.dart';
import 'package:collection/collection.dart';

final attendanceStreamProvider =
    StreamProvider.family<List<AttendanceRow>, DateTime>((ref, date) {
      return ref.watch(workforceRepositoryProvider).watchAttendance(date);
    });

class StaffListScreen extends ConsumerStatefulWidget {
  const StaffListScreen({super.key});

  @override
  ConsumerState<StaffListScreen> createState() => _StaffListScreenState();
}

class _StaffListScreenState extends ConsumerState<StaffListScreen> {
  final _search = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final staff = ref.watch(staffStreamProvider(_query));
    return Scaffold(
      appBar: AppBar(title: const Text('Staff')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push('/staff/new'),
        icon: const Icon(Icons.person_add_alt),
        label: const Text('Add staff'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: SearchField(
              controller: _search,
              hint: 'Search staff',
              onChanged: (value) => setState(() => _query = value),
            ),
          ),
          Expanded(
            child: AsyncView(
              value: staff,
              builder: (rows) {
                if (rows.isEmpty) {
                  return const EmptyState(
                    title: 'No staff records',
                    message: 'Add real employees to record attendance, salaries and role permissions.',
                    icon: Icons.badge_outlined,
                  );
                }
                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
                  itemCount: rows.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final member = rows[index];
                    return SectionCard(
                      padding: const EdgeInsets.all(14),
                      onTap: () => context.push('/staff/${member.id}/edit'),
                      child: Row(
                        children: [
                          CircleAvatar(
                            radius: 20,
                            backgroundColor: AppColors.accentSoft,
                            child: Text(
                              member.fullName.isEmpty
                                  ? '?'
                                  : member.fullName[0].toUpperCase(),
                              style: const TextStyle(
                                color: AppColors.accent,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  member.fullName,
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleMedium,
                                ),
                                Text(
                                  '${member.designation.isEmpty ? member.role : member.designation} · ${member.employeeCode}',
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              ],
                            ),
                          ),
                          Text(
                            Money.format(member.basicSalaryPaise),
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        ],
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class StaffFormScreen extends ConsumerWidget {
  const StaffFormScreen({super.key, this.staffId});

  final String? staffId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    StaffRow? staff;
    if (staffId != null) {
      staff = ref
          .watch(staffStreamProvider(''))
          .value
          ?.where((row) => row.id == staffId)
          .firstOrNull;
    }
    return AppFormScreen(
      title: staffId == null ? 'Add staff' : 'Edit staff',
      saveLabel: 'Save staff',
      fields: [
        AppField(
          key: 'fullName',
          label: 'Full name',
          required: true,
          initial: staff?.fullName,
        ),
        AppField(
          key: 'employeeCode',
          label: 'Employee code',
          initial: staff?.employeeCode,
        ),
        AppField(
          key: 'phone',
          label: 'Phone',
          type: AppFieldType.phone,
          initial: staff?.phone,
        ),
        AppField(
          key: 'address',
          label: 'Address',
          type: AppFieldType.multiline,
          initial: staff?.address,
        ),
        AppField(
          key: 'designation',
          label: 'Designation',
          initial: staff?.designation,
        ),
        AppField(
          key: 'department',
          label: 'Department',
          initial: staff?.department,
        ),
        AppField(
          key: 'role',
          label: 'Role',
          type: AppFieldType.dropdown,
          initial: staff?.role ?? UserRole.staff,
          options: const [
            AppFieldOption('manager', 'Manager'),
            AppFieldOption('cashier', 'Cashier'),
            AppFieldOption('staff', 'Sales / general staff'),
            AppFieldOption('accountant', 'Accountant'),
            AppFieldOption('admin', 'Administrator'),
          ],
        ),
        AppField(
          key: 'employmentType',
          label: 'Employment type',
          type: AppFieldType.dropdown,
          initial: staff?.employmentType ?? 'Permanent',
          options: const [
            AppFieldOption('Permanent', 'Permanent'),
            AppFieldOption('Temporary', 'Temporary'),
            AppFieldOption('Contract', 'Contract'),
            AppFieldOption('Part-time', 'Part-time'),
            AppFieldOption('Daily Wage', 'Daily Wage'),
          ],
        ),
        AppField(
          key: 'salaryType',
          label: 'Salary type',
          type: AppFieldType.dropdown,
          initial: staff?.salaryType ?? 'monthly',
          options: const [
            AppFieldOption('monthly', 'Monthly'),
            AppFieldOption('daily', 'Daily wage'),
            AppFieldOption('weekly', 'Weekly'),
            AppFieldOption('hourly', 'Hourly'),
          ],
        ),
        AppField(
          key: 'basicSalary',
          label: 'Basic salary / rate',
          type: AppFieldType.money,
          initial: staff?.basicSalaryPaise,
        ),
        AppField(
          key: 'joiningDate',
          label: 'Joining date',
          type: AppFieldType.date,
          initial: staff?.joiningDate,
        ),
        AppField(
          key: 'emergencyName',
          label: 'Emergency contact name',
          initial: staff?.emergencyContactName,
        ),
        AppField(
          key: 'emergencyPhone',
          label: 'Emergency contact phone',
          type: AppFieldType.phone,
          initial: staff?.emergencyContactPhone,
        ),
        AppField(
          key: 'photo',
          label: 'Staff photo',
          type: AppFieldType.photo,
          photoOwner: 'staff',
          initial: staff?.photoRef,
        ),
        AppField(
          key: 'notes',
          label: 'Notes',
          type: AppFieldType.multiline,
          initial: staff?.notes,
        ),
      ],
      onSave: (values) async {
        await ref
            .read(workforceRepositoryProvider)
            .saveStaff(
              StaffInput(
                fullName: values['fullName'] as String? ?? '',
                employeeCode: values['employeeCode'] as String? ?? '',
                phone: values['phone'] as String? ?? '',
                address: values['address'] as String? ?? '',
                designation: values['designation'] as String? ?? '',
                department: values['department'] as String? ?? '',
                role: values['role'] as String? ?? UserRole.staff,
                employmentType:
                    values['employmentType'] as String? ?? 'Permanent',
                salaryType: values['salaryType'] as String? ?? 'monthly',
                basicSalaryPaise: values['basicSalary'] as int? ?? 0,
                joiningDate: values['joiningDate'] as DateTime?,
                emergencyContactName: values['emergencyName'] as String? ?? '',
                emergencyContactPhone:
                    values['emergencyPhone'] as String? ?? '',
                photoRef: values['photo'] as String?,
                notes: values['notes'] as String? ?? '',
              ),
              existingId: staffId,
            );
        ref.invalidate(staffStreamProvider);
      },
    );
  }
}

class DriverListScreen extends ConsumerWidget {
  const DriverListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final drivers = ref.watch(driversStreamProvider(''));
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Drivers & vehicles'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Drivers'),
              Tab(text: 'Vehicles'),
            ],
          ),
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () => context.push('/drivers/new'),
          icon: const Icon(Icons.add),
          label: const Text('Add driver'),
        ),
        body: TabBarView(
          children: [
            AsyncView(
              value: drivers,
              builder: (rows) {
                if (rows.isEmpty) {
                  return const EmptyState(
                    title: 'No drivers yet',
                    message: 'Add drivers and vehicles to assign deliveries and track delivery history.',
                    icon: Icons.drive_eta_outlined,
                  );
                }
                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                  itemCount: rows.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final driver = rows[index];
                    return SectionCard(
                      padding: const EdgeInsets.all(14),
                      onTap: () => context.push('/drivers/${driver.id}/edit'),
                      child: Row(
                        children: [
                          const Icon(Icons.drive_eta_outlined),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  driver.fullName,
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleMedium,
                                ),
                                Text(
                                  '${driver.licenceNumber.isEmpty ? 'No licence on file' : driver.licenceNumber} · ${driver.phone}',
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              ],
                            ),
                          ),
                          Text(Money.format(driver.basicSalaryPaise)),
                        ],
                      ),
                    );
                  },
                );
              },
            ),
            const _VehicleList(),
          ],
        ),
      ),
    );
  }
}

class _VehicleList extends ConsumerWidget {
  const _VehicleList();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final vehicles = ref.watch(vehiclesStreamProvider);
    return Scaffold(
      body: AsyncView(
        value: vehicles,
        builder: (rows) {
          if (rows.isEmpty) {
            return const EmptyState(
              title: 'No vehicles yet',
              message: 'Add the lorries and vans used for deliveries to track insurance and assignments.',
              icon: Icons.local_shipping_outlined,
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
            itemCount: rows.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final vehicle = rows[index];
              return SectionCard(
                padding: const EdgeInsets.all(14),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            vehicle.registrationNumber,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          Text(
                            [
                              vehicle.make,
                              vehicle.model,
                              vehicle.vehicleType,
                            ].where((value) => value.isNotEmpty).join(' · '),
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                    Text(
                      vehicle.insuranceExpiry == null
                          ? 'No insurance date'
                          : 'Ins. ${AppDate.display(vehicle.insuranceExpiry!)}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showVehicleForm(context, ref),
        icon: const Icon(Icons.add),
        label: const Text('Add vehicle'),
      ),
    );
  }

  Future<void> _showVehicleForm(BuildContext context, WidgetRef ref) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => Scaffold(
          appBar: AppBar(title: const Text('Add vehicle')),
          body: AppFormScreen(
            title: 'Add vehicle',
            saveLabel: 'Save vehicle',
            fields: const [
              AppField(
                key: 'registration',
                label: 'Registration number',
                required: true,
              ),
              AppField(key: 'type', label: 'Vehicle type'),
              AppField(key: 'make', label: 'Make'),
              AppField(key: 'model', label: 'Model'),
              AppField(key: 'capacity', label: 'Capacity'),
              AppField(
                key: 'insurance',
                label: 'Insurance expiry',
                type: AppFieldType.date,
              ),
              AppField(
                key: 'notes',
                label: 'Notes',
                type: AppFieldType.multiline,
              ),
            ],
            onSave: (values) async {
              await ref
                  .read(workforceRepositoryProvider)
                  .saveVehicle(
                    VehicleInput(
                      registrationNumber:
                          values['registration'] as String? ?? '',
                      vehicleType: values['type'] as String? ?? '',
                      make: values['make'] as String? ?? '',
                      model: values['model'] as String? ?? '',
                      capacity: values['capacity'] as String? ?? '',
                      insuranceExpiry: values['insurance'] as DateTime?,
                      notes: values['notes'] as String? ?? '',
                    ),
                  );
              ref.invalidate(vehiclesStreamProvider);
            },
          ),
        ),
      ),
    );
  }
}

class DriverFormScreen extends ConsumerWidget {
  const DriverFormScreen({super.key, this.driverId});

  final String? driverId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final drivers = ref.watch(driversStreamProvider('')).value ?? const [];
    final driver = driverId == null
        ? null
        : drivers.where((row) => row.id == driverId).firstOrNull;
    return AppFormScreen(
      title: driverId == null ? 'Add driver' : 'Edit driver',
      saveLabel: 'Save driver',
      fields: [
        AppField(
          key: 'fullName',
          label: 'Full name',
          required: true,
          initial: driver?.fullName,
        ),
        AppField(
          key: 'driverCode',
          label: 'Driver code',
          initial: driver?.driverCode,
        ),
        AppField(
          key: 'phone',
          label: 'Phone',
          type: AppFieldType.phone,
          initial: driver?.phone,
        ),
        AppField(
          key: 'licence',
          label: 'Licence number',
          initial: driver?.licenceNumber,
        ),
        AppField(
          key: 'licenceExpiry',
          label: 'Licence expiry',
          type: AppFieldType.date,
          initial: driver?.licenceExpiryDate,
        ),
        AppField(
          key: 'salaryType',
          label: 'Salary type',
          type: AppFieldType.dropdown,
          initial: driver?.salaryType ?? 'monthly',
          options: const [
            AppFieldOption('monthly', 'Monthly'),
            AppFieldOption('daily', 'Daily'),
            AppFieldOption('weekly', 'Weekly'),
          ],
        ),
        AppField(
          key: 'basicSalary',
          label: 'Salary / rate',
          type: AppFieldType.money,
          initial: driver?.basicSalaryPaise,
        ),
        AppField(
          key: 'joiningDate',
          label: 'Joining date',
          type: AppFieldType.date,
          initial: driver?.joiningDate,
        ),
        AppField(
          key: 'photo',
          label: 'Driver photo',
          type: AppFieldType.photo,
          photoOwner: 'driver',
          initial: driver?.photoRef,
        ),
        AppField(
          key: 'notes',
          label: 'Notes',
          type: AppFieldType.multiline,
          initial: driver?.notes,
        ),
      ],
      onSave: (values) async {
        await ref
            .read(workforceRepositoryProvider)
            .saveDriver(
              DriverInput(
                fullName: values['fullName'] as String? ?? '',
                driverCode: values['driverCode'] as String? ?? '',
                phone: values['phone'] as String? ?? '',
                licenceNumber: values['licence'] as String? ?? '',
                licenceExpiry: values['licenceExpiry'] as DateTime?,
                salaryType: values['salaryType'] as String? ?? 'monthly',
                basicSalaryPaise: values['basicSalary'] as int? ?? 0,
                joiningDate: values['joiningDate'] as DateTime?,
                photoRef: values['photo'] as String?,
                notes: values['notes'] as String? ?? '',
              ),
              existingId: driverId,
            );
        ref.invalidate(driversStreamProvider);
      },
    );
  }
}

class AttendanceScreen extends ConsumerStatefulWidget {
  const AttendanceScreen({super.key});

  @override
  ConsumerState<AttendanceScreen> createState() => _AttendanceScreenState();
}

class _AttendanceScreenState extends ConsumerState<AttendanceScreen> {
  DateTime _date = DateTime.now();

  @override
  Widget build(BuildContext context) {
    final staff = ref.watch(staffStreamProvider(''));
    final attendance = ref.watch(attendanceStreamProvider(_date));
    final recorded = {
      for (final row in attendance.value ?? const <AttendanceRow>[])
        row.staffId: row.status,
    };
    return Scaffold(
      appBar: AppBar(
        title: const Text('Attendance'),
        actions: [
          TextButton(
            onPressed: () async {
              final picked = await showDatePicker(
                context: context,
                initialDate: _date,
                firstDate: DateTime(2020),
                lastDate: DateTime.now(),
              );
              if (picked != null) setState(() => _date = picked);
            },
            child: Text(AppDate.display(_date)),
          ),
        ],
      ),
      body: AsyncView(
        value: staff,
        builder: (rows) {
          if (rows.isEmpty) {
            return const EmptyState(
              title: 'No staff',
              message: 'Add staff before recording attendance.',
              icon: Icons.fact_check_outlined,
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: rows.length,
            separatorBuilder: (_, _) => const Divider(),
            itemBuilder: (context, index) {
              final member = rows[index];
              final status = recorded[member.id];
              return ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(member.fullName),
                subtitle: Text(
                  status == null
                      ? 'Not marked'
                      : status.replaceAll('_', ' ').toUpperCase(),
                ),
                trailing: PopupMenuButton<String>(
                  icon: const Icon(Icons.more_horiz),
                  onSelected: (value) async {
                    await ref
                        .read(workforceRepositoryProvider)
                        .markAttendance(
                          staffId: member.id,
                          date: _date,
                          status: value,
                        );
                    ref.invalidate(attendanceStreamProvider);
                  },
                  itemBuilder: (context) => const [
                    PopupMenuItem(
                      value: AttendanceStatus.present,
                      child: Text('Present'),
                    ),
                    PopupMenuItem(
                      value: AttendanceStatus.absent,
                      child: Text('Absent'),
                    ),
                    PopupMenuItem(
                      value: AttendanceStatus.halfDay,
                      child: Text('Half day'),
                    ),
                    PopupMenuItem(
                      value: AttendanceStatus.paidLeave,
                      child: Text('Paid leave'),
                    ),
                    PopupMenuItem(
                      value: AttendanceStatus.unpaidLeave,
                      child: Text('Unpaid leave'),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class SalaryScreen extends ConsumerStatefulWidget {
  const SalaryScreen({super.key});

  @override
  ConsumerState<SalaryScreen> createState() => _SalaryScreenState();
}

class _SalaryScreenState extends ConsumerState<SalaryScreen> {
  String _status = '';

  @override
  Widget build(BuildContext context) {
    final salaries = ref.watch(salaryStreamProvider(_status));
    return Scaffold(
      appBar: AppBar(
        title: const Text('Salary'),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.filter_list),
            onSelected: (value) => setState(() => _status = value),
            itemBuilder: (context) => const [
              PopupMenuItem(value: '', child: Text('All')),
              PopupMenuItem(value: 'pending', child: Text('Pending')),
              PopupMenuItem(
                value: 'partially_paid',
                child: Text('Partly paid'),
              ),
              PopupMenuItem(value: 'paid', child: Text('Paid')),
            ],
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _generate,
        icon: const Icon(Icons.calculate_outlined),
        label: const Text('Generate'),
      ),
      body: AsyncView(
        value: salaries,
        builder: (rows) {
          if (rows.isEmpty) {
            return const EmptyState(
              title: 'No salary records',
              message: 'Generate salary from attendance and configured pay rules. No amount is assumed automatically.',
              icon: Icons.payments_outlined,
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
            itemCount: rows.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final salary = rows[index];
              return SectionCard(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            salary.personName,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        ),
                        Text(
                          Money.format(salary.netSalaryPaise),
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ],
                    ),
                    Text(
                      '${AppDate.display(salary.periodStart)} – ${AppDate.display(salary.periodEnd)} · ${salary.status.replaceAll('_', ' ')}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: LinearProgressIndicator(
                            value: salary.netSalaryPaise == 0
                                ? 0
                                : (salary.amountPaidPaise /
                                          salary.netSalaryPaise)
                                      .clamp(0.0, 1.0),
                            minHeight: 5,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          'Balance ${Money.format(salary.balanceDuePaise)}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        TextButton(
                          onPressed: () => _slip(salary),
                          child: const Text('Slip'),
                        ),
                        if (salary.balanceDuePaise > 0)
                          TextButton(
                            onPressed: () => _pay(salary),
                            child: const Text('Pay'),
                          ),
                      ],
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }

  /// Builds the salary slip PDF and lets the user print or share it.
  Future<void> _slip(SalaryRecordRow salary) async {
    try {
      final db = ref.read(databaseProvider);
      final payments =
          await (db.select(db.salaryPayments)
                ..where((t) => t.salaryId.equals(salary.id))
                ..orderBy([(t) => OrderingTerm.asc(t.paidAt)]))
              .get();
      var code = '';
      var designation = '';
      if (salary.personType == 'driver') {
        final driver = await (db.select(
          db.drivers,
        )..where((t) => t.id.equals(salary.personId))).getSingleOrNull();
        code = driver?.driverCode ?? '';
        designation = 'Driver';
      } else {
        final staff = await (db.select(
          db.staffMembers,
        )..where((t) => t.id.equals(salary.personId))).getSingleOrNull();
        code = staff?.employeeCode ?? '';
        designation = staff?.designation ?? '';
      }
      final profile = await ref.read(businessRepositoryProvider).profile();
      const builder = SalarySlipPdfBuilder();
      final bytes = await builder.build(
        salary: salary,
        business: profile,
        payments: payments,
        employeeCode: code,
        designation: designation,
      );
      if (!mounted) return;
      final action = await showModalBottomSheet<String>(
        context: context,
        builder: (context) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.print_outlined),
                title: const Text('Print salary slip'),
                onTap: () => Navigator.pop(context, 'print'),
              ),
              ListTile(
                leading: const Icon(Icons.ios_share),
                title: const Text('Share PDF'),
                onTap: () => Navigator.pop(context, 'share'),
              ),
            ],
          ),
        ),
      );
      if (action == 'print') {
        await builder.print(bytes, 'Salary slip ${salary.personName}');
      } else if (action == 'share') {
        await builder.share(bytes, salary.personName, salary.periodStart);
      }
    } catch (error) {
      if (mounted) showActionMessage(context, error.toString());
    }
  }

  Future<void> _generate() async {
    final staff = ref.read(staffStreamProvider('')).value ?? const [];
    final drivers = ref.read(driversStreamProvider('')).value ?? const [];
    if (staff.isEmpty && drivers.isEmpty) {
      showActionMessage(context, 'Add staff or drivers first');
      return;
    }
    String personId = staff.isNotEmpty ? staff.first.id : drivers.first.id;
    String personType = staff.isNotEmpty ? 'staff' : 'driver';
    final now = DateTime.now();
    var start = DateTime(now.year, now.month, 1);
    var end = now;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 20,
          bottom: MediaQuery.of(context).viewInsets.bottom + 20,
        ),
        child: StatefulBuilder(
          builder: (context, setModalState) {
            final options = [
              for (final member in staff)
                (member.id, '${member.fullName} · staff', 'staff'),
              for (final driver in drivers)
                (driver.id, '${driver.fullName} · driver', 'driver'),
            ];
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Generate salary',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 4),
                Text(
                  'Basic pay is computed from the configured salary type and '
                  'recorded attendance. Review before paying.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: personId,
                  isExpanded: true,
                  items: options
                      .map(
                        (option) => DropdownMenuItem(
                          value: option.$1,
                          child: Text(option.$2),
                        ),
                      )
                      .toList(),
                  onChanged: (value) {
                    final selected = options.firstWhere(
                      (option) => option.$1 == value,
                    );
                    setModalState(() {
                      personId = selected.$1;
                      personType = selected.$3;
                    });
                  },
                  decoration: const InputDecoration(labelText: 'Person'),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () async {
                          final picked = await showDatePicker(
                            context: context,
                            initialDate: start,
                            firstDate: DateTime(2020),
                            lastDate: DateTime.now(),
                          );
                          if (picked != null) {
                            setModalState(() => start = picked);
                          }
                        },
                        child: Text('From ${AppDate.display(start)}'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () async {
                          final picked = await showDatePicker(
                            context: context,
                            initialDate: end,
                            firstDate: DateTime(2020),
                            lastDate: DateTime.now(),
                          );
                          if (picked != null) {
                            setModalState(() => end = picked);
                          }
                        },
                        child: Text('To ${AppDate.display(end)}'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: () async {
                    try {
                      await ref
                          .read(workforceRepositoryProvider)
                          .generateSalary(
                            personId: personId,
                            personType: personType,
                            periodStart: start,
                            periodEnd: end,
                          );
                      ref.invalidate(salaryStreamProvider);
                      if (context.mounted) Navigator.pop(context);
                    } catch (error) {
                      if (context.mounted) {
                        showActionMessage(context, error.toString());
                      }
                    }
                  },
                  child: const Text('Generate'),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Future<void> _pay(SalaryRecordRow salary) async {
    final amount = TextEditingController(
      text: (salary.balanceDuePaise / 100).toStringAsFixed(2),
    );
    var method = 'cash';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text('Pay ${salary.personName}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: amount,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'Amount',
                  prefixText: '₹ ',
                ),
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                initialValue: method,
                items: const [
                  DropdownMenuItem(value: 'cash', child: Text('Cash')),
                  DropdownMenuItem(value: 'bank', child: Text('Bank transfer')),
                  DropdownMenuItem(value: 'upi', child: Text('UPI')),
                ],
                onChanged: (value) =>
                    setDialogState(() => method = value ?? method),
                decoration: const InputDecoration(labelText: 'Method'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Pay'),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true) return;
    final paise = Money.tryParseRupees(amount.text) ?? 0;
    if (paise <= 0) return;
    try {
      await ref
          .read(workforceRepositoryProvider)
          .paySalary(salaryId: salary.id, amountPaise: paise, method: method);
      ref.invalidate(salaryStreamProvider);
      if (mounted) showActionMessage(context, 'Salary payment recorded');
    } catch (error) {
      if (mounted) showActionMessage(context, error.toString());
    }
  }
}
