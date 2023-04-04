using Oceananigans
using Oceananigans.Grids: AbstractGrid

using KernelAbstractions: @kernel, @index

import Oceananigans.Utils: active_cells_work_layout

const ActiveCellsIBG = ImmersedBoundaryGrid{<:Any, <:Any, <:Any, <:Any, <:Any, <:Any, <:AbstractArray}

@inline use_only_active_interior_cells(grid::AbstractGrid)   = nothing
@inline use_only_active_interior_cells(grid::ActiveCellsIBG) = Val(:interior)

@inline use_only_active_surface_cells(grid::AbstractGrid)   = nothing
@inline use_only_active_surface_cells(grid::ActiveCellsIBG) = Val(:surface)

@inline active_cells_work_layout(size, ::Val{:surface},  grid::ActiveCellsIBG) = min(length(grid.active_cells_surface),  256), length(grid.active_cells_surface)
@inline active_cells_work_layout(size, ::Val{:interior}, grid::ActiveCellsIBG) = min(length(grid.active_cells_interior), 256), length(grid.active_cells_interior)

@inline active_linear_index_to_interior_tuple(idx, grid::ActiveCellsIBG) = Base.map(Int, grid.active_cells_interior[idx])
@inline active_linear_index_to_surface_tuple(idx, grid::ActiveCellsIBG)  = Base.map(Int, grid.active_cells_surface[idx])

function ImmersedBoundaryGrid(grid, ib, active_cells_map::Bool) 

    ibg = ImmersedBoundaryGrid(grid, ib)
    TX, TY, TZ = topology(ibg)
    
    # Create the cells map on the CPU, then switch it to the GPU
    if active_cells_map 
        map_interior = active_cells_map_interior(ibg)
        map_interior = arch_array(architecture(ibg), map_interior)

        map_surface = active_cells_map_surface(ibg)
        map_surface = arch_array(architecture(ibg), map_surface)
    else
        map_interior = nothing
        map_surface  = nothing
    end

    return ImmersedBoundaryGrid{TX, TY, TZ}(ibg.underlying_grid, 
                                            ibg.immersed_boundary, 
                                            map_interior, map_surface)
end

@inline active_cell(i, j, k, ibg) = !immersed_cell(i, j, k, ibg)
@inline active_column(i, j, k, grid, column) = column[i, j, k] != 0

function compute_active_cells_interior(ibg)
    is_immersed_operation = KernelFunctionOperation{Center, Center, Center}(active_cell, ibg)
    active_cells_field = Field{Center, Center, Center}(ibg, Bool)
    set!(active_cells_field, is_immersed_operation)
    return active_cells_field
end

function compute_active_cells_surface(ibg)
    one_field = ConditionalOperation{Center, Center, Center}(OneField(Int), identity, ibg, NotImmersed(truefunc), 0.0)
    column    = sum(one_field, dims = 3)
    is_immersed_column = KernelFunctionOperation{Center, Center, Nothing}(active_column, ibg, computed_dependencies = (column, ))
    active_cells_field = Field{Center, Center, Nothing}(ibg, Bool)
    set!(active_cells_field, is_immersed_column)
    return active_cells_field
end

const MAXUInt8  = 2^8  - 1
const MAXUInt16 = 2^16 - 1
const MAXUInt32 = 2^32 - 1

function active_cells_map_interior(ibg)
    active_cells_field = compute_active_cells_interior(ibg)
    full_indices       = findall(arch_array(CPU(), interior(active_cells_field)))

    # Reduce the size of the active_cells_map (originally a tuple of Int64)
    N = maximum(size(ibg))
    IntType = N > MAXUInt8 ? (N > MAXUInt16 ? (N > MAXUInt32 ? UInt64 : UInt32) : UInt16) : UInt8
    smaller_indices = getproperty.(full_indices, Ref(:I)) .|> Tuple{IntType, IntType, IntType}
    
    return smaller_indices
end

function active_cells_map_surface(ibg)
    active_cells_field = compute_active_cells_surface(ibg)
    full_indices       = findall(arch_array(CPU(), interior(active_cells_field, :, :, 1)))
    
    Nx, Ny, Nz = size(ibg)
    # Reduce the size of the active_cells_map (originally a tuple of Int64)
    N = max(Nx, Ny)
    IntType = N > MAXUInt8 ? (N > MAXUInt16 ? (N > MAXUInt32 ? UInt64 : UInt32) : UInt16) : UInt8
    smaller_indices = getproperty.(full_indices, Ref(:I)) .|> Tuple{IntType, IntType}
    
    return smaller_indices
end
