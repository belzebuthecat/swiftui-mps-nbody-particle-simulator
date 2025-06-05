import simd
import Foundation

struct ParticleGenerator {
    static func generateParticles(
        type: SimulationSettings.SimulationType,
        count: Int,
        radius: Float,
        thickness: Float,
        initialSpeed: Float,
        initialCoreSpin: Float,
        minParticleSize: Float = 2.0,
        maxParticleSize: Float = 60.0,
        collisionVelocity: Float = 1.0,
        firstGalaxyRotation: simd_float3x3? = nil,
        secondGalaxyRotation: simd_float3x3? = nil,
        sameDirection: Bool = false,
        settings: SimulationSettings
    ) -> ([simd_float3], [simd_float3], [simd_float4], [Float]) {
        var positions = [simd_float3](repeating: .zero, count: count)
        var velocities = [simd_float3](repeating: .zero, count: count)
        var colors = [simd_float4](repeating: .zero, count: count)
        var sizes = [Float](repeating: 0.0, count: count)
        
        if settings.useRandomColors {
            settings.generateRandomColors()
        }
        
        generateParticleSizes(sizes: &sizes, count: count, minSize: minParticleSize, maxSize: maxParticleSize)
        
        switch type {
        case .universe:
            let R = max(radius, 1.0)
            for i in 0..<count {
                let u = Float.random(in: 0...1)
                let cosTheta = Float.random(in: -1...1)
                let sinTheta = sqrt(max(0, 1 - cosTheta * cosTheta))
                let phi = Float.random(in: 0..<2 * Float.pi)
                let r = R * cbrt(u)
                let x = r * sinTheta * cos(phi)
                let y = r * cosTheta * (Float.random(in: 0...1) < 0.5 ? 1 : -1)
                let z = r * sinTheta * sin(phi)
                positions[i] = simd_float3(x, y, z)
                let sizeFactor = sqrt(sizes[i] / maxParticleSize)
                let outwardDir = simd_normalize(simd_float3(x, y, z) + 1e-6)
                velocities[i] = outwardDir * initialSpeed * sizeFactor
            }
            for i in 0..<count {
                let speed = simd_length(velocities[i])
                let maxSpeed = initialSpeed * 1.5
                let t = min(speed / maxSpeed, 1.0)
                colors[i] = simd_float4(velocityToColor(t, settings), Float(settings.particleOpacity))
            }
            
        case .galaxy:
            let R = max(radius, 1.0)
            var maxSpeed: Float = 0
            for i in 0..<count {
                let t = Float(i) / Float(count)
                let armCount: Float = 6
                let armSeparation = (4.0 * Float.pi) / armCount
                let radiusFactor = sqrt(Float.random(in: 0..<100))
                let rr = radius * radiusFactor
                let spiralTightness: Float = 5.0
                let baseAngle = pow(rr, 0.15) * spiralTightness * 0.4
                let armOffset = (Float(i % Int(armCount))) * armSeparation
                let targetAngle = baseAngle + armOffset

                // distanza angolare dal centro braccio con offset esponenziale
                let deviation = Float.random(in: -100...100)
                let decay = exp(-rr / (radius * 0.8))
                let angle = targetAngle + deviation * decay * 0.5

                let x = rr * cos(angle)
                let z = rr * sin(angle)
                let y = thickness * 0.5 * Float.random(in: -1...1) * exp(-rr / radius)
                positions[i] = simd_float3(x, y, z)

                let sizeFactor = sqrt(minParticleSize / sizes[i])
                let vx = -sin(angle)
                let vz = cos(angle)
                var speed = initialSpeed * sqrt(rr / max(1, radius)) * sizeFactor
                let coreThreshold = radius * 0.3
                if rr < coreThreshold {
                    let extra = initialCoreSpin * (coreThreshold - rr) / coreThreshold
                    speed += extra
                }
                velocities[i] = simd_float3(vx * speed, 0, vz * speed)
                maxSpeed = max(maxSpeed, speed)
            }
            for i in 0..<count {
                let speed = simd_length(velocities[i])
                let t = min(speed / maxSpeed, 1.0)
                colors[i] = simd_float4(velocityToColor(t, settings), Float(settings.particleOpacity))
            }
            
        case .collision:
            let R = max(radius, 1.0)
            let halfCount = count / 2
            let baseCollisionSpeed = initialSpeed * 0.5
            let finalCollisionSpeed = baseCollisionSpeed * collisionVelocity
            let radiusScaleFactor = sqrt(R / 100.0)
            let scaledCollisionSpeed = finalCollisionSpeed * radiusScaleFactor
            let firstRotation = firstGalaxyRotation ?? createRandomRotationMatrix()
            let secondRotation = secondGalaxyRotation ?? createRandomRotationMatrix()
            var maxSpeedFirstGalaxy: Float = 0
            var maxSpeedSecondGalaxy: Float = 0
            for i in 0..<halfCount {
                let rr = sqrt(Float.random(in: 0...1)) * R
                let angle = Float.random(in: 0..<2 * Float.pi)
                let x_flat = rr * cos(angle)
                let z_flat = rr * sin(angle)
                let y_flat = thickness * 0.5 * Float.random(in: -1...1)
                var flatPos = simd_float3(x_flat, y_flat, z_flat)
                flatPos = matrix_multiply(firstRotation, flatPos)
                flatPos.x -= radius * 1.5
                positions[i] = flatPos
                let sizeFactor = sqrt(minParticleSize / sizes[i])
                var vx = -sin(angle)
                var vz = cos(angle)
                let vy: Float = 0.0
                var velVector = simd_float3(vx, vy, vz)
                velVector = matrix_multiply(firstRotation, velVector)
                var speed = initialSpeed * sqrt(rr / max(1, R)) * sizeFactor
                let coreThreshold = R * 0.3
                if rr < coreThreshold {
                    let extra = initialCoreSpin * (coreThreshold - rr) / coreThreshold
                    speed += extra
                }
                let finalVelocity = velVector * speed + simd_float3(scaledCollisionSpeed, 1.50, 1.50)
                velocities[i] = finalVelocity
                maxSpeedFirstGalaxy = max(maxSpeedFirstGalaxy, simd_length(finalVelocity))
            }
            for j in 0..<halfCount {
                let i = halfCount + j
                let rr = sqrt(Float.random(in: 0...1)) * R
                let angle = Float.random(in: 0..<2 * Float.pi)
                let x_flat = rr * cos(angle)
                let z_flat = rr * sin(angle)
                let y_flat = thickness * 0.5 * Float.random(in: -1...1)
                var flatPos = simd_float3(x_flat, y_flat, z_flat)
                flatPos = matrix_multiply(secondRotation, flatPos)
                flatPos.x += radius * 1.5
                positions[i] = flatPos
                let sizeFactor = sqrt(minParticleSize / sizes[i])
                var vx = sameDirection ? -sin(angle) : sin(angle)
                var vz = sameDirection ? cos(angle) : -cos(angle)
                let vy: Float = 0.0
                var velVector = simd_float3(vx, vy, vz)
                velVector = matrix_multiply(secondRotation, velVector)
                var speed = initialSpeed * sqrt(rr / max(1, R)) * sizeFactor
                let coreThreshold = R * 0.3
                if rr < coreThreshold {
                    let extra = initialCoreSpin * (coreThreshold - rr) / coreThreshold
                    speed += extra
                }
                let finalVelocity = velVector * speed + simd_float3(-scaledCollisionSpeed, -1.50, -1.50)
                velocities[i] = finalVelocity
                maxSpeedSecondGalaxy = max(maxSpeedSecondGalaxy, simd_length(finalVelocity))
            }
            for i in 0..<count {
                let speed = simd_length(velocities[i])
                let maxSpeed = i < halfCount ? maxSpeedFirstGalaxy : maxSpeedSecondGalaxy
                let t = min(speed / maxSpeed, 1.0)
                if i < halfCount {
                    colors[i] = simd_float4(velocityToColor(t, settings), Float(settings.particleOpacity))
                } else {
                    if settings.useRandomColors {
                        colors[i] = simd_float4(velocityToColorSecondGalaxy(t, settings), Float(settings.particleOpacity))
                    } else {
                        colors[i] = simd_float4(inverseVelocityToColor(t, settings), Float(settings.particleOpacity))
                    }
                }
            }
        }
        
        return (positions, velocities, colors, sizes)
    }
    
