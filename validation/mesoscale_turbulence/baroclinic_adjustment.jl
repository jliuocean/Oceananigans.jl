using Printf
using Statistics
using GLMakie
using Random
using JLD2

GLMakie.inline!(false)

using Oceananigans
using Oceananigans.Units
using Oceananigans.Models.HydrostaticFreeSurfaceModels: fields
using Oceananigans.TurbulenceClosures: VerticallyImplicitTimeDiscretization

# Domain
Lx = 500kilometers  # east-west extent [m]
Ly = 1000kilometers # north-south extent [m]
Lz = 1kilometers    # depth [m]

Nx = 512
Ny = 1024
Nz = 64

movie_interval = 0.2day
stop_time = 80days
Δt₀ = 5minutes

grid = RectilinearGrid(topology = (Periodic, Bounded, Bounded), 
                       size = (Nx, Ny, Nz), 
                       x = (0, Lx),
                       y = (-Ly/2, Ly/2),
                       z = (-Lz, 0),
                       halo = (3, 3, 3))

coriolis = BetaPlane(latitude=-45)

Δx, Δy, Δz = Lx/Nx, Ly/Ny, Lz/Nz

𝒜 = Δz/Δx # Grid cell aspect ratio.

κh = 0.1    # [m² s⁻¹] horizontal diffusivity
νh = 0.1    # [m² s⁻¹] horizontal viscosity
κz = 𝒜 * κh # [m² s⁻¹] vertical diffusivity
νz = 𝒜 * νh # [m² s⁻¹] vertical viscosity

diffusive_closure = AnisotropicDiffusivity(νh = νh,
                                           νz = νz,
                                           κh = κh,
                                           κz = κz,
					                       time_discretization = VerticallyImplicitTimeDiscretization())

convective_adjustment = ConvectiveAdjustmentVerticalDiffusivity(convective_κz = 1.0,
                                                                convective_νz = 0.0)

#####
##### Model building
#####

@info "Building a model..."

closures = (diffusive_closure, convective_adjustment)

model = HydrostaticFreeSurfaceModel(architecture = GPU(),
                                    grid = grid,
                                    coriolis = coriolis,
                                    buoyancy = BuoyancyTracer(),
                                    closure = closures,
                                    tracers = (:b, :c),
                                    momentum_advection = WENO5(),
                                    tracer_advection = WENO5(),
                                    free_surface = ImplicitFreeSurface())

@info "Built $model."

#####
##### Initial conditions
#####

"""
Linear ramp from 0 to 1 between -Δy/2 and +Δy/2.

For example:

y < y₀           => ramp = 0
y₀ < y < y₀ + Δy => ramp = y / Δy
y > y₀ + Δy      => ramp = 1
"""
ramp(y, Δy) = min(max(0, y/Δy + 1/2), 1)

# Parameters
N² = 4e-6 # [s⁻²] buoyancy frequency / stratification
M² = 8e-8 # [s⁻²] horizontal buoyancy gradient

Δy = 50kilometers
Δc = 2Δy
Δb = Δy * M²
ϵb = 1e-2 * Δb # noise amplitude

bᵢ(x, y, z) = N² * z + Δb * ramp(y, Δy) + ϵb * randn()
cᵢ(x, y, z) = exp(-y^2 / 2Δc^2)

set!(model, b=bᵢ, c=cᵢ)

#####
##### Simulation building
#####

wall_clock = [time_ns()]

function print_progress(sim)
    @printf("[%05.2f%%] i: %d, t: %s, wall time: %s, max(u): (%6.8e, %6.8e, %6.8e) m/s, next Δt: %s\n",
            100 * (sim.model.clock.time / sim.stop_time),
            sim.model.clock.iteration,
            prettytime(sim.model.clock.time),
            prettytime(1e-9 * (time_ns() - wall_clock[1])),
            maximum(abs, sim.model.velocities.u),
            maximum(abs, sim.model.velocities.v),
            maximum(abs, sim.model.velocities.w),
            prettytime(sim.Δt.Δt))

    wall_clock[1] = time_ns()
    
    return nothing
