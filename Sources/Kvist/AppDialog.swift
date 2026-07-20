import AppKit
import SwiftUI

enum AppDialogActionRole {
    case primary
    case secondary
    case destructive
    case cancel
}

struct AppDialogAction {
    let title: String
    let role: AppDialogActionRole
}

struct AppDialogField {
    let label: String
    let placeholder: String
    let isRequired: Bool

    init(label: String, placeholder: String, isRequired: Bool = true) {
        self.label = label
        self.placeholder = placeholder
        self.isRequired = isRequired
    }
}

struct AppDialogResult {
    let actionIndex: Int?
    let values: [String]
}

@MainActor
enum AppDialog {
    static func run(
        title: String,
        message: String,
        fields: [AppDialogField] = [],
        actions: [AppDialogAction]
    ) -> AppDialogResult {
        let session = AppDialogSession(fieldCount: fields.count)
        let dialogSize = NSSize(
            width: 440,
            height: dialogHeight(
                fieldCount: fields.count,
                message: message
            )
        )
        let content = AppDialogView(
            title: title,
            message: message,
            fields: fields,
            actions: actions,
            session: session
        )
        .frame(width: dialogSize.width, height: dialogSize.height)
        let panel = AppDialogPanel(
            contentRect: NSRect(
                origin: .zero,
                size: dialogSize
            ),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        panel.isReleasedWhenClosed = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .modalPanel
        panel.collectionBehavior = [.fullScreenAuxiliary]
        let hostingView = NSHostingView(rootView: content.preferredColorScheme(.dark))
        hostingView.frame = NSRect(origin: .zero, size: dialogSize)
        panel.contentView = hostingView
        panel.setContentSize(dialogSize)
        session.panel = panel

        let parent = NSApp.keyWindow ?? NSApp.mainWindow
        if let parent {
            let parentFrame = parent.frame
            let panelFrame = panel.frame
            panel.setFrameOrigin(NSPoint(
                x: parentFrame.midX - panelFrame.width / 2,
                y: parentFrame.midY - panelFrame.height / 2
            ))
            parent.addChildWindow(panel, ordered: .above)
        } else {
            panel.center()
        }

        panel.makeKeyAndOrderFront(nil)
        NSApp.runModal(for: panel)
        if let parent {
            parent.removeChildWindow(panel)
        }
        panel.orderOut(nil)

        return AppDialogResult(
            actionIndex: session.actionIndex,
            values: session.values.map {
                $0.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        )
    }

    static func message(title: String, message: String, details: String? = nil) {
        let actions = details == nil
            ? [AppDialogAction(title: "OK", role: .primary)]
            : [
                AppDialogAction(title: "Show Details", role: .secondary),
                AppDialogAction(title: "OK", role: .primary)
            ]
        let result = run(
            title: title,
            message: message,
            actions: actions
        )
        guard result.actionIndex == 0, let details else { return }
        let detailsResult = run(
            title: "\(title) Details",
            message: details,
            actions: [
                AppDialogAction(title: "Copy Details", role: .secondary),
                AppDialogAction(title: "OK", role: .primary)
            ]
        )
        guard detailsResult.actionIndex == 0 else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(details, forType: .string)
    }

    private static func dialogHeight(fieldCount: Int, message: String) -> CGFloat {
        let explicitLines = message.split(
            separator: "\n",
            omittingEmptySubsequences: false
        )
        let estimatedLines = explicitLines.reduce(0) { count, line in
            count + max(1, Int(ceil(Double(line.count) / 58.0)))
        }
        let messageHeight = min(CGFloat(estimatedLines) * 18, 154)
        return min(
            460,
            max(176, 132 + messageHeight + CGFloat(fieldCount * 64))
        )
    }
}

private final class AppDialogPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
private final class AppDialogSession: ObservableObject {
    @Published var values: [String]
    weak var panel: NSPanel?
    private(set) var actionIndex: Int?

    init(fieldCount: Int) {
        values = Array(repeating: "", count: fieldCount)
    }

    func finish(actionIndex: Int) {
        self.actionIndex = actionIndex
        NSApp.stopModal()
    }

    func cancel() {
        actionIndex = nil
        NSApp.stopModal()
    }
}

private struct AppDialogView: View {
    let title: String
    let message: String
    let fields: [AppDialogField]
    let actions: [AppDialogAction]
    @ObservedObject var session: AppDialogSession
    @FocusState private var focusedField: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(AppTheme.primary)

            messageView

            fieldsSection

            Spacer(minLength: 18)

            HStack(spacing: 8) {
                Spacer(minLength: 0)

                ForEach(actions.indices, id: \.self, content: actionButton)
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 22)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppTheme.raisedFill)
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(AppTheme.inputBorder, lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .onAppear {
            if !fields.isEmpty {
                focusedField = 0
            }
        }
        .onExitCommand {
            session.cancel()
        }
    }

    @ViewBuilder
    private var messageView: some View {
        if messageNeedsScrolling {
            ScrollView {
                messageText
            }
            .scrollIndicators(.visible)
            .frame(maxHeight: 154)
            .padding(.top, 7)
        } else {
            messageText
                .padding(.top, 7)
        }
    }

    private var messageText: some View {
        Text(message)
            .font(.system(size: 13))
            .foregroundStyle(AppTheme.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .textSelection(.enabled)
    }

    private var messageNeedsScrolling: Bool {
        message.count > 420 || message.filter(\.isNewline).count > 6
    }

    @ViewBuilder
    private var fieldsSection: some View {
        if !fields.isEmpty {
            VStack(spacing: 11) {
                ForEach(fields.indices, id: \.self) { index in
                    VStack(alignment: .leading, spacing: 5) {
                        Text(fields[index].label)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(AppTheme.secondary)

                        TextField(
                            fields[index].placeholder,
                            text: $session.values[index]
                        )
                        .textFieldStyle(.plain)
                        .font(.system(size: 13))
                        .foregroundStyle(AppTheme.primary)
                        .padding(.horizontal, 9)
                        .frame(height: 30)
                        .background(AppTheme.inputFill)
                        .overlay {
                            RoundedRectangle(cornerRadius: 5)
                                .stroke(
                                    focusedField == index
                                        ? AppTheme.actionBlue
                                        : AppTheme.edge,
                                    lineWidth: focusedField == index ? 1.5 : 1
                                )
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 5))
                        .focused($focusedField, equals: index)
                    }
                }
            }
            .padding(.top, 16)
        }
    }

    @ViewBuilder
    private func actionButton(index: Int) -> some View {
        let action = actions[index]
        let button = Button(role: buttonRole(for: action.role)) {
            if action.role == .cancel {
                session.cancel()
            } else {
                session.finish(actionIndex: index)
            }
        } label: {
            Text(action.title)
        }
        .buttonStyle(AppDialogButtonStyle(role: action.role))
        .disabled(
            action.role == .primary
                && fields.indices.contains { index in
                    fields[index].isRequired
                        && session.values[index]
                            .trimmingCharacters(in: .whitespacesAndNewlines)
                            .isEmpty
                }
        )

        if action.role == .primary {
            button.keyboardShortcut(.defaultAction)
        } else if action.role == .cancel {
            button.keyboardShortcut(.cancelAction)
        } else {
            button
        }
    }

    private func buttonRole(for role: AppDialogActionRole) -> ButtonRole? {
        switch role {
        case .destructive: return .destructive
        case .cancel: return .cancel
        case .primary, .secondary: return nil
        }
    }
}

private struct AppDialogButtonStyle: ButtonStyle {
    let role: AppDialogActionRole
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(foregroundColor)
            .padding(.horizontal, 15)
            .frame(minWidth: 78, minHeight: 30)
            .background(backgroundColor.opacity(configuration.isPressed ? 0.78 : 1))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .contentShape(Rectangle())
            .opacity(isEnabled ? 1 : 0.46)
    }

    private var backgroundColor: Color {
        switch role {
        case .primary: return AppTheme.actionBlue
        case .destructive: return AppTheme.destructiveButton
        case .secondary, .cancel: return AppTheme.disabledFill
        }
    }

    private var foregroundColor: Color {
        switch role {
        case .primary: return AppTheme.onAccent
        case .destructive: return AppTheme.onDestructive
        case .secondary, .cancel: return AppTheme.primary
        }
    }
}
