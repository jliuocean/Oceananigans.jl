using Oceananigans.Architectures
using Oceananigans.Architectures: device_event
using Oceananigans.BoundaryConditions
using Oceananigans.TurbulenceClosures: calculate_diffusivities!
using Oceananigans.Models.NonhydrostaticModels: update_hydrostatic_pressure!

import Oceananigans.TimeSteppers: update_state!

compute_auxiliary_fields!(auxiliary_fields) = Tuple(compute!(a) for a in auxiliary_fields)

"""
    update_state!(model::HydrostaticFreeSurfaceModel)

Update peripheral aspects of the model (auxiliary fields, halo regions, diffusivities,
hydrostatic pressure) to the current model state.
"""
update_state!(model::HydrostaticFreeSurfaceModel) = update_state!(model, model.grid)

function update_state!(model::HydrostaticFreeSurfaceModel, grid)

    fill_halo_regions!(prognostic_fields(model), model.clock, fields(model))
    fill_horizontal_velocity_halos!(model.velocities.u, model.velocities.v, model.architecture)

    @apply_regionally update_state_actions!(model)

    fill_halo_regions!(model.velocities.w, model.clock, fields(model))
    fill_halo_regions!(model.diffusivity_fields, model.clock, fields(model))
    fill_halo_regions!(model.pressure.pHY′)
    
    return nothing
end

function update_state_actions!(model) 
    compute_w_from_continuity!(model)
    calculate_diffusivities!(model.diffusivity_fields, model.closure, model)
    update_hydrostatic_pressure!(model.pressure.pHY′, model.architecture, model.grid, model.buoyancy, model.tracers)
end
