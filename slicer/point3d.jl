module point3d

using Printf
using LinearAlgebra

export Point3D, Point3DCache, translate!, distFromPoint

# A simple immutable 3D point.
struct Point3D
    values::NTuple{3, Float64}
end

# Constructors
function Point3D(x::Real, y::Real, z::Real)
    return Point3D((Float64(x), Float64(y), Float64(z)))
end

function Point3D(coords::AbstractVector{<:Real})
    if length(coords) < 3
        error("Expected at least 3 coordinates.")
    end
    return Point3D(coords[1], coords[2], coords[3])
end

# Allow iteration over coordinates.
function Base.iterate(p::Point3D, state=1)
    state > 3 && return nothing
    return (p.values[state], state+1)
end

Base.length(p::Point3D) = 3

# Indexing: get coordinate i.
Base.getindex(p::Point3D, i::Int) = p.values[i]

# Show string.
function Base.show(io::IO, p::Point3D)
    print(io, @sprintf("<Point3D: [%.3f, %.3f, %.3f]>", p[1], p[2], p[3]))
end

# Since Point3D is immutable, translation returns a new point.
function translate!(p::Point3D, offset::NTuple{3, Float64})
    return Point3D(p[1] + offset[1], p[2] + offset[2], p[3] + offset[3])
end

# Euclidean distance between two points.
function distFromPoint(p::Point3D, q::Point3D)
    dx = p[1] - q[1]
    dy = p[2] - q[2]
    dz = p[3] - q[3]
    return sqrt(dx^2 + dy^2 + dz^2)
end

# A mutable cache for points.
mutable struct Point3DCache
    point_hash::Dict{NTuple{3, Float64}, Point3D}
    minx::Float64
    miny::Float64
    minz::Float64
    maxx::Float64
    maxy::Float64
    maxz::Float64
end

function Point3DCache()
    return Point3DCache(Dict{NTuple{3, Float64}, Point3D}(), 9e99, 9e99, 9e99, -9e99, -9e99, -9e99)
end

function rehash!(cache::Point3DCache)
    old_hash = copy(cache.point_hash)
    new_hash = Dict{NTuple{3, Float64}, Point3D}()
    for pt in values(old_hash)
        key = (round(pt[1], digits=4), round(pt[2], digits=4), round(pt[3], digits=4))
        new_hash[key] = pt
    end
    cache.point_hash = new_hash
end

function translate!(cache::Point3DCache, offset::NTuple{3, Float64})
    cache.minx += offset[1]
    cache.miny += offset[2]
    cache.minz += offset[3]
    cache.maxx += offset[1]
    cache.maxy += offset[2]
    cache.maxz += offset[3]
    for pt in values(cache.point_hash)
        newpt = translate!(pt, offset)
        key = (round(newpt[1], digits=4), round(newpt[2], digits=4), round(newpt[3], digits=4))
        cache.point_hash[key] = newpt
    end
    rehash!(cache)
end

function add(cache::Point3DCache, x::Real, y::Real, z::Real)
    key = (round(x, digits=4), round(y, digits=4), round(z, digits=4))
    if haskey(cache.point_hash, key)
        return cache.point_hash[key]
    end
    pt = Point3D(x, y, z)
    cache.point_hash[key] = pt
    if x < cache.minx; cache.minx = x; end
    if x > cache.maxx; cache.maxx = x; end
    if y < cache.miny; cache.miny = y; end
    if y > cache.maxy; cache.maxy = y; end
    if z < cache.minz; cache.minz = z; end
    if z > cache.maxz; cache.maxz = z; end
    return pt
end

function Base.iterate(cache::Point3DCache, state=nothing)
    return iterate(values(cache.point_hash), state)
end

function get_volume(cache::Point3DCache)
    return (cache.minx, cache.miny, cache.minz, cache.maxx, cache.maxy, cache.maxz)
end

end # module point3d
