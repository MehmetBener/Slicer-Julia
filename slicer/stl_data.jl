module stl_data

using .TextThermometer: TextThermometer
using .point3d: Point3DCache
using .vector: Vector
using .facet3d: Facet3DCache
using .line_segment3d: LineSegment3DCache

import Base: showerror

struct StlEndOfFileException <: Exception
    msg::String
end
showerror(io::IO, e::StlEndOfFileException) = print(io, e.msg)

struct StlMalformedLineException <: Exception
    msg::String
end
showerror(io::IO, e::StlMalformedLineException) = print(io, e.msg)

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
    return StlData(Point3DCache(), LineSegment3DCache(), Facet3DCache(), "",
                   Any[], Any[], Any[], Dict{Int, Vector{Any}}())
end

function _read_ascii_line(self::StlData, f::IO; watchwords::Union{Nothing, String}=nothing)
    line = readline(f)
    if line == ""
        throw(StlEndOfFileException("Reached end of file"))
    end
    words = split(lowercase(strip(line)))
    if isempty(words)
        return []
    end
    if words[1] == "endsolid"
        throw(StlEndOfFileException("Encountered 'endsolid'"))
    end
    argstart = 1
    if watchwords !== nothing
        expected = split(lowercase(watchwords))
        argstart = length(expected) + 1
        for i in eachindex(expected)
            if i > length(words) || words[i] != expected[i]
                throw(StlMalformedLineException("Malformed line: expected \"$watchwords\", got \"$line\""))
            end
        end
    end
    return [parse(Float64, val) for val in words[argstart:end]]
end

function _read_ascii_vertex(self::StlData, f::IO)
    point = _read_ascii_line(self, f; watchwords="vertex")
    return add!(self.points, point[1], point[2], point[3])
end

function quantz(self::StlData, pt, quanta::Float64=1e-3)
    x, y, z = pt
    zq = floor(z / quanta + 0.5) * quanta
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
            if quanta > 0.0
                vertex1 = quantz(self, vertex1, quanta)
                vertex2 = quantz(self, vertex2, quanta)
                vertex3 = quantz(self, vertex3, quanta)
                if vertex1 == vertex2 || vertex2 == vertex3 || vertex3 == vertex1
                    continue  # zero–area facet; skip to next facet
                end
                vec1 = Vector(vertex1) - Vector(vertex2)
                vec2 = Vector(vertex3) - Vector(vertex2)
                if vec1.angle(vec2) < 1e-8
                    continue  # zero–area facet; skip to next facet
                end
            end
        catch e
            if isa(e, StlEndOfFileException)
                return nothing
            elseif isa(e, StlMalformedLineException)
                continue  # Skip to next facet.
            else
                rethrow(e)
            end
        end
        add!(self.edges, vertex1, vertex2)
        add!(self.edges, vertex2, vertex3)
        add!(self.edges, vertex3, vertex1)
        return add!(self.facets, vertex1, vertex2, vertex3, normal)
    end
end

function _read_binary_facet(self::StlData, f::IO; quanta::Float64=1e-3)
    data = read(f, Float32, 12)
    _ = read(f, UInt16)
    normal = data[1:3]
    vertex1 = data[4:6]
    vertex2 = data[7:9]
    vertex3 = data[10:12]
    vertex1 = (Float64(vertex1[1]), Float64(vertex1[2]), Float64(vertex1[3]))
    vertex2 = (Float64(vertex2[1]), Float64(vertex2[2]), Float64(vertex2[3]))
    vertex3 = (Float64(vertex3[1]), Float64(vertex3[2]), Float64(vertex3[3]))
    if quanta > 0.0
        vertex1 = quantz(self, vertex1, quanta)
        vertex2 = quantz(self, vertex2, quanta)
        vertex3 = quantz(self, vertex3, quanta)
        if vertex1 == vertex2 || vertex2 == vertex3 || vertex3 == vertex1
            return nothing
        end
        vec1 = Vector(vertex1) - Vector(vertex2)
        vec2 = Vector(vertex3) - Vector(vertex2)
        if vec1.angle(vec2) < 1e-8
            return nothing
        end
    end
    v1 = add!(self.points, vertex1...)
    v2 = add!(self.points, vertex2...)
    v3 = add!(self.points, vertex3...)
    add!(self.edges, v1, v2)
    add!(self.edges, v2, v3)
    add!(self.edges, v3, v1)
    return add!(self.facets, v1, v2, v3, normal)
