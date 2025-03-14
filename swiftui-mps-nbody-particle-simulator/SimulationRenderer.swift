import MetalKit
import simd

class SimulationRenderer: NSObject, MTKViewDelegate, ObservableObject {
    @Published var currentFPS: Int = 0
    @Published var isOrbiting: Bool = false
    @Published var orbitSpeed: Float = 0.1
    @Published var orbitX: Bool = false
    @Published var orbitY: Bool = false
    @Published var orbitZ: Bool = false
    
    @Published var autoModeEnabled: Bool = false
    @Published var autoRestartInterval: Double = 2.0 // Minutes
    private var lastAutoRestartTime: CFTimeInterval = 0
    
    // Camera transition properties
    private var targetCameraDistance: Float = 500.0
    private var transitionStartDistance: Float = 500.0
    private var transitionStartTime: CFTimeInterval = 0
    private var isTransitioning: Bool = false
    private var transitionDuration: CFTimeInterval = 30.0 // 10 second transitions
    private var transitionStartedAt: CFTimeInterval = 0
    private var hasLoggedStart: Bool = false
    
    // Auto zoom properties
    private var lastCameraAdjustmentTime: CFTimeInterval = 0
    private var cameraAdjustmentInterval: CFTimeInterval = 10.0
    private var simulationStartTime: CFTimeInterval = 0
    
    private var lastMouseLocation: CGPoint?
    private var lastFrameTime: CFTimeInterval = 0
    private var frameCount: Int = 0
    
    let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let renderPipeline: MTLRenderPipelineState
    
    private var positionBufferA: MTLBuffer!
    private var positionBufferB: MTLBuffer!
    private var velocityBuffer: MTLBuffer!
    private var colorBuffer: MTLBuffer!
    private var sizeBuffer: MTLBuffer!
    private var usingBufferA: Bool = true
    
    struct SimParams {
        var deltaTime: Float
        var gravitationalConstant: Float
        var smoothingLength: Float
        var particleCount: UInt32
        var interactionSkip: UInt32
        var bloom: Float
        var colorMix: Float
        var blackHoleEnabled: UInt32
        var blackHoleMass: Float
        var blackHolePosition: simd_float4
        var blackHoleAccretionRadius: Float
        var blackHoleSpin: Float
        var secondBlackHoleEnabled: UInt32
        var secondBlackHoleMass: Float
        var secondBlackHolePosition: simd_float4
        var secondBlackHoleAccretionRadius: Float
        var secondBlackHoleSpin: Float
        var particleOpacity: Float
        var _padding: simd_float3
        var _extraPadding: simd_float4
    }
    private var simParams = SimParams(deltaTime: 0.1,
                                      gravitationalConstant: 1.0,
                                      smoothingLength: 100,
                                      particleCount: 0,
                                      interactionSkip: 1,
                                      bloom: 1.0,
                                      colorMix: 0.0,
                                      blackHoleEnabled: 1,
                                      blackHoleMass: 0,
                                      blackHolePosition: simd_float4(0,0,0,0),
                                      blackHoleAccretionRadius: 0.0,
                                      blackHoleSpin: 0.0,
                                      secondBlackHoleEnabled: 1,
                                      secondBlackHoleMass: 0,
                                      secondBlackHolePosition: simd_float4(0,0,0,0),
                                      secondBlackHoleAccretionRadius: 0.0,
                                      secondBlackHoleSpin: 0.0,
                                      particleOpacity: 0.25,
                                      _padding: simd_float3(0, 0, 0),
                                      _extraPadding: simd_float4(0, 0, 0 ,0))
    
    private var paramsBuffer: MTLBuffer!
    
    var mpsSimulation: MPSParticleSimulation!
    
    private var cameraYaw: Float = 0.0
    private var cameraPitch: Float = 0.0
    private var cameraRoll: Float = 0.0
    private var cameraDistance: Float = 500.0
    private var initialFarPlane: Float = 1000.0
    
    private var isFirstInit: Bool = true
    
    private var lastSettings = SimulationSettings()
    private var settingsRef: SimulationSettings
    
