#####
##### Momentum and tracer advective flux operators for upwind-biased advection schemes
#####
##### See topologically_conditional_interpolation.jl for an explanation of the underscore-prepended
##### functions _symmetric_interpolate_*, _left_biased_interpolate_*, and _right_biased_interpolate_*.
#####

const UpwindScheme = AbstractUpwindBiasedAdvectionScheme

@inline upwind_biased_product(ũ, ψᴸ, ψᴿ) = ((ũ + abs(ũ)) * ψᴸ + (ũ - abs(ũ)) * ψᴿ) / 2

@inline sign_val(u) = Val(Int(sign(u)))

# Upwind interpolate -> choose _left_biased if u > 0 and _right_biased if u < 0
for (d, ξ) in enumerate((:x, :y, :z))
    code = [:ᵃ, :ᵃ, :ᵃ]

    for loc in (:ᶜ, :ᶠ)
        code[d] = loc
        second_order_interp = Symbol(:ℑ, ξ, code...)
        alt_interp       = Symbol(:_upwind_interpolate_, ξ, code...)
        alt_left_interp  = Symbol(:_left_biased_interpolate_, ξ, code...)
        alt_right_interp = Symbol(:_right_biased_interpolate_, ξ, code...)

        @eval begin
            @inline $alt_interp(i, j, k, grid, u, args...) = $alt_interp(i, j, k, grid, sign_val(u), args...)
            @inline $alt_interp(i, j, k, grid, ::Val{0},  args...) =  $alt_left_interp(i, j, k, grid, args...)
            @inline $alt_interp(i, j, k, grid, ::Val{1},  args...) =  $alt_left_interp(i, j, k, grid, args...)
            @inline $alt_interp(i, j, k, grid, ::Val{-1}, args...) = $alt_right_interp(i, j, k, grid, args...)
        end
    end
end

#####
##### Momentum advection operators
#####
##### Note the convention "advective_momentum_flux_AB" corresponds to the advection _of_ B _by_ A.
#####

@inline function advective_momentum_flux_Uu(i, j, k, grid, scheme::UpwindScheme, U, u)

    ũ  = _symmetric_interpolate_xᶜᵃᵃ(i, j, k, grid, scheme, Ax_qᶠᶜᶜ, U)
    uᴿ =    _upwind_interpolate_xᶜᵃᵃ(i, j, k, grid, ũ, scheme, u)

    return ũ * uᴿ
end

@inline function advective_momentum_flux_Vu(i, j, k, grid, scheme::UpwindScheme, V, u)

    ṽ  = _symmetric_interpolate_xᶠᵃᵃ(i, j, k, grid, scheme, Ay_qᶜᶠᶜ, V)
    uᴿ =    _upwind_interpolate_yᵃᶠᵃ(i, j, k, grid, ṽ, scheme, u)

    return ṽ * uᴿ
end

@inline function advective_momentum_flux_Wu(i, j, k, grid, scheme::UpwindScheme, W, u)

    w̃  = _symmetric_interpolate_xᶠᵃᵃ(i, j, k, grid, scheme, Az_qᶜᶜᶠ, W)
    uᴿ =    _upwind_interpolate_zᵃᵃᶠ(i, j, k, grid, w̃, scheme, u)

    return w̃ * uᴿ
end

@inline function advective_momentum_flux_Uv(i, j, k, grid, scheme::UpwindScheme, U, v)

    ũ  = _symmetric_interpolate_yᵃᶠᵃ(i, j, k, grid, scheme, Ax_qᶠᶜᶜ, U)
    vᴿ =    _upwind_interpolate_xᶠᵃᵃ(i, j, k, grid, ũ, scheme, v)
 
    return ũ * vᴿ
end

@inline function advective_momentum_flux_Vv(i, j, k, grid, scheme::UpwindScheme, V, v)

    ṽ  = _symmetric_interpolate_yᵃᶜᵃ(i, j, k, grid, scheme, Ay_qᶜᶠᶜ, V)
    vᴿ =    _upwind_interpolate_yᵃᶜᵃ(i, j, k, grid, ṽ, scheme, v)

    return ṽ * vᴿ
end

@inline function advective_momentum_flux_Wv(i, j, k, grid, scheme::UpwindScheme, W, v)

    w̃  = _symmetric_interpolate_yᵃᶠᵃ(i, j, k, grid, scheme, Az_qᶜᶜᶠ, W)
    vᴿ =    _upwind_interpolate_zᵃᵃᶠ(i, j, k, grid, w̃, scheme, v)

    return w̃ * vᴿ
end

@inline function advective_momentum_flux_Uw(i, j, k, grid, scheme::UpwindScheme, U, w)

    ũ  = _symmetric_interpolate_zᵃᵃᶠ(i, j, k, grid, scheme, Ax_qᶠᶜᶜ, U)
    wᴿ =    _upwind_interpolate_xᶠᵃᵃ(i, j, k, grid, ũ, scheme, w)

    return ũ * wᴿ
end

@inline function advective_momentum_flux_Vw(i, j, k, grid, scheme::UpwindScheme, V, w)

    ṽ  = _symmetric_interpolate_zᵃᵃᶠ(i, j, k, grid, scheme, Ay_qᶜᶠᶜ, V)
    wᴿ =    _upwind_interpolate_yᵃᶠᵃ(i, j, k, grid, ṽ, scheme, w)

    return ṽ * wᴿ
end

@inline function advective_momentum_flux_Ww(i, j, k, grid, scheme::UpwindScheme, W, w)

    w̃  = _symmetric_interpolate_zᵃᵃᶜ(i, j, k, grid, scheme, Az_qᶜᶜᶠ, W)
    wᴿ =    _upwind_interpolate_zᵃᵃᶜ(i, j, k, grid, w̃, scheme, w)

    return w̃ * wᴿ
end

#####
##### Tracer advection operators
#####
    
@inline function advective_tracer_flux_x(i, j, k, grid, scheme::UpwindScheme, U, c) 

    @inbounds ũ = U[i, j, k]
    cᴿ =_upwind_interpolate_xᶠᵃᵃ(i, j, k, grid, ũ, scheme, c)

    return Axᶠᶜᶜ(i, j, k, grid) * ũ * cᴿ
end

@inline function advective_tracer_flux_y(i, j, k, grid, scheme::UpwindScheme, V, c)

    @inbounds ṽ = V[i, j, k]
    cᴿ =_upwind_interpolate_yᵃᶠᵃ(i, j, k, grid, ṽ, scheme, c)

    return Ayᶜᶠᶜ(i, j, k, grid) * ṽ * cᴿ
end

@inline function advective_tracer_flux_z(i, j, k, grid, scheme::UpwindScheme, W, c)

    @inbounds w̃ = W[i, j, k]
    cᴿ =_upwind_interpolate_zᵃᵃᶠ(i, j, k, grid, w̃, scheme, c)

    return Azᶜᶜᶠ(i, j, k, grid) * w̃ * cᴿ
end