import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import 'package:nexgen_command/features/sales/models/material_models.dart';
import 'package:nexgen_command/features/sales/models/sales_models.dart';
import 'package:nexgen_command/features/sales/services/install_plan_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// PdfService — generates install plan PDFs for sales jobs
// ─────────────────────────────────────────────────────────────────────────────

class PdfService {

  /// Generate a multi-page install plan PDF.
  Future<Uint8List> generateInstallPlan(
    SalesJob job,
    List<InstallTask> day1Tasks,
    List<InstallTask> day2Tasks,
  ) async {
    final doc = pw.Document();

    // ── Color constants ──
    final headerBg = PdfColor.fromHex('#07091A');
    final accentCyan = PdfColor.fromHex('#00D4FF');
    const white = PdfColors.white;
    final lightGray = PdfColor.fromHex('#F1EFE8');
    final darkText = PdfColor.fromHex('#111527');

    // ── PAGE 1 — Job header + customer info ──
    doc.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.letter,
      margin: const pw.EdgeInsets.all(32),
      build: (context) => [
        // Header bar
        pw.Container(
          color: headerBg,
          padding: const pw.EdgeInsets.all(16),
          child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text('NEX-GEN LED',
                    style: pw.TextStyle(color: accentCyan, fontSize: 14, fontWeight: pw.FontWeight.bold)),
                  pw.Text('Install Plan',
                    style: pw.TextStyle(color: white, fontSize: 10)),
                ],
              ),
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: [
                  pw.Text('Job #${job.jobNumber}',
                    style: pw.TextStyle(color: white, fontSize: 10)),
                  pw.Text('Day 1: ${_formatDate(job.day1Date)}',
                    style: pw.TextStyle(color: white, fontSize: 9)),
                  pw.Text('Day 2: ${_formatDate(job.day2Date)}',
                    style: pw.TextStyle(color: white, fontSize: 9)),
                ],
              ),
            ],
          ),
        ),
        pw.SizedBox(height: 16),

        // Customer info
        pw.Text(job.prospect.fullName,
          style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold, color: darkText)),
        pw.Text(
          '${job.prospect.address}, ${job.prospect.city}, ${job.prospect.state} ${job.prospect.zipCode}',
          style: pw.TextStyle(fontSize: 10, color: PdfColors.grey700)),
        pw.Text(
          '${job.prospect.phone}  ·  ${job.prospect.email}',
          style: pw.TextStyle(fontSize: 10, color: PdfColors.grey700)),
        pw.SizedBox(height: 12),

        // Zone summary pills
        pw.Wrap(
          spacing: 8,
          runSpacing: 4,
          children: job.zones.map((z) => pw.Container(
            padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: pw.BoxDecoration(
              color: lightGray,
              borderRadius: pw.BorderRadius.circular(4),
            ),
            child: pw.Text(
              '${z.name} · ${z.runLengthFt.toStringAsFixed(0)}ft · ${z.colorPreset.label}',
              style: pw.TextStyle(fontSize: 9, color: darkText)),
          )).toList(),
        ),
        pw.SizedBox(height: 12),

        // Salesperson notes
        if (job.prospect.salespersonNotes.isNotEmpty) ...[
          pw.Text('Notes',
            style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
          pw.Container(
            padding: const pw.EdgeInsets.all(8),
            color: lightGray,
            child: pw.Text(job.prospect.salespersonNotes,
              style: const pw.TextStyle(fontSize: 9)),
          ),
          pw.SizedBox(height: 12),
        ],

        // Photo references (URLs only — remote images can't be reliably embedded in PDF)
        if (job.prospect.homePhotoUrls.isNotEmpty) ...[
          pw.Text('Install photos',
            style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 4),
          pw.Text(
            '${job.prospect.homePhotoUrls.length} photo(s) attached — view in Lumina app or job portal',
            style: pw.TextStyle(fontSize: 9, color: PdfColors.grey700)),
        ],
      ],
    ));

    // ── PAGE 2 — Day 1 work order ──
    doc.addPage(pw.Page(
      pageFormat: PdfPageFormat.letter,
      margin: const pw.EdgeInsets.all(32),
      build: (context) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          _buildDayHeader('Day 1 — Pre-wire & Electrical', job.day1Date, headerBg, accentCyan, white),
          pw.SizedBox(height: 12),
          _buildTaskTable(day1Tasks, darkText, lightGray),
          pw.SizedBox(height: 12),
          pw.Text(
            'All wires must be labeled "INJ-N" and capped before Day 2.',
            style: pw.TextStyle(fontSize: 9, color: PdfColors.grey700)),
        ],
      ),
    ));

    // ── PAGE 3 — Day 2 work order ──
    doc.addPage(pw.Page(
      pageFormat: PdfPageFormat.letter,
      margin: const pw.EdgeInsets.all(32),
      build: (context) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          _buildDayHeader('Day 2 — Install (Rails & Lights)', job.day2Date, headerBg, accentCyan, white),
          pw.SizedBox(height: 12),
          _buildTaskTable(day2Tasks, darkText, lightGray),
        ],
      ),
    ));

    // ── PAGE 4 — Materials list ──
    final mats = _buildMaterials(job);
    doc.addPage(pw.Page(
      pageFormat: PdfPageFormat.letter,
      margin: const pw.EdgeInsets.all(32),
      build: (context) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Container(
            color: headerBg,
            padding: const pw.EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: pw.Text('Materials — Job #${job.jobNumber}',
              style: pw.TextStyle(color: white, fontSize: 13, fontWeight: pw.FontWeight.bold)),
          ),
          pw.SizedBox(height: 12),
          _buildMaterialsTable(mats, darkText, lightGray),
          pw.SizedBox(height: 8),
          pw.Text('All wire lengths include 10% buffer.',
            style: pw.TextStyle(fontSize: 9, color: PdfColors.grey700)),
        ],
      ),
    ));

    return doc.save();
  }

  /// Share/save the generated PDF.
  Future<void> savePdfToDevice(Uint8List bytes, String filename) async {
    await Printing.sharePdf(bytes: bytes, filename: filename);
  }

  // ── Private helpers ─────────────────────────────────────────

  pw.Widget _buildDayHeader(
    String title,
    DateTime? date,
    PdfColor bg,
    PdfColor accent,
    PdfColor textColor,
  ) {
    return pw.Container(
      color: bg,
      padding: const pw.EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(title,
            style: pw.TextStyle(color: textColor, fontSize: 13, fontWeight: pw.FontWeight.bold)),
          pw.Text(_formatDate(date),
            style: pw.TextStyle(color: accent, fontSize: 11)),
        ],
      ),
    );
  }

  pw.Widget _buildTaskTable(
    List<InstallTask> tasks,
    PdfColor textColor,
    PdfColor altRow,
  ) {
    return pw.Table(
      columnWidths: {
        0: const pw.FlexColumnWidth(1.5),  // Category
        1: const pw.FlexColumnWidth(6.5),  // Description
        2: const pw.FlexColumnWidth(1),    // Photo
        3: const pw.FlexColumnWidth(1),    // Done
      },
      border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
      children: [
        // Header row
        pw.TableRow(
          decoration: pw.BoxDecoration(color: PdfColor.fromHex('#E0DED6')),
          children: [
            _cell('Category', bold: true, color: textColor),
            _cell('Description', bold: true, color: textColor),
            _cell('Photo', bold: true, color: textColor),
            _cell('Done', bold: true, color: textColor),
          ],
        ),
        // Data rows
        ...tasks.asMap().entries.map((entry) {
          final i = entry.key;
          final task = entry.value;
          final rowColor = i.isOdd ? altRow : PdfColors.white;
          return pw.TableRow(
            decoration: pw.BoxDecoration(color: rowColor),
            children: [
              _cell(task.category, color: textColor),
              _cell(task.description, color: textColor),
              _cell(task.requiresPhoto ? '[photo]' : '', color: textColor),
              // Empty checkbox area for physical sign-off
              pw.Padding(
                padding: const pw.EdgeInsets.all(4),
                child: pw.Container(
                  width: 12,
                  height: 12,
                  decoration: pw.BoxDecoration(
                    border: pw.Border.all(color: PdfColors.grey600, width: 0.5),
                  ),
                ),
              ),
            ],
          );
        }),
      ],
    );
  }

  pw.Widget _buildMaterialsTable(
    Map<String, dynamic> mats,
    PdfColor textColor,
    PdfColor altRow,
  ) {
    final rows = <_MaterialRow>[];

    final wire14 = (mats['wire14_2_ft'] as double?) ?? 0;
    final wire12 = (mats['wire12_2_ft'] as double?) ?? 0;
    final wire10 = (mats['wire10_2_ft'] as double?) ?? 0;
    final ground = (mats['ground10awg_ft'] as double?) ?? 0;
    final supply350 = (mats['supply350w_count'] as int?) ?? 0;
    final supply600 = (mats['supply600w_count'] as int?) ?? 0;
    final outlets = (mats['newOutlets_count'] as int?) ?? 0;
    final outletNotes = (mats['newOutlets_notes'] as List<String>?) ?? [];

    if (wire14 > 0) rows.add(_MaterialRow('14/2 wire', '≤30ft runs', '${wire14.ceil()}ft', ''));
    if (wire12 > 0) rows.add(_MaterialRow('12/2 wire', '30–90ft runs', '${wire12.ceil()}ft', ''));
    if (wire10 > 0) rows.add(_MaterialRow('10/2 wire', '90–140ft runs', '${wire10.ceil()}ft', ''));
    if (ground > 0) rows.add(_MaterialRow('10AWG ground', 'Common ground', '${ground.ceil()}ft', ''));
    if (supply350 > 0) rows.add(_MaterialRow('350w power supply', 'Additional power', '$supply350', ''));
    if (supply600 > 0) rows.add(_MaterialRow('600w power supply', 'Additional power', '$supply600', ''));
    if (outlets > 0) rows.add(_MaterialRow('New outlet', 'Electrician install', '$outlets', outletNotes.join(', ')));

    return pw.Table(
      columnWidths: {
        0: const pw.FlexColumnWidth(2),
        1: const pw.FlexColumnWidth(2),
        2: const pw.FlexColumnWidth(1),
        3: const pw.FlexColumnWidth(3),
      },
      border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
      children: [
        pw.TableRow(
          decoration: pw.BoxDecoration(color: PdfColor.fromHex('#E0DED6')),
          children: [
            _cell('Item', bold: true, color: textColor),
            _cell('Specification', bold: true, color: textColor),
            _cell('Qty', bold: true, color: textColor),
            _cell('Notes', bold: true, color: textColor),
          ],
        ),
        ...rows.asMap().entries.map((entry) {
          final i = entry.key;
          final row = entry.value;
          final rowColor = i.isOdd ? altRow : PdfColors.white;
          return pw.TableRow(
            decoration: pw.BoxDecoration(color: rowColor),
            children: [
              _cell(row.item, color: textColor),
              _cell(row.spec, color: textColor),
              _cell(row.qty, color: textColor),
              _cell(row.notes, color: textColor),
            ],
          );
        }),
      ],
    );
  }

  pw.Widget _cell(String text, {bool bold = false, PdfColor? color}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.all(4),
      child: pw.Text(
        text,
        style: pw.TextStyle(
          fontSize: 8,
          fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
          color: color ?? PdfColors.black,
        ),
      ),
    );
  }

  Map<String, dynamic> _buildMaterials(SalesJob job) {
    double wire14 = 0, wire12 = 0, wire10 = 0, ground = 0;
    int supply350 = 0, supply600 = 0, newOutlets = 0;
    final outletNotes = <String>[];

    // Find controller mount
    PowerMount? controllerMount;
    for (final zone in job.zones) {
      for (final mount in zone.mounts) {
        if (mount.isController) {
          controllerMount = mount;
          break;
        }
      }
      if (controllerMount != null) break;
    }

    for (final zone in job.zones) {
      // Wire from injections
      for (final inj in zone.injections) {
        final buffered = inj.wireRunFt * 1.1;
        switch (inj.wireGauge) {
          case WireGauge.g14_2:
            wire14 += buffered;
          case WireGauge.g12_2:
            wire12 += buffered;
          case WireGauge.g10_2:
            wire10 += buffered;
          case WireGauge.direct:
          case WireGauge.exceeds:
            break;
        }
      }

      // Mounts
      for (final mount in zone.mounts) {
        // Ground wire from additional mounts to controller
        if (!mount.isController && controllerMount != null) {
          final dist = (mount.positionFt - controllerMount.positionFt).abs();
          ground += dist * 1.1;
        }

        // Supply counts
        if (!mount.isController) {
          if (mount.supplySize.contains('350')) supply350++;
          if (mount.supplySize.contains('600')) supply600++;
        }

        // New outlets
        if (mount.outletType == OutletType.newRequired) {
          newOutlets++;
          if (mount.outletNote.isNotEmpty) outletNotes.add(mount.outletNote);
        }
      }
    }

    return {
      'wire14_2_ft': wire14,
      'wire12_2_ft': wire12,
      'wire10_2_ft': wire10,
      'ground10awg_ft': ground,
      'supply350w_count': supply350,
      'supply600w_count': supply600,
      'newOutlets_count': newOutlets,
      'newOutlets_notes': outletNotes,
    };
  }

  static const _months = [
    '', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  static const _days = ['', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

  String _formatDate(DateTime? date) {
    if (date == null) return 'TBD';
    final wd = _days[date.weekday];
    final mo = _months[date.month];
    return '$wd, $mo ${date.day}, ${date.year}';
  }

  // ── Packing list PDF ────────────────────────────────────────────────────

  /// Generate a single-page packing list from a job material list.
  Future<Uint8List> generatePackingList(JobMaterialList matList) async {
    final doc = pw.Document();
    final headerBg = PdfColor.fromHex('#07091A');
    final accentCyan = PdfColor.fromHex('#00D4FF');
    const white = PdfColors.white;
    final darkText = PdfColor.fromHex('#111527');
    final altRow = PdfColor.fromHex('#F1EFE8');

    doc.addPage(pw.Page(
      pageFormat: PdfPageFormat.letter,
      margin: const pw.EdgeInsets.all(32),
      build: (context) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Container(
            color: headerBg,
            padding: const pw.EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text('Packing List',
                    style: pw.TextStyle(color: white, fontSize: 14, fontWeight: pw.FontWeight.bold)),
                pw.Text('Job #${matList.jobNumber}',
                    style: pw.TextStyle(color: accentCyan, fontSize: 11)),
              ],
            ),
          ),
          pw.SizedBox(height: 12),
          pw.Table(
            columnWidths: {
              0: const pw.FlexColumnWidth(5),
              1: const pw.FlexColumnWidth(1.5),
              2: const pw.FlexColumnWidth(1),
              3: const pw.FlexColumnWidth(1),
            },
            border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
            children: [
              pw.TableRow(
                decoration: pw.BoxDecoration(color: PdfColor.fromHex('#E0DED6')),
                children: [
                  _cell('Material', bold: true, color: darkText),
                  _cell('Qty', bold: true, color: darkText),
                  _cell('Unit', bold: true, color: darkText),
                  _cell('✓', bold: true, color: darkText),
                ],
              ),
              ...matList.lines.where((l) => l.checkedOutQty > 0).toList().asMap().entries.map((entry) {
                final i = entry.key;
                final line = entry.value;
                final rowColor = i.isOdd ? altRow : PdfColors.white;
                return pw.TableRow(
                  decoration: pw.BoxDecoration(color: rowColor),
                  children: [
                    _cell(line.materialName, color: darkText),
                    _cell(line.checkedOutQty.toStringAsFixed(0), color: darkText),
                    _cell(line.unit == MaterialUnit.piece ? 'pcs' : 'ea', color: darkText),
                    pw.Padding(
                      padding: const pw.EdgeInsets.all(4),
                      child: pw.Container(
                        width: 12, height: 12,
                        decoration: pw.BoxDecoration(
                          border: pw.Border.all(color: PdfColors.grey600, width: 0.5),
                        ),
                      ),
                    ),
                  ],
                );
              }),
            ],
          ),
          pw.SizedBox(height: 8),
          pw.Text('${matList.lines.where((l) => l.checkedOutQty > 0).length} items · ${_formatDate(DateTime.now())}',
              style: pw.TextStyle(fontSize: 9, color: PdfColors.grey700)),
        ],
      ),
    ));

    return doc.save();
  }
}

class _MaterialRow {
  final String item;
  final String spec;
  final String qty;
  final String notes;
  const _MaterialRow(this.item, this.spec, this.qty, this.notes);
}

final pdfServiceProvider = Provider<PdfService>((ref) => PdfService());
