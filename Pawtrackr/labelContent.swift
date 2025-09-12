import SwiftUI

/// A compact, centered label block with optional SF Symbol icon, title and subtitle.
/// Useful inside dashed placeholders, empty states, and card headers.
public struct LabelContent: View {
    public enum Size {
        case sm, md, lg

        var titleFont: Font {
            switch self {
            case .sm: return .subheadline.weight(.semibold)
            case .md: return .headline.weight(.semibold)
            case .lg: return .title3.weight(.semibold)
            }
        }

        var subtitleFont: Font {
            switch self {
            case .sm: return .caption
            case .md: return .footnote
            case .lg: return .callout
            }
        }

        var icon: CGFloat {
            switch self {
            case .sm: return 18
            case .md: return 22
            case .lg: return 28
            }
        }

        var spacing: CGFloat {
            switch self {
            case .sm: return 4
            case .md: return 6
            case .lg: return 8
            }
        }
    }

    let title: String
    let subtitle: String?
    let systemImage: String?
    let size: Size
    let alignment: HorizontalAlignment

    public init(
        title: String,
        subtitle: String? = nil,
        systemImage: String? = nil,
        size: Size = .md,
        alignment: HorizontalAlignment = .center
    ) {
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
        self.size = size
        self.alignment = alignment
    }

    public var body: some View {
        VStack(alignment: alignment, spacing: size.spacing) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: size.icon, weight: .semibold))
                    .imageScale(.medium)
                    .accessibilityHidden(true)
            }
            Text(title)
                .font(size.titleFont)
                .multilineTextAlignment(alignment == .leading ? .leading : (alignment == .trailing ? .trailing : .center))
            if let subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(size.subtitleFont)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(alignment == .leading ? .leading : (alignment == .trailing ? .trailing : .center))
            }
        }
        .frame(maxWidth: .infinity, alignment: Alignment(horizontal: alignment, vertical: .center))
        .accessibilityElement(children: .combine)
    }
}

/// A rounded container with a dashed border, ideal for "add photo" or "tap to add" placeholders.
public struct DashedPlaceholder<Content: View>: View {
    let cornerRadius: CGFloat
    let lineWidth: CGFloat
    let dash: [CGFloat]
    let content: Content

    public init(
        cornerRadius: CGFloat = 12,
        lineWidth: CGFloat = 1,
        dash: [CGFloat] = [6, 6],
        @ViewBuilder content: () -> Content
    ) {
        self.cornerRadius = cornerRadius
        self.lineWidth = lineWidth
        self.dash = dash
        self.content = content()
    }

    public var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(style: StrokeStyle(lineWidth: lineWidth, dash: dash))
                .foregroundStyle(.quaternary)
            content
                .padding(16)
        }
        .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

/// A ready‑to‑use "Add Photo" placeholder that can be tapped to open a picker.
public struct AddPhotoPlaceholder: View {
    let title: String
    let subtitle: String?
    let size: LabelContent.Size
    let cornerRadius: CGFloat
    let onTap: (() -> Void)?

    public init(
        title: String = "Add Photo",
        subtitle: String? = "Tap to upload or take a picture",
        size: LabelContent.Size = .md,
        cornerRadius: CGFloat = 12,
        onTap: (() -> Void)? = nil
    ) {
        self.title = title
        self.subtitle = subtitle
        self.size = size
        self.cornerRadius = cornerRadius
        self.onTap = onTap
    }

    public var body: some View {
        Group {
            if let onTap {
                Button(action: onTap) {
                    placeholderContent
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(title))
                .accessibilityHint(Text(NSLocalizedString("a11y.opens_photo_chooser", comment: "")))
            } else {
                placeholderContent
            }
        }
    }

    private var placeholderContent: some View {
        DashedPlaceholder(cornerRadius: cornerRadius) {
            LabelContent(
                title: title,
                subtitle: subtitle,
                systemImage: "photo.on.rectangle.angled",
                size: size
            )
            .padding(.vertical, size == .lg ? 24 : (size == .md ? 18 : 12))
        }
    }
}

#Preview("Library placeholder") {
    VStack(spacing: 16) {
        AddPhotoPlaceholder()
            .frame(height: 140)
        DashedPlaceholder {
            LabelContent(title: "Attach Receipt",
                         subtitle: "PDF, PNG, or JPEG",
                         systemImage: "paperclip",
                         size: .sm)
                .padding(.vertical, 12)
        }
        .frame(height: 80)
    }
    .padding()
}
