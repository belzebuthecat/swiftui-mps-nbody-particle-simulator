# SwiftUI MPS NBody Particle Simulator

SwiftUI MPS NBody Particle Simulator is a powerful MacOS application for simulating galaxies, universe expansion, and galactic collisions using GPU-accelerated particle simulations with Metal Performance Shaders (MPS). The application renders thousands of particles in real-time, creating stunning visualizations of cosmic phenomena while allowing extensive user customization.

## Features

### Simulation Types
- **Universe Mode**: Simulate an expanding universe with particles moving outward from a central point
- **Galaxy Mode**: Create rotating spiral galaxies with customizable parameters
- **Collision Mode**: Simulate galactic collisions with realistic gravitational interactions

### Black Hole Physics
- **Realistic Black Holes**: Include central supermassive black holes in simulations
- **Frame-Dragging Effect**: Simulate relativistic frame-dragging (Lense-Thirring effect) with black hole spin
- **Binary Black Holes**: Create binary black hole systems in collision simulations with customizable masses
- **Interactive Gravitational Forces**: Control the gravitational interaction between black holes

### Particle System
- **High Performance**: Render up to 100,000 particles with real-time physics
- **Variable Particle Sizing**: Configure minimum and maximum particle sizes for visual diversity
- **Dynamic Coloring**: Color particles based on velocity with customizable color schemes
- **Random Color Generation**: Create random color schemes for unique visualizations

### Camera Controls
- **Interactive Camera**: Pan, orbit, and zoom to explore simulations from any angle
- **Automatic Camera**: Enable auto-orbit mode with customizable axes and speed
- **Auto-Zoom**: Automatic camera transitions to keep all particles in frame

### Collision Configurations
- **Predefined Orientations**: Choose from various predefined galactic collision orientations
- **Random Orientations**: Generate random collision configurations
- **Velocity Control**: Adjust collision velocity for different interaction scenarios
- **Opposing/Same Direction Spins**: Configure galaxies to rotate in same or opposite directions

## System Requirements

- Mac with Metal-compatible GPU

## Build Instructions

### Prerequisites
- Xcode 12.0 or newer
- Swift 5.3 or newer

### Steps to Build

1. Clone the repository:
```bash
git clone https://github.com/dlnetworks/swiftui-mps-nbody-particle-simulator.git
cd swiftui-mps-nbody-particle-simulator
```

2. Open the project in Xcode:
```bash
open swiftui-mps-nbody-particle-simulator.xcodeproj
```

3. Select your target device (your Mac)

4. Build the project (⌘+B) or Run (⌘+R)

## Usage Instructions

### Basic Controls
- **Mouse Drag**: Rotate camera view
- **Scroll Wheel**: Zoom in/out
- **Hide/Show Controls**: Click the hamburger menu (≡) in the top-left corner

### Keyboard Shortcuts
- **R**: Reset simulation
- **C**: Generate new random colors (when "Use Random Colors" is enabled)

### Simulation Settings

#### General Settings
- **Type**: Choose between Universe, Galaxy, or Collision simulation modes
- **Start/Pause Simulation**: Control simulation playback
- **Restart**: Reset to initial conditions
- **Auto Mode**: Enable automatic simulation restarts at specified intervals
- **Camera Orbit**: Enable automatic camera rotation around the simulation

#### Physics Parameters
- **Gravitational Force**: Control the strength of gravity
- **Number of Particles**: Adjust particle count (1,000 to 100,000)
- **Particle Size Range**: Set minimum and maximum particle sizes
- **Galaxy Radius**: Control the size of the galaxy
- **Disk Thickness**: Adjust the thickness of the galactic disk
- **Initial Rotation**: Set the initial rotational velocity
- **Initial Core Spin**: Control the central region's rotation speed
- **Smoothing Length**: Adjust gravitational smoothing (prevents numerical instabilities)
- **Interaction Rate**: Control how many particles interact (affects performance)

#### Black Hole Settings
- **Black Hole Enabled**: Toggle central black hole
- **Black Hole Mass**: Adjust the mass of the central black hole
- **Black Hole Spin**: Set black hole spin from counter-clockwise to clockwise
- **Second Black Hole**: Enable secondary black hole (collision mode only)
- **Black Hole Interaction Gravity**: Adjust gravitational interaction between black holes

#### Visual Settings
- **Use Random Colors**: Toggle random color generation
- **New Colors**: Generate a new random color scheme

## Tips for Best Results

1. **Performance Optimization**:
   - For smoother performance, reduce particle count or interaction rate on older hardware
   - The "Interaction Rate" slider significantly affects performance - lower values improve framerate

2. **Creating Realistic Galaxies**:
   - Increase "Initial Core Spin" for a more pronounced galactic bulge
   - Set "Disk Thickness" to 1-5% of galaxy radius for realistic spiral galaxies
   - Enable black hole with mass proportional to galaxy size

3. **Spectacular Collisions**:
   - Enable both black holes with higher masses
   - Set "Collision Velocity" between 0.05-0.20 for more dramatic interactions
   - Try different auto-restart intervals to see various collision orientations

4. **Visualization Tips**:
   - Use random colors for more visually distinct galaxy components
   - Enable camera orbit on multiple axes for cinematic views

## Troubleshooting

- **Low Framerate**: Reduce particle count, disable black holes, or lower interaction rate
- **Particles Moving Too Fast**: Decrease gravitational force or initial rotation values
- **Crash on Startup**: Ensure your Mac has a Metal-compatible GPU and meets system requirements
- **Visual Glitches**: Reset the simulation or restart the application

## Acknowledgements

- 100% of this code was generated using ChatGPT and ClaudeAI. Please direct any bug reports
  or problems to either one of them.
- Mainly based on https://github.com/N0rvel/galaxy_sim