    init(settings: SimulationSettings) {
        self.settingsRef = settings
        guard let device = MTLCreateSystemDefaultDevice() else { fatalError("Metal GPU device not available") }
        self.device = device
        self.commandQueue = device.makeCommandQueue()!
        let library = device.makeDefaultLibrary()!
        guard let vertexFunc = library.makeFunction(name: "particleVertexShader"),
              let fragFunc = library.makeFunction(name: "particleFragmentShader") else {
            fatalError("Failed to load shader functions")
        }
        let renderDesc = MTLRenderPipelineDescriptor()
        renderDesc.vertexFunction = vertexFunc
        renderDesc.fragmentFunction = fragFunc
        renderDesc.colorAttachments[0].pixelFormat = .bgra8Unorm
        renderDesc.colorAttachments[0].isBlendingEnabled = true
        renderDesc.colorAttachments[0].rgbBlendOperation = .add
        renderDesc.colorAttachments[0].alphaBlendOperation = .add
        renderDesc.colorAttachments[0].sourceRGBBlendFactor = .one
        renderDesc.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
        renderDesc.colorAttachments[0].sourceAlphaBlendFactor = .one
        renderDesc.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha
        do {
            renderPipeline = try device.makeRenderPipelineState(descriptor: renderDesc)
        } catch {
            fatalError("Failed to create render pipeline state: \(error)")
        }
        super.init()
        allocateBuffers(particleCount: settings.particleCount)
        paramsBuffer = device.makeBuffer(length: MemoryLayout<SimParams>.size, options: .storageModeShared)
        mpsSimulation = MPSParticleSimulation(device: device, paramsBuffer: paramsBuffer)
        resetSimulation()
    }
    
    private func allocateBuffers(particleCount: Int) {
        let count = particleCount
        let positionBufferLength = MemoryLayout<simd_float3>.stride * count
        let colorBufferLength = MemoryLayout<simd_float4>.stride * count
        let sizeBufferLength = MemoryLayout<Float>.stride * count
        
        positionBufferA = device.makeBuffer(length: positionBufferLength, options: .storageModeShared)
        positionBufferB = device.makeBuffer(length: positionBufferLength, options: .storageModeShared)
        velocityBuffer  = device.makeBuffer(length: positionBufferLength, options: .storageModeShared)
        colorBuffer     = device.makeBuffer(length: colorBufferLength, options: .storageModeShared)
        sizeBuffer      = device.makeBuffer(length: sizeBufferLength, options: .storageModeShared)
    }
    
    // Apply smooth camera transition with easing
    private func updateCameraTransition() {
        if !isTransitioning {
            return
        }
        
        let currentTime = CACurrentMediaTime()
        let elapsedTime = currentTime - transitionStartTime
        
        // Log transition start
        if !hasLoggedStart {
            print("Camera transition started - target duration: \(transitionDuration) seconds")
            transitionStartedAt = currentTime
            hasLoggedStart = true
        }
        
        if elapsedTime >= transitionDuration {
            // Transition complete - log actual duration
            let actualDuration = currentTime - transitionStartedAt
            print("Camera transition completed after \(String(format: "%.2f", actualDuration)) seconds")
            
            // Reset transition state
            cameraDistance = targetCameraDistance
            isTransitioning = false
            hasLoggedStart = false
            return
        }
        
        // Calculate progress with easing
        let progress = Float(elapsedTime / transitionDuration)
        let easedProgress = easingFunction(progress)
        
        // Interpolate between start and target distances
        cameraDistance = transitionStartDistance + (targetCameraDistance - transitionStartDistance) * easedProgress
    }
    // Cubic easing function for smooth transitions
    private func easingFunction(_ x: Float) -> Float {
        return x < 0.5 ? 4 * x * x * x : 1 - pow(-2 * x + 2, 3) / 2
    }
    
    // Start a smooth transition to a new camera distance
    private func startCameraTransition(to targetDistance: Float) {
        // Avoid unnecessary transitions for small changes
        if abs(targetDistance - cameraDistance) < 0.5 {
            return
        }
        
        targetCameraDistance = targetDistance
        transitionStartDistance = cameraDistance
        transitionStartTime = CACurrentMediaTime()
        isTransitioning = true
        print("Starting camera transition from \(cameraDistance) to \(targetDistance)")
    }
    
