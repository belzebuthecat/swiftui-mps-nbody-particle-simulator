import MetalPerformanceShaders

class MPSParticleSimulation: MPSKernel {
    
public var blackHoleJustIngested: Bool = false
public var hasRecentlyAccretedParticle: Bool {
    return blackHoleJustIngested
}
    
    var pipelineState: MTLComputePipelineState
    var paramsBuffer: MTLBuffer
    
    // Add variables to track black hole positions and velocities
    var blackHolePosition: simd_float3 = .zero
    var blackHoleVelocity: simd_float3 = .zero
    var secondBlackHolePosition: simd_float3 = .zero
    var secondBlackHoleVelocity: simd_float3 = .zero
    
    // Add variables for black hole spin
    var blackHoleSpin: Float = 0.0
    var secondBlackHoleSpin: Float = 0.0
    
    // Make rotation matrices public so they can be accessed by SimulationRenderer
    var firstGalaxyRotation: simd_float3x3 = simd_float3x3(1.0)
    var secondGalaxyRotation: simd_float3x3 = simd_float3x3(1.0)
    
    // Add a variable to track elapsed time
    private var accumulatedTime: Float = 0.0
    
    // Track black hole properties
    private var blackHoleMass: Float = 0.0
    private var secondBlackHoleMass: Float = 0.0
    private var blackHoleGravityMultiplier: Float = 1.0
    private var bothBlackHolesEnabled: Bool = false
    
    // Track which predefined orientation to use next time
    private static var useRandom: Bool = true
    private static var predefinedIndex: Int = 0
    
    // Flag to track if galaxies should spin in the same direction
    private var sameDirectionFlag: Bool = false
    
    // Debugging info to print in console
    private var currentOrientationName: String = "random"
    
    // Public property to check if galaxies spin in the same direction
    var galaxiesSpinInSameDirection: Bool {
        return sameDirectionFlag
    }
    
    // Define orientation types
    enum GalaxyOrientation: Int, CaseIterable {
        case edgeOnParallelOppositeSpins = 0
        case edgeOnParallelSameSpins = 1
        case edgeOnPerpendicularSpins = 2
        case edgeOn45Degrees = 3
        
        static var count: Int { return 4 } // 4 predefined orientations
        
        var name: String {
            switch self {
            case .edgeOnParallelOppositeSpins: return "Edge-On Parallel (Opposite Spins)"
            case .edgeOnParallelSameSpins: return "Edge-On Parallel (Same Spins)"
            case .edgeOnPerpendicularSpins: return "Edge-On Perpendicular"
            case .edgeOn45Degrees: return "Edge-On 45 Degrees"
            }
        }
    }

