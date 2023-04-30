using Oceananigans.Architectures: arch_array

import Oceananigans.Architectures: architecture

"""
    BatchedTridiagonalSolver

A batched solver for large numbers of triadiagonal systems.
"""
struct BatchedTridiagonalSolver{A, B, C, T, G, P}
    a :: A
    b :: B
    c :: C
    t :: T
    grid :: G
    parameters :: P
end

architecture(solver::BatchedTridiagonalSolver) = architecture(solver.grid)


"""
    BatchedTridiagonalSolver(grid;
                             lower_diagonal,
                             diagonal,
                             upper_diagonal,
                             scratch = arch_array(architecture(grid), zeros(eltype(grid), size(grid)...)),
                             parameters = nothing)

Construct a solver for batched tridiagonal systems on `grid` of the form

```
                    bⁱʲ¹ ϕⁱʲ¹ + cⁱʲ¹ ϕⁱʲ²   = fⁱʲ¹,
    aⁱʲᵏ⁻¹ ϕⁱʲᵏ⁻¹ + bⁱʲᵏ ϕⁱʲᵏ + cⁱʲᵏ ϕⁱʲᵏ⁺¹ = fⁱʲᵏ,  k = 2, ..., N-1
    aⁱʲᴺ⁻¹ ϕⁱʲᴺ⁻¹ + bⁱʲᴺ ϕⁱʲᴺ               = fⁱʲᴺ,
```
or in matrix form
```
    ⎡ bⁱʲ¹   cⁱʲ¹     0       ⋯         0   ⎤ ⎡ ϕⁱʲ¹ ⎤   ⎡ fⁱʲ¹ ⎤
    ⎢ aⁱʲ¹   bⁱʲ²   cⁱʲ²      0    ⋯    ⋮   ⎥ ⎢ ϕⁱʲ² ⎥   ⎢ fⁱʲ² ⎥
    ⎢  0      ⋱      ⋱       ⋱              ⎥ ⎢   .  ⎥   ⎢   .  ⎥
    ⎢  ⋮                                0   ⎥ ⎢ ϕⁱʲᵏ ⎥   ⎢ fⁱʲᵏ ⎥
    ⎢  ⋮           aⁱʲᴺ⁻²   bⁱʲᴺ⁻¹   cⁱʲᴺ⁻¹ ⎥ ⎢      ⎥   ⎢   .  ⎥
    ⎣  0      ⋯      0      aⁱʲᴺ⁻¹    bⁱʲᴺ  ⎦ ⎣ ϕⁱʲᴺ ⎦   ⎣ fⁱʲᴺ ⎦
```

where `a` is the `lower_diagonal`, `b` is the `diagonal`, and `c` is the `upper_diagonal`.

Note the convention used here for indexing the upper and lower diagonals; this can be different from 
other implementations where, e.g., `aⁱʲ²` may appear at the second row, instead of `aⁱʲ¹` as above.

`ϕ` is the solution and `f` is the right hand side source term passed to `solve!(ϕ, tridiagonal_solver, f)`.

`a`, `b`, `c`, and `f` can be specified in three ways:

1. A 1D array means, e.g., that `aⁱʲᵏ = a[k]`.

2. A 3D array means, e.g., that `aⁱʲᵏ = a[i, j, k]`.

Other coefficient types can be used by extending `get_coefficient`.
"""
function BatchedTridiagonalSolver(grid;
                                  lower_diagonal,
                                  diagonal,
                                  upper_diagonal,
                                  scratch = arch_array(architecture(grid), zeros(eltype(grid), size(grid)...)),
                                  parameters = nothing)

    return BatchedTridiagonalSolver(lower_diagonal, diagonal, upper_diagonal, scratch, grid, parameters)
end

@inline get_coefficient(i, j, k, grid, a::AbstractArray{T, 1}, p, args...) where {T} = @inbounds a[k]
@inline get_coefficient(i, j, k, grid, a::AbstractArray{T, 3}, p, args...) where {T} = @inbounds a[i, j, k]

"""
    solve!(ϕ, solver::BatchedTridiagonalSolver, rhs, args...)

Solve the batched tridiagonal system of linear equations with right hand side
`rhs` and lower diagonal, diagonal, and upper diagonal coefficients described by the
`BatchedTridiagonalSolver` `solver`. `BatchedTridiagonalSolver` uses a modified
TriDiagonal Matrix Algorithm (TDMA).

The result is stored in `ϕ` which must have size `(grid.Nx, grid.Ny, grid.Nz)`.

Reference implementation per Numerical Recipes, Press et al. 1992 (§ 2.4). Note that
a slightly different notation from Press et al. is used for indexing the off-diagonal
elements; see [`BatchedTridiagonalSolver`](@ref).
"""
function solve!(ϕ, solver::BatchedTridiagonalSolver, rhs, args... )

    a, b, c, t, parameters = solver.a, solver.b, solver.c, solver.t, solver.parameters
    grid = solver.grid

    launch!(architecture(solver), grid, :xy,
            solve_batched_tridiagonal_system_kernel!, ϕ, a, b, c, rhs, t, grid, parameters, Tuple(args))

    return nothing
end

@inline float_eltype(ϕ::AbstractArray{T}) where T <: AbstractFloat = T
@inline float_eltype(ϕ::AbstractArray{<:Complex{T}}) where T <: AbstractFloat = T

@kernel function solve_batched_tridiagonal_system_kernel!(ϕ, a, b, c, f, t, grid, p, args)
    Nx, Ny, Nz = size(grid)

    i, j = @index(Global, NTuple)

    @inbounds begin
        β  = get_coefficient(i, j, 1, grid, b, p, args...)
        f₁ = get_coefficient(i, j, 1, grid, f, p, args...)
        ϕ[i, j, 1] = f₁ / β

        @unroll for k = 2:Nz
            cᵏ⁻¹ = get_coefficient(i, j, k-1, grid, c, p, args...)
            bᵏ   = get_coefficient(i, j, k,   grid, b, p, args...)
            aᵏ⁻¹ = get_coefficient(i, j, k-1, grid, a, p, args...)

            t[i, j, k] = cᵏ⁻¹ / β
            β = bᵏ - aᵏ⁻¹ * t[i, j, k]

            fᵏ = get_coefficient(i, j, k, grid, f, p, args...)
            
            # If the problem is not diagonally-dominant such that `β ≈ 0`,
            # the algorithm is unstable and we elide the forward pass update of ϕ.
            definitely_diagonally_dominant = abs(β) > 10 * eps(float_eltype(ϕ))
            !definitely_diagonally_dominant && break
            ϕ[i, j, k] = (fᵏ - aᵏ⁻¹ * ϕ[i, j, k-1]) / β
        end

        @unroll for k = Nz-1:-1:1
            ϕ[i, j, k] -= t[i, j, k+1] * ϕ[i, j, k+1]
        end
    end
end