    // Adjust camera distance to keep particles in view
    private func adjustCameraForOptimalView() {
        let count = settingsRef.particleCount
        if count <= 0 { return }
        
        // Get particle positions
        var positions = [simd_float3](repeating: .zero, count: count)
        let currentPosBuffer = usingBufferA ? positionBufferA! : positionBufferB!
        memcpy(&positions, currentPosBuffer.contents(), MemoryLayout<simd_float3>.stride * count)
        
        // Calculate bounding box
        var minPos = simd_float3(Float.greatestFiniteMagnitude, Float.greatestFiniteMagnitude, Float.greatestFiniteMagnitude)
        var maxPos = simd_float3(-Float.greatestFiniteMagnitude, -Float.greatestFiniteMagnitude, -Float.greatestFiniteMagnitude)
        
        for i in 0..<count {
            let pos = positions[i]
            minPos.x = min(minPos.x, pos.x)
            minPos.y = min(minPos.y, pos.y)
            minPos.z = min(minPos.z, pos.z)
            maxPos.x = max(maxPos.x, pos.x)
            maxPos.y = max(maxPos.y, pos.y)
            maxPos.z = max(maxPos.z, pos.z)
        }
        
        // Calculate box dimensions
        let size = maxPos - minPos
        let diagonal = sqrt(size.x * size.x + size.y * size.y + size.z * size.z)
        
        // Calculate ideal camera distance based on field of view
        let fovRadians: Float = 60.0 * (.pi / 180)
        let padding: Float = 1.0 // Padding factor
        let distance = (diagonal * 0.5) / tan(fovRadians * 0.5) * padding
        
        // Ensure minimum distance
        let minDistance = Float(settingsRef.radius) * 1.3
        let finalDistance = max(distance, minDistance)
        
        // Start transition to new distance
        startCameraTransition(to: finalDistance)
    }
    
    func updateParticleColors() {
        let currentPosBuffer = usingBufferA ? positionBufferA! : positionBufferB!
        let count = settingsRef.particleCount
        
        var positions = [simd_float3](repeating: .zero, count: count)
        var velocities = [simd_float3](repeating: .zero, count: count)
        var colors = [simd_float4](repeating: .zero, count: count)
        
        currentPosBuffer.contents().copyMemory(from: &positions, byteCount: 0)
        memcpy(&positions, currentPosBuffer.contents(), MemoryLayout<simd_float3>.stride * count)
        
        velocityBuffer.contents().copyMemory(from: &velocities, byteCount: 0)
        memcpy(&velocities, velocityBuffer.contents(), MemoryLayout<simd_float3>.stride * count)
        
        if settingsRef.simType == .collision {
            let halfCount = count / 2
            
            var maxSpeedFirstGalaxy: Float = 0
            for i in 0..<halfCount {
                let speed = simd_length(velocities[i])
                maxSpeedFirstGalaxy = max(maxSpeedFirstGalaxy, speed)
            }
            
            var maxSpeedSecondGalaxy: Float = 0
            for i in halfCount..<count {
                let speed = simd_length(velocities[i])
                maxSpeedSecondGalaxy = max(maxSpeedSecondGalaxy, speed)
            }
            
            for i in 0..<count {
                let speed = simd_length(velocities[i])
                let maxSpeed = i < halfCount ? maxSpeedFirstGalaxy : maxSpeedSecondGalaxy
                let t = min(speed / maxSpeed, 1.0)
                
                if i < halfCount {
                    colors[i] = simd_float4(velocityToColor(t, settingsRef), Float(settingsRef.particleOpacity))
                } else {
                    if settingsRef.useRandomColors {
                        colors[i] = simd_float4(velocityToColorSecondGalaxy(t, settingsRef), Float(settingsRef.particleOpacity))
                    } else {
                        colors[i] = simd_float4(inverseVelocityToColor(t, settingsRef), Float(settingsRef.particleOpacity))
                    }
                }
            }
        } else {
            var maxSpeed: Float = 0
            for i in 0..<count {
                let speed = simd_length(velocities[i])
                maxSpeed = max(maxSpeed, speed)
            }
            
            for i in 0..<count {
                let speed = simd_length(velocities[i])
                let t = min(speed / maxSpeed, 1.0)
                colors[i] = simd_float4(velocityToColor(t, settingsRef), Float(settingsRef.particleOpacity))
            }
        }
        
        colorBuffer.contents().copyMemory(from: colors, byteCount: MemoryLayout<simd_float4>.stride * count)
    }
    
