module stl_data

# Example includes to pull in your needed modules
include(joinpath(@__DIR__, "point3d.jl"))
using .point3d: Point3DCache, Point3D, translate!

include(joinpath(@__DIR__, "vector.jl"))
using .vector: Vector, dot, cross

include(joinpath(@__DIR__, "line_segment3d.jl"))
using .line_segment3d: LineSegment3DCache, LineSegment3D, translate!

include(joinpath(@__DIR__, "facet3d.jl"))
using .facet3d: Facet3DCache, Facet3D, translate!

include(joinpath(@__DIR__, "text_thermometer.jl"))
using .text_thermometer: TextThermometer, set_target!, update!, clear!

import Base: read, stat, position, open, parse, occursin

struct StlEndOfFileException <: Exception
    msg::String
end

struct StlMalformedLineException <: Exception
    msg::String
end

mutable struct StlData
    points::Point3DCache
    edges::LineSegment3DCache
    facets::Facet3DCache
    filename::String
    dupe_faces::Vector{Any}
    dupe_edges::Vector{Any}
    hole_edges::Vector{Any}
    layer_facets::Dict{Int, Vector{Any}}
end

function StlData()
    StlData(
        Point3DCache(),
        LineSegment3DCache(),
        Facet3DCache(),
        "",
        Any[],
        Any[],
        Any[],
        Dict{Int, Vector{Any}}()
    )
end

function _read_ascii_line(self::StlData, f::IO; watchwords::Union{Nothing,String}=nothing)
    line = readline(f)
    if isempty(line)
        # Could be blank or just whitespace
        return []
    end
    local txt = lowercase(strip(line))
    if txt == ""
        return []
    end
    if startswith(txt, "endsolid")
        throw(StlEndOfFileException("Encountered 'endsolid'"))
    end
    words = split(txt)
    if watchwords !== nothing
        expected = split(lowercase(watchwords))
        if length(words) < length(expected)
            throw(StlMalformedLineException("Malformed line: expected '$watchwords', got '$line'"))
        end
        for i in eachindex(expected)
            if words[i] != expected[i]
                throw(StlMalformedLineException("Malformed line: expected '$watchwords', got '$line'"))
            end
        end
        # Return numeric parts
        return [parse(Float64, w) for w in words[(length(expected)+1):end] if occursin(r"[0-9\-\.eE]", w)]
    else
        # No watchwords; just parse floats
        return [parse(Float64, w) for w in words if occursin(r"[0-9\-\.eE]", w)]
    end
end

function _read_ascii_vertex(self::StlData, f::IO)
    coords = _read_ascii_line(self, f; watchwords="vertex")
    return add(self.points, coords[1], coords[2], coords[3])
end

function quantz(self::StlData, pt, quanta::Float64=1e-3)
    x, y, z = pt
    zq = floor(z/quanta + 0.5)*quanta
    return (x, y, zq)
end

function _read_ascii_facet(self::StlData, f::IO; quanta::Float64=1e-3)
    while true
        try
            normal = _read_ascii_line(self, f; watchwords="facet normal")
            _ = _read_ascii_line(self, f; watchwords="outer loop")
            vertex1 = _read_ascii_vertex(self, f)
            vertex2 = _read_ascii_vertex(self, f)
            vertex3 = _read_ascii_vertex(self, f)
            _ = _read_ascii_line(self, f; watchwords="endloop")
            _ = _read_ascii_line(self, f; watchwords="endfacet")

            if quanta > 0
                vertex1 = quantz(self, vertex1, quanta)
                vertex2 = quantz(self, vertex2, quanta)
                vertex3 = quantz(self, vertex3, quanta)
                if vertex1 == vertex2 || vertex2 == vertex3 || vertex3 == vertex1
                    continue
                end
                vec1 = Vector(vertex1) - Vector(vertex2)
                vec2 = Vector(vertex3) - Vector(vertex2)
                if angle(vec1, vec2) < 1e-8
                    continue
                end
            end
        catch e
            if e isa StlEndOfFileException
                return nothing
            elseif e isa EOFError
                return nothing
            elseif e isa StlMalformedLineException
                # skip bad line
                continue
            else
                rethrow(e)
            end
        end

        add(self.edges, vertex1, vertex2)
        add(self.edges, vertex2, vertex3)
        add(self.edges, vertex3, vertex1)
        return add(self.facets, vertex1, vertex2, vertex3, normal)
    end
