import SwiftUI

class SimulationSettings: ObservableObject {
    enum SimulationType: String, CaseIterable, Identifiable {
        case universe = "Universe"
        case galaxy = "Galaxy"
        case collision = "Collision"
        var id: Self { self }
    }
    @Published var simType: SimulationType = .collision
    @Published var isRunning: Bool = false
    @Published var particleCount: Int = 50000
    @Published var radius: Double = 10000.0
    @Published var thickness: Double = 1.0
    @Published var initialRotation: Double = 1.0
    @Published var smoothing: Double = 100
    @Published var interactionRate: Double = 0.2

    @Published var initialCoreSpin: Double = 0.5
    @Published var bloom: Double = 0.0
    @Published var colorMix: Double = 0.0
    @Published var particleOpacity: Double = 0.1 // New property for particle opacity
    
    // Flag for random color schemes
    @Published var useRandomColors: Bool = true
    
    // Store the current random colors when random mode is enabled
    // First galaxy colors
    var currentLowVelocityColor: SIMD3<Float> = SIMD3<Float>(0.012, 0.063, 0.988)
    var currentHighVelocityColor: SIMD3<Float> = SIMD3<Float>(1.0, 0.376, 0.188)
    
    // Second galaxy colors (only used in collision mode with random colors)
    var secondGalaxyLowVelocityColor: SIMD3<Float> = SIMD3<Float>(0.0, 0.7, 0.3)
    var secondGalaxyHighVelocityColor: SIMD3<Float> = SIMD3<Float>(1.0, 0.8, 0.0)
    
    // Particle size controls
    @Published var minParticleSize: Double = 5.0 // Default min particle size
    @Published var maxParticleSize: Double = 10.0 // Default max particle size
    
    // Gravitational and collision controls
    @Published var gravitationalForce: Double = 1.0
    @Published var collisionVelocity: Double = 0.10
    @Published var blackHoleGravityMultiplier: Double = 1.0 // Multiplier only for black hole interactions

    @Published var blackHoleEnabled: Bool = true
    @Published var blackHoleMass: Double = 10000.0
    @Published var blackHoleAccretionRadius: Double = 0.0
    @Published var blackHoleSpin: Double = 0.0 // New property for black hole spin (-1.0 to 1.0)

    @Published var secondBlackHoleEnabled: Bool = true
    @Published var secondBlackHoleMass: Double = 10000.0
    @Published var secondBlackHoleAccretionRadius: Double = 0.0
    @Published var secondBlackHoleSpin: Double = 0.0 // New property for second black hole spin (-1.0 to 1.0)
    
    // Method to generate new random colors
    func generateRandomColors() {
        if useRandomColors {
            // Generate random colors for the first galaxy
            currentLowVelocityColor = SIMD3<Float>(
                Float.random(in: 0...1),
                Float.random(in: 0...1),
                Float.random(in: 0...1)
            )
            
            currentHighVelocityColor = SIMD3<Float>(
                Float.random(in: 0...1),
                Float.random(in: 0...1),
                Float.random(in: 0...1)
            )
            
            // Generate different random colors for the second galaxy
            secondGalaxyLowVelocityColor = SIMD3<Float>(
                Float.random(in: 0...1),
                Float.random(in: 0...1),
                Float.random(in: 0...1)
            )
            
            secondGalaxyHighVelocityColor = SIMD3<Float>(
                Float.random(in: 0...1),
                Float.random(in: 0...1),
                Float.random(in: 0...1)
            )
        } else {
            // Reset to default colors
            currentLowVelocityColor = SIMD3<Float>(0.012, 0.063, 0.988)
            currentHighVelocityColor = SIMD3<Float>(1.0, 0.376, 0.188)
            
            // Default complementary colors for second galaxy
            secondGalaxyLowVelocityColor = SIMD3<Float>(0.0, 0.7, 0.3)
            secondGalaxyHighVelocityColor = SIMD3<Float>(1.0, 0.8, 0.0)
        }
    }
}
