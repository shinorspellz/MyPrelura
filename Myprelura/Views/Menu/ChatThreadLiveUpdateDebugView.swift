import SwiftUI

/// Debug → trace why a push notification fires but the open chat thread does not show the new line.
/// Follow counters: if **WS frame** increases but **PARSE DROP** appears, the payload shape is wrong; if **PARSE OK** runs but **UI DRAIN** does not, the bridge / SwiftUI path failed; if **UI HANDLE** runs but the bubble is missing, check merge / `displayedMessages` / timeline.
struct ChatThreadLiveUpdateDebugView: View {
    @ObservedObject private var state = ChatThreadUIUpdateDebugState.shared

    var body: some View {
        List {
            Section {
                Text(
                    "Open the thread **before** reproducing. Push can arrive while the app is backgrounded — the chat socket is disconnected then, so no live row until you foreground and refetch. "
                        + "This screen shows whether a **WebSocket JSON** arrived, whether it **parsed** as a `Message`, whether the **bridge** queued it, and whether **`onChange` drained** it into the thread handler."
                )
                .font(.caption)
                .foregroundStyle(Theme.Colors.secondaryText)
                .listRowBackground(Color.clear)
            } header: {
                Text("How to read this")
            }

            Section {
                LabeledContent("WS text frames") { Text("\(state.wsStringReceiveCount)") }
                LabeledContent("JSON objects routed") { Text("\(state.jsonObjectReceiveCount)") }
                LabeledContent("Parse → onNewMessage") { Text("\(state.parseSuccessCount)") }
                LabeledContent("Parse dropped") { Text("\(state.parseDropCount)").foregroundStyle(state.parseDropCount > 0 ? Color.orange : Theme.Colors.primaryText) }
                LabeledContent("Server error frames") { Text("\(state.serverErrorFrameCount)").foregroundStyle(state.serverErrorFrameCount > 0 ? Color.red : Theme.Colors.primaryText) }
                LabeledContent("Bridge enqueue") { Text("\(state.bridgeEmitCount)") }
                LabeledContent("UI onChange drains") { Text("\(state.uiOnChangeDrainCount)") }
                LabeledContent("UI thread outcomes") { Text("\(state.uiHandlerOutcomeCount)") }
            } header: {
                Text("Counters (session)")
            } footer: {
                Text("If **serverErr** > 0, Django sent `{\"error\":...}` (handler exception) — no `chat_message` broadcast. If parseOk > 0 but uiDrain stays 0, the bridge / onChange path did not run. If uiOutcome > 0 but no bubble, merge or displayedMessages filtered the row out.")
            }

            Section {
                if state.entries.isEmpty {
                    Text("No events yet. Open a DM and send/receive a message with this screen dismissed (or in split view).")
                        .font(.caption)
                        .foregroundStyle(Theme.Colors.secondaryText)
                } else {
                    ForEach(state.entries) { entry in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(entry.at.formatted(date: .abbreviated, time: .standard))
                                .font(.caption2)
                                .foregroundStyle(Theme.Colors.secondaryText)
                            Text(entry.line)
                                .font(.caption)
                                .foregroundStyle(Theme.Colors.primaryText)
                                .textSelection(.enabled)
                        }
                    }
                }
                Button("Copy full trace") {
                    UIPasteboard.general.string = state.exportText()
                }
                Button("Clear trace + counters", role: .destructive) {
                    state.clear()
                }
            } header: {
                Text("Recent events (newest first)")
            } footer: {
                Text("Same lines are also appended to the notification debug log as source `chat_ui_trace`.")
            }
        }
        .listStyle(.insetGrouped)
        .background(Theme.Colors.background)
        .navigationTitle("Chat live update trace")
        .navigationBarTitleDisplayMode(.inline)
    }
}
