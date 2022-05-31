import Oceananigans.TimeSteppers: calculate_tendencies!

using Oceananigans: fields
using Oceananigans.Utils: work_layout
using Oceananigans.Models: calculate_boundary_tendency_contributions!
using Oceananigans.Grids: XBoundedGrid, YBoundedGrid, ZBoundedGrid

"""
    calculate_tendencies!(model::NonhydrostaticModel)

Calculate the interior and boundary contributions to tendency terms without the
contribution from non-hydrostatic pressure.
"""
function calculate_tendencies!(model::NonhydrostaticModel)

    # Note:
    #
    # "tendencies" is a NamedTuple of OffsetArrays corresponding to the tendency data for use
    # in GPU computations.
    #
    # "model.timestepper.Gⁿ" is a NamedTuple of Fields, whose data also corresponds to
    # tendency data.

    # Calculate contributions to momentum and tracer tendencies from fluxes and volume terms in the
    # interior of the domain
    calculate_interior_tendency_contributions!(model)
                                               
    # Calculate contributions to momentum and tracer tendencies from user-prescribed fluxes across the
    # boundaries of the domain
    calculate_boundary_tendency_contributions!(model)

    return nothing
end

""" Store previous value of the source term and calculate current source term. """
function calculate_interior_tendency_contributions!(model)

    tendencies           = model.timestepper.Gⁿ
    arch                 = model.architecture
    grid                 = model.grid
    advection            = model.advection
    coriolis             = model.coriolis
    buoyancy             = model.buoyancy
    stokes_drift         = model.stokes_drift
    closure              = model.closure
    background_fields    = model.background_fields
    velocities           = model.velocities
    tracers              = model.tracers
    hydrostatic_pressure = model.pressures.pHY′
    diffusivities        = model.diffusivity_fields
    forcings             = model.forcing
    clock                = model.clock
    u_immersed_bc        = velocities.u.boundary_conditions.immersed
    v_immersed_bc        = velocities.v.boundary_conditions.immersed
    w_immersed_bc        = velocities.w.boundary_conditions.immersed

    workgroup, worksize = work_layout(grid, :xyz)

    calculate_Gu_kernel! = calculate_Gu!(device(arch), workgroup, worksize)
    calculate_Gv_kernel! = calculate_Gv!(device(arch), workgroup, worksize)
    calculate_Gw_kernel! = calculate_Gw!(device(arch), workgroup, worksize)
    calculate_Gc_kernel! = calculate_Gc!(device(arch), workgroup, worksize)

    barrier = Event(device(arch))

    momentum_kernel_args = (advection,
                            coriolis,
                            stokes_drift,
                            closure,
                            buoyancy,
                            background_fields,
                            velocities,
                            tracers,
                            diffusivities,
                            forcings,
                            hydrostatic_pressure,
                            clock)

    Gu_event = calculate_Gu_kernel!(tendencies.u, grid, u_immersed_bc, momentum_kernel_args...; dependencies=barrier)
    Gv_event = calculate_Gv_kernel!(tendencies.v, grid, v_immersed_bc, momentum_kernel_args...; dependencies=barrier)
    Gw_event = calculate_Gw_kernel!(tendencies.w, grid, w_immersed_bc, momentum_kernel_args...; dependencies=barrier)
    
    events = [Gu_event, Gv_event, Gw_event]

    for tracer_index in 1:length(tracers)
        @inbounds c_tendency = tendencies[tracer_index+3]
        @inbounds forcing = forcings[tracer_index+3]
        @inbounds c_immersed_bc = tracers[tracer_index].boundary_conditions.immersed

        Gc_event = calculate_Gc_kernel!(c_tendency,
                                        grid,
                                        c_immersed_bc,
                                        Val(tracer_index),
                                        advection,
                                        closure,
                                        buoyancy,
                                        background_fields,
                                        velocities,
                                        tracers,
                                        diffusivities,
                                        forcing,
                                        clock,
                                        dependencies=barrier)

        push!(events, Gc_event)
    end

    wait(device(arch), MultiEvent(Tuple(events)))

    return nothing
end

#####
##### Tendency calculators for u, v, w-velocity
#####

""" Calculate the right-hand-side of the u-velocity equation. """
@kernel function calculate_Gu!(Gu, args...)
    i, j, k = @index(Global, NTuple)
    @inbounds Gu[i, j, k] = u_velocity_tendency(i, j, k, args...)
end

""" Calculate the right-hand-side of the v-velocity equation. """
@kernel function calculate_Gv!(Gv, args...)
    i, j, k = @index(Global, NTuple)
    @inbounds Gv[i, j, k] = v_velocity_tendency(i, j, k, args...)
end

""" Calculate the right-hand-side of the w-velocity equation. """
@kernel function calculate_Gw!(Gw, args...)
    i, j, k = @index(Global, NTuple)
    @inbounds Gw[i, j, k] = w_velocity_tendency(i, j, k, args...)
end

#####
##### Tracer(s)
#####

""" Calculate the right-hand-side of the tracer advection-diffusion equation. """
@kernel function calculate_Gc!(Gc, args...)
    i, j, k = @index(Global, NTuple)
    @inbounds Gc[i, j, k] = tracer_tendency(i, j, k, args...)
end

