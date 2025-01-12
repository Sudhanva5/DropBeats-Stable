import SwiftUI
import Lottie

struct LottieConfettiView: View {
    let isVisible: Bool
    
    var body: some View {
        LottieView(animation: .named("Animation"))
            .playing(isVisible)
            .looping(false)
    }
}

private struct LottieView: NSViewRepresentable {
    let animation: LottieAnimation?
    var isPlaying: Bool = false
    var looping: Bool = false
    
    func makeNSView(context: Context) -> LottieAnimationView {
        let view = LottieAnimationView(animation: animation)
        view.contentMode = .scaleAspectFit
        view.loopMode = looping ? .loop : .playOnce
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        view.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        view.translatesAutoresizingMaskIntoConstraints = true
        return view
    }
    
    func updateNSView(_ nsView: LottieAnimationView, context: Context) {
        if isPlaying {
            nsView.play()
        }
    }
    
    func playing(_ playing: Bool) -> LottieView {
        var view = self
        view.isPlaying = playing
        return view
    }
    
    func looping(_ looping: Bool) -> LottieView {
        var view = self
        view.looping = looping
        return view
    }
} 
