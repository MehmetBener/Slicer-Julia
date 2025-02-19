module slicer

using DataStructures: OrderedDict
using Printf
using Random
using Dates
using LinearAlgebra
using Statistics
# For file and path operations
import Base.Filesystem: isfile, isdir, mkpath
import Base: joinpath, dirname, homedir

# Geometry2D functions – these should be implemented to match your geometry code.
module Geometry2D
export orient_paths, union, offset, close_paths, diff, paths_bounds,
       make_infill_lines, clip, make_infill_triangles, make_infill_grid,
       make_infill_hexagons

"Stub: return the given paths unchanged."
orient_paths(paths) = paths

"Stub: return the union (concatenation) of two sets of paths."
union(paths1, paths2) = vcat(paths1, paths2)

"Stub: perform an offset on paths."
offset(paths, dist) = paths

"Stub: return closed paths."
close_paths(paths) = paths

"Stub: difference of paths."
diff(paths1, paths2) = paths1

"Stub: compute bounds of a set of paths."
paths_bounds(paths) = (0.0, 0.0, 100.0, 100.0)

"Stub: create infill lines."
make_infill_lines(bounds, base_ang, density, width) = [[ [bounds[1], bounds[2]], [bounds[3], bounds[4]] ]]

"Stub: clip paths."
clip(paths, mask; subj_closed=false) = paths

"Stub: create infill triangles."
make_infill_triangles(bounds, base_ang, density, width) = [[ [bounds[1], bounds[2]], [bounds[3], bounds[4]] ]]

"Stub: create infill grid."
make_infill_grid(bounds, base_ang, density, width) = [[ [bounds[1], bounds[2]], [bounds[3], bounds[4]] ]]

"Stub: create infill hexagons."
make_infill_hexagons(bounds, base_ang, density, width) = [[ [bounds[1], bounds[2]], [bounds[3], bounds[4]] ]]

end # module Geometry2D

# Bring functions into our namespace:
using .Geometry2D: orient_paths, union, offset, close_paths, diff, paths_bounds,
                   make_infill_lines, clip, make_infill_triangles, make_infill_grid,
                   make_infill_hexagons

# A simple TextThermometer placeholder.
struct TextThermometer
    target::Int
    current::Int
end

function TextThermometer(target::Int)
    return TextThermometer(target, 0)
end

function set_target!(thermo::TextThermometer, target)
    thermo.target = target
end

function update!(thermo::TextThermometer, value)
    thermo.current = value
    # (You could print a progress message here)
end

function clear!(thermo::TextThermometer)
    thermo.current = 0
end

const slicer_configs = OrderedDict{String, Vector{Tuple{String, Any, Any, Any, String}}}()

slicer_configs["Quality"] = [
    ("layer_height",      Float64,  0.2, (0.01, 0.5), "Slice layer height in mm."),
    ("shell_count",       Int,      2, (1, 10),     "Number of outer shells to print."),
    ("random_starts",     Bool,   true, nothing,       "Enable randomizing of perimeter starts."),
    ("top_layers",        Int,      3, (0, 10),     "Number of layers to print on the top side of the object."),
    ("bottom_layers",     Int,      3, (0, 10),     "Number of layers to print on the bottom side of the object."),
    ("infill_type",       Vector{String}, "Grid", ["Lines", "Triangles", "Grid", "Hexagons"], "Pattern that the infill will be printed in."),
    ("infill_density",    Float64,  30.0, (0.0, 100.0),  "Infill density in percent."),
    ("infill_overlap",    Float64, 0.15, (0.0, 1.0),  "Amount, in mm that infill will overlap with perimeter extrusions."),
    ("feed_rate",         Int,     60, (1, 300),    "Speed while extruding. (mm/s)"),
    ("travel_rate_xy",    Int,    100, (1, 300),    "Travel motion speed (mm/s)"),
    ("travel_rate_z",     Float64,   5.0, (0.1, 30.0),  "Z-axis  motion speed (mm/s)")
]

slicer_configs["Support"] = [
    ("support_type",      Vector{String}, "External", ["None", "External", "Everywhere"], "What kind of support structure to add."),
    ("support_outset",    Float64,   0.5, (0.0, 2.0),   "How far support structures should be printed away from model, horizontally."),
    ("support_density",   Float64,  33.0, (0.0, 100.0), "Density of support structure internals."),
    ("overhang_angle",    Int,      45, (0, 90),    "Angle from vertical that support structures should be printed for.")
]

slicer_configs["Adhesion"] = [
    ("adhesion_type",     Vector{String}, "None", ["None", "Brim", "Raft"], "What kind of base adhesion structure to add."),
    ("brim_width",        Float64,  3.0, (0.0, 20.0),   "Width of brim to print on first layer to help with part adhesion."),
    ("raft_layers",       Int,      3, (1, 5),      "Number of layers to use in making the raft."),
    ("raft_outset",       Float64,  3.0, (0.0, 50.0),   "How much bigger raft should be than the model footprint."),
    ("skirt_outset",      Float64,  0.0, (0.0, 20.0),   "How far the skirt should be printed away from model."),
    ("skirt_layers",      Int,      0, (0, 1000),   "Number of layers to print print the skirt on."),
    ("prime_length",      Float64, 10.0, (0.0, 1000.0), "Length of filament to extrude when priming hotends.")
]

slicer_configs["Retraction"] = [
    ("retract_enable",    Bool,   true, nothing,       "Enable filament retraction."),
    ("retract_speed",     Float64,  30.0, (0.0, 200.0), "Speed to retract filament at. (mm/s)"),
    ("retract_dist",      Float64,   3.0, (0.0, 20.0),  "Distance to retract filament between extrusion moves. (mm)"),
    ("retract_extruder",  Float64,   3.0, (0.0, 50.0),  "Distance to retract filament on extruder change. (mm)"),
    ("retract_lift",      Float64,   0.0, (0.0, 10.0),  "Distance to lift the extruder head during retracted moves. (mm)")
]

