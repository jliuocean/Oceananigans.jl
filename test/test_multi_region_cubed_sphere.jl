include("dependencies_for_runtests.jl")
include("data_dependencies.jl")

using Oceananigans.Grids: halo_size
using Oceananigans.Utils: Iterate, getregion
using Oceananigans.BoundaryConditions: fill_halo_regions!
using Oceananigans.Fields: replace_horizontal_velocity_halos!

function get_halo_data(field, side, k_index=1)
    Nx, Ny, _ = size(field)
    Hx, Hy, _ = halo_size(field.grid)
    
    if side == :west
        return field.data[-Hx+1:0, 1:Ny, k_index]
    elseif side == :east
        return field.data[Nx+1:Nx+Hx, 1:Ny, k_index]
    elseif side == :south
        return field.data[1:Nx, -Hy+1:0, k_index]
    elseif side == :north
        return field.data[1:Nx, Ny+1:Ny+Hy, k_index]
    end
end

function get_halo_data_endpoint(field, side, endpoint, k_index=1)
    Nx, Ny, _ = size(field)
    Hx, Hy, _ = halo_size(field.grid)
    
    if side == :west
        if endpoint == :first
            return field.data[-Hx+1:0, 1, k_index]
        elseif endpoint == :last
            return field.data[-Hx+1:0, Ny, k_index]
        end
    elseif side == :east
        if endpoint == :first
            return field.data[Nx+1:Nx+Hx, 1, k_index]
        elseif endpoint == :last
            return field.data[Nx+1:Nx+Hx, Ny, k_index]
        end
    elseif side == :south
        if endpoint == :first
            return field.data[1, -Hy+1:0, k_index]
        elseif endpoint == :last
            return field.data[Nx, -Hy+1:0, k_index]
        end
    elseif side == :north
        if endpoint == :first
            return field.data[1, Ny+1:Ny+Hy, k_index]
        elseif endpoint == :last
            return field.data[Nx, Ny+1:Ny+Hy, k_index]
        end
    end
end

function get_halo_data_subset(field, side, index_to_skip, k_index=1)
    Nx, Ny, _ = size(field)
    Hx, Hy, _ = halo_size(field.grid)
    
    if side == :west
        if index_to_skip == :first
            return field.data[-Hx+1:0, 2:Ny, k_index]
        elseif index_to_skip == :last
            return field.data[-Hx+1:0, 1:Ny-1, k_index]
        end
    elseif side == :east
        if index_to_skip == :first
            return field.data[Nx+1:Nx+Hx, 2:Ny, k_index]
        elseif index_to_skip == :last
            return field.data[Nx+1:Nx+Hx, 1:Ny-1, k_index]
        end
    elseif side == :south
        if index_to_skip == :first
            return field.data[2:Nx, -Hy+1:0, k_index]
        elseif index_to_skip == :last
            return field.data[1:Nx-1, -Hy+1:0, k_index]
        end
    elseif side == :north
        if index_to_skip == :first
            return field.data[2:Nx, Ny+1:Ny+Hy, k_index]
        elseif index_to_skip == :last
            return field.data[1:Nx-1, Ny+1:Ny+Hy, k_index]
        end
    end
end

"""
    create_test_data(grid, region)

Create an array with integer values of the form, e.g., 541 corresponding to region=5, i=4, j=2.
If `trailing_zeros > 0` then all values are multiplied with `10trailing_zeros`, e.g., for
`trailing_zeros = 2` we have that 54100 corresponds to region=5, i=4, j=2.
"""
function create_test_data(grid, region; trailing_zeros=0)
    Nx, Ny, Nz = size(grid)

    (Nx > 9 || Ny > 9) && error("this won't work; use a grid with Nx, Ny ≤ 9.")

    !(trailing_zeros isa Integer) && error("trailing_zeros has to be an integer")

    factor = trailing_zeros == 0 ? 1 : 10^(trailing_zeros)

    return factor .* [100region + 10i + j for i in 1:Nx, j in 1:Ny, k in 1:Nz]
end

create_c_test_data(grid, region) = create_test_data(grid, region, trailing_zeros=0)
create_u_test_data(grid, region) = create_test_data(grid, region, trailing_zeros=1)
create_v_test_data(grid, region) = create_test_data(grid, region, trailing_zeros=2)

