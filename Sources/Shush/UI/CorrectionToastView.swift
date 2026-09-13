import ShushDictionary
import SwiftUI

/// Content for `CorrectionToastPanel`. Mirrors `DictionaryPanel`'s warning-row styling so a
/// flagged rule reads the same way here as it does in the full dictionary editor.
struct CorrectionToastView: View {
    let correction: CorrectionDiff.Correction
    let onSave: () -> Void
    let onDismiss: () -> Void

    private var warnings: [DictionaryWarning] {
        DictionaryWarning.check(.correction(hear: correction.hear, write: correction.write))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.snug) {
            HStack(spacing: DS.Space.tight) {
                Text(correction.hear)
                    .font(DS.Font.body)
                    .foregroundStyle(DS.Color.textSecondary)
                    .strikethrough()
                Image(systemName: "arrow.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(DS.Color.textTertiary)
                Text(correction.write)
                    .font(DS.Font.label)
                    .foregroundStyle(DS.Color.textPrimary)
            }
            .lineLimit(1)

            Text("Save this as a dictionary correction?")
                .font(DS.Font.meta)
                .foregroundStyle(DS.Color.textTertiary)

            if let warning = warnings.first {
                HStack(alignment: .top, spacing: DS.Space.snug) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(DS.Color.warning)
                    Text(warning.message)
                        .font(DS.Font.meta)
                        .foregroundStyle(DS.Color.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(DS.Space.snug)
                .background(DS.Color.warning.opacity(0.1), in: .rect(cornerRadius: DS.Radius.control))
            }

            HStack(spacing: DS.Space.snug) {
                Spacer()
                Button("Dismiss", action: onDismiss)
                    .buttonStyle(.plain)
                    .font(DS.Font.button)
                    .foregroundStyle(DS.Color.textSecondary)
                Button(warnings.isEmpty ? "Save" : "Save Anyway", action: onSave)
                    .buttonStyle(.plain)
                    .font(DS.Font.button)
                    .foregroundStyle(.white)
                    .padding(.horizontal, DS.Space.roomy)
                    .frame(height: 28)
                    .background(DS.Color.primary, in: .rect(cornerRadius: DS.Radius.control))
            }
        }
        .padding(DS.Space.roomy)
        .frame(width: 360, alignment: .leading)
        .background(DS.Color.surface, in: .rect(cornerRadius: DS.Radius.card))
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.card)
                .strokeBorder(DS.Color.border, lineWidth: DS.Border.hairline)
        )
    }
}