    private static func generateParticleSizes(sizes: inout [Float], count: Int, minSize: Float, maxSize: Float) {
        let sizeRange = maxSize - minSize
        let largeParticleCount = max(1, Int(Float(count) * 0.001))
        let regularParticleCount = count - largeParticleCount
        let largeSizeThreshold = minSize + sizeRange * 0.01
        for i in 0..<regularParticleCount {
            let t = pow(Float.random(in: 0...1), 2)
            let size = minSize + (largeSizeThreshold - minSize) * t
            sizes[i] = size
        }
        for i in regularParticleCount..<count {
            let t = Float.random(in: 0...1)
            let size = largeSizeThreshold + (maxSize - largeSizeThreshold) * pow(t, 0.33)
            sizes[i] = size
        }
        sizes.shuffle()
    }
    
    private static func velocityToColor(_ normalizedVelocity: Float, _ settings: SimulationSettings) -> SIMD3<Float> {
        let lowVelocityColor = settings.currentLowVelocityColor
        let highVelocityColor = settings.currentHighVelocityColor
        
        // Apply a slight curve to emphasize certain velocity ranges while maintaining smoothness
        let t = pow(normalizedVelocity, 1.2)
        
        // Simple linear interpolation between low and high velocity colors
        return mix(lowVelocityColor, highVelocityColor, t)
    }
    
    private static func velocityToColorSecondGalaxy(_ normalizedVelocity: Float, _ settings: SimulationSettings) -> SIMD3<Float> {
        let lowVelocityColor = settings.secondGalaxyLowVelocityColor
        let highVelocityColor = settings.secondGalaxyHighVelocityColor
        
        // Apply a slight curve to emphasize certain velocity ranges while maintaining smoothness
        let t = pow(normalizedVelocity, 1.2)
        
        // Simple linear interpolation between low and high velocity colors
        return mix(lowVelocityColor, highVelocityColor, t)
    }
    
    private static func inverseVelocityToColor(_ normalizedVelocity: Float, _ settings: SimulationSettings) -> SIMD3<Float> {
        let lowVelocityColor = SIMD3<Float>(1.0) - settings.currentLowVelocityColor
        let highVelocityColor = SIMD3<Float>(1.0) - settings.currentHighVelocityColor
        
        // Apply a slight curve to emphasize certain velocity ranges while maintaining smoothness
        let t = pow(normalizedVelocity, 1.2)
        
        // Simple linear interpolation between low and high velocity colors
        return mix(lowVelocityColor, highVelocityColor, t)
    }
    
    private static func mix(_ color1: SIMD3<Float>, _ color2: SIMD3<Float>, _ t: Float) -> SIMD3<Float> {
        return color1 * (1 - t) + color2 * t
    }
    
    static func createRandomRotationMatrix() -> simd_float3x3 {
        let angleX = Float.random(in: 0..<2 * Float.pi)
        let angleY = Float.random(in: 0..<2 * Float.pi)
        let angleZ = Float.random(in: 0..<2 * Float.pi)
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
        return rotX * rotY * rotZ
    }
}