slicer_configs["Materials"] = [
    ("abs_bed_temp",        Int,      90,  (0, 150),  "The bed temperature to use for ABS filament. (C)"),
    ("abs_hotend_temp",     Int,     230,  (150, 300),  "The extruder temperature to use for ABS filament. (C)"),
    ("abs_max_speed",       Float64,  75.0,  (0, 150),  "The maximum speed when extruding ABS filament. (mm/s)"),
    ("hips_bed_temp",       Int,     100,  (0, 150),  "The bed temperature to use for dissolvable HIPS filament. (C)"),
    ("hips_hotend_temp",    Int,     230,  (150, 300),  "The extruder temperature to use for dissolvable HIPS filament. (C)"),
    ("hips_max_speed",      Float64,  30.0,  (0, 150),  "The maximum speed when extruding dissolvable HIPS filament. (mm/s)"),
    ("nylon_bed_temp",      Int,      70,  (0, 150),  "The bed temperature to use for Nylon filament. (C)"),
    ("nylon_hotend_temp",   Int,     255,  (150, 300),  "The extruder temperature to use for Nylon filament. (C)"),
    ("nylon_max_speed",     Float64,  75.0,  (0, 150),  "The maximum speed when extruding Nylon filament. (mm/s)"),
    ("pc_bed_temp",         Int,     130,  (0, 150),  "The bed temperature to use for Polycarbonate filament. (C)"),
    ("pc_hotend_temp",      Int,     290,  (150, 300),  "The extruder temperature to use for Polycarbonate filament. (C)"),
    ("pc_max_speed",        Float64,  75.0,  (0, 150),  "The maximum speed when extruding Polycarbonate filament. (mm/s)"),
    ("pet_bed_temp",        Int,      70,  (0, 150),  "The bed temperature to use for PETG/PETT filament. (C)"),
    ("pet_hotend_temp",     Int,     230,  (150, 300),  "The extruder temperature to use for PETG/PETT filament. (C)"),
    ("pet_max_speed",       Float64,  75.0,  (0, 150),  "The maximum speed when extruding PETG/PETT filament. (mm/s)"),
    ("pla_bed_temp",        Int,      45,  (0, 150),  "The bed temperature to use for PLA filament. (C)"),
    ("pla_hotend_temp",     Int,     205,  (150, 300),  "The extruder temperature to use for PLA filament. (C)"),
    ("pla_max_speed",       Float64,  75.0,  (0, 150),  "The maximum speed when extruding PLA filament. (mm/s)"),
    ("pp_bed_temp",         Int,     110,  (0, 150),  "The bed temperature to use for Polypropylene filament. (C)"),
    ("pp_hotend_temp",      Int,     250,  (150, 300),  "The extruder temperature to use for Polypropylene filament. (C)"),
    ("pp_max_speed",        Float64,  75.0,  (0, 150),  "The maximum speed when extruding Polypropylene filament. (mm/s)"),
    ("pva_bed_temp",        Int,      60,  (0, 150),  "The bed temperature to use for dissolvable PVA filament. (C)"),
    ("pva_hotend_temp",     Int,     220,  (150, 300),  "The extruder temperature to use for dissolvable PVA filament. (C)"),
    ("pva_max_speed",       Float64,  30.0,  (0, 150),  "The maximum speed when extruding dissolvable PVA filament. (mm/s)"),
    ("softpla_bed_temp",    Int,      30,  (0, 150),  "The bed temperature to use for flexible SoftPLA filament. (C)"),
    ("softpla_hotend_temp", Int,     230,  (150, 300),  "The extruder temperature to use for flexible SoftPLA filament. (C)"),
    ("softpla_max_speed",   Float64,  30.0,  (0, 150),  "The maximum speed when extruding flexible SoftPLA filament. (mm/s)"),
    ("tpe_bed_temp",        Int,      30,  (0, 150),  "The bed temperature to use for flexible TPE filament. (C)"),
    ("tpe_hotend_temp",     Int,     220,  (150, 300),  "The extruder temperature to use for flexible TPE filament. (C)"),
    ("tpe_max_speed",       Float64,  30.0,  (0, 150),  "The maximum speed when extruding flexible TPE filament. (mm/s)"),
    ("tpu_bed_temp",        Int,      50,  (0, 150),  "The bed temperature to use for flexible TPU filament. (C)"),
    ("tpu_hotend_temp",     Int,     250,  (150, 300),  "The extruder temperature to use for flexible TPU filament. (C)"),
    ("tpu_max_speed",       Float64,  30.0,  (0, 150),  "The maximum speed when extruding flexible TPU filament. (mm/s)")
]

