import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:buildstock/core/audit/audit_writer.dart';
import 'package:buildstock/core/database/app_database.dart';
import 'package:buildstock/core/database/database_provider.dart';
import 'package:buildstock/core/domain/enums.dart';
import 'package:buildstock/core/errors/app_failure.dart';
import 'package:buildstock/core/utils/dates.dart';
import 'package:buildstock/core/utils/ids.dart';
import 'package:buildstock/core/utils/json.dart';

class StaffInput {
  const StaffInput({
    required this.fullName,
    required this.employeeCode,
    this.phone = '',
    this.email = '',
    this.address = '',
    this.designation = '',
    this.department = '',
    this.role = UserRole.staff,
    this.employmentType = 'Permanent',
    this.assignedStoreId,
    this.salaryType = SalaryType.monthly,
    this.basicSalaryPaise = 0,
    this.joiningDate,
    this.emergencyContactName = '',
    this.emergencyContactPhone = '',
    this.notes = '',
    this.photoRef,
    this.permissions = const [],
  });

  final String fullName;
  final String employeeCode;
  final String phone;
  final String email;
  final String address;
  final String designation;
  final String department;
  final String role;
  final String employmentType;
  final String? assignedStoreId;
  final String salaryType;
  final int basicSalaryPaise;
  final DateTime? joiningDate;
  final String emergencyContactName;
  final String emergencyContactPhone;
  final String notes;
  final String? photoRef;
  final List<String> permissions;
}

class DriverInput {
  const DriverInput({
    required this.fullName,
    required this.driverCode,
    this.phone = '',
    this.address = '',
    this.licenceNumber = '',
    this.licenceExpiry,
    this.assignedStoreId,
    this.vehicleId,
    this.salaryType = SalaryType.monthly,
    this.basicSalaryPaise = 0,
    this.joiningDate,
    this.notes = '',
    this.photoRef,
  });

  final String fullName;
  final String driverCode;
  final String phone;
  final String address;
  final String licenceNumber;
  final DateTime? licenceExpiry;
  final String? assignedStoreId;
  final String? vehicleId;
  final String salaryType;
  final int basicSalaryPaise;
  final DateTime? joiningDate;
  final String notes;
  final String? photoRef;
}

class VehicleInput {
  const VehicleInput({
    required this.registrationNumber,
    this.vehicleType = '',
    this.make = '',
    this.model = '',
    this.capacity = '',
    this.assignedStoreId,
    this.assignedDriverId,
    this.insuranceExpiry,
    this.notes = '',
  });

  final String registrationNumber;
  final String vehicleType;
  final String make;
  final String model;
  final String capacity;
  final String? assignedStoreId;
  final String? assignedDriverId;
  final DateTime? insuranceExpiry;
  final String notes;
}

class WorkforceRepository {
  WorkforceRepository(this.services);

  final AppServices services;

  AppDatabase get db => services.db;
  AuditWriter get audit => AuditWriter(services);

  // ------------------------------------------------------------------- staff

  Stream<List<StaffRow>> watchStaff({String query = ''}) {
    final statement = db.select(db.staffMembers)
      ..where((t) => t.deletedAt.isNull());
    if (query.trim().isNotEmpty) {
      final pattern = '%${query.trim()}%';
      statement.where(
        (t) =>
            t.fullName.like(pattern) |
            t.phone.like(pattern) |
            t.employeeCode.like(pattern),
      );
    }
    statement.orderBy([(t) => OrderingTerm.asc(t.fullName)]);
    return statement.watch();
  }

  Future<StaffRow?> staffById(String id) => (db.select(
    db.staffMembers,
  )..where((t) => t.id.equals(id))).getSingleOrNull();

