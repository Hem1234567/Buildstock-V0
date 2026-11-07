// String constants shared by the database, sync payloads and Firestore rules.
// They are intentionally plain strings so an offline upgrade never fails to
// decode data written by an older build.

abstract final class SyncStatus {
  static const pending = 'pending';
  static const syncing = 'syncing';
  static const synced = 'synced';
  static const failed = 'failed';
  static const conflict = 'conflict';

  static const all = [pending, syncing, synced, failed, conflict];
}

abstract final class DocumentType {
  static const invoice = 'invoice';
  static const estimate = 'estimate';
  static const quotation = 'quotation';
}

abstract final class DocumentStatus {
  static const draft = 'draft';
  static const finalized = 'finalized';
  static const cancelled = 'cancelled';
  static const converted = 'converted';
}

abstract final class SaleType {
  static const retail = 'retail';
  static const wholesale = 'wholesale';
}

abstract final class PaymentMethods {
  static const cash = 'cash';
  static const upi = 'upi';
  static const bank = 'bank';
  static const cheque = 'cheque';
  static const credit = 'credit';
  static const other = 'other';

  static const all = [cash, upi, bank, cheque, credit, other];
}

abstract final class MovementType {
  static const opening = 'opening_stock';
  static const purchaseIn = 'purchase_in';
  static const saleOut = 'sale_out';
  static const customerReturn = 'customer_return';
  static const supplierReturn = 'supplier_return';
  static const transferOut = 'transfer_out';
  static const transferIn = 'transfer_in';
  static const adjustmentIn = 'adjustment_in';
  static const adjustmentOut = 'adjustment_out';
  static const damage = 'damage';
  static const correction = 'correction';

  static const all = [
    opening,
    purchaseIn,
    saleOut,
    customerReturn,
    supplierReturn,
    transferOut,
    transferIn,
    adjustmentIn,
    adjustmentOut,
    damage,
    correction,
  ];

  static bool isInbound(String type) => const {
    opening,
    purchaseIn,
    customerReturn,
    transferIn,
    adjustmentIn,
    correction,
  }.contains(type);
}

abstract final class DeliveryStatus {
  static const pending = 'pending';
  static const assigned = 'assigned';
  static const loaded = 'loaded';
  static const inTransit = 'in_transit';
  static const partiallyDelivered = 'partially_delivered';
  static const delivered = 'delivered';
  static const failed = 'failed';
  static const cancelled = 'cancelled';

  static const all = [
    pending,
    assigned,
    loaded,
    inTransit,
    partiallyDelivered,
    delivered,
    failed,
    cancelled,
  ];
}

abstract final class SalaryStatus {
  static const draft = 'draft';
  static const pending = 'pending';
  static const partiallyPaid = 'partially_paid';
  static const paid = 'paid';
  static const cancelled = 'cancelled';
}

abstract final class EmploymentType {
  static const all = [
    'Permanent',
    'Temporary',
    'Contract',
    'Part-time',
    'Daily Wage',
  ];
}

abstract final class SalaryType {
  static const monthly = 'monthly';
  static const daily = 'daily';
  static const weekly = 'weekly';
  static const hourly = 'hourly';

  static const all = [monthly, daily, weekly, hourly];
}

abstract final class StaffRole {
  static const owner = 'owner';
  static const admin = 'admin';
  static const manager = 'manager';
  static const cashier = 'cashier';
  static const sales = 'sales';
  static const purchase = 'purchase';
  static const inventory = 'inventory';
  static const storekeeper = 'storekeeper';
  static const accountant = 'accountant';
  static const deliveryCoordinator = 'delivery_coordinator';
  static const custom = 'custom';

  static const all = [
    owner,
    admin,
    manager,
    cashier,
    sales,
    purchase,
    inventory,
    storekeeper,
    accountant,
    deliveryCoordinator,
    custom,
  ];
}

abstract final class AttendanceStatus {
  static const present = 'present';
  static const absent = 'absent';
  static const halfDay = 'half_day';
  static const paidLeave = 'paid_leave';
  static const unpaidLeave = 'unpaid_leave';

  static const all = [present, absent, halfDay, paidLeave, unpaidLeave];
}

abstract final class ReturnType {
  static const saleReturn = 'sale_return';
  static const purchaseReturn = 'purchase_return';

  /// Reduces what a customer owes (price correction, goodwill, damaged goods
  /// settled in money). Never moves stock.
  static const creditNote = 'credit_note';

  /// Increases what a customer owes (undercharge, extra charges). Never moves
  /// stock.
  static const debitNote = 'debit_note';

  /// Reduces what you owe a supplier. Never moves stock.
  static const purchaseDebitNote = 'purchase_debit_note';

  /// Increases what you owe a supplier. Never moves stock.
  static const purchaseCreditNote = 'purchase_credit_note';

  static const noteTypes = [
    creditNote,
    debitNote,
    purchaseDebitNote,
    purchaseCreditNote,
  ];

  static bool isNote(String type) => noteTypes.contains(type);

  static bool isCustomerNote(String type) =>
      type == creditNote || type == debitNote;

  static String label(String type) => switch (type) {
    saleReturn => 'Sales return',
    purchaseReturn => 'Purchase return',
    creditNote => 'Credit note (customer)',
    debitNote => 'Debit note (customer)',
    purchaseDebitNote => 'Debit note (supplier, reduces payable)',
    purchaseCreditNote => 'Credit note (supplier, increases payable)',
    _ => type,
  };

  static String shortLabel(String type) => switch (type) {
    saleReturn => 'Sales return',
    purchaseReturn => 'Purchase return',
    creditNote => 'Credit note',
    debitNote => 'Debit note',
    purchaseDebitNote => 'Supplier debit note',
    purchaseCreditNote => 'Supplier credit note',
    _ => type,
  };

  /// Number prefix for the document series.
  static String prefix(String type) => switch (type) {
    saleReturn => 'SRN',
    purchaseReturn => 'PRN',
    creditNote => 'CRN',
    debitNote => 'DBN',
    purchaseDebitNote => 'PDN',
    purchaseCreditNote => 'PCN',
    _ => 'RET',
  };
}

abstract final class TransferStatus {
  static const draft = 'draft';
  static const inTransit = 'in_transit';
  static const received = 'received';
  static const cancelled = 'cancelled';
}

abstract final class UserRole {
  static const owner = 'owner';
  static const admin = 'admin';
  static const manager = 'manager';
  static const cashier = 'cashier';
  static const staff = 'staff';
  static const driver = 'driver';
  static const accountant = 'accountant';

  static const assignable = [
    admin,
    manager,
    cashier,
    staff,
    driver,
    accountant,
  ];
}

abstract final class PaymentDirection {
  static const incoming = 'in';
  static const outgoing = 'out';
}

abstract final class PartyType {
  static const customer = 'customer';
  static const supplier = 'supplier';
  static const staff = 'staff';
  static const driver = 'driver';
  static const other = 'other';
}

abstract final class UploadStatus {
  static const pending = 'pending';
  static const uploading = 'uploading';
  static const uploaded = 'uploaded';
  static const failed = 'failed';
}
