#####
##### Centered advection scheme
#####

"""
    struct Centered{N, FT, CA} <: AbstractCenteredAdvectionScheme{N, FT}

Centered reconstruction scheme.
"""
struct Centered{N, FT, CA} <: AbstractCenteredAdvectionScheme{N, FT}
    "advection scheme used near boundaries"
    buffer_scheme :: CA

    function Centered{N, FT}(buffer_scheme::CA) where {N, FT, CA}

        return new{N, FT, CA}(buffer_scheme)
    end
end

function Centered(FT::DataType = Float64; grid = nothing, order = 2) 

    if !(grid isa Nothing) 
        FT = eltype(grid)
    end

    mod(order, 2) != 0 && throw(ArgumentError("Centered reconstruction scheme is defined only for even orders"))

    N  = Int(order ÷ 2)
    if N > 1 
        buffer_scheme = Centered(FT; grid, order = order - 2)
    else
        buffer_scheme = nothing
    end
    return Centered{N, FT}(buffer_scheme)
end

Base.summary(a::Centered{N}) where N = string("Centered reconstruction order ", N*2)

Base.show(io::IO, a::Centered{N, FT, XT, YT, ZT}) where {N, FT, XT, YT, ZT} =
    print(io, summary(a), " \n",
              " Boundary scheme: ", "\n",
              "    └── ", summary(a.buffer_scheme), "\n",
              " Directions:", "\n",
              "    ├── X $(XT == Nothing ? "regular" : "stretched") \n",
              "    ├── Y $(YT == Nothing ? "regular" : "stretched") \n",
              "    └── Z $(ZT == Nothing ? "regular" : "stretched")" )


Adapt.adapt_structure(to, scheme::Centered{N, FT}) where {N, FT} =
    Centered{N, FT}(Adapt.adapt(to, scheme.coeff_xᶠᵃᵃ), Adapt.adapt(to, scheme.coeff_xᶜᵃᵃ),
                    Adapt.adapt(to, scheme.coeff_yᵃᶠᵃ), Adapt.adapt(to, scheme.coeff_yᵃᶜᵃ),
                    Adapt.adapt(to, scheme.coeff_zᵃᵃᶠ), Adapt.adapt(to, scheme.coeff_zᵃᵃᶜ),
                    Adapt.adapt(to, scheme.buffer_scheme))
                    
# Useful aliases
Centered(grid, FT::DataType=Float64; kwargs...) = Centered(FT; grid, kwargs...)

CenteredSecondOrder(grid=nothing, FT::DataType=Float64) = Centered(grid, FT; order=2)
CenteredFourthOrder(grid=nothing, FT::DataType=Float64) = Centered(grid, FT; order=4)

const ACAS = AbstractCenteredAdvectionScheme

# left and right biased for Centered reconstruction are just symmetric!
@inline upwind_biased_interpolate_x(i, j, k, grid, dir, scheme::ACAS, args...) = symmetric_interpolate_x(i, j, k, grid, scheme, args...)
@inline upwind_biased_interpolate_y(i, j, k, grid, dir, scheme::ACAS, args...) = symmetric_interpolate_y(i, j, k, grid, scheme, args...)
@inline upwind_biased_interpolate_z(i, j, k, grid, dir, scheme::ACAS, args...) = symmetric_interpolate_z(i, j, k, grid, scheme, args...)

# uniform centered reconstruction
for buffer in advection_buffers
    @eval begin
        @inline function symmetric_interpolate_x(i, j, k, grid, parent_scheme::Centered{$buffer, FT, <:Nothing}, ψ, idx, loc, args...) where FT 
            scheme = _topologically_conditional_scheme_x(i, j, k, grid, SymmetricStencil(), loc, parent_scheme)
            return @inbounds $(calc_reconstruction_stencil(buffer, :symmetric, :x, false))
        end
        @inline function symmetric_interpolate_x(i, j, k, grid, parent_scheme::Centered{$buffer, FT, <:Nothing}, ψ::Function, idx, loc, args...) where FT 
            scheme = _topologically_conditional_scheme_x(i, j, k, grid, SymmetricStencil(), loc, parent_scheme)
            return @inbounds $(calc_reconstruction_stencil(buffer, :symmetric, :x,  true))
        end

        @inline function symmetric_interpolate_y(i, j, k, grid, parent_scheme::Centered{$buffer, FT, XT, <:Nothing}, ψ, idx, loc, args...) where {FT, XT} 
            scheme = _topologically_conditional_scheme_x(i, j, k, grid, SymmetricStencil(), loc, parent_scheme)
            return @inbounds $(calc_reconstruction_stencil(buffer, :symmetric, :y, false))
        end
        @inline function symmetric_interpolate_y(i, j, k, grid, parent_scheme::Centered{$buffer, FT, XT, <:Nothing}, ψ::Function, idx, loc, args...) where {FT, XT} 
            scheme = _topologically_conditional_scheme_y(i, j, k, grid, SymmetricStencil(), loc, parent_scheme)
            return @inbounds $(calc_reconstruction_stencil(buffer, :symmetric, :y,  true))
        end
    
        @inline function symmetric_interpolate_z(i, j, k, grid, parent_scheme::Centered{$buffer, FT, XT, YT, <:Nothing}, ψ, idx, loc, args...)           where {FT, XT, YT} 
            scheme = _topologically_conditional_scheme_z(i, j, k, grid, SymmetricStencil(), loc, parent_scheme)
            return @inbounds $(calc_reconstruction_stencil(buffer, :symmetric, :z, false))
        end
        @inline function symmetric_interpolate_z(i, j, k, grid, parent_scheme::Centered{$buffer, FT, XT, YT, <:Nothing}, ψ::Function, idx, loc, args...) where {FT, XT, YT} 
            scheme = _topologically_conditional_scheme_z(i, j, k, grid, SymmetricStencil(), loc, parent_scheme)
            return @inbounds $(calc_reconstruction_stencil(buffer, :symmetric, :z,  true))
        end
    end
end
