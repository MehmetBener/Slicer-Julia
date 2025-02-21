module facet3d

export Facet3D, Facet3DCache, get_facet, vertex_facets, edge_facets

using ..point3d: Point3D
using ..line_segment3d: LineSegment3D

mutable struct Facet3D
    vertices::Base.Vector{Point3D}   # or Array{Point3D,1}
    normal::Base.Vector{Float64}       # or Array{Float64,1}
    count::Int
end

"""
    Facet3D(v1, v2, v3, norm)

Construct a Facet3D from three 3D vectors `v1`, `v2`, `v3` and a normal vector `norm`.
All inputs must be 3-element arrays (or tuples) of real numbers.
"""
function Facet3D(v1, v2, v3, norm)
    # Verify each input is a 3D vector.
    for x in (v1, v2, v3, norm)
        if length(x) != 3
            throw(TypeError("Expected 3D vector."))
        end
        for y in x
            if !(y isa Real)
                throw(TypeError("Expected 3D vector."))
            end
        end
    end
    verts = [Point3D(v1), Point3D(v2), Point3D(v3)]
    # Reorder vertices in a normalized order.
    while verts[1] > verts[2] || verts[1] > verts[3]
        verts = vcat(verts[2:end], [verts[1]])
    end
    # Call the default constructor (automatically generated) with (vertices, norm, count).
    f = Facet3D(verts, Array{Float64,1}(norm), 1)
    fixup_normal!(f)
    return f
end

Base.length(f::Facet3D) = 4

function Base.getindex(f::Facet3D, idx::Int)
    lst = vcat(f.vertices, [f.norm])
    return lst[idx]
end

function Base.hash(f::Facet3D, h::UInt)
    return hash((f.vertices, f.norm), h)
end

# Comparison for sorting (using Base.isless).
function Base.isless(a::Facet3D, b::Facet3D)
    cl1 = [ sort([v[i] for v in a.vertices]) for i in 1:3 ]
    cl2 = [ sort([v[i] for v in b.vertices]) for i in 1:3 ]
    for i in reverse(1:3)
        for (c1, c2) in zip(cl1[i], cl2[i])
            if c1 != c2
                return c1 < c2
            end
        end
    end
    return false
end

"""
    format(f::Facet3D, fmt::AbstractString)

Return a formatted string for `f` using format specifiers:
- If `fmt` contains `"a"`, vertices are comma–separated in square brackets.
- If `fmt` contains `"s"`, vertices are space–separated.
- Otherwise, a default `" - "` separator is used.
"""
function format(f::Facet3D, fmt::AbstractString)
    pfx = ""
    sep = " - "
    sfx = ""
    if occursin("a", fmt)
        pfx = "["
        sep = ", "
        sfx = "]"
    elseif occursin("s", fmt)
        pfx = ""
        sep = " "
        sfx = ""
    end
    ifx = join([string(f[i]) for i in 1:3], sep)
    return pfx * ifx * sfx
end

#------ Internal Helper Functions -------------------------------------------

function _side_of_line(line, pt)
    # line: tuple of two 2D points; pt: 2D point.
    return (line[2][1] - line[1][1]) * (pt[2] - line[1][2]) -
           (line[2][2] - line[1][2]) * (pt[1] - line[1][1])
end

function _clockwise_line(line, pt)
    if _side_of_line(line, pt) < 0
        return (line[2], line[1])
    else
        return (line[1], line[2])
    end
end

function _shoestring_algorithm(path)
    if path[1] == path[end]
        path = path[2:end]
    end
    out = 0.0
    for (p1, p2) in zip(path, vcat(path[2:end], [path[1]]))
        out += p1[1] * p2[2]
        out -= p2[1] * p1[2]
    end
    return out
end

function _z_intercept(p1, p2, z)
    if (p1[3] > z && p2[3] > z) || (p1[3] < z && p2[3] < z) || (p1[3] == z && p2[3] == z)
        return nothing
    end
    u = (z - p1[3])/(p2[3] - p1[3])
    delta = [p2[i] - p1[i] for i in 1:3]
    return [delta[i]*u + p1[i] for i in 1:3]
