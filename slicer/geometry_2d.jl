module Geometry2D

export SCALING_FACTOR, offset, union, diff, clip, paths_contain,
       orient_path, orient_paths, paths_bounds, close_path, close_paths,
       make_infill_lines, make_infill_triangles, make_infill_grid, make_infill_hexagons

using MathConstants  # for π, if needed
using Statistics     # for hypot
# Assumed that a module named `pyclipper` is available with the following functions:
#   PyclipperOffset(), scale_to_clipper(), scale_from_clipper(), JT_SQUARE,
#   ET_CLOSEDPOLYGON, PT_SUBJECT, PT_CLIP, CT_UNION, CT_DIFFERENCE,
#   CT_INTERSECTION, PFT_EVENODD, Orientation(), ReversePath(), Execute(),
#   Execute2(), PolyTreeToPaths(), PointInPolygon()

const SCALING_FACTOR = 1000

#-------------------------------------------------------------------------
# Offset
#-------------------------------------------------------------------------
function offset(paths, amount)
    pco = pyclipper.PyclipperOffset()
    pco.ArcTolerance = SCALING_FACTOR / 40
    paths_scaled = pyclipper.scale_to_clipper(paths, SCALING_FACTOR)
    pco.AddPaths(paths_scaled, pyclipper.JT_SQUARE, pyclipper.ET_CLOSEDPOLYGON)
    outpaths = pco.Execute(amount * SCALING_FACTOR)
    outpaths = pyclipper.scale_from_clipper(outpaths, SCALING_FACTOR)
    return outpaths
end

#-------------------------------------------------------------------------
# Union
#-------------------------------------------------------------------------
function union(paths1, paths2)
    if isempty(paths1)
        return paths2
    end
    if isempty(paths2)
        return paths1
    end
    pc = pyclipper.Pyclipper()
    # Check that paths1 and paths2 are not already scaled (i.e. not a list of numbers)
    if !isempty(paths1)
        if paths1[1][1] isa Number
            error("ClipperException")
        end
        paths1 = pyclipper.scale_to_clipper(paths1, SCALING_FACTOR)
        pc.AddPaths(paths1, pyclipper.PT_SUBJECT, true)
    end
    if !isempty(paths2)
        if paths2[1][1] isa Number
            error("ClipperException")
        end
        paths2 = pyclipper.scale_to_clipper(paths2, SCALING_FACTOR)
        pc.AddPaths(paths2, pyclipper.PT_CLIP, true)
    end
    try
        outpaths = pc.Execute(pyclipper.CT_UNION, pyclipper.PFT_EVENODD, pyclipper.PFT_EVENODD)
    catch e
        println("paths1=$(paths1)")
        println("paths2=$(paths2)")
        rethrow(e)
    end
    outpaths = pyclipper.scale_from_clipper(outpaths, SCALING_FACTOR)
    return outpaths
end

#-------------------------------------------------------------------------
# Difference
#-------------------------------------------------------------------------
function diff(subj, clip_paths; subj_closed=true)
    if isempty(subj)
        return []
    end
    if isempty(clip_paths)
        return subj
    end
    pc = pyclipper.Pyclipper()
    subj_scaled = pyclipper.scale_to_clipper(subj, SCALING_FACTOR)
    pc.AddPaths(subj_scaled, pyclipper.PT_SUBJECT, subj_closed)
    clip_scaled = pyclipper.scale_to_clipper(clip_paths, SCALING_FACTOR)
    pc.AddPaths(clip_scaled, pyclipper.PT_CLIP, true)
    outpaths = pc.Execute(pyclipper.CT_DIFFERENCE, pyclipper.PFT_EVENODD, pyclipper.PFT_EVENODD)
    outpaths = pyclipper.scale_from_clipper(outpaths, SCALING_FACTOR)
    return outpaths
end

#-------------------------------------------------------------------------
# Clip (Intersection)
#-------------------------------------------------------------------------
function clip(subj, clip_paths; subj_closed=true)
    if isempty(subj)
        return []
    end
    if isempty(clip_paths)
        return []
    end
    pc = pyclipper.Pyclipper()
    subj_scaled = pyclipper.scale_to_clipper(subj, SCALING_FACTOR)
    pc.AddPaths(subj_scaled, pyclipper.PT_SUBJECT, subj_closed)
    clip_scaled = pyclipper.scale_to_clipper(clip_paths, SCALING_FACTOR)
    pc.AddPaths(clip_scaled, pyclipper.PT_CLIP, true)
    out_tree = pc.Execute2(pyclipper.CT_INTERSECTION, pyclipper.PFT_EVENODD, pyclipper.PFT_EVENODD)
    outpaths = pyclipper.PolyTreeToPaths(out_tree)
    outpaths = pyclipper.scale_from_clipper(outpaths, SCALING_FACTOR)
    return outpaths
end

#-------------------------------------------------------------------------
# Paths Contain
#-------------------------------------------------------------------------
function paths_contain(pt, paths)
    cnt = 0
    pt_scaled = pyclipper.scale_to_clipper([pt], SCALING_FACTOR)[1]
    for path in paths
        path_scaled = pyclipper.scale_to_clipper(path, SCALING_FACTOR)
        if pyclipper.PointInPolygon(pt_scaled, path_scaled)
            cnt = 1 - cnt
        end
    end
    return cnt % 2 != 0
