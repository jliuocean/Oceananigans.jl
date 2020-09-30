import Oceananigans: tupleit

#####
##### Some utilities for tupling
#####

tupleit(t::Tuple) = t
tupleit(a::AbstractArray) = Tuple(a)
tupleit(nt) = tuple(nt)

parenttuple(obj) = Tuple(f.data.parent for f in obj)

@inline datatuple(obj::Nothing) = nothing
@inline datatuple(obj::AbstractArray) = obj
@inline datatuple(obj::Tuple) = Tuple(datatuple(o) for o in obj)
@inline datatuple(obj::NamedTuple) = NamedTuple{propertynames(obj)}(datatuple(o) for o in obj)
@inline datatuples(objs...) = (datatuple(obj) for obj in objs)