    private func velocityToColor(_ normalizedVelocity: Float, _ settings: SimulationSettings) -> SIMD3<Float> {
        let lowVelocityColor = settings.currentLowVelocityColor
        let highVelocityColor = settings.currentHighVelocityColor
        
        let t = pow(normalizedVelocity, 1.2)
        
        return mix(lowVelocityColor, highVelocityColor, t)
    }
    
    private func velocityToColorSecondGalaxy(_ normalizedVelocity: Float, _ settings: SimulationSettings) -> SIMD3<Float> {
        let lowVelocityColor = settings.secondGalaxyLowVelocityColor
        let highVelocityColor = settings.secondGalaxyHighVelocityColor
        
        let t = pow(normalizedVelocity, 1.2)
        
        return mix(lowVelocityColor, highVelocityColor, t)
    }
    
    private func inverseVelocityToColor(_ normalizedVelocity: Float, _ settings: SimulationSettings) -> SIMD3<Float> {
        let lowVelocityColor = SIMD3<Float>(1.0) - settings.currentLowVelocityColor
        let highVelocityColor = SIMD3<Float>(1.0) - settings.currentHighVelocityColor
        
        let t = pow(normalizedVelocity, 1.2)
        
        return mix(lowVelocityColor, highVelocityColor, t)
    }
    
    private func mix(_ color1: SIMD3<Float>, _ color2: SIMD3<Float>, _ t: Float) -> SIMD3<Float> {
        return color1 * (1 - t) + color2 * t
    }
    
    func autoRestartSimulation() {
        resetSimulation()
        
        // Reset simulation time tracking
        simulationStartTime = CACurrentMediaTime()
        
        // Set random camera position
        cameraYaw = Float.random(in: 0..<2 * Float.pi)
        cameraPitch = Float.random(in: -Float.pi/3...Float.pi/3)
        cameraRoll = Float.random(in: -Float.pi/6...Float.pi/6)
        
        // Run camera adjustment with delay to ensure particles are loaded
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self = self else { return }
            self.adjustCameraForOptimalView()
        }
        