end

function _read_binary_facet(self::StlData, f::IO; quanta::Float64=1e-3)
    data = read(f, Float32, 12)  # normal + 3 vertices
    if length(data) < 12
        # likely EOF
        return nothing
    end
    _ = read(f, UInt16)  # attribute byte count
    normal = data[1:3]
    vertex1 = (Float64(data[4]), Float64(data[5]), Float64(data[6]))
    vertex2 = (Float64(data[7]), Float64(data[8]), Float64(data[9]))
    vertex3 = (Float64(data[10]), Float64(data[11]), Float64(data[12]))

    if quanta > 0
        vertex1 = quantz(self, vertex1, quanta)
        vertex2 = quantz(self, vertex2, quanta)
        vertex3 = quantz(self, vertex3, quanta)
        if vertex1 == vertex2 || vertex2 == vertex3 || vertex3 == vertex1
            return nothing
        end
        vec1 = Vector(vertex1) - Vector(vertex2)
        vec2 = Vector(vertex3) - Vector(vertex2)
        if angle(vec1, vec2) < 1e-8
            return nothing
        end
    end

    v1 = add(self.points, vertex1[1], vertex1[2], vertex1[3])
    v2 = add(self.points, vertex2[1], vertex2[2], vertex2[3])
    v3 = add(self.points, vertex3[1], vertex3[2], vertex3[3])

    add(self.edges, v1, v2)
    add(self.edges, v2, v3)
    add(self.edges, v3, v1)
    return add(self.facets, v1, v2, v3, normal)
end

function read_file(self::StlData, filename::String)
    self.filename = filename
    println("Loading model from $filename")
    file_size = stat(filename).size
    open(filename, "r") do f
        header = read(f, UInt8, 80)
        if isempty(header)
            return
        end
        header_str = String(header)
        # Check if ASCII or binary
        if startswith(lowercase(header_str[1:min(end,6)]), "solid")
            # ASCII attempt
            thermo = TextThermometer(target=file_size)
            seek(f, 0)
            while !eof(f)
                pos0 = position(f)
                facet = _read_ascii_facet(self, f)
                if facet === nothing
                    break
                end
                update!(thermo, position(f))
                if position(f) == pos0
                    # Means no progress; break out to avoid infinite loop
                    break
                end
            end
            clear!(thermo)
        else
            # Binary
            chunk = read(f, UInt8, 4)
            facets_count = reinterpret(UInt32, chunk)[1]
            thermo = TextThermometer(target=facets_count)
            for n in 1:facets_count
                update!(thermo, n)
                _ = _read_binary_facet(self, f)
            end
            clear!(thermo)
        end
    end
end

function _write_ascii_file(self::StlData, filename::String)
    open(filename, "w") do f
        write(f, "solid Model\n")
        for facet in sorted(self.facets)
            v0 = facet[1]
            v1 = facet[2]
            v2 = facet[3]
            nrm = facet[4]
            s = @sprintf("  facet normal %s\n    outer loop\n      vertex %s\n      vertex %s\n      vertex %s\n    endloop\n  endfacet\n",
                         string(nrm), string(v0), string(v1), string(v2))
            write(f, s)
        end
        write(f, "endsolid Model\n")
    end
end

function _write_binary_file(self::StlData, filename::String)
    open(filename, "w") do f
        header = lpad("Binary STL Model", 80)
        write(f, header)
        num_facets = length(self.facets)
        write(f, UInt32(num_facets))
        # Implementation left as an exercise...
    end
end

function write_file(self::StlData, filename::String; binary::Bool=false)
    if binary
        _write_binary_file(self, filename)
    else
        _write_ascii_file(self, filename)
    end
end

function _check_manifold_duplicate_faces(self::StlData)
    return [f for f in values(self.facets.facet_hash) if f.count != 1]
end