  Future<String> saveStaff(StaffInput input, {String? existingId}) async {
    if (input.fullName.trim().isEmpty) {
      throw const ValidationFailure('Staff name is required');
    }
    final existing = existingId == null ? null : await staffById(existingId);
    final id = existing?.id ?? Ids.staff();
    final now = DateTime.now();
    final identity = services.identity;
    await db.transaction(() async {
      await db
          .into(db.staffMembers)
          .insertOnConflictUpdate(
            StaffMembersCompanion.insert(
              id: id,
              shopId: Value(identity.shopId),
              employeeCode: input.employeeCode.trim().isEmpty
                  ? 'EMP${now.millisecondsSinceEpoch % 10000}'
                  : input.employeeCode.trim(),
              fullName: input.fullName.trim(),
              phone: Value(input.phone),
              email: Value(input.email),
              address: Value(input.address),
              photoRef: Value(input.photoRef),
              designation: Value(input.designation),
              department: Value(input.department),
              role: Value(input.role),
              employmentType: Value(input.employmentType),
              assignedStoreId: Value(input.assignedStoreId),
              salaryType: Value(input.salaryType),
              basicSalaryPaise: Value(input.basicSalaryPaise),
              joiningDate: Value(input.joiningDate),
              emergencyContactName: Value(input.emergencyContactName),
              emergencyContactPhone: Value(input.emergencyContactPhone),
              permissionsJson: Value(jsonEncode(input.permissions)),
              notes: Value(input.notes),
              createdAt: existing?.createdAt ?? now,
              updatedAt: now,
              version: Value((existing?.version ?? 0) + 1),
              deviceId: Value(identity.deviceId),
              syncStatus: const Value(SyncStatus.pending),
            ),
          );
      final row = await staffById(id);
      await services.outbox.enqueue(
        shopId: identity.shopId,
        deviceId: identity.deviceId,
        userId: identity.userId,
        entityType: 'staff',
        collection: 'staff',
        entityId: id,
        payload: Json.toCloud(row!.toJson()),
        baseVersion: existing?.version ?? 0,
        priority: 15,
      );
      await audit.write(
        action: existing == null ? 'staff_created' : 'staff_updated',
        entityType: 'staff',
        entityId: id,
        before: existing?.toJson(),
        after: row.toJson(),
      );
    });
    return id;
  }

  // ----------------------------------------------------------------- drivers

  Stream<List<DriverRow>> watchDrivers({String query = ''}) {
    final statement = db.select(db.drivers)..where((t) => t.deletedAt.isNull());
    if (query.trim().isNotEmpty) {
      final pattern = '%${query.trim()}%';
      statement.where((t) => t.fullName.like(pattern) | t.phone.like(pattern));
    }
    statement.orderBy([(t) => OrderingTerm.asc(t.fullName)]);
    return statement.watch();
  }

  Future<DriverRow?> driverById(String id) =>
      (db.select(db.drivers)..where((t) => t.id.equals(id))).getSingleOrNull();

  Future<String> saveDriver(DriverInput input, {String? existingId}) async {
    if (input.fullName.trim().isEmpty) {
      throw const ValidationFailure('Driver name is required');
    }
    final existing = existingId == null ? null : await driverById(existingId);
    final id = existing?.id ?? Ids.driver();
    final now = DateTime.now();
    final identity = services.identity;
    await db.transaction(() async {
      await db
          .into(db.drivers)
          .insertOnConflictUpdate(
            DriversCompanion.insert(
              id: id,
              shopId: Value(identity.shopId),
              driverCode: input.driverCode.trim().isEmpty
                  ? 'DRV${now.millisecondsSinceEpoch % 10000}'
                  : input.driverCode.trim(),
              fullName: input.fullName.trim(),
              phone: Value(input.phone),
              address: Value(input.address),
              photoRef: Value(input.photoRef),
              licenceNumber: Value(input.licenceNumber),
              licenceExpiryDate: Value(input.licenceExpiry),
              assignedStoreId: Value(input.assignedStoreId),
              vehicleId: Value(input.vehicleId),
              salaryType: Value(input.salaryType),
              basicSalaryPaise: Value(input.basicSalaryPaise),
              joiningDate: Value(input.joiningDate),
              notes: Value(input.notes),
              createdAt: existing?.createdAt ?? now,
              updatedAt: now,
              version: Value((existing?.version ?? 0) + 1),
              deviceId: Value(identity.deviceId),
              syncStatus: const Value(SyncStatus.pending),
            ),
          );
      final row = await driverById(id);
      await services.outbox.enqueue(
        shopId: identity.shopId,
        deviceId: identity.deviceId,
        userId: identity.userId,
        entityType: 'driver',
        collection: 'drivers',
        entityId: id,
        payload: Json.toCloud(row!.toJson()),
        baseVersion: existing?.version ?? 0,
        priority: 15,
      );
      await audit.write(
        action: existing == null ? 'driver_created' : 'driver_updated',
        entityType: 'driver',
        entityId: id,
        before: existing?.toJson(),
        after: row.toJson(),
      );
    });
    return id;
  }

