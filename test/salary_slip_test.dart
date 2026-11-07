import 'package:flutter_test/flutter_test.dart';

import 'package:buildstock/features/staff/data/salary_slip_pdf.dart';

void main() {
  test('slip totals add earnings and subtract deductions', () {
    final totals = SalarySlipPdfBuilder.totals(
      basic: 1500000,
      overtime: 50000,
      incentive: 25000,
      advance: 100000,
      attendance: 20000,
      other: 5000,
    );
    expect(totals.earnings, 1575000);
    expect(totals.deductions, 125000);
    expect(totals.net, 1450000);
  });

  test('bonus counts as an earning', () {
    final totals = SalarySlipPdfBuilder.totals(basic: 100, bonus: 50);
    expect(totals.earnings, 150);
    expect(totals.net, 150);
  });
}