@testset "Testing conformal cubed sphere partitions..." begin
    for n = 1:4
        @test length(CubedSpherePartition(; R=n)) == 6n^2
    end
end

@testset "Testing conformal cubed sphere face grid from file" begin
    Nz = 1
    z = (-1, 0)

    cs32_filepath = datadep"cubed_sphere_32_grid/cubed_sphere_32_grid.jld2"

    for panel in 1:6
        grid = OrthogonalSphericalShellGrid(cs32_filepath; panel, Nz, z)
        @test grid isa OrthogonalSphericalShellGrid
    end

    for arch in archs
        @info "  Testing conformal cubed sphere face grid from file [$(typeof(arch))]..."

        # read cs32 grid from file
        grid_cs32 = ConformalCubedSphereGrid(cs32_filepath, arch; Nz, z)

        Nx, Ny, Nz = size(grid_cs32)
        radius = getregion(grid_cs32, 1).radius

        # construct a ConformalCubedSphereGrid similar to cs32
        grid = ConformalCubedSphereGrid(arch; z, panel_size=(Nx, Ny, Nz), radius)

        for panel in 1:6

            CUDA.@allowscalar begin
                # Test only on cca and ffa; fca and cfa are all zeros on grid_cs32!
                # Only test interior points since halo regions are not filled for grid_cs32!

                @test isapprox(getregion(grid, panel).φᶜᶜᵃ[1:Nx, 1:Ny], getregion(grid_cs32, panel).φᶜᶜᵃ[1:Nx, 1:Ny])
                @test isapprox(getregion(grid, panel).λᶜᶜᵃ[1:Nx, 1:Ny], getregion(grid_cs32, panel).λᶜᶜᵃ[1:Nx, 1:Ny])

                # before we test, make sure we don't consider +180 and -180 longitudes as being "different"
                getregion(grid, panel).λᶠᶠᵃ[getregion(grid, panel).λᶠᶠᵃ .≈ -180] .= 180

                # and if poles are included, they have the same longitude.
                getregion(grid, panel).λᶠᶠᵃ[getregion(grid, panel).φᶠᶠᵃ .≈ +90] = getregion(grid_cs32, panel).λᶠᶠᵃ[getregion(grid, panel).φᶠᶠᵃ .≈ +90]
                getregion(grid, panel).λᶠᶠᵃ[getregion(grid, panel).φᶠᶠᵃ .≈ -90] = getregion(grid_cs32, panel).λᶠᶠᵃ[getregion(grid, panel).φᶠᶠᵃ .≈ -90]
                @test isapprox(getregion(grid, panel).φᶠᶠᵃ[1:Nx, 1:Ny], getregion(grid_cs32, panel).φᶠᶠᵃ[1:Nx, 1:Ny])
                @test isapprox(getregion(grid, panel).λᶠᶠᵃ[1:Nx, 1:Ny], getregion(grid_cs32, panel).λᶠᶠᵃ[1:Nx, 1:Ny])
            end
        end
    end
end

