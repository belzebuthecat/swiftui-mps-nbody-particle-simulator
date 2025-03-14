#include <metal_stdlib>
using namespace metal;

struct SimParams {
    float deltaTime;
    float gravitationalConstant;
    float smoothingLength;
    uint  particleCount;
    uint  interactionSkip;
    float bloom;
    float colorMix;
    uint  blackHoleEnabled;
    float blackHoleMass;
    float4 blackHolePosition;
    float blackHoleAccretionRadius;
    float blackHoleSpin;            // New parameter for black hole spin
    uint  secondBlackHoleEnabled;
    float secondBlackHoleMass;
    float4 secondBlackHolePosition;
    float secondBlackHoleAccretionRadius;
    float secondBlackHoleSpin;      // New parameter for second black hole spin
    float particleOpacity;
    float3 _padding;                // Padding for alignment
    float4 _extraPadding;           // Extra padding to ensure total size of 144 bytes
};

// Helper function to calculate spin effect (frame-dragging) of a black hole on a particle
float3 calculateSpinEffect(float3 particlePos, float3 blackHolePos, float spinValue, float smoothing) {
    // Return zero if no spin
    if (spinValue == 0.0) {
        return float3(0.0);
    }
    
    // Get vector from black hole to particle
    float3 relativePos = particlePos - blackHolePos;
    
    // Calculate distance squared with smoothing to avoid division by zero
    float distSqr = dot(relativePos, relativePos) + smoothing * smoothing;
    
    // Use inverse square law (same as gravity) for more gradual, natural falloff
    float distEffect = 1.0 / distSqr;
    
    // Reduce intensity significantly for more subtle effect
    // Scale factor reduced from 50000 to a smaller value
    float spinIntensity = spinValue * 5000.0 * distEffect;
    
    // Choose the rotation axis - typically perpendicular to the galaxy plane (y-axis)
    float3 spinAxis = float3(0.0, 1.0, 0.0);
    
    // Apply the cross product to get the tangential force
    return cross(spinAxis, relativePos) * spinIntensity;
}

kernel void computeParticles(device const float3 *posIn       [[ buffer(0) ]],
                             device float3       *velocities  [[ buffer(1) ]],
                             device float3       *posOut      [[ buffer(2) ]],
                             constant SimParams& params       [[ buffer(3) ]],
                             uint id                           [[ thread_position_in_grid ]]) {
    uint N = params.particleCount;
    if (id >= N) return;
    
    float3 position_i = posIn[id];
    float3 velocity_i = velocities[id];
    float3 acceleration = float3(0.0);
    float softening = params.smoothingLength;
    
    if (params.interactionSkip != 0) {
        float G = params.gravitationalConstant;
        for (uint j = 0; j < N; j += params.interactionSkip) {
            if (j == id) continue;
            float3 r = posIn[j] - position_i;
            float distSqr = dot(r, r) + softening * softening;
            if (distSqr == 0) continue;
            float invDist = rsqrt(distSqr);
            float invDist3 = invDist * invDist * invDist;
            acceleration += r * (G * invDist3);
        }
    }
    
    if (params.blackHoleEnabled == 1) {
        float3 r = params.blackHolePosition.xyz - position_i;
        float dist = length(r);
        if (dist < params.blackHoleAccretionRadius) {
            float repulsion = (params.blackHoleAccretionRadius - dist) * 10.0;
            acceleration += -normalize(r) * repulsion;
        } else {
            float distSqr = dot(r, r) + softening * softening;
            float invDist = rsqrt(distSqr);
            float invDist3 = invDist * invDist * invDist;
            acceleration += r * (params.gravitationalConstant * params.blackHoleMass * invDist3);
            
            // Apply spin effect (frame-dragging) from the first black hole
            acceleration += calculateSpinEffect(position_i, params.blackHolePosition.xyz,
                                               params.blackHoleSpin, softening);
        }
    }
    
    if (params.secondBlackHoleEnabled == 1) {
        float3 r = params.secondBlackHolePosition.xyz - position_i;
        float dist = length(r);
        if (dist < params.secondBlackHoleAccretionRadius) {
            float repulsion = (params.secondBlackHoleAccretionRadius - dist) * 10.0;
            acceleration += -normalize(r) * repulsion;
        } else {
            float distSqr = dot(r, r) + softening * softening;
            float invDist = rsqrt(distSqr);
            float invDist3 = invDist * invDist * invDist;
            acceleration += r * (params.gravitationalConstant * params.secondBlackHoleMass * invDist3);
            
            // Apply spin effect (frame-dragging) from the second black hole
            acceleration += calculateSpinEffect(position_i, params.secondBlackHolePosition.xyz,
                                               params.secondBlackHoleSpin, softening);
        }
    }
    
    velocity_i += acceleration * params.deltaTime;
    float3 newPos = position_i + velocity_i * params.deltaTime;
    velocities[id] = velocity_i;
    posOut[id] = newPos;
}