end

#-------------------------------------------------------------------------
# Orient a Single Path
#-------------------------------------------------------------------------
function orient_path(path, dir)
    orient = pyclipper.Orientation(path)
    path_scaled = pyclipper.scale_to_clipper(path, SCALING_FACTOR)
    if orient != dir
        path_scaled = pyclipper.ReversePath(path_scaled)
    end
    path_oriented = pyclipper.scale_from_clipper(path_scaled, SCALING_FACTOR)
    return path_oriented
end

#-------------------------------------------------------------------------
# Orient Multiple Paths
#-------------------------------------------------------------------------
function orient_paths(paths)
    out = []
    while !isempty(paths)
        path = popfirst!(paths)
        path = orient_path(path, !paths_contain(path[1], paths))
        push!(out, path)
    end
    return out
end

#-------------------------------------------------------------------------
# Compute Bounds for a Set of Paths
#-------------------------------------------------------------------------
function paths_bounds(paths)
    if isempty(paths)
        return (0, 0, 0, 0)
    end
    minx = nothing
    miny = nothing
    maxx = nothing
    maxy = nothing
    for path in paths
        for (x, y) in path
            if minx === nothing || x < minx
                minx = x
            end
            if maxx === nothing || x > maxx
                maxx = x
            end
            if miny === nothing || y < miny
                miny = y
            end
            if maxy === nothing || y > maxy
                maxy = y
            end
        end
    end
    return (minx, miny, maxx, maxy)
end

#-------------------------------------------------------------------------
# Close a Path (ensure first and last point are the same)
#-------------------------------------------------------------------------
function close_path(path)
    if isempty(path)
        return path
    end
    if path[1] == path[end]
        return path
    end
    return vcat(path, [path[1]])
end

function close_paths(paths)
    return [close_path(path) for path in paths]
end

#-------------------------------------------------------------------------
# Infill Pattern Generators
#-------------------------------------------------------------------------

function make_infill_pat(rect, baseang, spacing, rots)
    minx, miny, maxx, maxy = rect
    w = maxx - minx
    h = maxy - miny
    cx = floor((maxx + minx) / 2 / spacing) * spacing
    cy = floor((maxy + miny) / 2 / spacing) * spacing
    r = hypot(w, h) / sqrt(2)
    n = ceil(Int, r / spacing)
    out = []
    for rot in rots
        c1 = cos((baseang + rot) * π / 180)
        s1 = sin((baseang + rot) * π / 180)
        c2 = cos((baseang + rot + 90) * π / 180) * spacing
        s2 = sin((baseang + rot + 90) * π / 180) * spacing
        for i in (1 - n):(n - 1)
            cp = (cx + c2 * i, cy + s2 * i)
            line = [(cp[1] + r * c1, cp[2] + r * s1),
                    (cp[1] - r * c1, cp[2] - r * s1)]
            push!(out, line)
        end
    end
    return out
end

function make_infill_lines(rect, base_ang, density, ewidth)
    if density <= 0.0
        return []
    end
    density = min(density, 1.0)
    spacing = ewidth / density
    return make_infill_pat(rect, base_ang, spacing, [0])
end

function make_infill_triangles(rect, base_ang, density, ewidth)
    if density <= 0.0
        return []
    end
    density = min(density, 1.0)
    spacing = 3.0 * ewidth / density
    return make_infill_pat(rect, base_ang, spacing, [0, 60, 120])
end

function make_infill_grid(rect, base_ang, density, ewidth)
    if density <= 0.0
        return []
    end
    density = min(density, 1.0)
    spacing = 2.0 * ewidth / density
    return make_infill_pat(rect, base_ang, spacing, [0, 90])
end

function make_infill_hexagons(rect, base_ang, density, ewidth)
    if density <= 0.0
        return []
    end
    density = min(density, 1.0)
    ext = 0.5 * ewidth / tan(60.0 * π / 180)
    aspect = 3.0 / sin(60.0 * π / 180)
    col_spacing = ewidth * (4/3) / density
    row_spacing = col_spacing * aspect
    minx, maxx, miny, maxy = rect
    w = maxx - minx
    h = maxy - miny
    cx = (maxx + minx) / 2
    cy = (maxy + miny) / 2
    r = max(w, h) * sqrt(2.0)
    n_col = ceil(Int, r / col_spacing)
    n_row = ceil(Int, r / row_spacing)
    out = []
    s = sin(base_ang * π / 180)
    c = cos(base_ang * π / 180)
    for col in -n_col:(n_col - 1)
        path = []
        base_x = col * col_spacing
        for row in -n_row:(n_row - 1)
            base_y = row * row_spacing
            x1 = base_x + ewidth/2.0
            x2 = base_x + col_spacing - ewidth/2.0
            if isodd(col)
                x1, x2 = x2, x1
            end
            push!(path, (x1, base_y + ext))
            push!(path, (x2, base_y + row_spacing/6 - ext))
            push!(path, (x2, base_y + row_spacing/2 + ext))
            push!(path, (x1, base_y + row_spacing * 2/3 - ext))
        end
        rotated = [(x * c - y * s, x * s + y * c) for (x, y) in path]
        push!(out, rotated)
    end
    return out
end

end  # module Geometry2D