end

wizard = TimeStepWizard(cfl=0.2, Δt=Δt₀, max_Δt=Δt₀)

simulation = Simulation(model, Δt=wizard, stop_time=stop_time, progress=print_progress, iteration_interval=100)

slicers = (west = FieldSlicer(i=1),
           east = FieldSlicer(i=grid.Nx),
           south = FieldSlicer(j=1),
           north = FieldSlicer(j=grid.Ny),
           bottom = FieldSlicer(k=1),
           top = FieldSlicer(k=grid.Nz))

for side in keys(slicers)
    field_slicer = slicers[side]

    simulation.output_writers[side] = JLD2OutputWriter(model, fields(model),
                                                       schedule = TimeInterval(movie_interval),
                                                       field_slicer = field_slicer,
                                                       prefix = "baroclinic_adj_$(side)_slice",
                                                       force = true)
end

simulation.output_writers[:fields] = JLD2OutputWriter(model, fields(model),
                                                      schedule = TimeInterval(10day),
                                                      field_slicer = nothing,
                                                      prefix = "baroclinic_adj_fields",
                                                      force = true)

B = AveragedField(model.tracers.b, dims=1)
C = AveragedField(model.tracers.c, dims=1)
U = AveragedField(model.velocities.u, dims=1)
V = AveragedField(model.velocities.v, dims=1)
W = AveragedField(model.velocities.w, dims=1)

simulation.output_writers[:zonal] = JLD2OutputWriter(model, (b=B, c=C, u=U, v=V, w=W),
                                                     schedule = TimeInterval(movie_interval),
                                                     prefix = "baroclinic_adj_zonal_average",
                                                     force = true)

@info "Running the simulation..."

run!(simulation, pickup=false)

@info "Simulation completed in " * prettytime(simulation.run_time)

#####
##### Visualize
#####

fig = Figure(resolution = (1400, 700))
ax_b = fig[1:5, 1] = LScene(fig)
ax_c = fig[1:5, 2] = LScene(fig)

# Extract surfaces on all 6 boundaries

iter = Node(0)
sides = keys(slicers)

zonal_file = jldopen("baroclinic_adj_zonal_average.jld2")
slice_files = NamedTuple(side => jldopen("baroclinic_adj_$(side)_slice.jld2") for side in sides)

# Build coordinates, rescaling the vertical coordinate
x, y, z = nodes((Center, Center, Center), grid)

zscale = 100
z = z .* zscale

zonal_slice_displacement = 1.35

#####
##### Plot buoyancy...
#####

b_slices = (
      west = @lift(Array(slice_files.west["timeseries/b/"   * string($iter)][1, :, :])),
      east = @lift(Array(slice_files.east["timeseries/b/"   * string($iter)][1, :, :])),
     south = @lift(Array(slice_files.south["timeseries/b/"  * string($iter)][:, 1, :])),
     north = @lift(Array(slice_files.north["timeseries/b/"  * string($iter)][:, 1, :])),
    bottom = @lift(Array(slice_files.bottom["timeseries/b/" * string($iter)][:, :, 1])),
       top = @lift(Array(slice_files.top["timeseries/b/"    * string($iter)][:, :, 1]))
)

clims_b = @lift extrema(slice_files.top["timeseries/b/" * string($iter)][:])
kwargs_b = (colorrange=clims_b, colormap=:balance, show_axis=false)

