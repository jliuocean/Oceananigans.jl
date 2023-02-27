"""
    struct MortonArray{T, N} <: AbstractArray{T, 3}

A three dimensional array organized in memory as Morton curve. 
The array is indexed in with `arr[i, j, k]` and picks from memory at location
`arr.underlying_data[morton_encode3d(i, j, k, h.min_axis, h.Nx2, h.Ny2)...]`
"""
struct MortonArray{T} <: AbstractArray{T, 3}
    underlying_data   :: AbstractArray{T, 1}
    min_axis          :: Int
    underlying_size   :: Tuple

    MortonArray{T}(underlying_data::AbstractArray, min_axis::Int, underlying_size::Tuple) where T = new{T}(underlying_data, min_axis, underlying_size)
end

using Base: @propagate_inbounds

@propagate_inbounds Base.getindex(h::MortonArray, i, j, k)       =  getindex(h.underlying_data,      morton_encode3d(i, j, k, h.min_axis)...)
@propagate_inbounds Base.setindex!(h::MortonArray, val, i, j, k) = setindex!(h.underlying_data, val, morton_encode3d(i, j, k, h.min_axis)...)
@propagate_inbounds Base.lastindex(h::MortonArray)               = lastindex(h.underlying_data)
@propagate_inbounds Base.lastindex(h::MortonArray, dim)          = lastindex(h.underlying_data, dim)

Base.size(h::MortonArray)      = h.underlying_size
Base.size(h::MortonArray, dim) = h.underlying_size[dim]

function MortonArray(FT, arch, underlying_size)
    Nx, Ny, Nz = underlying_size

    Nx2 = Base.nextpow(2, Nx)
    Ny2 = Base.nextpow(2, Ny)
    Nz2 = Base.nextpow(2, Nz)

    underlying_data  = zeros(FT, arch, Nx * Ny * Nz)

    min_axis = min(ndigits(Nx2, base = 2), ndigits(Ny2, base = 2), ndigits(Nz2, base = 2))

    return MortonArray{FT}(underlying_data, min_axis, underlying_size)
end

Adapt.adapt_structure(to, mo::MortonArray) = MortonArray(Adapt.adapt(to, mo.underlying_data), mo.min_axis, mo.underlying_size)
"""
    function morton_encode3d(i, j, k, min_axis)

returns the encoded morton index corresponding to a 3D cartesian index (i, j, k).
`min_axis` is the minimum between the number of bits of the smallest powers
of 2 larger than the data size
"""
function morton_encode3d(i, j, k, min_axis)
	i = i - 1
	j = j - 1
	k = k - 1

    d = 0
    pos = 0
    for t in 0:min_axis-1
        a = i & 0x1
        b = j & 0x1
		c = k & 0x1
        i = i >> 1
        j = j >> 1
		k = k >> 1
        temp = ((c<<2)|(b<<1)|a)
        d |= temp << pos
        pos = pos + 3
	end
	d |= (i | j | k) << pos

	# now we have that
	# d = i + Nx * (j + Ny * k)

	return d+1
end
