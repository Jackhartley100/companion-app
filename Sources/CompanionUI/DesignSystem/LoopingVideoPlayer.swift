import SwiftUI
#if canImport(UIKit)
import AVFoundation
import UIKit
#endif

#if canImport(UIKit)
/// A silent, gapless, seamlessly-looping video background.
///
/// Built on `AVPlayerLooper` rather than observing "did play to end" and
/// seeking back to zero — that approach leaves a visible stutter at the loop
/// point, which a hero background plays constantly and a stutter would be
/// seen on every single loop.
public struct LoopingVideoPlayer: UIViewRepresentable {
    let url: URL

    public init(url: URL) {
        self.url = url
    }

    public func makeUIView(context: Context) -> PlayerLayerView {
        let item = AVPlayerItem(url: url)
        let queuePlayer = AVQueuePlayer()
        queuePlayer.isMuted = true
        let looper = AVPlayerLooper(player: queuePlayer, templateItem: item)
        context.coordinator.looper = looper
        context.coordinator.player = queuePlayer

        let view = PlayerLayerView()
        view.playerLayer.player = queuePlayer
        view.playerLayer.videoGravity = .resizeAspectFill
        queuePlayer.play()
        return view
    }

    public func updateUIView(_ uiView: PlayerLayerView, context: Context) {}

    public func makeCoordinator() -> Coordinator { Coordinator() }

    public final class Coordinator {
        var looper: AVPlayerLooper?
        var player: AVQueuePlayer?
    }

    /// A `UIView` whose backing layer is `AVPlayerLayer`, so the video
    /// resizes with the view instead of needing a manual `CALayer` frame
    /// update on every layout pass.
    public final class PlayerLayerView: UIView {
        public override class var layerClass: AnyClass { AVPlayerLayer.self }
        var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
    }
}
#endif