slicer_configs["Machine"] = [
    ("bed_geometry",      Vector{String}, "Rectangular", ["Rectangular", "Cylindrical"], "The shape of the build volume cross-section."),
    ("bed_size_x",        Float64,  200.0, (0.0,1000.0),    "The X-axis size of the build platform bed."),
    ("bed_size_y",        Float64,  200.0, (0.0,1000.0),    "The Y-axis size of the build platform bed."),
    ("bed_center_x",      Float64,  100.0, (-500.0,500.0),  "The X coordinate of the center of the bed."),
    ("bed_center_y",      Float64,  100.0, (-500.0,500.0),  "The Y coordinate of the center of the bed."),
    ("bed_temp",          Int,     70, (0, 150),    "The temperature to set the heated bed to."),

    ("extruder_count",    Int,      1, (1, 4),      "The number of extruders this machine has."),
    ("default_nozzle",    Int,      0, (0, 4),      "The default extruder used for printing."),
    ("infill_nozzle",     Int,     -1, (-1, 4),     "The extruder used for infill material.  -1 means use default nozzle."),
    ("support_nozzle",    Int,     -1, (-1, 4),     "The extruder used for support material.  -1 means use default nozzle."),

    ("nozzle_0_temp",      Int,    190, (150, 250),  "The temperature of the nozzle for extruder 0. (C)"),
    ("nozzle_0_filament",  Float64, 1.75, (1.0, 3.5),  "The diameter of the filament for extruder 0. (mm)"),
    ("nozzle_0_diam",      Float64,  0.4, (0.1, 1.5),  "The diameter of the nozzle for extruder 0. (mm)"),
    ("nozzle_0_xoff",      Float64,  0.0, (-100.0, 100.0), "The X positional offset for extruder 0. (mm)"),
    ("nozzle_0_yoff",      Float64,  0.0, (-100.0, 100.0), "The Y positional offset for extruder 0. (mm)"),
    ("nozzle_0_max_speed", Float64, 75.0, (0.0, 200.0),  "The maximum speed when using extruder 0. (mm/s)"),

    ("nozzle_1_temp",      Int,    190, (150, 250),  "The temperature of the nozzle for extruder 1. (C)"),
    ("nozzle_1_filament",  Float64, 1.75, (1.0, 3.5),  "The diameter of the filament for extruder 1. (mm)"),
    ("nozzle_1_diam",      Float64,  0.4, (0.1, 1.5),  "The diameter of the nozzle for extruder 1. (mm)"),
    ("nozzle_1_xoff",      Float64, 25.0, (-100.0, 100.0), "The X positional offset for extruder 1. (mm)"),
    ("nozzle_1_yoff",      Float64,  0.0, (-100.0, 100.0), "The Y positional offset for extruder 1. (mm)"),
    ("nozzle_1_max_speed", Float64, 75.0, (0.0, 200.0),  "The maximum speed when using extruder 1. (mm/s)"),

    ("nozzle_2_temp",      Int,    190, (150, 250),  "The temperature of the nozzle for extruder 2. (C)"),
    ("nozzle_2_filament",  Float64, 1.75, (1.0, 3.5),  "The diameter of the filament for extruder 2. (mm)"),
    ("nozzle_2_diam",      Float64,  0.4, (0.1, 1.5),  "The diameter of the nozzle for extruder 2. (mm)"),
    ("nozzle_2_xoff",      Float64, -25.0, (-100.0, 100.0), "The X positional offset for extruder 2. (mm)"),
    ("nozzle_2_yoff",      Float64,  0.0, (-100.0, 100.0), "The Y positional offset for extruder 2. (mm)"),
    ("nozzle_2_max_speed", Float64, 75.0, (0.0, 200.0),  "The maximum speed when using extruder 2. (mm/s)"),

    ("nozzle_3_temp",      Int,    190, (150, 250),  "The temperature of the nozzle for extruder 3. (C)"),
    ("nozzle_3_filament",  Float64, 1.75, (1.0, 3.5),  "The diameter of the filament for extruder 3. (mm)"),
    ("nozzle_3_diam",      Float64,  0.4, (0.1, 1.5),  "The diameter of the nozzle for extruder 3. (mm)"),
    ("nozzle_3_xoff",      Float64,  0.0, (-100.0, 100.0), "The X positional offset for extruder 3. (mm)"),
    ("nozzle_3_yoff",      Float64, 25.0, (-100.0, 100.0), "The Y positional offset for extruder 3. (mm)"),
    ("nozzle_3_max_speed", Float64, 75.0, (0.0, 200.0),  "The maximum speed when using extruder 3. (mm/s)")
]

mutable struct Slicer
    models::Any  # user–defined models (assumed to have methods like center!(), assign_layers!(), etc.)
    conf::Dict{String, Any}
    conf_metadata::Dict{String, Any}
    raw_layer_paths::Dict{Int, Vector{Vector{Tuple{Any,Any}}}}  # per–layer, per–nozzle paths storage
    last_pos::NTuple{3, Float64}
    last_e::Float64
    last_nozl::Int
    total_build_time::Float64
    mag::Float64
    layer::Int
    # Additional slicing parameters (set during slicing)
    dflt_nozl::Int
    infl_nozl::Int
    supp_nozl::Int
    center_point::Tuple{Float64,Float64}
    layer_h::Float64
    raft_layers::Int
    extrusion_ratio::Float64
    extrusion_width::Float64
    infill_width::Float64
    support_width::Float64
    layer_paths::Vector{Any}
    perimeter_paths::Vector{Any}
    skirt_bounds::Any
    dead_paths::Vector{Any}
    top_masks::Vector{Any}
    bot_masks::Vector{Any}
    support_outline::Vector{Any}
    support_infill::Vector{Any}
    skirt_paths::Any
    brim_paths::Any
    raft_outline::Any
    raft_infill::Any
    layers::Int
    layer_zs::Vector{Float64}
    thermo::TextThermometer
end

# Constructor for Slicer; any keyword arguments override defaults.
function Slicer(models; kwargs...)
    conf = Dict{String,Any}()
    conf_metadata = Dict{String,Any}()
    for (sect, opts) in slicer_configs
        for (name, typ, dflt, rng, desc) in opts
            conf[name] = dflt
            conf_metadata[name] = Dict("type" => typ, "default" => dflt, "range" => rng, "descr" => desc)
        end
    end
    s = Slicer(
        models,
        conf,
        conf_metadata,
        Dict{Int, Vector{Vector{Tuple{Any,Any}}}}(),
        (0.0, 0.0, 0.0),
        0.0,
        0,
        0.0,
        4.0,
        0,
        0,
        0,
        (0.0, 0.0),
        0.0,
        0,
        1.25,
        0.0,
        0.0,
        0.0,
        Any[],
        Any[],
        nothing,
        Any[],
        Any[],
        nothing,
        nothing,
        nothing,
        nothing,
        0,
        Float64[],
        TextThermometer(0)
    )
    config!(s; kwargs...)
    return s