end

#------ Methods on Facet3D ----------------------------------------------------

function translate!(f::Facet3D, offset)
    for a in 1:3
        for v in f.vertices
            v[a] += offset[a]
        end
    end
end

function get_footprint(f::Facet3D, z::Union{Nothing,Float64}=nothing)
    if z === nothing
        path = [v[1:2] for v in f.vertices]
    else
        opath = vcat(f.vertices, [f.vertices[1]])
        path = []
        for (v1, v2) in zip(opath[1:end-1], opath[2:end])
            if v1[3] > z
                push!(path, v1[1:2])
            end
            if (v1[3] > z && v2[3] < z) || (v1[3] < z && v2[3] > z)
                icept = _z_intercept(v1, v2, z)
                if icept !== nothing
                    push!(path, icept[1:2])
                end
            end
        end
    end
    if isempty(path)
        return nothing
    end
    a = _shoestring_algorithm(path)
    if a == 0
        return nothing
    end
    if a > 0
        path = reverse(path)
    end
    return path
end

function overhang_angle(f::Facet3D)
    vert = Array{Float64,1}([0.0, 0.0, -1.0])
    ang = vert.angle(f.norm) * 180.0 / π
    return 90.0 - ang
end

function intersects_z(f::Facet3D, z::Float64)
    zs = [v[3] for v in f.vertices]
    return z ≥ minimum(zs) && z ≤ maximum(zs)
end

function z_range(f::Facet3D)
    zs = [v[3] for v in f.vertices]
    return (minimum(zs), maximum(zs))
end

function slice_at_z(f::Facet3D, z::Float64; quanta::Float64=1e-3)
    z = floor(z / quanta + 0.5) * quanta + quanta/2
    minz, maxz = z_range(f)
    if z < minz || z > maxz
        return nothing
    end
    if hypot(f.norm[1], f.norm[2]) < 1e-6
        return nothing
    end
    norm2d = f.norm[1:2]
    vl = f.vertices
    vl2 = vcat(vl[2:end], [vl[1]])
    for (v1, v2) in zip(vl, vl2)
        if v1[3] == z && v2[3] == z
            line = ((v1[1], v1[2]), (v2[1], v2[2]))
            pt = (v1[1] + norm2d[1], v1[2] + norm2d[2])
            return _clockwise_line(line, pt)
        end
    end
    if z == minimum([v[3] for v in vl]) || z == maximum([v[3] for v in vl])
        return nothing
    end
    vl3 = vcat(vl2[2:end], [vl2[1]])
    for (v1, v2, v3) in zip(vl, vl2, vl3)
        if v2[3] == z
            u = (z - v1[3])/(v3[3] - v1[3])
            px = v1[1] + u*(v3[1]-v1[1])
            py = v1[2] + u*(v3[2]-v1[2])
            line = ((v2[1], v2[2]), (px, py))
            pt = (v2[1] + norm2d[1], v2[2] + norm2d[2])
            return _clockwise_line(line, pt)
        end
    end
    isects = Any[]
    for (v1, v2) in zip(vl, vl2)
        if v1[3] == v2[3]
            continue
        end
        u = (z - v1[3])/(v2[3]-v1[3])
        if u ≥ 0.0 && u ≤ 1.0
            push!(isects, (v1, v2))
        end
    end
    if length(isects) < 2
        return nothing
    end
    (p1, p2) = isects[1]
    (p3, p4) = isects[2]
    u1 = (z - p1[3])/(p2[3]-p1[3])
    u2 = (z - p3[3])/(p4[3]-p3[3])
    px = p1[1] + u1*(p2[1]-p1[1])
    py = p1[2] + u1*(p2[2]-p1[2])
    qx = p3[1] + u2*(p4[1]-p3[1])
    qy = p3[2] + u2*(p4[2]-p3[2])
    line = ((px, py), (qx, qy))
    pt = (px + norm2d[1], py + norm2d[2])
    return _clockwise_line(line, pt)
end

