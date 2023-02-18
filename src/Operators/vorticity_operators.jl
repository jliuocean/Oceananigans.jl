""" Vertical circulation associated with horizontal velocities u, v. """
@inline Γᶠᶠᶜ(i, j, k, grid, u, v) = δxᶠᵃᵃ(i, j, k, grid, Δy_qᶜᶠᶜ, v) - δyᵃᶠᵃ(i, j, k, grid, Δx_qᶠᶜᶜ, u)

""" Vertical vorticity associated with horizontal velocities u, v. """
@inline ζ₃ᶠᶠᶜ(i, j, k, grid, u, v) = Γᶠᶠᶜ(i, j, k, grid, u, v) / Azᶠᶠᶜ(i, j, k, grid)

#####
##### Vertical circulation at the corners of the cubed sphere needs to treated in a special manner.
##### See: https://github.com/CliMA/Oceananigans.jl/issues/1584
#####

@inline function Γᶠᶠᶜ(i, j, k, grid::OrthogonalSphericalShellGrid, u, v)
    # South-west corner
    if i == 1 && j == 1
        return Δy_qᶜᶠᶜ(i, j, k, grid, v) - Δx_qᶠᶜᶜ(i, j, k, grid, u) + Δx_qᶠᶜᶜ(i, j-0x1, k, grid, u)

    # South-east corner
    elseif i == grid.Nx+0x1 && j == 1
        return - Δy_qᶜᶠᶜ(i-0x1, j, k, grid, v) - Δx_qᶠᶜᶜ(i, j, k, grid, u) + Δx_qᶠᶜᶜ(i, j-0x1, k, grid, u)

    # North-west corner
    elseif i == 1 && j == grid.Ny+0x1
        return Δy_qᶜᶠᶜ(i, j, k, grid, v) - Δx_qᶠᶜᶜ(i, j, k, grid, u) + Δx_qᶠᶜᶜ(i, j-0x1, k, grid, u)

    # North-east corner
    elseif i == grid.Nx+0x1 && j == grid.Ny+0x1
        return - Δy_qᶜᶠᶜ(i-0x1, j, k, grid, v) - Δx_qᶠᶜᶜ(i, j, k, grid, u) + Δx_qᶠᶜᶜ(i, j-0x1, k, grid, u)

    # Not a corner
    else
        return δxᶠᵃᵃ(i, j, k, grid, Δy_qᶜᶠᶜ, v) - δyᵃᶠᵃ(i, j, k, grid, Δx_qᶠᶜᶜ, u)
    end
end