        // Ensure simulation is running
        if !settingsRef.isRunning {
            settingsRef.isRunning = true
        }
    }
    
    func resetSimulation() {
            mpsSimulation.initializeBlackHoles(
                simType: settingsRef.simType,
                radius: Float(settingsRef.radius),
                initialSpeed: Float(settingsRef.initialRotation),
                collisionVelocity: Float(settingsRef.collisionVelocity)
            )
            
            let (positions, velocities, colors, sizes) = ParticleGenerator.generateParticles(
                type: settingsRef.simType,
                count: settingsRef.particleCount,
                radius: Float(settingsRef.radius),
                thickness: Float(settingsRef.thickness),
                initialSpeed: Float(settingsRef.initialRotation),
                initialCoreSpin: Float(settingsRef.initialCoreSpin),
                minParticleSize: Float(settingsRef.minParticleSize),
                maxParticleSize: Float(settingsRef.maxParticleSize),
                collisionVelocity: Float(settingsRef.collisionVelocity),
                firstGalaxyRotation: settingsRef.simType == .collision ? mpsSimulation.firstGalaxyRotation : nil,
                secondGalaxyRotation: settingsRef.simType == .collision ? mpsSimulation.secondGalaxyRotation : nil,
                sameDirection: settingsRef.simType == .collision ? mpsSimulation.galaxiesSpinInSameDirection : false,
                settings: settingsRef
            )
            
            let count = settingsRef.particleCount
            positionBufferA.contents().copyMemory(from: positions, byteCount: MemoryLayout<simd_float3>.stride * count)
            positionBufferB.contents().copyMemory(from: positions, byteCount: MemoryLayout<simd_float3>.stride * count)
            velocityBuffer.contents().copyMemory(from: velocities, byteCount: MemoryLayout<simd_float3>.stride * count)
            colorBuffer.contents().copyMemory(from: colors, byteCount: MemoryLayout<simd_float4>.stride * count)
            sizeBuffer.contents().copyMemory(from: sizes, byteCount: MemoryLayout<Float>.stride * count)
            
            usingBufferA = true
            
            if isFirstInit {
                cameraDistance = max(Float(settingsRef.radius) * 4, 100)
                initialFarPlane = Float(settingsRef.radius) * 2 + 2000
                isFirstInit = false
            }
            
            updateFarPlaneForRadius(Float(settingsRef.radius))
            
            mpsSimulation.setBlackHoleProperties(
                firstEnabled: settingsRef.blackHoleEnabled,
                firstMass: Float(settingsRef.blackHoleMass),
                firstSpin: Float(settingsRef.blackHoleSpin),
                secondEnabled: settingsRef.secondBlackHoleEnabled,
                secondMass: Float(settingsRef.secondBlackHoleMass),
                secondSpin: Float(settingsRef.secondBlackHoleSpin),
                gravityMultiplier: Float(settingsRef.blackHoleGravityMultiplier)
            )
        }
        
        private func updateFarPlaneForRadius(_ radius: Float) {
            let radiusFarPlane = radius * 1 + 1000
            let cameraFarPlane = cameraDistance * 2
            initialFarPlane = max(radiusFarPlane, cameraFarPlane, 10000.0)
        }
        
        private func updateSimParams() {
            simParams.deltaTime = 0.1
            simParams.gravitationalConstant = Float(settingsRef.gravitationalForce)
            simParams.smoothingLength = Float(settingsRef.smoothing)
            simParams.particleCount = UInt32(settingsRef.particleCount)
            let rate = settingsRef.interactionRate <= 0 ? 0 : floor(1.0 / settingsRef.interactionRate)
            simParams.interactionSkip = UInt32(max(1, rate))
            
            simParams.bloom = Float(settingsRef.bloom)
            simParams.colorMix = Float(settingsRef.colorMix)
            simParams.particleOpacity = Float(settingsRef.particleOpacity)
            
            simParams.blackHoleEnabled = settingsRef.blackHoleEnabled ? 1 : 0
            simParams.blackHoleMass = Float(settingsRef.blackHoleMass)
            simParams.blackHoleAccretionRadius = Float(settingsRef.blackHoleAccretionRadius)
            simParams.blackHoleSpin = Float(settingsRef.blackHoleSpin)
            
            simParams.secondBlackHoleEnabled = (settingsRef.simType == .collision && settingsRef.secondBlackHoleEnabled) ? 1 : 0
            simParams.secondBlackHoleMass = Float(settingsRef.secondBlackHoleMass)
            simParams.secondBlackHoleAccretionRadius = Float(settingsRef.secondBlackHoleAccretionRadius)
            simParams.secondBlackHoleSpin = Float(settingsRef.secondBlackHoleSpin)
            
            mpsSimulation.setBlackHoleProperties(
                firstEnabled: settingsRef.blackHoleEnabled,
                firstMass: Float(settingsRef.blackHoleMass),
                firstSpin: Float(settingsRef.blackHoleSpin),
                secondEnabled: settingsRef.secondBlackHoleEnabled,
                secondMass: Float(settingsRef.secondBlackHoleMass),
                secondSpin: Float(settingsRef.secondBlackHoleSpin),
                gravityMultiplier: Float(settingsRef.blackHoleGravityMultiplier)
            )
            
            let paramsPointer = paramsBuffer.contents().bindMemory(to: SimParams.self, capacity: 1)
            paramsPointer.pointee = simParams
        }
        
        func updateSimulationIfNeeded(settings: SimulationSettings) {
            let needReset = settings.particleCount != lastSettings.particleCount ||
                            settings.simType != lastSettings.simType ||
                            settings.radius != lastSettings.radius ||
                            settings.thickness != lastSettings.thickness ||
                            settings.initialRotation != lastSettings.initialRotation ||
                            settings.initialCoreSpin != lastSettings.initialCoreSpin ||
                            settings.minParticleSize != lastSettings.minParticleSize ||
                            settings.maxParticleSize != lastSettings.maxParticleSize ||
                            settings.collisionVelocity != lastSettings.collisionVelocity
                            
            if needReset {
                if settings.particleCount != lastSettings.particleCount || settings.simType != lastSettings.simType {
                    allocateBuffers(particleCount: settings.particleCount)
                }
                resetSimulation()
            }
            
            lastSettings.simType = settings.simType
            lastSettings.particleCount = settings.particleCount
            lastSettings.radius = settings.radius
            lastSettings.thickness = settings.thickness
            lastSettings.initialRotation = settings.initialRotation
            lastSettings.initialCoreSpin = settings.initialCoreSpin
            lastSettings.smoothing = settings.smoothing
            lastSettings.interactionRate = settings.interactionRate
            lastSettings.blackHoleEnabled = settings.blackHoleEnabled
            lastSettings.blackHoleMass = settings.blackHoleMass
            lastSettings.blackHoleAccretionRadius = settings.blackHoleAccretionRadius
            lastSettings.blackHoleSpin = settings.blackHoleSpin
            lastSettings.secondBlackHoleEnabled = settings.secondBlackHoleEnabled
            lastSettings.secondBlackHoleMass = settings.secondBlackHoleMass
            lastSettings.secondBlackHoleAccretionRadius = settings.secondBlackHoleAccretionRadius
            lastSettings.secondBlackHoleSpin = settings.secondBlackHoleSpin
            lastSettings.bloom = settings.bloom
            lastSettings.colorMix = settings.colorMix
            lastSettings.gravitationalForce = settings.gravitationalForce
            lastSettings.collisionVelocity = settings.collisionVelocity
            lastSettings.minParticleSize = settings.minParticleSize
            lastSettings.maxParticleSize = settings.maxParticleSize
            lastSettings.blackHoleGravityMultiplier = settings.blackHoleGravityMultiplier
        }
        
        func handleMouseDrag(event: NSEvent) {
            let location = event.locationInWindow
            if lastMouseLocation == nil { lastMouseLocation = location }
            let dx = Float(location.x - (lastMouseLocation?.x ?? location.x))
            let dy = Float(location.y - (lastMouseLocation?.y ?? location.y))
            lastMouseLocation = location
            cameraYaw   += dx * 0.005
            cameraPitch += dy * 0.005
            cameraPitch = min(max(cameraPitch, -Float.pi/2 + 0.01), Float.pi/2 - 0.01)
        }
        
    func handleScroll(event: NSEvent) {
        let deltaY = Float(event.scrollingDeltaY)
        let zoomSpeed = max(1.0, cameraDistance / 500.0) * 5.0
        
        // Apply immediate camera distance change for responsive zooming
        cameraDistance = max(cameraDistance - deltaY * zoomSpeed, 5.0)
        
        // Update far plane to match new distance
        updateFarPlane()
    }
        
        private func updateFarPlane() {
            initialFarPlane = max(cameraDistance * 2, 10000.0)
        }
        
        func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}
        
        func draw(in view: MTKView) {
            guard let drawable = view.currentDrawable,
                  let renderPassDescriptor = view.currentRenderPassDescriptor else { return }
            
            updateSimParams()
            
            // Update camera transition if in progress
            if isTransitioning {
                updateCameraTransition()
            }
            
            // Handle continuous camera adjustment in auto mode
            let currentTime = CACurrentMediaTime()
            if settingsRef.isRunning && autoModeEnabled && (currentTime - lastCameraAdjustmentTime >= cameraAdjustmentInterval) {
                if !isTransitioning {
                    adjustCameraForOptimalView()
                    lastCameraAdjustmentTime = currentTime
                }
            }
            
            // Handle auto restart
            if autoModeEnabled {
                let intervalInSeconds = autoRestartInterval * 60
                
                if lastAutoRestartTime == 0 || (currentTime - lastAutoRestartTime) >= intervalInSeconds {
                    autoRestartSimulation()
                    lastAutoRestartTime = currentTime
                }
            }
            
            // Handle orbiting camera
            if isOrbiting {
                if orbitX {
                    cameraPitch += orbitSpeed * 0.01
                }
                
                if orbitY {
                    cameraYaw += orbitSpeed * 0.01
                }
                
                if orbitZ {
                    cameraRoll += orbitSpeed * 0.01
                }
            }
            
            // Handle simulation update
            if settingsRef.isRunning {
                let posInBuffer  = usingBufferA ? positionBufferA! : positionBufferB!
                let posOutBuffer = usingBufferA ? positionBufferB! : positionBufferA!
                if let commandBuffer = commandQueue.makeCommandBuffer() {
                    mpsSimulation.encode(commandBuffer: commandBuffer,
                                           posInBuffer: posInBuffer,
                                           velocityBuffer: velocityBuffer,
                                           posOutBuffer: posOutBuffer)
                    commandBuffer.commit()
                }
                usingBufferA.toggle()
            }
            
            // Render particles
            if let commandBuffer2 = commandQueue.makeCommandBuffer(),
               let renderEncoder = commandBuffer2.makeRenderCommandEncoder(descriptor: renderPassDescriptor) {
                renderEncoder.setRenderPipelineState(renderPipeline)
                let currentPosBuffer = usingBufferA ? positionBufferA! : positionBufferB!
                renderEncoder.setVertexBuffer(currentPosBuffer, offset: 0, index: 0)
                renderEncoder.setVertexBuffer(colorBuffer, offset: 0, index: 1)
                renderEncoder.setVertexBuffer(sizeBuffer, offset: 0, index: 2)
                var mvpMatrix = computeViewProjectionMatrix(aspect: Float(view.drawableSize.width / view.drawableSize.height))
                renderEncoder.setVertexBytes(&mvpMatrix, length: MemoryLayout<matrix_float4x4>.stride, index: 3)
                renderEncoder.setFragmentBuffer(paramsBuffer, offset: 0, index: 0)
                renderEncoder.drawPrimitives(type: .point, vertexStart: 0, vertexCount: settingsRef.particleCount)
                renderEncoder.endEncoding()
                commandBuffer2.present(drawable)
                commandBuffer2.commit()
            }
            
            // Calculate FPS
            let currentFrameTime = CACurrentMediaTime()
            frameCount += 1
            
            if lastFrameTime == 0 {
                lastFrameTime = currentFrameTime
            }
            
            let elapsed = currentFrameTime - lastFrameTime
            if elapsed >= 1.0 {
                let fps = Int(Double(frameCount) / elapsed)
                DispatchQueue.main.async {
                    self.currentFPS = fps
                }
                frameCount = 0
                lastFrameTime = currentFrameTime
            }
        }
        
        private func computeViewProjectionMatrix(aspect: Float) -> matrix_float4x4 {
            // Create rotation matrices for each axis
            let rotX = simd_float3x3(
                simd_float3(1, 0, 0),
                simd_float3(0, cos(cameraPitch), -sin(cameraPitch)),
                simd_float3(0, sin(cameraPitch), cos(cameraPitch))
            )
            
            let rotY = simd_float3x3(
                simd_float3(cos(cameraYaw), 0, sin(cameraYaw)),
                simd_float3(0, 1, 0),
                simd_float3(-sin(cameraYaw), 0, cos(cameraYaw))
            )
            
            let rotZ = simd_float3x3(
                simd_float3(cos(cameraRoll), -sin(cameraRoll), 0),
                simd_float3(sin(cameraRoll), cos(cameraRoll), 0),
                simd_float3(0, 0, 1)
            )
            
            // Start with the camera looking down the -Z axis
            let initialCameraDir = simd_float3(0, 0, 1)
            let initialUp = simd_float3(0, 1, 0)
            let initialRight = simd_float3(1, 0, 0)
            
            // Apply the rotations in sequence
            let combinedRot = rotZ * rotX * rotY
            
            // Transform the basis vectors
            let cameraDir = combinedRot * initialCameraDir
            let upVector = combinedRot * initialUp
            let rightVector = combinedRot * initialRight
            
            // Position the camera
            let cameraPos = cameraDir * cameraDistance
            
            // Create view matrix
            var view = matrix_float4x4(1.0)
            view.columns = (
                SIMD4<Float>(rightVector.x, upVector.x, cameraDir.x, 0),
                SIMD4<Float>(rightVector.y, upVector.y, cameraDir.y, 0),
                SIMD4<Float>(rightVector.z, upVector.z, cameraDir.z, 0),
                SIMD4<Float>(-dot(rightVector, cameraPos), -dot(upVector, cameraPos), -dot(cameraDir, cameraPos), 1)
            )
            
            // Create projection matrix
            let near: Float = 0.0001
            let far: Float = initialFarPlane
            let fov: Float = 60.0 * (.pi/180)
            let ys = 1 / tan(fov/2)
            let xs = ys / aspect
            let A = -far / (far - near)
            let B = -far * near / (far - near)
            
            var proj = matrix_float4x4(0.0)
            proj.columns = (
                SIMD4<Float>(xs, 0, 0, 0),
                SIMD4<Float>(0, ys, 0, 0),
                SIMD4<Float>(0, 0, A, -1),
                SIMD4<Float>(0, 0, B, 0)
            )
            
            return proj * view
        }
    }
