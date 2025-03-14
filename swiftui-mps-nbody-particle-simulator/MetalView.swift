import SwiftUI
import MetalKit

struct MetalView: NSViewRepresentable {
    @ObservedObject var settings: SimulationSettings
    @ObservedObject var renderer: SimulationRenderer

    func makeNSView(context: Context) -> MTKView {
        let mtkView = MetalMTKView()
        mtkView.device = renderer.device
        mtkView.delegate = renderer
        mtkView.framebufferOnly = true
        mtkView.colorPixelFormat = .bgra8Unorm
        mtkView.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        mtkView.enableSetNeedsDisplay = false
        mtkView.isPaused = false
        mtkView.preferredFramesPerSecond = 240
        return mtkView
    }
    
    func updateNSView(_ nsView: MTKView, context: Context) {
        renderer.updateSimulationIfNeeded(settings: settings)
    }
}

class MetalMTKView: MTKView {
    override func mouseDown(with event: NSEvent) {
        super.mouseDown(with: event)
    }
    override func mouseDragged(with event: NSEvent) {
        (delegate as? SimulationRenderer)?.handleMouseDrag(event: event)
    }
    override func scrollWheel(with event: NSEvent) {
        (delegate as? SimulationRenderer)?.handleScroll(event: event)
    }
}
