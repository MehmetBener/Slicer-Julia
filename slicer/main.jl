using ArgParse

# Bring in STL data code
include("stl_data.jl")
using .stl_data

# Bring in Slicer code
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
            help = "Configures extruder(s) for given materials, in order."

        "--set-option", "-S"
            nargs = '*'
            metavar = "OPTNAME=VALUE"
            help = "Set a slicing config option."

        "--query-option", "-Q"
            nargs = '*'
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

        "infile"
            nargs = '*'
            help = "Optional STL filename(s)."
    end
    return s
end

function run_main()
    s = build_parser()
    parsed_args = parse_args(s)

    if get(parsed_args, "verbose", false)
        println("Parsed arguments: ", parsed_args)
    end

    stl = StlData()

    infile_list = get(parsed_args, "infile", String[])
    if length(infile_list) == 0
        println("No STL file provided; continuing without one.")
    else
        infile = infile_list[1]
        stl.read_file(infile)
        if get(parsed_args, "verbose", false)
            println("Read $(infile) with $(length(stl.facets.facet_hash)) facets")
        end
        if !get(parsed_args, "no_validation", false)
            manifold = stl.check_manifold(verbose=get(parsed_args, "verbose", false))
            if manifold && (get(parsed_args, "verbose", false) || get(parsed_args, "gui_display", false))
                println("$(infile) is manifold.")
            end
            if !manifold
                exit(1)  # changed from -1
            end
        else
            println("Skipping validation.")
        end
    end

    slicer = Slicer([stl])
    slicer.load_configs!()

    if haskey(parsed_args, "set_option")
        for opt in parsed_args["set_option"]
            if !occursin("=", opt)
                continue
            end
            key, val = split(opt, '=', limit=2)
            slicer.set_config!(key, val)
        end
    end

    if haskey(parsed_args, "query_option")
        for qopt in parsed_args["query_option"]
            slicer.display_configs_help(key=qopt, vals_only=true)
        end
    end

    # Filament argument
    if haskey(parsed_args, "filament") && !isempty(parsed_args["filament"])
        materials = split(lowercase(parsed_args["filament"]), ",")
        for (extnum, material) in enumerate(materials)
            mat_bed_key = "$(material)_bed_temp"
            mat_hotend_key = "$(material)_hotend_temp"
            if !haskey(slicer.conf, mat_hotend_key)
                println("Unknown material: $(material)")
                exit(1)
            end
        end
        newbedtemp = maximum([slicer.conf["$(material)_bed_temp"] for material in materials])
        slicer.set_config!("bed_temp", string(newbedtemp))
        for (extnum, material) in enumerate(materials)
            println("Configuring extruder$(extnum-1) for $(material)")
            slicer.set_config!("nozzle_$(extnum-1)_temp", string(slicer.conf["$(material)_hotend_temp"]))
            slicer.set_config!("nozzle_$(extnum-1)_max_speed", string(slicer.conf["$(material)_max_speed"]))
        end
    end

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

    # Actually run the slicer to produce GCode
    slicer.slice_to_file!(outfile, showgui = get(parsed_args, "gui_display", false))
    println("Slicing complete.")

    if get(parsed_args, "write_configs", false)
        slicer.save_configs!()
    end

    if get(parsed_args, "help_configs", false)
        slicer.display_configs_help()
    elseif get(parsed_args, "show_configs", false)
        slicer.display_configs_help(vals_only=true)
    end

    exit(0)
end

if abspath(PROGRAM_FILE) == @__FILE__
    run_main()
end