@testset "Testing conformal cubed sphere fill halos for tracers" begin
    for FT in float_types
        for arch in archs
            @info "  Testing fill halos for tracers [$FT, $(typeof(arch))]..."

            Nx, Ny, Nz = 9, 9, 1

            grid = ConformalCubedSphereGrid(arch, FT; panel_size = (Nx, Ny, Nz), z = (0, 1), radius = 1, horizontal_direction_halo=2)
            c = CenterField(grid)

            region = Iterate(1:6)
            @apply_regionally data = create_c_test_data(grid, region)
            set!(c, data)
            fill_halo_regions!(c)

            Hx, Hy, Hz = halo_size(c.grid)

            west_indices  = 1:Hx, 1:Ny
            south_indices = 1:Nx, 1:Hy
            east_indices  = Nx-Hx+1:Nx, 1:Ny
            north_indices = 1:Nx, Ny-Hy+1:Ny

            # Confirm that the tracer halos were filled according to connectivity described at ConformalCubedSphereGrid docstring.
            CUDA.@allowscalar begin
                switch_device!(grid, 1)
                @test get_halo_data(getregion(c, 1), :west)  == reverse(create_c_test_data(grid, 5)[north_indices...], dims=1)'
                @test get_halo_data(getregion(c, 1), :east)  ==         create_c_test_data(grid, 2)[west_indices...]
                @test get_halo_data(getregion(c, 1), :south) ==         create_c_test_data(grid, 6)[north_indices...]
                @test get_halo_data(getregion(c, 1), :north) == reverse(create_c_test_data(grid, 3)[west_indices...], dims=2)'

                switch_device!(grid, 2)
                @test get_halo_data(getregion(c, 2), :west)  ==         create_c_test_data(grid, 1)[east_indices...]
                @test get_halo_data(getregion(c, 2), :east)  == reverse(create_c_test_data(grid, 4)[south_indices...], dims=1)'
                @test get_halo_data(getregion(c, 2), :south) == reverse(create_c_test_data(grid, 6)[east_indices...], dims=2)'
                @test get_halo_data(getregion(c, 2), :north) ==         create_c_test_data(grid, 3)[south_indices...]

                switch_device!(grid, 3)
                @test get_halo_data(getregion(c, 3), :west)  == reverse(create_c_test_data(grid, 1)[north_indices...], dims=1)'
                @test get_halo_data(getregion(c, 3), :east)  ==         create_c_test_data(grid, 4)[west_indices...]
                @test get_halo_data(getregion(c, 3), :south) ==         create_c_test_data(grid, 2)[north_indices...]
                @test get_halo_data(getregion(c, 3), :north) == reverse(create_c_test_data(grid, 5)[west_indices...], dims=2)'

                switch_device!(grid, 4)
                @test get_halo_data(getregion(c, 4), :west)  ==         create_c_test_data(grid, 3)[east_indices...]
                @test get_halo_data(getregion(c, 4), :east)  == reverse(create_c_test_data(grid, 6)[south_indices...], dims=1)'
                @test get_halo_data(getregion(c, 4), :south) == reverse(create_c_test_data(grid, 2)[east_indices...], dims=2)'
                @test get_halo_data(getregion(c, 4), :north) ==         create_c_test_data(grid, 5)[south_indices...]

                switch_device!(grid, 5)
                @test get_halo_data(getregion(c, 5), :west)  == reverse(create_c_test_data(grid, 3)[north_indices...], dims=1)'
                @test get_halo_data(getregion(c, 5), :east)  ==         create_c_test_data(grid, 6)[west_indices...]
                @test get_halo_data(getregion(c, 5), :south) ==         create_c_test_data(grid, 4)[north_indices...]
                @test get_halo_data(getregion(c, 5), :north) == reverse(create_c_test_data(grid, 1)[west_indices...], dims=2)'

                switch_device!(grid, 6)
                @test get_halo_data(getregion(c, 6), :west)  ==         create_c_test_data(grid, 5)[east_indices...]
                @test get_halo_data(getregion(c, 6), :east)  == reverse(create_c_test_data(grid, 2)[south_indices...], dims=1)'
                @test get_halo_data(getregion(c, 6), :south) == reverse(create_c_test_data(grid, 4)[east_indices...], dims=2)'
                @test get_halo_data(getregion(c, 6), :north) ==         create_c_test_data(grid, 1)[south_indices...]
            end
        end
    end
end