end

# Update configuration from keyword arguments.
function config!(s::Slicer; kwargs...)
    for (key, val) in kwargs
        if haskey(s.conf, key)
            s.conf[key] = val
        end
    end
end

# Return the configuration filename (here in ~/.config/Mandoline)
function get_conf_filename(s::Slicer)
    return joinpath(homedir(), ".config", "Mandoline")
end

# Set a configuration key from a string value.
function set_config!(s::Slicer, key::String, valstr::String)
    key = strip(key)
    valstr = strip(valstr)
    if !haskey(s.conf_metadata, key)
        println("Ignoring unknown config option: $key")
        return
    end
    meta = s.conf_metadata[key]
    typ = meta["type"]
    rng = meta["range"]
    badval = true
    typestr = ""
    errmsg = ""
    if typ == Bool
        typestr = "boolean "
        errmsg = "Value should be either true or false"
        if valstr in ["True", "true", "False", "false"]
            s.conf[key] = (valstr in ["True", "true"])
            badval = false
        end
    elseif typ == Int
        typestr = "integer "
        if rng !== nothing
            errmsg = @sprintf("Value should be between %d and %d, inclusive.", rng[1], rng[2])
        end
        try
            val = parse(Int, valstr)
            if rng === nothing || (val >= rng[1] && val <= rng[2])
                s.conf[key] = val
                badval = false
            end
        catch
        end
    elseif typ == Float64
        typestr = "float "
        if rng !== nothing
            errmsg = @sprintf("Value should be between %.2f and %.2f, inclusive.", rng[1], rng[2])
        end
        try
            val = parse(Float64, valstr)
            if rng === nothing || (val >= rng[1] && val <= rng[2])
                s.conf[key] = val
                badval = false
            end
        catch
        end
    elseif typ == Vector{String}
        typestr = ""
        if rng !== nothing
            errmsg = "Valid options are: " * join(rng, ", ")
        end
        if rng !== nothing && (valstr in rng)
            s.conf[key] = valstr
            badval = false
        end
    end
    if badval
        println("Ignoring bad $(typestr)configuration value: $key=$valstr")
        println(errmsg)
    end
end

# Load configuration values from file.
function load_configs!(s::Slicer)
    conffile = get_conf_filename(s)
    if !isfile(conffile)
        return
    end
    println("Loading configs from $conffile")
    for line in eachline(conffile)
        line = strip(line)
        if isempty(line) || startswith(line, "#")
            continue
        end
        parts = split(line, "=")
        if length(parts) >= 2
            key = parts[1]
            val = join(parts[2:end], "=")
            set_config!(s, key, val)
        end
    end
end

# Save current configuration values to file.
function save_configs!(s::Slicer)
    conffile = get_conf_filename(s)
    confdir = dirname(conffile)
    if !isdir(confdir)
        mkpath(confdir)
    end
    open(conffile, "w") do f
        for (sect, opts) in slicer_configs
            println(f, "# $sect")
            for (name, typ, dflt, rng, desc) in opts
                println(f, "$name=$(s.conf[name])")
            end
            println(f, "\n")
        end
    end
    println("Saving configs to $conffile")
end

# Display configuration help; optionally only values.
function display_configs_help(s::Slicer; key::Union{Nothing, String}=nothing, vals_only::Bool=false)
    if key !== nothing
        key = strip(key)
        if !haskey(s.conf_metadata, key)
            println("Unknown config option: $key")
            return
        end
    end
    for (sect, opts) in slicer_configs
        if !vals_only && key === nothing
            println("$sect:")
        end
        for (name, typ, dflt, rng, desc) in opts
            if key !== nothing && key != name
                continue
            end
            local typename, rngstr
            if typ == Bool
                typename = "bool"
                rngstr = "true/false"
            elseif typ == Int
                typename = "int"
                rngstr = "$(rng[1]) ... $(rng[2])"
            elseif typ == Float64
                typename = "float"
                rngstr = "$(rng[1]) ... $(rng[2])"
            elseif typ == Vector{String}
                typename = "opt"
                rngstr = join(rng, ", ")
            else
                typename = "unknown"
                rngstr = ""
            end
            println("  $name = $(s.conf[name])")
            if !vals_only
                println("          Type: $typename  ($rngstr)")
                println("          $desc")
            end
        end
    end
end

function slice_to_file!(s::Slicer, filename::String; showgui::Bool=false)
    println("Slicing start")
    s.dflt_nozl = s.conf["default_nozzle"]
    s.infl_nozl = s.conf["infill_nozzle"]
    s.supp_nozl = s.conf["support_nozzle"]
    s.center_point = (s.conf["bed_center_x"], s.conf["bed_center_y"])
    if s.infl_nozl == -1
        s.infl_nozl = s.dflt_nozl
    end
    if s.supp_nozl == -1
        s.supp_nozl = s.dflt_nozl
    end
    dflt_nozl_d = s.conf["nozzle_$(s.dflt_nozl)_diam"]
    infl_nozl_d = s.conf["nozzle_$(s.infl_nozl)_diam"]
    supp_nozl_d = s.conf["nozzle_$(s.supp_nozl)_diam"]

    s.layer_h = s.conf["layer_height"]
    s.raft_layers = (s.conf["adhesion_type"] == "Raft") ? s.conf["raft_layers"] : 0
    s.extrusion_ratio = 1.25
    s.extrusion_width = dflt_nozl_d * s.extrusion_ratio
    s.infill_width = infl_nozl_d * s.extrusion_ratio
    s.support_width = supp_nozl_d * s.extrusion_ratio

    # For each model, center and assign layers.
    for model in s.models
        # (Assumes model has methods center! and assign_layers!)
        center_z = (model.points.maxz - model.points.minz) / 2.0
        model.center!((s.center_point[1], s.center_point[2], center_z))
        model.assign_layers!(s.layer_h)
    end
    height = maximum([model.points.maxz - model.points.minz for model in s.models])
    s.layers = Int(floor(height / s.layer_h))
    s.layer_zs = [s.layer_h * (layer + 1) for layer in 0:(s.layers + s.raft_layers)]
    s.thermo = TextThermometer(s.layers)

    println("Perimeters")
    _slicer_task_perimeters!(s)

    println("Support")
    _slicer_task_support!(s)

    println("Raft, Brim, and Skirt")
    _slicer_task_adhesion!(s)

    println("Infill")
    _slicer_task_fill!(s)

    println("Pathing")
    _slicer_task_pathing!(s)

    println("Writing GCode to $filename")
    _slicer_task_gcode!(s, filename)

    let hrs = Int(floor(s.total_build_time / 3600))
        mins = Int(floor((s.total_build_time % 3600) / 60))
        println(@sprintf("Slicing complete.  Estimated build time: %dh %02dm", hrs, mins))
    end

    if showgui
        println("Launching slice viewer")
        _display_paths(s)
    end