function is_clockwise(f::Facet3D)
    v1 = Array{Float64,1}(f.vertices[2] - f.vertices[1])
    v2 = Array{Float64,1}(f.vertices[3] - f.vertices[1])
    return dot(f.norm, cross(v1, v2)) < 0
end

function fixup_normal!(f::Facet3D)
    if norm(f.norm) > 0
        if is_clockwise(f)
            f.vertices = [f.vertices[1], f.vertices[3], f.vertices[2]]
        end
    else
        v1 = Vector(f.vertices[3] - f.vertices[1])
        v2 = Vector(f.vertices[2] - f.vertices[1])
        f.norm = cross(v1, v2)
        if norm(f.norm) > 1e-6
            f.norm = normalize(f.norm)
        end
    end
end

mutable struct Facet3DCache
    vertex_hash::Dict{Any, Vector{Any}}
    edge_hash::Dict{Any, Vector{Any}}
    facet_hash::Dict{Any, Any}
end

function Facet3DCache()
    return Facet3DCache(Dict(), Dict(), Dict())
end

function rehash!(cache::Facet3DCache)
    oldhash = deepcopy(cache.facet_hash)
    cache.vertex_hash = Dict()
    cache.edge_hash = Dict()
    cache.facet_hash = Dict()
    for facet in values(oldhash)
        _rehash_facet!(cache, facet)
    end
end

function _rehash_facet!(cache::Facet3DCache, facet::Facet3D)
    pts = (facet[1], facet[2], facet[3])
    cache.facet_hash[pts] = facet
    _add_edge!(cache, pts[1], pts[2], facet)
    _add_edge!(cache, pts[2], pts[3], facet)
    _add_edge!(cache, pts[3], pts[1], facet)
    _add_vertex!(cache, pts[1], facet)
    _add_vertex!(cache, pts[2], facet)
    _add_vertex!(cache, pts[3], facet)
end

function translate!(cache::Facet3DCache, offset)
    for facet in values(cache.facet_hash)
        translate!(facet, offset)
    end
    rehash!(cache)
end

function _add_vertex!(cache::Facet3DCache, pt, facet::Facet3D)
    if !haskey(cache.vertex_hash, pt)
        cache.vertex_hash[pt] = Any[]
    end
    push!(cache.vertex_hash[pt], facet)
end

function _add_edge!(cache::Facet3DCache, p1, p2, facet::Facet3D)
    edge = (p1 > p2) ? (p1, p2) : (p2, p1)
    if !haskey(cache.edge_hash, edge)
        cache.edge_hash[edge] = Any[]
    end
    push!(cache.edge_hash[edge], facet)
end

function vertex_facets(cache::Facet3DCache, pt)
    return Base.get(cache.vertex_hash, pt, Any[])
end

function edge_facets(cache::Facet3DCache, p1, p2)
    edge = (p1 > p2) ? (p1, p2) : (p2, p1)
    return Base.get(cache.edge_hash, edge, Any[])
end

# Renamed from "get" to "get_facet" to avoid conflict with Base.get.
function get_facet(cache::Facet3DCache, p1, p2, p3)
    key = (p1, p2, p3)
    return Base.get(cache.facet_hash, key, nothing)
end

function add!(cache::Facet3DCache, p1, p2, p3, norm)
    key = (p1, p2, p3)
    if haskey(cache.facet_hash, key)
        facet = cache.facet_hash[key]
        facet.count += 1
        return facet
    end
    facet = Facet3D(p1, p2, p3, norm)
    cache.facet_hash[key] = facet
    _add_edge!(cache, p1, p2, facet)
    _add_edge!(cache, p2, p3, facet)
    _add_edge!(cache, p3, p1, facet)
    _add_vertex!(cache, p1, facet)
    _add_vertex!(cache, p2, facet)
    _add_vertex!(cache, p3, facet)
    return facet
end

function sorted(cache::Facet3DCache)
    vals = collect(values(cache.facet_hash))
    return sort(vals)
end

Base.iterate(cache::Facet3DCache) = iterate(values(cache.facet_hash))
Base.length(cache::Facet3DCache) = length(cache.facet_hash)

end  # module Facet3DModule