function _check_manifold_hole_edges(self::StlData)
    return [e for e in values(self.edges.seghash) if e.count == 1]
end

function _check_manifold_excess_edges(self::StlData)
    return [e for e in values(self.edges.seghash) if e.count > 2]
end

function check_manifold(self::StlData; verbose::Bool=false)
    is_manifold = true
    self.dupe_faces = _check_manifold_duplicate_faces(self)
    for face in self.dupe_faces
        is_manifold = false
        if verbose
            println("NON-MANIFOLD DUPLICATE FACE: ", face)
        end
    end
    self.hole_edges = _check_manifold_hole_edges(self)
    for edge in self.hole_edges
        is_manifold = false
        if verbose
            println("NON-MANIFOLD HOLE EDGE: ", edge)
        end
    end
    self.dupe_edges = _check_manifold_excess_edges(self)
    for edge in self.dupe_edges
        is_manifold = false
        if verbose
            println("NON-MANIFOLD DUPLICATE EDGE: ", edge)
        end
    end
    return is_manifold
end

function center(self::StlData, cp::NTuple{3,Float64})
    cx = (self.points.minx + self.points.maxx)/2
    cy = (self.points.miny + self.points.maxy)/2
    cz = (self.points.minz + self.points.maxz)/2
    translate(self, (cp[1] - cx, cp[2] - cy, cp[3] - cz))
end

function translate(self::StlData, offset::NTuple{3,Float64})
    translate!(self.points, offset)
    translate!(self.edges, offset)
    translate!(self.facets, offset)
end

function assign_layers(self::StlData, layer_height::Float64)
    self.layer_facets = Dict{Int, Vector{Any}}()
    for facet in values(self.facets.facet_hash)
        minz, maxz = facet.z_range()
        minl = floor(Int, minz / layer_height + 0.01)
        maxl = ceil(Int, maxz / layer_height - 0.01)
        for layer in minl:maxl
            if !haskey(self.layer_facets, layer)
                self.layer_facets[layer] = Any[]
            end
            push!(self.layer_facets[layer], facet)
        end
    end
end

function get_layer_facets(self::StlData, layer::Int)
    return get(self.layer_facets, layer, Any[])
end

function slice_at_z(self::StlData, z::Float64, layer_h::Float64)
    ptkey(pt) = @sprintf("%.3f, %.3f", pt[1], pt[2])
    layer = floor(Int, z / layer_h + 0.5)
    paths = Dict{String, Vector{Vector{Any}}}()
    for facet in get_layer_facets(self, layer)
        line = facet.slice_at_z(z)
        if line === nothing
            continue
        end
        path = collect(line)
        key1 = ptkey(path[1])
        key2 = ptkey(last(path))
        if haskey(paths, key2) && !isempty(paths[key2]) && (last(paths[key2][1]) == path[1])
            continue
        end
        if !haskey(paths, key1)
            paths[key1] = Vector{Vector{Any}}()
        end
        push!(paths[key1], path)
    end

    outpaths = Any[]
    deadpaths = Any[]
    while !isempty(paths)
        k = first(keys(paths))
        arr = popfirst!(paths, k)
        path = arr[1]
        if isempty(arr)
            delete!(paths, k)
        end
        key1 = ptkey(path[1])
        key2 = ptkey(last(path))
        if key1 == key2
            push!(outpaths, path)
            continue
        elseif haskey(paths, key2)
            opath = popfirst!(paths[key2])[1]
            if isempty(paths[key2])
                delete!(paths, key2)
            end
            append!(path, opath[2:end])
        elseif haskey(paths, key1)
            opath = popfirst!(paths[key1])[1]
            if isempty(paths[key1])
                delete!(paths, key1)
            end
            opath = reverse(opath)
            append!(opath, path[2:end])
            path = opath
        else
            push!(deadpaths, path)
            continue
        end
        key1 = ptkey(path[1])
        if !haskey(paths, key1)
            paths[key1] = Vector{Vector{Any}}()
        end
        push!(paths[key1], path)
    end
    if !isempty(deadpaths)
        println("\nIncomplete Polygon at z=$(z)")
    end
    return (outpaths, deadpaths)
end

end  # module stl_data