end

function _slicer_task_perimeters!(s::Slicer)
    set_target!(s.thermo, 2 * s.layers)
    s.layer_paths = []
    s.perimeter_paths = []
    s.skirt_bounds = nothing
    random_starts = s.conf["random_starts"]
    s.dead_paths = []
    for layer in 1:s.layers
        update!(s.thermo, layer)
        z = s.layer_zs[layer]
        paths = []         # gather paths for this layer
        layer_dead_paths = []
        for model in s.models
            # (Assumes model.slice_at_z returns (model_paths, dead_paths))
            model_paths, dead_paths = model.slice_at_z(z - s.layer_h/2, s.layer_h)
            append!(layer_dead_paths, dead_paths)
            model_paths = orient_paths(model_paths)
            paths = union(paths, model_paths)
        end
        push!(s.layer_paths, paths)
        push!(s.dead_paths, layer_dead_paths)
        # Compute perimeters
        perims = []
        randpos = rand()
        for i in 1:s.conf["shell_count"]
            shell = offset(paths, -((i - 0.5) * s.extrusion_width))
            shell = close_paths(shell)
            if random_starts
                shell = [ (i == 1 ? path : vcat(path[Int(floor(randpos * (length(path)-1)))+1:end],
                                                 path[2:Int(floor(randpos * (length(path)-1)) + 1)])) for path in shell ]
            end
            insert!(perims, 1, shell)
        end
        push!(s.perimeter_paths, perims)
        # Skirt bounds calculation
        if layer <= s.conf["skirt_layers"]
            s.skirt_bounds = isnothing(s.skirt_bounds) ? paths : union(s.skirt_bounds, paths)
        end
    end

    s.top_masks = []
    s.bot_masks = []
    for layer in 1:s.layers
        update!(s.thermo, s.layers + layer)
        below = (layer < 2) ? [] : s.perimeter_paths[layer - 1][1]
        perim = s.perimeter_paths[layer][1]
        above = (layer >= s.layers) ? [] : s.perimeter_paths[layer + 1][1]
        push!(s.top_masks, diff(perim, above))
        push!(s.bot_masks, diff(perim, below))
    end
    clear!(s.thermo)
end

function _slicer_task_support!(s::Slicer)
    set_target!(s.thermo, 5)
    s.support_outline = []
    s.support_infill = []
    supp_type = s.conf["support_type"]
    if supp_type == "None"
        return
    end
    supp_ang = s.conf["overhang_angle"]
    outset = s.conf["support_outset"]
    layer_height = s.conf["layer_height"]

    # Collect all facets from all models (assumes each facet provides z_range(), overhang_angle(), get_footprint())
    facets = reduce(vcat, [model.get_facets() for model in s.models])
    facet_cnt = length(facets)
    layer_facets = [Any[] for _ in 1:s.layers]
    for (fnum, facet) in enumerate(facets)
        update!(s.thermo, 0 + Float64(fnum) / facet_cnt)
        minz, maxz = facet.z_range()
        minl = ceil(Int, minz / layer_height)
        maxl = floor(Int, maxz / layer_height)
        for layer in minl:maxl
            if layer ≥ 1 && layer ≤ s.layers
                push!(layer_facets[layer], facet)
            end
        end
    end

    drop_mask = nothing
    drop_paths = [Any[] for _ in 1:s.layers]
    for layer in reverse(1:s.layers)
        update!(s.thermo, 1 + Float64(s.layers - layer) / s.layers)
        adds = []
        diffs = []
        for facet in layer_facets[layer]
            footprint = facet.get_footprint()
            if isempty(footprint)
                continue
            end
            if facet.overhang_angle() < supp_ang
                push!(diffs, footprint)
            else
                push!(adds, footprint)
            end
        end
        drop_mask = isnothing(drop_mask) ? union(adds...) : union(drop_mask, union(adds...))
        if !isempty(diffs)
            drop_mask = diff(drop_mask, union(diffs...))
        end
        drop_paths[layer] = drop_mask
    end

    cumm_mask = nothing
    for layer in 1:s.layers
        update!(s.thermo, 2 + Float64(layer) / s.layers)
        mask = offset(s.layer_paths[layer], outset)
        if layer > 1 && supp_type == "Everywhere"
            mask = union(mask, s.layer_paths[layer - 1])
        end
        if layer < s.layers
            mask = union(mask, s.layer_paths[layer + 1])
        end
        if supp_type == "External"
            cumm_mask = isnothing(cumm_mask) ? mask : union(cumm_mask, mask)
            mask = cumm_mask
        end
        overhang = diff(drop_paths[layer], mask)
        overhang = offset(overhang, s.extrusion_width)
        overhang = offset(overhang, -2 * s.extrusion_width)
        overhang = offset(overhang, s.extrusion_width)
        drop_paths[layer] = close_paths(overhang)
    end

    for layer in 1:s.layers
        update!(s.thermo, 3 + Float64(layer) / s.layers)
        outline = []
        infill = []
        overhangs = drop_paths[layer]
        density = s.conf["support_density"] / 100.0
        if density > 0.0
            outline = offset(overhangs, -s.extrusion_width / 2)
            outline = close_paths(outline)
            mask = offset(outline, s.conf["infill_overlap"] - s.extrusion_width)
            bounds = paths_bounds(mask)
            lines = make_infill_lines(bounds, 0, density, s.extrusion_width)
            infill = clip(lines, mask; subj_closed=false)
        end
        push!(s.support_outline, outline)
        push!(s.support_infill, infill)
    end
    clear!(s.thermo)
