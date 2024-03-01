module Architectures

export AbstractArchitecture
export CPU, GPU, MultiGPU
export device, architecture, array_type, on_architecture, unified_array, device_copy_to!

using CUDA
using KernelAbstractions
using Adapt
using OffsetArrays

"""
    AbstractArchitecture

Abstract supertype for architectures supported by Oceananigans.
"""
abstract type AbstractArchitecture end

"""
    CPU <: AbstractArchitecture

Run Oceananigans on one CPU node. Uses multiple threads if the environment
variable `JULIA_NUM_THREADS` is set.
"""
struct CPU <: AbstractArchitecture end

"""
    GPU <: AbstractArchitecture

Run Oceananigans on a single NVIDIA CUDA GPU.
"""
struct GPU <: AbstractArchitecture end

#####
##### These methods are extended in DistributedComputations.jl
#####

device(::CPU) = KernelAbstractions.CPU()
device(::GPU) = CUDA.CUDABackend(; always_inline=true)

architecture() = nothing
architecture(::Number) = nothing
architecture(::Array) = CPU()
architecture(::CuArray) = GPU()
architecture(a::SubArray) = architecture(parent(a))
architecture(a::OffsetArray) = architecture(parent(a))

"""
    child_architecture(arch)

Return `arch`itecture of child processes.
On single-process, non-distributed systems, return `arch`.
"""
child_architecture(arch) = arch

array_type(::CPU) = Array
array_type(::GPU) = CuArray

on_architecture(::CPU, a::Array)   = a
on_architecture(::CPU, a::CuArray) = Array(a)
on_architecture(::GPU, a::Array)   = CuArray(a)
on_architecture(::GPU, a::CuArray) = a

on_architecture(::CPU, a::BitArray) = a
on_architecture(::GPU, a::BitArray) = CuArray(a)

on_architecture(::GPU, a::SubArray{<:Any, <:Any, <:CuArray}) = a
on_architecture(::CPU, a::SubArray{<:Any, <:Any, <:CuArray}) = Array(a)

on_architecture(::GPU, a::SubArray{<:Any, <:Any, <:Array}) = CuArray(a)
on_architecture(::CPU, a::SubArray{<:Any, <:Any, <:Array}) = a

on_architecture(::CPU, a::AbstractRange) = a
on_architecture(::CPU, ::Nothing)   = nothing
on_architecture(::CPU, a::Number)   = a
on_architecture(::CPU, a::Function) = a

on_architecture(::GPU, a::AbstractRange) = a
on_architecture(::GPU, ::Nothing)   = nothing
on_architecture(::GPU, a::Number)   = a
on_architecture(::GPU, a::Function) = a

on_architecture(arch::CPU, a::OffsetArray) = OffsetArray(on_architecture(arch, a.parent), a.offsets...)
on_architecture(arch::GPU, a::OffsetArray) = OffsetArray(on_architecture(arch, a.parent), a.offsets...)

cpu_architecture(::CPU) = CPU()
cpu_architecture(::GPU) = CPU()

unified_array(::CPU, a) = a
unified_array(::GPU, a) = a

function unified_array(::GPU, arr::AbstractArray) 
    buf = Mem.alloc(Mem.Unified, sizeof(arr))
    vec = unsafe_wrap(CuArray{eltype(arr),length(size(arr))}, convert(CuPtr{eltype(arr)}, buf), size(arr))
    finalizer(vec) do _
        Mem.free(buf)
    end
    copyto!(vec, arr)
    return vec
end

## GPU to GPU copy of contiguous data
@inline function device_copy_to!(dst::CuArray, src::CuArray; async::Bool = false) 
    n = length(src)
    context!(context(src)) do
        GC.@preserve src dst begin
            unsafe_copyto!(pointer(dst, 1), pointer(src, 1), n; async)
        end
    end
    return dst
end
 
@inline device_copy_to!(dst::Array, src::Array; kw...) = Base.copyto!(dst, src)

@inline unsafe_free!(a::CuArray) = CUDA.unsafe_free!(a)
@inline unsafe_free!(a)          = nothing

# Convert arguments to GPU-compatible types
@inline convert_args(::CPU, args) = args
@inline convert_args(::GPU, args) = CUDA.cudaconvert(args)
@inline convert_args(::GPU, args::Tuple) = map(CUDA.cudaconvert, args)

end # module

