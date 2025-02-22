module line_segment3d

export LineSegment3D, LineSegment3DCache, segment_length, translate!, get_seg, endpoint_segments, add!

using ..point3d: Point3D, distFromPoint, translate!

# A 3D line segment defined by two endpoints.
mutable struct LineSegment3D
    p1::Point3D
    p2::Point3D
    count::Int
end

function LineSegment3D(p1::Point3D, p2::Point3D)
    if p1 > p2
        p1, p2 = p2, p1
    end
    return LineSegment3D(p1, p2, 1)
end

Base.length(seg::LineSegment3D) = 2

function Base.iterate(seg::LineSegment3D, state=1)
    if state == 1
        return (seg.p1, 2)
    elseif state == 2
        return (seg.p2, 3)
    else
        return nothing
    end
end

function Base.getindex(seg::LineSegment3D, i::Int)
    if i == 1
        return seg.p1
    elseif i == 2
        return seg.p2
    else
        error("Index $(i) out of bounds for LineSegment3D")
    end
end

function Base.hash(seg::LineSegment3D, h::UInt)
    return hash((seg.p1, seg.p2), h)
end

function Base.isless(seg1::LineSegment3D, seg2::LineSegment3D)
    if seg1.p1 != seg2.p1
        return seg1.p1 < seg2.p1
    else
        return seg1.p2 < seg2.p2
    end
end

function Base.show(io::IO, seg::LineSegment3D)
    print(io, "<LineSegment3D: (", seg.p1, " - ", seg.p2, ")>")
end

# Translate a line segment (again, real code would reconstruct the points if they are immutable).
function translate!(seg::LineSegment3D, offset::NTuple{3,Float64})
    seg.p1 = translate!(seg.p1, offset)
    seg.p2 = translate!(seg.p2, offset)
    return seg
end

# Compute the Euclidean length of the segment.
function segment_length(seg::LineSegment3D)
    return distFromPoint(seg.p1, seg.p2)
end

# A cache for line segments.
mutable struct LineSegment3DCache
    seghash::Dict{Any, LineSegment3D}
    endhash::Dict{Any, Vector{LineSegment3D}}
end

function LineSegment3DCache()
    return LineSegment3DCache(Dict(), Dict())
end

function _add_endpoint!(cache::LineSegment3DCache, p, seg::LineSegment3D)
    if !haskey(cache.endhash, p)
        cache.endhash[p] = LineSegment3D[]
    end
    push!(cache.endhash[p], seg)
end

function rehash!(cache::LineSegment3DCache)
    new_seghash = Dict{Any, LineSegment3D}()
    new_endhash = Dict{Any, Vector{LineSegment3D}}()
    for seg in values(cache.seghash)
        key = (seg.p1, seg.p2)
        new_seghash[key] = seg
        for p in (seg.p1, seg.p2)
            if !haskey(new_endhash, p)
                new_endhash[p] = LineSegment3D[]
            end
            push!(new_endhash[p], seg)
        end
    end
    cache.seghash = new_seghash
    cache.endhash = new_endhash
    return cache
end

function translate!(cache::LineSegment3DCache, offset::NTuple{3,Float64})
    for seg in values(cache.seghash)
        translate!(seg, offset)
    end
    rehash!(cache)
end

function endpoint_segments(cache::LineSegment3DCache, p)
    return get(cache.endhash, p, LineSegment3D[])
end

function get_seg(cache::LineSegment3DCache, p1, p2)
    key = p1 < p2 ? (p1, p2) : (p2, p1)
    return get(cache.seghash, key, nothing)
end

function add!(cache::LineSegment3DCache, p1, p2)
    key = p1 < p2 ? (p1, p2) : (p2, p1)
    if haskey(cache.seghash, key)
        seg = cache.seghash[key]
        seg.count += 1
        return seg
    end
    seg = LineSegment3D(p1, p2)
    cache.seghash[key] = seg
    _add_endpoint!(cache, p1, seg)
    _add_endpoint!(cache, p2, seg)
    return seg
end

function Base.iterate(cache::LineSegment3DCache, state=nothing)
    return iterate(values(cache.seghash), state)
end

Base.length(cache::LineSegment3DCache) = length(cache.seghash)

end # module line_segment3d