  // ---------------------------------------------------------------- vehicles

  Stream<List<VehicleRow>> watchVehicles() => (db.select(
    db.vehicles,
  )..orderBy([(t) => OrderingTerm.asc(t.registrationNumber)])).watch();

  Future<String> saveVehicle(VehicleInput input, {String? existingId}) async {
    if (input.registrationNumber.trim().isEmpty) {
      throw const ValidationFailure('Registration number is required');
    }
    final existing = existingId == null
        ? null
        : await (db.select(
            db.vehicles,
          )..where((t) => t.id.equals(existingId))).getSingleOrNull();
    final id = existing?.id ?? Ids.vehicle();
    final now = DateTime.now();
    final identity = services.identity;
    await db.transaction(() async {
      await db
          .into(db.vehicles)
          .insertOnConflictUpdate(
            VehiclesCompanion.insert(
              id: id,
              shopId: Value(identity.shopId),
              registrationNumber: input.registrationNumber.trim().toUpperCase(),
              vehicleType: Value(input.vehicleType),
              make: Value(input.make),
              model: Value(input.model),
              capacity: Value(input.capacity),
              assignedStoreId: Value(input.assignedStoreId),
              assignedDriverId: Value(input.assignedDriverId),
              insuranceExpiry: Value(input.insuranceExpiry),
              notes: Value(input.notes),
              createdAt: existing?.createdAt ?? now,
              updatedAt: now,
              version: Value((existing?.version ?? 0) + 1),
              deviceId: Value(identity.deviceId),
            ),
          );
      final row = await (db.select(
        db.vehicles,
      )..where((t) => t.id.equals(id))).getSingle();
      await services.outbox.enqueue(
        shopId: identity.shopId,
        deviceId: identity.deviceId,
        userId: identity.userId,
        entityType: 'vehicle',
        collection: 'vehicles',
        entityId: id,
        payload: Json.toCloud(row.toJson()),
        baseVersion: existing?.version ?? 0,
        priority: 15,
      );
    });
    return id;
  }

  // -------------------------------------------------------------- attendance

  Stream<List<AttendanceRow>> watchAttendance(DateTime date) {
    final start = AppDate.startOfDay(date);
    final end = AppDate.endOfDay(date);
    return (db.select(db.attendanceRecords)
          ..where((t) => t.date.isBetweenValues(start, end))
          ..orderBy([(t) => OrderingTerm.asc(t.date)]))
        .watch();
  }