end

function _slicer_task_adhesion!(s::Slicer)
    adhesion = s.conf["adhesion_type"]
    skirt_w  = s.conf["skirt_outset"]
    brim_w   = s.conf["brim_width"]
    raft_w   = s.conf["raft_outset"]

    # Skirt
    if !isempty(s.support_outline)
        skirt_mask = offset(union(s.skirt_bounds, s.support_outline[1]), skirt_w)
    else
        skirt_mask = offset(s.skirt_bounds, skirt_w)
    end
    skirt = offset(skirt_mask, brim_w + skirt_w + s.extrusion_width / 2)
    s.skirt_paths = close_paths(skirt)

    # Brim
    brim = []
    if adhesion == "Brim"
        rings = ceil(Int, brim_w / s.extrusion_width)
        for i in 0:(rings - 1)
            for path in offset(s.layer_paths[1], (i + 0.5) * s.extrusion_width)
                push!(brim, path)
            end
        end
    end
    s.brim_paths = close_paths(brim)

    # Raft
    raft_outline = []
    raft_infill = []
    if adhesion == "Raft"
        rings = ceil(Int, brim_w / s.extrusion_width)
        outset_val = raft_w + max(skirt_w + s.extrusion_width, s.conf["raft_outset"] + s.extrusion_width)
        paths = union(s.layer_paths[1], s.support_outline[1])
        raft_outline = offset(paths, outset_val)
        bounds = paths_bounds(raft_outline)
        mask = offset(raft_outline, s.conf["infill_overlap"] - s.extrusion_width)
        lines = make_infill_lines(bounds, 0, 0.75, s.extrusion_width)
        push!(raft_infill, clip(lines, mask; subj_closed=false))
        for layer in 1:(s.raft_layers - 1)
            base_ang = 90 * (mod(layer, 2))
            lines = make_infill_lines(bounds, base_ang, 1.0, s.extrusion_width)
            push!(raft_infill, clip(lines, raft_outline; subj_closed=false))
        end
    end
    s.raft_outline = close_paths(raft_outline)
    s.raft_infill = raft_infill
    clear!(s.thermo)
end

function _slicer_task_fill!(s::Slicer)
    set_target!(s.thermo, s.layers)
    s.solid_infill = []
    s.sparse_infill = []
    for layer in 1:s.layers
        update!(s.thermo, layer)
        top_cnt = s.conf["top_layers"]
        bot_cnt = s.conf["bottom_layers"]
        top_masks = s.top_masks[layer:min(s.layers, layer + top_cnt - 1)]
        perims = s.perimeter_paths[layer]
        bot_masks = s.bot_masks[max(1, layer - bot_cnt + 1):layer]
        outmask = []
        for mask in top_masks
            outmask = union(outmask, close_paths(mask))
        end
        for mask in bot_masks
            outmask = union(outmask, close_paths(mask))
        end
        solid_mask = clip(outmask, perims[1])
        bounds = paths_bounds(perims[1])
        solid_infill = []
        base_ang = (layer % 2 == 0) ? 45 : -45
        solid_mask = offset(solid_mask, s.conf["infill_overlap"] - s.extrusion_width)
        lines = make_infill_lines(bounds, base_ang, 1.0, s.extrusion_width)
        for line in lines
            clipped = clip([line], solid_mask; subj_closed=false)
            append!(solid_infill, clipped)
        end
        push!(s.solid_infill, solid_infill)

        # Sparse infill
        sparse_infill = []
        infill_type = s.conf["infill_type"]
        density = s.conf["infill_density"] / 100.0
        if density > 0.0
            if density >= 0.99
                infill_type = "Lines"
            end
            mask = offset(perims[1], s.conf["infill_overlap"] - s.infill_width)
            mask = diff(mask, solid_mask)
            if infill_type == "Lines"
                base_ang = (layer % 2 == 0) ? 135 : 45
                lines = make_infill_lines(bounds, base_ang, density, s.infill_width)
            elseif infill_type == "Triangles"
                base_ang = 60 * mod(layer, 3)
                lines = make_infill_triangles(bounds, base_ang, density, s.infill_width)
            elseif infill_type == "Grid"
                base_ang = (layer % 2 == 0) ? 135 : 45
                lines = make_infill_grid(bounds, base_ang, density, s.infill_width)
            elseif infill_type == "Hexagons"
                base_ang = 120 * mod(layer, 3)
                lines = make_infill_hexagons(bounds, base_ang, density, s.infill_width)
            else
                lines = []
            end
            lines = clip(lines, mask; subj_closed=false)
            append!(sparse_infill, lines)
        end
        push!(s.sparse_infill, sparse_infill)
    end
    clear!(s.thermo)
end