    init(device: MTLDevice, paramsBuffer: MTLBuffer) {
        self.paramsBuffer = paramsBuffer
        let library = device.makeDefaultLibrary()!
        guard let function = library.makeFunction(name: "computeParticles") else {
            fatalError("Could not find computeParticles function in library")
        }
        do {
            pipelineState = try device.makeComputePipelineState(function: function)
        } catch {
            fatalError("Could not create compute pipeline state: \(error)")
        }
        super.init(device: device)
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    // Method to set galaxy rotation matrices
    func setGalaxyRotations(first: simd_float3x3, second: simd_float3x3) {
        firstGalaxyRotation = first
        secondGalaxyRotation = second
    }
    
    // Method to create a random rotation matrix
    private func createRandomRotationMatrix() -> simd_float3x3 {
        // Generate random rotation angles
        let angleX = Float.random(in: 0..<2 * Float.pi)
        let angleY = Float.random(in: 0..<2 * Float.pi)
        let angleZ = Float.random(in: 0..<2 * Float.pi)
        
        // Create rotation matrices for each axis
        let rotX = simd_float3x3(
            simd_float3(1, 0, 0),
            simd_float3(0, cos(angleX), -sin(angleX)),
            simd_float3(0, sin(angleX), cos(angleX))
        )
        
        let rotY = simd_float3x3(
            simd_float3(cos(angleY), 0, sin(angleY)),
            simd_float3(0, 1, 0),
            simd_float3(-sin(angleY), 0, cos(angleY))
        )
        
        let rotZ = simd_float3x3(
            simd_float3(cos(angleZ), -sin(angleZ), 0),
            simd_float3(sin(angleZ), cos(angleZ), 0),
            simd_float3(0, 0, 1)
        )
        
        // Combine rotations
        return rotX * rotY * rotZ
    }
    
    // Helper method to create a rotation matrix for a specific axis with a specific angle
    private func createRotationMatrix(axis: String, angle: Float) -> simd_float3x3 {
        switch axis {
        case "x":
            return simd_float3x3(
                simd_float3(1, 0, 0),
                simd_float3(0, cos(angle), -sin(angle)),
                simd_float3(0, sin(angle), cos(angle))
            )
        case "y":
            return simd_float3x3(
                simd_float3(cos(angle), 0, sin(angle)),
                simd_float3(0, 1, 0),
                simd_float3(-sin(angle), 0, cos(angle))
            )
        case "z":
            return simd_float3x3(
                simd_float3(cos(angle), -sin(angle), 0),
                simd_float3(sin(angle), cos(angle), 0),
                simd_float3(0, 0, 1)
            )
        default:
            return simd_float3x3(1.0) // Identity matrix as fallback
        }
    }
    
    // Create predefined orientations
    private func getPredefinedOrientation(index: Int) -> (simd_float3x3, simd_float3x3, Bool) {
        // Half PI for 90-degree rotations
        let halfPi = Float.pi / 2
        // Quarter PI for 45-degree rotations
        let quarterPi = Float.pi / 4
        
        // Safely get the orientation using the index
        guard let orientation = GalaxyOrientation(rawValue: index) else {
            return (createRandomRotationMatrix(), createRandomRotationMatrix(), false)
        }
        
        var first = simd_float3x3(1.0)
        var second = simd_float3x3(1.0)
        var sameDirection = false
        
        // Save the orientation name for debugging
        currentOrientationName = orientation.name
        
        switch orientation {
        case .edgeOnParallelOppositeSpins:
            // Both galaxies edge-on, vertically aligned, flat sides facing each other
            // We need to rotate around Z-axis by 90 degrees to view them edge-on from the camera
            first = createRotationMatrix(axis: "z", angle: halfPi)
            second = createRotationMatrix(axis: "z", angle: halfPi)
            sameDirection = false
            
        case .edgeOnParallelSameSpins:
            // Same as above but with same spin direction
            first = createRotationMatrix(axis: "z", angle: halfPi)
            // For the second galaxy, rotate 90 degrees around Z, then 180 around Y to flip spin direction
            second = createRotationMatrix(axis: "z", angle: halfPi) * createRotationMatrix(axis: "y", angle: Float.pi)
            sameDirection = true
            
        case .edgeOnPerpendicularSpins:
            // First galaxy edge-on vertical (rotated around Z)
            first = createRotationMatrix(axis: "z", angle: halfPi)
            // Second galaxy edge-on horizontal (rotated around X)
            second = createRotationMatrix(axis: "x", angle: halfPi)
            sameDirection = false
            
        case .edgeOn45Degrees:
            // First galaxy rotated 45 degrees
            first = createRotationMatrix(axis: "z", angle: quarterPi)
            // Second galaxy rotated 135 degrees (45 + 90)
            second = createRotationMatrix(axis: "z", angle: quarterPi + halfPi)
            sameDirection = false
        }
        
        return (first, second, sameDirection)
    }
    
    // Method to get the next orientation - alternating between random and predefined
    private func getNextOrientations() -> (simd_float3x3, simd_float3x3, Bool) {
        if MPSParticleSimulation.useRandom {
            // Switch to predefined for next time
            MPSParticleSimulation.useRandom = false
            // Set debug name
            currentOrientationName = "random"
            // Return random orientation
            return (createRandomRotationMatrix(), createRandomRotationMatrix(), false)
        } else {
            // Switch to random for next time
            MPSParticleSimulation.useRandom = true
            
            // Get a predefined orientation
            let result = getPredefinedOrientation(index: MPSParticleSimulation.predefinedIndex)
            
            // Increment predefined index for next time
            MPSParticleSimulation.predefinedIndex = (MPSParticleSimulation.predefinedIndex + 1) % GalaxyOrientation.count
            
            return result
        }
    }
    
    // Method to set black hole properties
    func setBlackHoleProperties(
        firstEnabled: Bool,
        firstMass: Float,
        firstSpin: Float,
        secondEnabled: Bool,
        secondMass: Float,
        secondSpin: Float,
        gravityMultiplier: Float
    ) {
        blackHoleMass = firstMass
        blackHoleSpin = firstSpin
        secondBlackHoleMass = secondMass
        secondBlackHoleSpin = secondSpin
        blackHoleGravityMultiplier = gravityMultiplier
        bothBlackHolesEnabled = firstEnabled && secondEnabled
        
        // Update the params buffer with new spin values
        updateParamsBuffer()
    }
    
    // Method to initialize black hole initial positions and velocities
    func initializeBlackHoles(
        simType: SimulationSettings.SimulationType,
        radius: Float,
        initialSpeed: Float,
        collisionVelocity: Float = 1.0
    ) {
        if simType == .collision {
            // Get the next orientation - alternating between random and predefined
            let (firstRot, secondRot, sameDirection) = getNextOrientations()
            
            // Set the rotation matrices
            firstGalaxyRotation = firstRot
            secondGalaxyRotation = secondRot
            sameDirectionFlag = sameDirection
            
            // Print what orientation we're using (for debugging)
            print("Using orientation: \(currentOrientationName)")
            
            // Calculate collision velocity based on user setting
            // collisionVelocity parameter is a multiplier
            let baseCollisionSpeed = initialSpeed * 0.5
            let finalCollisionSpeed = baseCollisionSpeed * collisionVelocity
            
            // Scale with radius for larger galaxies to have proportional collision speed
            let radiusScaleFactor = sqrt(radius / 100.0)
            let scaledCollisionSpeed = finalCollisionSpeed * radiusScaleFactor
            
            // First black hole - left galaxy
            let basePosition = simd_float3(0, 0, 0)
            let rotatedPosition = matrix_multiply(firstGalaxyRotation, basePosition)
            blackHolePosition = simd_float3(rotatedPosition.x - radius * 1.5, rotatedPosition.y, rotatedPosition.z)
            
            // The velocity should be aligned with the galaxy's motion but towards the collision
            blackHoleVelocity = simd_float3(scaledCollisionSpeed, 1.50, 1.50)
            
            // Second black hole - right galaxy
            let basePosition2 = simd_float3(0, 0, 0)
            let rotatedPosition2 = matrix_multiply(secondGalaxyRotation, basePosition2)
            secondBlackHolePosition = simd_float3(rotatedPosition2.x + radius * 1.5, rotatedPosition2.y, rotatedPosition2.z)
            
            // The velocity should be aligned with the galaxy's motion but towards the collision
            secondBlackHoleVelocity = simd_float3(-scaledCollisionSpeed, -1.50, -1.50)
        } else if simType == .galaxy {
            // Single galaxy - black hole at center
            blackHolePosition = simd_float3(0, 0, 0)
            blackHoleVelocity = simd_float3(0, 0, 0)
            secondBlackHolePosition = simd_float3(0, 0, 0)
            secondBlackHoleVelocity = simd_float3(0, 0, 0)
            
            // Reset rotations
            firstGalaxyRotation = simd_float3x3(1.0)
            secondGalaxyRotation = simd_float3x3(1.0)
            sameDirectionFlag = false
        } else {
            // Universe - black hole at center
            blackHolePosition = simd_float3(0, 0, 0)
            blackHoleVelocity = simd_float3(0, 0, 0)
            secondBlackHolePosition = simd_float3(0, 0, 0)
            secondBlackHoleVelocity = simd_float3(0, 0, 0)
            
            // Reset rotations
            firstGalaxyRotation = simd_float3x3(1.0)
            secondGalaxyRotation = simd_float3x3(1.0)
            sameDirectionFlag = false
        }
    }
    
    // Calculate the angular velocity/drag effect of a spinning black hole on a particle
    private func calculateSpinEffect(position: simd_float3, blackHolePos: simd_float3, spinValue: Float) -> simd_float3 {
        // Return zero if no spin
        if spinValue == 0 {
            return .zero
        }
        
        // Get vector from black hole to particle
        let relativePos = position - blackHolePos
        
        // Calculate distance squared with a small epsilon to avoid division by zero
        let distSqr = simd_dot(relativePos, relativePos) + 0.0001
        
        // Use inverse square law for more gradual falloff
        let distEffect = 1.0 / distSqr
        
        // Reduce intensity for more subtle effect
        let spinIntensity = spinValue * 5000.0 * distEffect
        
        // Choose the rotation axis - typically perpendicular to the galaxy plane
        let spinAxis = simd_float3(0, 1, 0)
        
        // Apply the cross product to get the tangential force
        return simd_cross(spinAxis, relativePos) * spinIntensity
    }
    
    // New encode method: binds posIn, velocity, posOut, and params.
    func encode(commandBuffer: MTLCommandBuffer, posInBuffer: MTLBuffer, velocityBuffer: MTLBuffer, posOutBuffer: MTLBuffer) {
        guard let encoder = commandBuffer.makeComputeCommandEncoder() else { return }
        encoder.setComputePipelineState(pipelineState)
        encoder.setBuffer(posInBuffer, offset: 0, index: 0)
        encoder.setBuffer(velocityBuffer, offset: 0, index: 1)
        encoder.setBuffer(posOutBuffer, offset: 0, index: 2)
        encoder.setBuffer(paramsBuffer, offset: 0, index: 3)
        
        // Update black hole positions based on their velocities and gravity between them
        updateBlackHolePositions()
        
        // Update the black hole positions in the params buffer
        updateParamsBuffer()
        
        let count = posInBuffer.length / MemoryLayout<simd_float3>.stride
        let threadsPerGroup = MTLSize(width: 256, height: 1, depth: 1)
        let groupCount = MTLSize(width: (count + 255) / 256, height: 1, depth: 1)
        encoder.dispatchThreadgroups(groupCount, threadsPerThreadgroup: threadsPerGroup)
        encoder.endEncoding()
    }
    
    // Update black hole positions based on their velocities and gravity between them
    private func updateBlackHolePositions() {
        // Get deltaTime from the params buffer
        let params = paramsBuffer.contents().bindMemory(to: SimulationRenderer.SimParams.self, capacity: 1)
        let deltaTime = params.pointee.deltaTime
        let G = params.pointee.gravitationalConstant
        
        // Accumulate time
        accumulatedTime += deltaTime
        
        // Only calculate black hole gravity interaction if both are enabled
        if bothBlackHolesEnabled {
            // Calculate the gravitational force between the black holes
            let r = secondBlackHolePosition - blackHolePosition
            let distSqr = simd_dot(r, r) + params.pointee.smoothingLength * params.pointee.smoothingLength
            
            if distSqr > 0.001 { // Avoid numerical issues when too close
                let invDist = 1.0 / sqrt(distSqr)
                let invDist3 = invDist * invDist * invDist
                
                // Apply gravitational constant and black hole gravity multiplier
                let forceMagnitude = G * blackHoleGravityMultiplier
                
                // Calculate acceleration for first black hole
                let accel1 = r * (forceMagnitude * secondBlackHoleMass * invDist3)
                blackHoleVelocity += accel1 * deltaTime
                
                // Calculate acceleration for second black hole (equal and opposite)
                let accel2 = -r * (forceMagnitude * blackHoleMass * invDist3)
                secondBlackHoleVelocity += accel2 * deltaTime
                
                // Add spin effects between black holes
                // Calculate the spin effect from first black hole on second black hole
                let spinEffect1to2 = calculateSpinEffect(
                    position: secondBlackHolePosition,
                    blackHolePos: blackHolePosition,
                    spinValue: blackHoleSpin
                )
                
                // Calculate the spin effect from second black hole on first black hole
                let spinEffect2to1 = calculateSpinEffect(
                    position: blackHolePosition,
                    blackHolePos: secondBlackHolePosition,
                    spinValue: secondBlackHoleSpin
                )
                
                // Apply the spin effects to the velocities
                blackHoleVelocity += spinEffect2to1 * deltaTime
                secondBlackHoleVelocity += spinEffect1to2 * deltaTime
            }
        }
        
        // Update black hole positions
        blackHolePosition += blackHoleVelocity * deltaTime
        secondBlackHolePosition += secondBlackHoleVelocity * deltaTime
    }
    
    // Update the black hole positions in the params buffer
    private func updateParamsBuffer() {
        let params = paramsBuffer.contents().bindMemory(to: SimulationRenderer.SimParams.self, capacity: 1)
        
        // Update first black hole position
        params.pointee.blackHolePosition = simd_float4(blackHolePosition.x,
                                                      blackHolePosition.y,
                                                      blackHolePosition.z, 0)
        
        // Update second black hole position
        params.pointee.secondBlackHolePosition = simd_float4(secondBlackHolePosition.x,
                                                            secondBlackHolePosition.y,
                                                            secondBlackHolePosition.z, 0)
        
        // Update black hole spin values
        params.pointee.blackHoleSpin = blackHoleSpin
        params.pointee.secondBlackHoleSpin = secondBlackHoleSpin
    }
}