  Future<void> markAttendance({
    required String staffId,
    required DateTime date,
    required String status,
    DateTime? checkIn,
    DateTime? checkOut,
    int overtimeMinutes = 0,
    String notes = '',
  }) async {
    final identity = services.identity;
    final day = AppDate.dateOnly(date);
    final id = 'att_${staffId}_${AppDate.isoDate(day)}';
    final now = DateTime.now();
    final existing = await (db.select(
      db.attendanceRecords,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
    await db.transaction(() async {
      await db
          .into(db.attendanceRecords)
          .insertOnConflictUpdate(
            AttendanceRecordsCompanion.insert(
              id: id,
              shopId: Value(identity.shopId),
              staffId: staffId,
              date: day,
              checkInTime: Value(checkIn),
              checkOutTime: Value(checkOut),
              status: Value(status),
              overtimeMinutes: Value(overtimeMinutes),
              notes: Value(notes),
              recordedBy: Value(identity.displayName ?? 'Local user'),
              createdAt: now,
              updatedAt: now,
              version: Value((existing?.version ?? 0) + 1),
              deviceId: Value(identity.deviceId),
            ),
          );
      final row = await (db.select(
        db.attendanceRecords,
      )..where((t) => t.id.equals(id))).getSingle();
      await services.outbox.enqueue(
        shopId: identity.shopId,
        deviceId: identity.deviceId,
        userId: identity.userId,
        entityType: 'attendance',
        collection: 'attendance',
        entityId: id,
        payload: Json.toCloud(row.toJson()),
        baseVersion: existing?.version ?? 0,
        priority: 20,
      );
    });
  }

  // ----------------------------------------------------------------- payroll

  Stream<List<SalaryRecordRow>> watchSalaries({String status = ''}) {
    final statement = db.select(db.salaryRecords)
      ..orderBy([(t) => OrderingTerm.desc(t.periodStart)]);
    if (status.isNotEmpty) {
      statement.where((t) => t.status.equals(status));
    }
    return statement.watch();
  }

  Future<void> generateSalary({
    required String personId,
    required String personType,
    required DateTime periodStart,
    required DateTime periodEnd,
    int incentivePaise = 0,
    int bonusPaise = 0,
    int otherDeductionsPaise = 0,
  }) async {
    final existing =
        await (db.select(db.salaryRecords)..where(
              (t) =>
                  t.personId.equals(personId) &
                  t.periodStart.equals(AppDate.startOfDay(periodStart)) &
                  t.periodEnd.equals(AppDate.endOfDay(periodEnd)) &
                  t.status.equals(SalaryStatus.cancelled).not(),
            ))
            .getSingleOrNull();
    if (existing != null) {
      throw const AppFailure(
        FailureCode.duplicate,
        'A salary record already exists for this person and period',
      );
    }

    String name = '';
    int basic = 0;
    String salaryType = SalaryType.monthly;
    String? storeId;
    if (personType == PartyType.staff) {
      final staff = await staffById(personId);
      if (staff == null) {
        throw const AppFailure(FailureCode.notFound, 'Staff not found');
      }
      name = staff.fullName;
      basic = staff.basicSalaryPaise;
      salaryType = staff.salaryType;
      storeId = staff.assignedStoreId;
    } else {
      final driver = await driverById(personId);
      if (driver == null) {
        throw const AppFailure(FailureCode.notFound, 'Driver not found');
      }
      name = driver.fullName;
      basic = driver.basicSalaryPaise;
      salaryType = driver.salaryType;
      storeId = driver.assignedStoreId;
    }

    final attendance =
        await (db.select(db.attendanceRecords)..where(
              (t) =>
                  t.staffId.equals(personId) &
                  t.date.isBiggerOrEqualValue(AppDate.startOfDay(periodStart)) &
                  t.date.isSmallerOrEqualValue(AppDate.endOfDay(periodEnd)),
            ))
            .get();

    double paidDays = 0;
    var overtimeMinutes = 0;
    for (final record in attendance) {
      overtimeMinutes += record.overtimeMinutes;
      switch (record.status) {
        case AttendanceStatus.present:
          paidDays += 1;
        case AttendanceStatus.halfDay:
          paidDays += 0.5;
        case AttendanceStatus.paidLeave:
          paidDays += 1;
        case AttendanceStatus.unpaidLeave:
        case AttendanceStatus.absent:
          break;
      }
    }

    final totalDays = periodEnd.difference(periodStart).inDays + 1;
    final perDay = switch (salaryType) {
      SalaryType.daily => basic,
      SalaryType.weekly => basic / 7,
      SalaryType.hourly => basic * 8,
      _ => basic / (totalDays <= 0 ? 30 : totalDays),
    };
    final basicPortion = (perDay * paidDays).round();
    final overtimeRate = salaryType == SalaryType.hourly
        ? basic
        : (basic / (totalDays * 8 * 60));
    final overtimePaise = (overtimeRate * overtimeMinutes).round();
    final absentDays = totalDays - paidDays;
    final attendanceDeduction = salaryType == SalaryType.monthly
        ? (perDay * absentDays).round()
        : 0;
    final gross = basicPortion + overtimePaise + incentivePaise + bonusPaise;
    final net = gross - attendanceDeduction - otherDeductionsPaise;

    final identity = services.identity;
    final now = DateTime.now();
    final id = Ids.salary();
    await db.transaction(() async {
      await db
          .into(db.salaryRecords)
          .insert(
            SalaryRecordsCompanion.insert(
              id: id,
              shopId: Value(identity.shopId),
              personId: personId,
              personType: Value(personType),
              personName: Value(name),
              storeId: Value(storeId),
              periodStart: AppDate.startOfDay(periodStart),
              periodEnd: AppDate.endOfDay(periodEnd),
              basicSalaryPaise: Value(basicPortion),
              overtimePaise: Value(overtimePaise),
              incentivePaise: Value(incentivePaise),
              bonusPaise: Value(bonusPaise),
              attendanceDeductionPaise: Value(attendanceDeduction),
              otherDeductionsPaise: Value(otherDeductionsPaise),
              grossSalaryPaise: Value(gross),
              netSalaryPaise: Value(net),
              balanceDuePaise: Value(net),
              status: const Value(SalaryStatus.pending),
              createdBy: Value(identity.displayName ?? 'Local user'),
              createdAt: now,
              updatedAt: now,
              deviceId: Value(identity.deviceId),
            ),
          );
      final row = await (db.select(
        db.salaryRecords,
      )..where((t) => t.id.equals(id))).getSingle();
      await services.outbox.enqueue(
        shopId: identity.shopId,
        deviceId: identity.deviceId,
        userId: identity.userId,
        entityType: 'salary_record',
        collection: 'salary_records',
        entityId: id,
        payload: Json.toCloud(row.toJson()),
        baseVersion: 0,
        priority: 25,
      );
      await audit.write(
        action: 'salary_generated',
        entityType: 'salary_record',
        entityId: id,
        after: {'person': name, 'net_salary_paise': net},
      );
    });
  }

  Future<void> paySalary({
    required String salaryId,
    required int amountPaise,
    required String method,
    String reference = '',
    DateTime? paidAt,
  }) async {
    if (amountPaise <= 0) {
      throw const ValidationFailure('Payment amount must be greater than zero');
    }
    final salary = await (db.select(
      db.salaryRecords,
    )..where((t) => t.id.equals(salaryId))).getSingleOrNull();
    if (salary == null) {
      throw const AppFailure(FailureCode.notFound, 'Salary record not found');
    }
    if (amountPaise > salary.balanceDuePaise) {
      throw const ValidationFailure(
        'Payment cannot exceed the outstanding salary balance',
      );
    }
    final identity = services.identity;
    final now = DateTime.now();
    final paid = paidAt ?? now;
    final paymentId = Ids.salaryPayment();
    final expenseId = Ids.expense();
    final newPaid = salary.amountPaidPaise + amountPaise;
    final balance = salary.netSalaryPaise - newPaid;
    final status = balance <= 0
        ? SalaryStatus.paid
        : SalaryStatus.partiallyPaid;

    await db.transaction(() async {
      await db
          .into(db.salaryPayments)
          .insert(
            SalaryPaymentsCompanion.insert(
              id: paymentId,
              shopId: Value(identity.shopId),
              salaryId: salaryId,
              amountPaise: amountPaise,
              paidAt: paid,
              method: Value(method),
              reference: Value(reference),
              idempotencyKey: 'salary:$salaryId:${now.microsecondsSinceEpoch}',
              createdBy: Value(identity.displayName ?? 'Local user'),
              createdAt: now,
              deviceId: Value(identity.deviceId),
            ),
          );
      await (db.update(
        db.salaryRecords,
      )..where((t) => t.id.equals(salaryId))).write(
        SalaryRecordsCompanion(
          amountPaidPaise: Value(newPaid),
          balanceDuePaise: Value(balance < 0 ? 0 : balance),
          status: Value(status),
          paymentDate: Value(paid),
          paymentMethod: Value(method),
          updatedAt: Value(now),
          version: Value(salary.version + 1),
          syncStatus: const Value(SyncStatus.pending),
        ),
      );

      // Salary is an expense, but not a duplicate payment row, so the day book
      // and expense reports count it exactly once.
      await db
          .into(db.expenses)
          .insert(
            ExpensesCompanion.insert(
              id: expenseId,
              shopId: Value(identity.shopId),
              categoryName: Value(
                salary.personType == PartyType.driver
                    ? 'Driver Salary'
                    : 'Staff Salary',
              ),
              amountPaise: amountPaise,
              paidAt: paid,
              method: Value(method),
              description: Value('Salary ${salary.personName}'),
              referenceType: const Value('salary'),
              referenceId: Value(salaryId),
              createdBy: Value(identity.displayName ?? 'Local user'),
              createdAt: now,
              updatedAt: now,
              deviceId: Value(identity.deviceId),
            ),
          );

      final paymentRow = await (db.select(
        db.salaryPayments,
      )..where((t) => t.id.equals(paymentId))).getSingle();
      final updatedSalary = await (db.select(
        db.salaryRecords,
      )..where((t) => t.id.equals(salaryId))).getSingle();
      final expenseRow = await (db.select(
        db.expenses,
      )..where((t) => t.id.equals(expenseId))).getSingle();

      await services.outbox.enqueue(
        shopId: identity.shopId,
        deviceId: identity.deviceId,
        userId: identity.userId,
        entityType: 'salary_payment',
        collection: 'salary_payments',
        entityId: paymentId,
        payload: Json.toCloud(paymentRow.toJson()),
        baseVersion: 0,
        priority: 26,
      );
      await services.outbox.enqueue(
        shopId: identity.shopId,
        deviceId: identity.deviceId,
        userId: identity.userId,
        entityType: 'salary_record',
        collection: 'salary_records',
        entityId: salaryId,
        payload: Json.toCloud(updatedSalary.toJson()),
        baseVersion: salary.version,
        priority: 25,
      );
      await services.outbox.enqueue(
        shopId: identity.shopId,
        deviceId: identity.deviceId,
        userId: identity.userId,
        entityType: 'expense',
        collection: 'expenses',
        entityId: expenseId,
        payload: Json.toCloud(expenseRow.toJson()),
        baseVersion: 0,
        priority: 55,
      );
      await audit.write(
        action: 'salary_paid',
        entityType: 'salary_record',
        entityId: salaryId,
        after: {'amount_paise': amountPaise, 'status': status},
      );
    });
  }
}

final workforceRepositoryProvider = Provider<WorkforceRepository>(
  (ref) => WorkforceRepository(ref.watch(servicesProvider)),
);

final staffStreamProvider = StreamProvider.family<List<StaffRow>, String>((
  ref,
  query,
) {
  return ref.watch(workforceRepositoryProvider).watchStaff(query: query);
});

final driversStreamProvider = StreamProvider.family<List<DriverRow>, String>((
  ref,
  query,
) {
  return ref.watch(workforceRepositoryProvider).watchDrivers(query: query);
});

final vehiclesStreamProvider = StreamProvider<List<VehicleRow>>(
  (ref) => ref.watch(workforceRepositoryProvider).watchVehicles(),
);

final salaryStreamProvider =
    StreamProvider.family<List<SalaryRecordRow>, String>((ref, status) {
      return ref
          .watch(workforceRepositoryProvider)
          .watchSalaries(status: status);
    });
