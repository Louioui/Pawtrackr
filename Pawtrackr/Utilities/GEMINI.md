
# Pawtrackr Development Mandates

## Data Integrity
- All date calculations must use safe unwrapping (guard/if let).
- CloudKit synchronization is enabled; avoid using unique constraints that conflict with CloudKit's record sharing logic.

## Reporting & Exports
- Use BusinessReportService for monthly PDF summaries.
- Use PDFReceiptService for individual visit receipts.
- CSV exports are handled via ExportService.

## Performance
- Parallelize view model refreshes using async let.
- Use SearchEngine for all model-based filtering.