@testset "Testing conformal cubed sphere fill halos for horizontal velocities" begin
    for FT in float_types
        for arch in archs

            @info "  Testing fill halos for horizontal velocities [$FT, $(typeof(arch))]..."

            Nx, Ny, Nz = 9, 9, 1

            grid = ConformalCubedSphereGrid(arch, FT; panel_size = (Nx, Ny, Nz), z = (0, 1), radius = 1, horizontal_direction_halo=2)

            u = XFaceField(grid)
            v = YFaceField(grid)
            
            region = Iterate(1:6)
            @apply_regionally u_data = create_u_test_data(grid, region)
            @apply_regionally v_data = create_v_test_data(grid, region)
            set!(u, u_data)
            set!(v, v_data)

            fill_halo_regions!(u)
            fill_halo_regions!(v)
            @apply_regionally replace_horizontal_velocity_halos!((; u, v, w = nothing), grid)

            Hx, Hy, Hz = halo_size(u.grid)

            west_indices  = 1:Hx, 1:Ny
            south_indices = 1:Nx, 1:Hy
            east_indices  = Nx-Hx+1:Nx, 1:Ny
            north_indices = 1:Nx, Ny-Hy+1:Ny
            
            west_indices_first = 1:Hx, 1
            west_indices_last = 1:Hx, Ny
            south_indices_first = 1, 1:Hy
            south_indices_last = Nx, 1:Hy
            east_indices_first = Nx-Hx+1:Nx, 1
            east_indices_last = Nx-Hx+1:Nx, Ny
            north_indices_first = 1, Ny-Hy+1:Ny
            north_indices_last = Nx, Ny-Hy+1:Ny
            
            west_indices_subset_skip_first_index  = 1:Hx, 2:Ny
            west_indices_subset_skip_last_index  = 1:Hx, 1:Ny-1
            south_indices_subset_skip_first_index = 2:Nx, 1:Hy
            south_indices_subset_skip_last_index = 1:Nx-1, 1:Hy
            east_indices_subset_skip_first_index  = Nx-Hx+1:Nx, 2:Ny
            east_indices_subset_skip_last_index  = Nx-Hx+1:Nx, 1:Ny-1
            north_indices_subset_skip_first_index = 2:Nx, Ny-Hy+1:Ny
            north_indices_subset_skip_last_index = 1:Nx-1, Ny-Hy+1:Ny

            # Confirm that the zonal velocity halos were filled according to connectivity described at ConformalCubedSphereGrid docstring.
            CUDA.@allowscalar begin
            
                # Panel 1
                switch_device!(grid, 1)
                
                # Trivial halo checks with no off-set in index
                @test get_halo_data(getregion(u, 1), :west)      ==   reverse(create_v_test_data(grid, 5)[north_indices...], dims=1)'
                @test get_halo_data(getregion(u, 1), :east)      ==           create_u_test_data(grid, 2)[west_indices...]
                @test get_halo_data(getregion(u, 1), :south)     ==           create_u_test_data(grid, 6)[north_indices...]

                # Non-trivial halo checks with off-set in index
                @test get_halo_data_subset(getregion(u, 1), 
                                           :north,
                                           index_to_skip=:first) == - reverse(create_v_test_data(grid, 3)[west_indices_subset_skip_first_index...], dims=2)'
                @test get_halo_data_endpoint(getregion(u, 1), 
                                             :north, :first)     ==          -create_u_test_data(grid, 5)[north_indices_first...]                
                
                # Panel 2
                switch_device!(grid, 2)
                
                # Trivial halo checks with no off-set in index
                @test get_halo_data(getregion(u, 2), :west)      ==           create_u_test_data(grid, 1)[east_indices...]
                @test get_halo_data(getregion(u, 2), :east)      ==   reverse(create_v_test_data(grid, 4)[south_indices...], dims=1)'
                @test get_halo_data(getregion(u, 2), :north)     ==           create_u_test_data(grid, 3)[south_indices...]                
                
                # Non-trivial halo checks with off-set in index
                @test get_halo_data_subset(getregion(u, 2), 
                                           :south, 
                                           index_to_skip=:first) == - reverse(create_v_test_data(grid, 6)[east_indices_subset_skip_first_index...], dims=2)'
                @test get_halo_data_endpoint(getregion(u, 2), 
                                             :south, :first)     ==          -create_v_test_data(grid, 1)[east_indices_first...]                
                
                # Panel 3
                switch_device!(grid, 3)
                
                # Trivial halo checks with no off-set in index
                @test get_halo_data(getregion(u, 3), :west)      ==   reverse(create_v_test_data(grid, 1)[north_indices...], dims=1)'
                @test get_halo_data(getregion(u, 3), :east)      ==           create_u_test_data(grid, 4)[west_indices...]
                @test get_halo_data(getregion(u, 3), :south)     ==           create_u_test_data(grid, 2)[north_indices...]

                # Non-trivial halo checks with off-set in index
                @test get_halo_data_subset(getregion(u, 3), 
                                           :north,
                                           index_to_skip=:first) == - reverse(create_v_test_data(grid, 5)[west_indices_subset_skip_first_index...], dims=2)'
                @test get_halo_data_endpoint(getregion(u, 3), 
                                             :north, :first)     ==          -create_u_test_data(grid, 1)[north_indices_first...]
                
                # Panel 4
                switch_device!(grid, 4)
                
                # Trivial halo checks with no off-set in index
                @test get_halo_data(getregion(u, 4), :west)      ==           create_u_test_data(grid, 3)[east_indices...]
                @test get_halo_data(getregion(u, 4), :east)      ==   reverse(create_v_test_data(grid, 6)[south_indices...], dims=1)'
                @test get_halo_data(getregion(u, 4), :north)     ==           create_u_test_data(grid, 5)[south_indices...]
                
                # Non-trivial halo checks with off-set in index
                @test get_halo_data_subset(getregion(u, 4), 
                                           :south,
                                           index_to_skip=:first) == - reverse(create_v_test_data(grid, 2)[east_indices_subset_skip_first_index...], dims=2)'
                @test get_halo_data_endpoint(getregion(u, 4), 
                                             :south, :first)     ==          -create_v_test_data(grid, 3)[east_indices_first...]
                
                # Panel 5
                switch_device!(grid, 5)
                
                # Trivial halo checks with no off-set in index
                @test get_halo_data(getregion(u, 5), :west)      ==   reverse(create_v_test_data(grid, 3)[north_indices...], dims=1)'
                @test get_halo_data(getregion(u, 5), :east)      ==           create_u_test_data(grid, 6)[west_indices...]
                @test get_halo_data(getregion(u, 5), :south)     ==           create_u_test_data(grid, 4)[north_indices...]
                
                # Non-trivial halo checks with off-set in index
                @test get_halo_data_subset(getregion(u, 5), 
                                           :north,
                                           index_to_skip=:first) == - reverse(create_v_test_data(grid, 1)[west_indices_subset_skip_first_index...], dims=2)'
                @test get_halo_data_endpoint(getregion(u, 5), 
                                             :north, :first)     ==          -create_u_test_data(grid, 3)[north_indices_first...]
                
                # Panel 6
                switch_device!(grid, 6)
                
                # Trivial halo checks with no off-set in index
                @test get_halo_data(getregion(u, 6), :west)      ==           create_u_test_data(grid, 5)[east_indices...]
                @test get_halo_data(getregion(u, 6), :east)      ==   reverse(create_v_test_data(grid, 2)[south_indices...], dims=1)'
                @test get_halo_data(getregion(u, 6), :north)     ==           create_u_test_data(grid, 1)[south_indices...]
                
                # Non-trivial halo checks with off-set in index
                @test get_halo_data_subset(getregion(u, 6), 
                                           :south,
                                           index_to_skip=:first) == - reverse(create_v_test_data(grid, 4)[east_indices_subset_skip_first_index...], dims=2)'
                @test get_halo_data_endpoint(getregion(u, 6), 
                                             :south, :first)     ==          -create_v_test_data(grid, 5)[east_indices_first...]
                
            end

            # Confirm that the meridional velocity halos were filled according to connectivity described at ConformalCubedSphereGrid docstring.
            CUDA.@allowscalar begin
            
                # Panel 1
                switch_device!(grid, 1)
                
                # Trivial halo checks with no off-set in index
                @test get_halo_data(getregion(v, 1), :east)      ==           create_v_test_data(grid, 2)[west_indices...]
                @test get_halo_data(getregion(v, 1), :south)     ==           create_v_test_data(grid, 6)[north_indices...]
                @test get_halo_data(getregion(v, 1), :north)     ==   reverse(create_u_test_data(grid, 3)[west_indices...], dims=2)'
                
                # Non-trivial halo checks with off-set in index
                @test get_halo_data_subset(getregion(v, 1), 
                                           :west,
                                           index_to_skip=:first) == - reverse(create_u_test_data(grid, 5)[north_indices_subset_skip_first_index...], dims=1)'
                @test get_halo_data_endpoint(getregion(v, 1), 
                                             :west, :first)      ==          -create_u_test_data(grid, 6)[north_indices_first...]
                
                # Panel 2
                switch_device!(grid, 2)
                
                # Trivial halo checks with no off-set in index
                @test get_halo_data(getregion(v, 2), :west)      ==           create_v_test_data(grid, 1)[east_indices...]
                @test get_halo_data(getregion(v, 2), :south)     ==   reverse(create_u_test_data(grid, 6)[east_indices...], dims=2)'
                @test get_halo_data(getregion(v, 2), :north)     ==           create_v_test_data(grid, 3)[south_indices...]                
                
                # Non-trivial halo checks with off-set in index
                @test get_halo_data_subset(getregion(v, 2), 
                                           :east,
                                           index_to_skip=:first) == - reverse(create_u_test_data(grid, 4)[south_indices_subset_skip_first_index...], dims=1)'
                @test get_halo_data_endpoint(getregion(v, 2), 
                                             :east, :first)      ==          -create_v_test_data(grid, 6)[east_indices_first...]
                
                # Panel 3
                switch_device!(grid, 3)
                
                # Trivial halo checks with no off-set in index
                @test get_halo_data(getregion(v, 3), :east)      ==           create_v_test_data(grid, 4)[west_indices...]
                @test get_halo_data(getregion(v, 3), :south)     ==           create_v_test_data(grid, 2)[north_indices...]
                @test get_halo_data(getregion(v, 3), :north)     ==   reverse(create_u_test_data(grid, 5)[west_indices...], dims=2)'           
                
                # Non-trivial halo checks with off-set in index
                @test get_halo_data_subset(getregion(v, 3), 
                                           :west,
                                           index_to_skip=:first) == - reverse(create_u_test_data(grid, 1)[north_indices_subset_skip_first_index...], dims=1)'
                @test get_halo_data_endpoint(getregion(v, 3), 
                                             :west, :first)      ==          -create_u_test_data(grid, 2)[north_indices_first...]
                
                # Panel 4
                switch_device!(grid, 4)
                
                # Trivial halo checks with no off-set in index
                @test get_halo_data(getregion(v, 4), :west)      ==           create_v_test_data(grid, 3)[east_indices...]
                @test get_halo_data(getregion(v, 4), :south)     ==   reverse(create_u_test_data(grid, 2)[east_indices...], dims=2)'
                @test get_halo_data(getregion(v, 4), :north)     ==           create_v_test_data(grid, 5)[south_indices...]
                
                # Non-trivial halo checks with off-set in index
                @test get_halo_data_subset(getregion(v, 4), 
                                           :east,
                                           index_to_skip=:first) == - reverse(create_u_test_data(grid, 6)[south_indices_subset_skip_first_index...], dims=1)'
                @test get_halo_data_endpoint(getregion(v, 4), 
                                             :east, :first)      ==          -create_v_test_data(grid, 2)[east_indices_first...]
                
                # Panel 5
                switch_device!(grid, 5)
                
                # Trivial halo checks with no off-set in index
                @test get_halo_data(getregion(v, 5), :east)      ==           create_v_test_data(grid, 6)[west_indices...]
                @test get_halo_data(getregion(v, 5), :south)     ==           create_v_test_data(grid, 4)[north_indices...]
                @test get_halo_data(getregion(v, 5), :north)     ==   reverse(create_u_test_data(grid, 1)[west_indices...], dims=2)'
                
                # Non-trivial halo checks with off-set in index
                @test get_halo_data_subset(getregion(v, 5), 
                                           :west,
                                           index_to_skip=:first) == - reverse(create_u_test_data(grid, 3)[north_indices_subset_skip_first_index...], dims=1)'
                @test get_halo_data_endpoint(getregion(v, 5), 
                                             :west, :first)      ==          -create_u_test_data(grid, 4)[borth_indices_first...] 
                
                # Panel 6
                switch_device!(grid, 6)
                
                # Trivial halo checks with no off-set in index
                @test get_halo_data(getregion(v, 6), :west)      ==           create_v_test_data(grid, 5)[east_indices...]
                @test get_halo_data(getregion(v, 6), :south)     ==   reverse(create_u_test_data(grid, 4)[east_indices...], dims=2)'
                @test get_halo_data(getregion(v, 6), :north)     ==           create_v_test_data(grid, 1)[south_indices...]
                
                # Non-trivial halo checks with off-set in index
                @test get_halo_data_subset(getregion(v, 6), 
                                           :east,
                                           index_to_skip=:first) == - reverse(create_u_test_data(grid, 2)[south_indices_subset_skip_first_index...], dims=1)'
                @test get_halo_data_endpoint(getregion(v, 6), 
                                             :east, :first)      ==          -create_v_test_data(grid, 4)[east_indices_first...]
                
            end
        end
    end
end