GLMakie.surface!(ax_b, y, z, b_slices.west;   transformation = (:yz, x[1]),   kwargs_b...)
GLMakie.surface!(ax_b, y, z, b_slices.east;   transformation = (:yz, x[end]), kwargs_b...)
GLMakie.surface!(ax_b, x, z, b_slices.south;  transformation = (:xz, y[1]),   kwargs_b...)
GLMakie.surface!(ax_b, x, z, b_slices.north;  transformation = (:xz, y[end]), kwargs_b...)
GLMakie.surface!(ax_b, x, y, b_slices.bottom; transformation = (:xy, z[1]),   kwargs_b...)
GLMakie.surface!(ax_b, x, y, b_slices.top;    transformation = (:xy, z[end]), kwargs_b...)

b_avg = @lift zonal_file["timeseries/b/" * string($iter)][1, :, :]
u_avg = @lift zonal_file["timeseries/u/" * string($iter)][1, :, :]

clims_u = @lift extrema(zonal_file["timeseries/u/" * string($iter)][1, :, :])

GLMakie.contour!(ax_b, y, z, b_avg; levels = 15, transformation = (:yz, zonal_slice_displacement * x[end]), show_axis=false)
GLMakie.surface!(ax_b, y, z, u_avg; transformation = (:yz, zonal_slice_displacement * x[end]), colorrange=clims_u, colormap=:balance)

rotate_cam!(ax_b.scene, (π/24, -π/6, 0))

#####
##### Plot tracer...
#####

c_slices = (
      west = @lift(Array(slice_files.west["timeseries/c/"   * string($iter)][1, :, :])),
      east = @lift(Array(slice_files.east["timeseries/c/"   * string($iter)][1, :, :])),
     south = @lift(Array(slice_files.south["timeseries/c/"  * string($iter)][:, 1, :])),
     north = @lift(Array(slice_files.north["timeseries/c/"  * string($iter)][:, 1, :])),
    bottom = @lift(Array(slice_files.bottom["timeseries/c/" * string($iter)][:, :, 1])),
       top = @lift(Array(slice_files.top["timeseries/c/"    * string($iter)][:, :, 1]))
)

clims_c = @lift extrema(slice_files.top["timeseries/c/" * string($iter)][:])
kwargs_c = (colorrange=clims_c, colormap=:deep, show_axis=false)

GLMakie.surface!(ax_c, y, z, c_slices.west;   transformation = (:yz, x[1]),   kwargs_c...)
GLMakie.surface!(ax_c, y, z, c_slices.east;   transformation = (:yz, x[end]), kwargs_c...)
GLMakie.surface!(ax_c, x, z, c_slices.south;  transformation = (:xz, y[1]),   kwargs_c...)
GLMakie.surface!(ax_c, x, z, c_slices.north;  transformation = (:xz, y[end]), kwargs_c...)
GLMakie.surface!(ax_c, x, y, c_slices.bottom; transformation = (:xy, z[1]),   kwargs_c...)
GLMakie.surface!(ax_c, x, y, c_slices.top;    transformation = (:xy, z[end]), kwargs_c...)

b_avg = @lift zonal_file["timeseries/b/" * string($iter)][1, :, :]
c_avg = @lift zonal_file["timeseries/c/" * string($iter)][1, :, :]

GLMakie.contour!(ax_c, y, z, b_avg; levels = 15, transformation = (:yz, zonal_slice_displacement * x[end]), show_axis=false)
GLMakie.surface!(ax_c, y, z, c_avg; transformation = (:yz, zonal_slice_displacement * x[end]), colorrange=clims_c, colormap=:deep)

rotate_cam!(ax_c.scene, (π/24, -π/6, 0))

#####
##### Make title and animate
#####

title = @lift(string("Buoyancy and zonally-averaged u at t = ",
                     prettytime(zonal_file["timeseries/t/" * string($iter)])))

fig[0, :] = Label(fig, title, textsize=30)


iterations = parse.(Int, keys(zonal_file["timeseries/t"]))

record(fig, "baroclinic_adjustment.mp4", iterations, framerate=8) do i
    @info "Plotting iteration $i of $(iterations[end])..."
    iter[] = i
end

display(fig)

for file in slice_files
    close(file)
end

close(zonal_file)

