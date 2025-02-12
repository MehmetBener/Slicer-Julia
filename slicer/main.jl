using ArgParse
include("stl_data.jl")
using .stl_data
include("Slicer.jl")
using .Slicer

function build_parser()
    s = ArgParseSettings()
    @add_arg_table s begin
        "--outfile", "-o"
            help = "Slices STL and writes GCode to file."
        
        "--no-validation", "-n"
            action = :store_true
            help = "Skip performing model validation."
        
        "--gui-display", "-g"
            action = :store_true
            help = "Show sliced paths output in GUI."
        
        "--verbose", "-v"
            action = :store_true
            help = "Show verbose output."
        
        "--no-raft"
            action = :append_const
            constant = Symbol("adhesion_type=None")
            help = "Force adhesion to not be generated."
        
        "--raft"
            action = :append_const
            constant = Symbol("adhesion_type=Raft")
            help = "Force raft generation."
        
        "--brim"
            action = :append_const
            constant = Symbol("adhesion_type=Brim")
            help = "Force brim generation."
        
        "--no-support"
            action = :append_const
            constant = Symbol("support_type=None")
            help = "Force external support structure generation."
        
        "--support"
            action = :append_const
            constant = Symbol("support_type=External")
            help = "Force external support structure generation."
        
        "--support-all"
            action = :append_const
            constant = Symbol("support_type=Everywhere")
            help = "Force external support structure generation."
        
        "--filament", "-f"
            metavar = "MATERIAL,..."
            help = "Configures extruder(s) for given materials, in order. Ex: -f PLA,TPU,PVA"
        
        "--set-option", "-S"
            nargs = '*'   # zero or more values
            metavar = "OPTNAME=VALUE"
            help = "Set a slicing config option."
        
        "--query-option", "-Q"
            nargs = '*'   # zero or more values
            metavar = "OPTNAME"
            help = "Display a slicing config option value."
        
        "--write-configs", "-w"
            action = :store_true
            help = "Save any changed slicing config options."
        
        "--help-configs"
            action = :store_true
            help = "Display help for all slicing options."
        
        "--show-configs"
            action = :store_true
            help = "Display values of all slicing options."
        
        # Positional argument: allow zero or more file names.
        "infile"
            nargs = '*'   # returns a vector of strings (empty if none provided)
            help = "Optional STL filename(s)."
    end
    return s
end

function run_main()
    # Build the parser and parse arguments.
    s = build_parser()
    parsed_args = parse_args(s)
    
    # Optionally print the parsed arguments when verbose is enabled.
    if get(parsed_args, "verbose", false)
        println("Parsed arguments: ", parsed_args)
    end

    # Create an instance of your STL data.
    # (Assumes that stl_data.jl defines a module StlData with a constructor StlData().)
    stl = stl_data.stl_data()

    # Process the positional argument "infile".
    # Since we used nargs='*', we get a vector (which may be empty).
    infile_list = get(parsed_args, "infile", String[])
    if length(infile_list) == 0
        println("No STL file provided; continuing without one.")
    else
        # Use the first file if multiple are provided.
        infile = infile_list[1]
        stl.read_file(infile)
        if get(parsed_args, "verbose", false)
            println("Read $(infile) ($(length(stl.facets)) facets, ",
                    stl.points.maxx - stl.points.minx, " x ",
                    stl.points.maxy - stl.points.miny, " x ",
                    stl.points.maxz - stl.points.minz, ")")
        end
        if !get(parsed_args, "no_validation", false)
            manifold = stl.check_manifold(verbose = get(parsed_args, "verbose", false))
            if manifold && (get(parsed_args, "verbose", false) || get(parsed_args, "gui_display", false))
                println("$(infile) is manifold.")
            end
            if !manifold
                exit(-1)
            end
        else
            println("Skipping validation.")
        end
    end

    # Create a Slicer instance with the STL data.
    # (Assumes Slicer.jl defines a module Slicer with a constructor Slicer(models).)
    slicer = Slicer.Slicer([stl])
    slicer.load_configs()

    # Process --set-option arguments.
    if haskey(parsed_args, "set_option")
        for opt in parsed_args["set_option"]
            # Convert opt to a string if it is a Symbol.
            opt_val = opt isa Symbol ? string(opt) : opt
            key, val = split(opt_val, '=', limit = 2)
            slicer.set_config(key, val)
        end
    end

    # Process --query-option arguments.
    if haskey(parsed_args, "query_option")
        for qopt in parsed_args["query_option"]
            slicer.display_configs_help(key = qopt, vals_only = true)
        end
    end

    # Process the filament argument if provided.
    if haskey(parsed_args, "filament") && !isempty(parsed_args["filament"])
        materials = split(lowercase(parsed_args["filament"]), ",")
        for (extnum, material) in enumerate(materials)
            if !haskey(slicer.conf, "$(material)_hotend_temp")
                println("Unknown material: $(material)")
                exit(-1)
            end
        end
        newbedtemp = maximum([slicer.conf["$(material)_bed_temp"] for material in materials])
        slicer.set_config("bed_temp", string(newbedtemp))
        for (extnum, material) in enumerate(materials)
            println("Configuring extruder$(extnum-1) for $(material)")
            slicer.set_config("nozzle_$(extnum-1)_temp", string(slicer.conf["$(material)_hotend_temp"]))
            slicer.set_config("nozzle_$(extnum-1)_max_speed", string(slicer.conf["$(material)_max_speed"]))
        end
    end

    # Determine the output file name.
    outfile = ""
    if haskey(parsed_args, "outfile") && !isempty(parsed_args["outfile"])
        outfile = parsed_args["outfile"]
    else
        if length(infile_list) > 0
            outfile = replace(infile_list[1], r"\.[^.]+$" => ".gcode")
        else
            outfile = "output.gcode"
        end
    end

    slicer.slice_to_file(outfile, showgui = get(parsed_args, "gui_display", false))
    println("Slicing complete.")
    exit(0)
end

if abspath(PROGRAM_FILE) == @__FILE__
    run_main()
end