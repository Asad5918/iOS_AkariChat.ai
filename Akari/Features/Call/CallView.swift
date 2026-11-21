import SwiftUI
import SwiftData

struct CallView: View {
    @State private var call: VoiceCallManager
    @State private var pulse = false
    @Environment(\.dismiss) private var dismiss

    init(conversation: Conversation, manager: ModelManager, context: ModelContext) {
        _call = State(initialValue: VoiceCallManager(
            conversation: conversation, engineProvider: { manager.engine }, context: context))
    }

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.10, green: 0.10, blue: 0.22), Color(red: 0.30, green: 0.14, blue: 0.40)],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()

            VStack(spacing: 18) {
                Spacer(minLength: 40)
                avatar
                Text(call.personaName)
                    .font(.system(size: 32, weight: .semibold))
                    .foregroundStyle(.white)
                Text(statusLine)
                    .font(.headline)
                    .foregroundStyle(.white.opacity(0.75))
                timer

                caption
                    .frame(maxWidth: .infinity, minHeight: 90, alignment: .top)
                    .padding(.horizontal, 28)

                Spacer()
                controls
                    .padding(.bottom, 24)
            }
        }
        .task { await call.start() }
        .onAppear { pulse = true }
        .onDisappear { call.end() }
        .onChange(of: call.phase) { _, phase in
            if phase == .ended && call.errorMessage == nil { dismiss() }
        }
    }

    private var avatar: some View {
        let speaking = call.phase == .speaking
        return ZStack {
            Circle()
                .stroke(.white.opacity(0.25), lineWidth: 2)
                .frame(width: 190, height: 190)
                .scaleEffect(pulse && (speaking || call.phase == .listening) ? 1.12 : 1)
                .animation(.easeInOut(duration: speaking ? 0.6 : 1.4).repeatForever(autoreverses: true), value: pulse)
            Circle()
                .fill(.white.opacity(0.12))
                .frame(width: 160, height: 160)
            Text(call.personaEmoji).font(.system(size: 84))
        }
    }

    private var statusLine: String {
        if let error = call.errorMessage { return error }
        switch call.phase {
        case .connecting: return "Connecting…"
        case .listening: return call.isMuted ? "Muted" : "Listening…"
        case .thinking: return "Thinking…"
        case .speaking: return "Speaking…"
        case .ended: return "Call ended"
        }
    }

    private var timer: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let seconds = Int(context.date.timeIntervalSince(call.startedAt ?? context.date))
            Text(String(format: "%02d:%02d", seconds / 60, seconds % 60))
                .font(.system(.title3, design: .monospaced))
                .foregroundStyle(.white.opacity(0.6))
        }
    }

    @ViewBuilder private var caption: some View {
        if call.phase == .speaking || (call.phase == .thinking && !call.reply.isEmpty) {
            Text(call.reply)
                .font(.body)
                .foregroundStyle(.white.opacity(0.9))
                .multilineTextAlignment(.center)
        } else if !call.heard.isEmpty {
            Text("“\(call.heard)”")
                .font(.body.italic())
                .foregroundStyle(.white.opacity(0.6))
                .multilineTextAlignment(.center)
        }
    }

    private var controls: some View {
        HStack(spacing: 34) {
            controlButton(call.isMuted ? "mic.slash.fill" : "mic.fill", active: call.isMuted) { call.toggleMute() }
            Button {
                call.end()
                dismiss()
            } label: {
                Image(systemName: "phone.down.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(.white)
                    .frame(width: 76, height: 76)
                    .background(.red, in: Circle())
            }
            controlButton(call.speakerOn ? "speaker.wave.3.fill" : "speaker.fill", active: call.speakerOn) { call.toggleSpeaker() }
        }
    }

    private func controlButton(_ symbol: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 24))
                .foregroundStyle(active ? .black : .white)
                .frame(width: 64, height: 64)
                .background(active ? Color.white : Color.white.opacity(0.18), in: Circle())
        }
    }
}