function _slicer_task_pathing!(s::Slicer)
    prime_nozls = [s.conf["default_nozzle"]]
    if s.conf["infill_nozzle"] != -1
        push!(prime_nozls, s.conf["infill_nozzle"])
    end
    if s.conf["support_nozzle"] != -1
        push!(prime_nozls, s.conf["support_nozzle"])
    end
    center_x = s.conf["bed_center_x"]
    center_y = s.conf["bed_center_y"]
    size_x = s.conf["bed_size_x"]
    size_y = s.conf["bed_size_y"]
    minx = center_x - size_x / 2
    maxx = center_x + size_x / 2
    miny = center_y - size_y / 2
    maxy = center_y + size_y / 2
    bed_geom = s.conf["bed_geometry"]
    rect_bed = (bed_geom == "Rectangular")
    cyl_bed = (bed_geom == "Cylindrical")
    maxlen = rect_bed ? (maxy - miny - 20) : (2 * π * sqrt((size_x^2) / 2) - 20)
    reps = s.conf["prime_length"] / maxlen
    ireps = ceil(Int, reps)
    for (noznum, nozl) in enumerate(prime_nozls)
        ewidth = s.extrusion_width * 1.25
        nozl_path = []
        for rep in 1:ireps
            if rect_bed
                x = minx + 5 + (((noznum - 1) * reps + rep) * ewidth)
                if iseven(rep)
                    y1 = miny + 10
                    y2 = maxy - 10
                else
                    y1 = maxy - 10
                    y2 = miny + 10
                end
                push!(nozl_path, [x, y1])
                if rep == ireps
                    part = reps - floor(reps)
                    push!(nozl_path, [x, y1 + (y2 - y1) * part])
                else
                    push!(nozl_path, [x, y2])
                end
            elseif cyl_bed
                r = maxx - 5 - (((noznum - 1) * reps + rep) * ewidth)
                part = (rep == ireps) ? (reps - floor(reps)) : 1.0
                steps = floor(Int, 2π * r * part / 4)
                stepang = 2π / steps
                for i in 0:(steps - 1)
                    push!(nozl_path, [r * cos(i * stepang), r * sin(i * stepang)])
                end
            end
        end
        _add_raw_layer_paths!(s, 0, [nozl_path], ewidth, noznum - 1)
    end

    if !isempty(s.brim_paths)
        paths = close_paths(s.brim_paths)
        if 0 < s.conf["skirt_layers"] + s.raft_layers
            _add_raw_layer_paths!(s, 0, paths, s.support_width, s.supp_nozl)
        end
    end
    if s.raft_outline !== nothing
        outline = close_paths(s.raft_outline)
        _add_raw_layer_paths!(s, 0, outline, s.support_width, s.supp_nozl)
    end
    if s.raft_infill !== nothing
        for layer in 1:s.raft_layers
            paths = s.raft_infill[layer]
            _add_raw_layer_paths!(s, layer, paths, s.support_width, s.supp_nozl)
        end
    end

    for slicenum in 1:length(s.perimeter_paths)
        update!(s.thermo, slicenum)
        layer = s.raft_layers + slicenum
        if !isempty(s.skirt_paths) && (layer < s.conf["skirt_layers"] + s.raft_layers)
            paths = close_paths(s.skirt_paths)
            _add_raw_layer_paths!(s, layer, paths, s.support_width, s.supp_nozl)
        end
        if slicenum <= length(s.support_outline)
            outline = close_paths(s.support_outline[slicenum])
            _add_raw_layer_paths!(s, layer, outline, s.support_width, s.supp_nozl)
            _add_raw_layer_paths!(s, layer, s.support_infill[slicenum], s.support_width, s.supp_nozl)
        end
        for paths in s.perimeter_paths[slicenum]
            paths = close_paths(paths)
            _add_raw_layer_paths!(s, layer, paths, s.extrusion_width, s.dflt_nozl)
        end
        _add_raw_layer_paths!(s, layer, s.solid_infill[slicenum], s.extrusion_width, s.dflt_nozl)
        _add_raw_layer_paths!(s, layer, s.sparse_infill[slicenum], s.infill_width, s.infl_nozl)
    end
    clear!(s.thermo)
end

function _slicer_task_gcode!(s::Slicer, filename::String)
    set_target!(s.thermo, s.layers)
    total_layers = s.layers + s.raft_layers
    open(filename, "w") do f
        println(f, ";FLAVOR:Marlin")
        println(f, @sprintf(";Layer height: %.2f", s.conf["layer_height"]))
        println(f, "M82 ;absolute extrusion mode")
        println(f, "G21 ;metric values")
        println(f, "G90 ;absolute positioning")
        println(f, "M107 ;Fan off")
        if s.conf["bed_temp"] > 0
            println(f, @sprintf("M140 S%d ;set bed temp", s.conf["bed_temp"]))
            println(f, @sprintf("M190 S%d ;wait for bed temp", s.conf["bed_temp"]))
        end
        println(f, @sprintf("M104 S%d ;set extruder0 temp", s.conf["nozzle_0_temp"]))
        println(f, @sprintf("M109 S%d ;wait for extruder0 temp", s.conf["nozzle_0_temp"]))
        println(f, "G28 X0 Y0 ;auto-home all axes")
        println(f, "G28 Z0 ;auto-home all axes")
        println(f, "G1 Z15 F6000 ;raise extruder")
        println(f, "G92 E0 ;Zero extruder")
        println(f, "M117 Printing...")
        println(f, ";LAYER_COUNT:$(total_layers)")
        set_target!(s.thermo, total_layers)
        for layer in 0:(total_layers - 1)
            update!(s.thermo, layer)
            println(f, ";LAYER:$layer")
            for nozl in 0:3
                if haskey(s.raw_layer_paths, layer) && !isempty(s.raw_layer_paths[layer][nozl + 1])
                    println(f, "( Nozzle $nozl )")
                    for (paths, width) in s.raw_layer_paths[layer][nozl + 1]
                        for line in _paths_gcode(s, paths, width, nozl, s.layer_zs[layer + 1])
                            print(f, line)
                        end
                    end
                end
            end
        end
        clear!(s.thermo)
    end
end