end

function read_file(self::StlData, filename::String)
    self.filename = filename
    println("Loading model")
    file_size = stat(filename).size
    open(filename, "r") do f
        header = read(f, UInt8, 80)
        if isempty(header)
            return  # End of file.
        end
        header_str = String(header)
        if startswith(lowercase(header_str[1:6]), "solid ") && (length(header_str) < 80)
            thermo = TextThermometer(file_size)
            while true
                facet = _read_ascii_facet(self, f)
                if facet === nothing
                    break
                end
                update!(thermo, position(f))
            end
            clear!(thermo)
        else
            chunk = read(f, UInt8, 4)
            facets_count = reinterpret(UInt32, chunk)[1]
            thermo = TextThermometer(Int(facets_count))
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
            # Assume facet is a tuple: (v0, v1, v2, normal)
            v0, v1, v2, norm = facet[1], facet[2], facet[3], facet[4]
            s = @sprintf("  facet normal %s\n    outer loop\n      vertex %s\n      vertex %s\n      vertex %s\n    endloop\n  endfacet\n",
                         string(norm), string(v0), string(v1), string(v2))
            write(f, s)
        end
        write(f, "endsolid Model\n")
    end
end

function _write_binary_file(self::StlData, filename::String)
    open(filename, "w") do f
        header = lpad("Binary STL Model", 80)
        write(f, header)
        num_facets = length(self.facets.facets)
        write(f, UInt32(num_facets))
        for facet in sorted(self.facets)
            norm = facet[4]
            v0, v1, v2 = facet[1], facet[2], facet[3]
            write(f, Float32(norm[1]))
            write(f, Float32(norm[2]))
            write(f, Float32(norm[3]))
            write(f, Float32(v0[1]))
            write(f, Float32(v0[2]))
            write(f, Float32(v0[3]))
            write(f, Float32(v1[1]))
            write(f, Float32(v1[2]))
            write(f, Float32(v1[3]))
            write(f, Float32(v2[1]))
            write(f, Float32(v2[2]))
            write(f, Float32(v2[3]))
            write(f, UInt16(0))
        end
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
    return [facet for facet in sorted(self.facets) if facet.count != 1]
end

function _check_manifold_hole_edges(self::StlData)
    return [edge for edge in self.edges.segments if edge.count == 1]
end

function _check_manifold_excess_edges(self::StlData)
    return [edge for edge in self.edges.segments if edge.count > 2]
end

function check_manifold(self::StlData; verbose::Bool=false)
    is_manifold = true
    self.dupe_faces = _check_manifold_duplicate_faces(self)
    for face in self.dupe_faces
        is_manifold = false
        println(@sprintf("NON-MANIFOLD DUPLICATE FACE! %s: %s", self.filename, string(face)))
    end
    self.hole_edges = _check_manifold_hole_edges(self)
    for edge in self.hole_edges
        is_manifold = false
        println(@sprintf("NON-MANIFOLD HOLE EDGE! %s: %s", self.filename, string(edge)))
    end
    self.dupe_edges = _check_manifold_excess_edges(self)
    for edge in self.dupe_edges
        is_manifold = false
        println(@sprintf("NON-MANIFOLD DUPLICATE EDGE! %s: %s", self.filename, string(edge)))
    end
    return is_manifold
end

get_facets(self::StlData) = self.facets
get_edges(self::StlData) = self.edges

function center(self::StlData, cp::Tuple{Float64,Float64,Float64})
    cx = (self.points.minx + self.points.maxx) / 2.0
    cy = (self.points.miny + self.points.maxy) / 2.0
    cz = (self.points.minz + self.points.maxz) / 2.0
    translate(self, (cp[1]-cx, cp[2]-cy, cp[3]-cz))
end

function translate(self::StlData, offset::Tuple{Float64,Float64,Float64})
    translate!(self.points, offset)
    translate!(self.edges, offset)
    translate!(self.facets, offset)
end

function assign_layers(self::StlData, layer_height::Float64)
    self.layer_facets = Dict{Int, Vector{Any}}()
    for facet in sorted(self.facets)
        minz, maxz = facet.z_range()  # assume facet has a method z_range()
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
        path = popfirst!(paths[k])[1]
        if isempty(paths[k])
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

end  # module StlData