struct VertexOut {
    float4 position [[ position ]];
    float4 color    [[ user(locn0) ]];
    float  pointSize [[ point_size ]];
    float  originalSize [[ user(locn1) ]]; // Store the original size for the fragment shader
    float  distanceFactor [[ user(locn2) ]]; // Store the distance factor for adaptive bloom
    float  viewDistance [[ user(locn3) ]]; // Store view distance for fading
};

vertex VertexOut particleVertexShader(uint vertexId [[ vertex_id ]],
                                      const device float3 *positions [[ buffer(0) ]],
                                      const device float4 *colors    [[ buffer(1) ]],
                                      const device float *sizes      [[ buffer(2) ]],
                                      constant float4x4 &mvpMatrix   [[ buffer(3) ]]) {
    VertexOut out;
    float3 worldPos = positions[vertexId];
    float4 pos4 = float4(worldPos, 1.0);
    out.position = mvpMatrix * pos4;
    out.color = colors[vertexId];
    
    // Use the custom size for each particle (as set by the user)
    float particleSize = sizes[vertexId];
    out.originalSize = particleSize; // Store original size
    
    // Calculate absolute distance from camera for distance-based fading
    float viewDistance = abs(out.position.z);
    out.viewDistance = viewDistance;
    
    // Scale point size based on distance from camera (in projection space)
    float distanceScale = 1.0;
    if (viewDistance > 1.0) {
        // Logarithmic scaling with distance but gentler to preserve user sizing
        distanceScale = max(1.0, log2(viewDistance) * 0.35); // Reduced factor for less aggressive scaling
    }
    
    out.distanceFactor = distanceScale; // Store the distance factor
    
    // Apply the user's size directly with distance scaling
    out.pointSize = particleSize * distanceScale;
    
    return out;
}

// Fragment shader for rendering round particles with distance fading and extremely minimal overlap intensity
fragment half4 particleFragmentShader(VertexOut in [[ stage_in ]],
                                      float2 pointCoord [[ point_coord ]],
                                      constant SimParams& params [[ buffer(0) ]]) {
    // Calculate distance from center of point sprite
    float2 centerOffset = pointCoord - float2(0.5, 0.5);
    float distFromCenter = length(centerOffset) * 2.0;
    
    // Discard fragment if outside of circle radius
    if (distFromCenter > 1.0) {
        discard_fragment();
    }
    
    // Sharper edge falloff to make particles more distinct
    float edgeSmoothness = 0.9; // Higher value means harder edges
    float alpha = 1.0;// - smoothstep(edgeSmoothness, 1.0, distFromCenter);
    
    // Apply distance-based fading ONLY for far distances
    float distanceFade = 1.0;
    if (in.viewDistance > 2000.0) {
        // Gradually fade particles at extreme distances
        distanceFade = max(0.3, 1.0 - (in.viewDistance - 2000.0) / 8000.0);
    }
    // No fading for close particles - they stay at full intensity
    
    // Apply a reduced radial gradient for less pronounced 3D effect
    float brightnessFactor = 0;//2.0 - (distFromCenter * distFromCenter) * 0.2;
    
    // Scale down the bloom effect and intensity dramatically
    float bloomScale = 0.25; // Significant reduction in overall bloom
    float adaptiveBloom = params.bloom * bloomScale;
    
    // Adjust bloom based on distance
    adaptiveBloom *= distanceFade;
    
    // Increase bloom slightly when zoomed in to enhance visibility
   // if (in.viewDistance < 100.0) {
   //     adaptiveBloom *= 1.3; // Boost bloom when close instead of fading
//    }
    
    // Size-based bloom factor
   // float sizeBloomFactor = clamp(in.originalSize / 100.0, 0.1, 0.8);
   // adaptiveBloom *= sizeBloomFactor;
    
    // Lower brightness floor to ensure particles are visible but not overwhelming
    float minBrightness = 1.0; // Slightly increased for better close-up visibility
    
    // Reduce color mixing to preserve original colors better
    float reducedColorMix = params.colorMix * 0.8;
    float4 baseColor = in.color;
    
    // Apply a color intensity reduction to prevent oversaturation
    //baseColor = baseColor * 0.5;
    
    // Apply color mix and adaptive bloom with reduced intensity
    float4 mixed = mix(baseColor, float4(1.0, 1.0, 1.0, 1.0) * 0.6, reducedColorMix);
    float4 final = mixed * max(minBrightness, brightnessFactor);
    
    // Apply a stronger gamma correction to increase contrast between particles
    final = pow(final, float4(1.3));
    
    // Calculate alpha with distance fading
    float distanceAdjustedAlpha = alpha;// * distanceFade;
    
    // Calculate final alpha - EXTREMELY reduced for minimal additive blending (just 1%)
    // This makes overlapping particles contribute only 1% of their color to the result
    float finalAlpha = 0.25;//clamp(distanceAdjustedAlpha * 0.01, 0.0, 0.0);
    
    // Output color with adjusted alpha for extremely minimal overlap intensity
    return half4(final.r, final.g, final.b, finalAlpha);
}