function _vdist(a, b)
    delta = a .- b
    return sqrt(sum(delta.^2))
end

function _add_raw_layer_paths!(s::Slicer, layer::Int, paths, width, nozl; do_not_cross=[])
    maxdist = 2.0
    joined = []
    if !isempty(paths)
        path = popfirst!(paths)
        while !isempty(paths)
            mindist = Inf
            minidx = nothing
            enda = false
            endb = false
            for (i, p) in enumerate(paths)
                for a in (first(path), last(path))
                    for b in (first(p), last(p))
                        d = _vdist(a, b)
                        if d < mindist
                            mindist = d
                            minidx = i
                            enda = (a === first(path))
                            endb = (b === first(p))
                        end
                    end
                end
            end
            if mindist <= maxdist && minidx !== nothing
                path2 = splice!(paths, minidx)
                if enda
                    path = vcat(path, (endb ? reverse(path2) : path2))
                else
                    path = vcat((endb ? path2 : reverse(path2)), path)
                end
            else
                if minidx !== nothing
                    if enda == endb
                        insert!(paths, 1, reverse(splice!(paths, minidx)))
                    else
                        insert!(paths, 1, splice!(paths, minidx))
                    end
                end
                push!(joined, path)
                if !isempty(paths)
                    path = popfirst!(paths)
                end
            end
        end
        push!(joined, path)
    end
    if !haskey(s.raw_layer_paths, layer)
        s.raw_layer_paths[layer] = [Any[] for _ in 1:4]
    end
    push!(s.raw_layer_paths[layer][nozl + 1], (joined, width))
end

function _tool_change_gcode(s::Slicer, newnozl::Int)
    retract_ext_dist = s.conf["retract_extruder"]
    retract_speed = s.conf["retract_speed"]
    if s.last_nozl == newnozl
        return String[]
    end
    gcode_lines = String[]
    push!(gcode_lines, @sprintf("G1 E%.3f F%.3f\n", -retract_ext_dist, retract_speed * 60.0))
    push!(gcode_lines, "T$(newnozl)\n")
    push!(gcode_lines, @sprintf("G1 E%.3f F%.3f\n", retract_ext_dist, retract_speed * 60.0))
    return gcode_lines
end

function _paths_gcode(s::Slicer, paths, ewidth, nozl, z)
    fil_diam = s.conf["nozzle_$(nozl)_filament"]
    nozl_diam = s.conf["nozzle_$(nozl)_filament"]
    max_speed = s.conf["nozzle_$(nozl)_max_speed"]
    layer_height = s.conf["layer_height"]
    retract_dist = s.conf["retract_dist"]
    retract_speed = s.conf["retract_speed"]
    retract_lift = s.conf["retract_lift"]
    feed_rate = s.conf["feed_rate"]
    travel_rate_xy = s.conf["travel_rate_xy"]
    travel_rate_z = s.conf["travel_rate_z"]
    ewidth = nozl_diam * s.extrusion_ratio
    xsect = π * ewidth / 2 * layer_height / 2
    fil_xsect = π * (fil_diam / 2)^2
    gcode_lines = String[]
    for line in _tool_change_gcode(s, nozl)
        push!(gcode_lines, line)
    end
    for path in paths
        ox, oy = path[1][1], path[1][2]
        if retract_lift > 0 || s.last_pos[3] != z
            s.total_build_time += abs(retract_lift) / travel_rate_z
            push!(gcode_lines, @sprintf("G1 Z%.2f F%.3f\n", z + retract_lift, travel_rate_z * 60.0))
        end
        dist = hypot(s.last_pos[1] - oy, s.last_pos[2] - ox)
        s.total_build_time += dist / travel_rate_xy
        push!(gcode_lines, @sprintf("G0 X%.2f Y%.2f F%.3f\n", ox, oy, travel_rate_xy * 60.0))
        if retract_lift > 0
            s.total_build_time += abs(retract_lift) / travel_rate_z
            push!(gcode_lines, @sprintf("G1 Z%.2f F%.3f\n", z, travel_rate_z * 60.0))
        end
        if retract_dist > 0
            s.total_build_time += abs(retract_dist) / retract_speed
            push!(gcode_lines, @sprintf("G1 E%.3f F%.3f\n", s.last_e + retract_dist, retract_speed * 60.0))
            s.last_e += retract_dist
        end
        for point in path[2:end]
            x, y = point[1], point[2]
            dist = hypot(y - oy, x - ox)
            fil_dist = dist * xsect / fil_xsect
            speed = min(feed_rate, max_speed) * 60.0
            s.total_build_time += dist / feed_rate
            s.last_e += fil_dist
            push!(gcode_lines, @sprintf("G1 X%.2f Y%.2f E%.3f F%.3f\n", x, y, s.last_e, speed))
            s.last_pos = (x, y, z)
            ox, oy = x, y
        end
        if retract_dist > 0
            s.total_build_time += abs(retract_dist) / retract_speed
            push!(gcode_lines, @sprintf("G1 E%.3f F%.3f\n", s.last_e - retract_dist, retract_speed * 60.0))
            s.last_e -= retract_dist
        end
    end
    return gcode_lines
end

function _display_paths(s::Slicer)
    try
        using Gtk.ShortNames
    catch e
        println("Gtk not available. GUI display skipped.")
        return
    end
    # A simple placeholder implementation.
    println("Launching GUI viewer – this part must be implemented using your preferred GUI toolkit.")
end

function _zoom(s::Slicer; incdec=0, val=nothing)
    println("Zoom functionality not implemented in this translation.")
end

function _redraw_paths(s::Slicer; incdec=0)
    println("Redrawing paths not implemented in this translation.")
end

function _draw_line(s::Slicer, paths; offset=0, colors=["red", "green", "blue"], ewidth=0.5)
    println("Drawing line not implemented in this translation.")
end

end  # module MandolineSlicer
