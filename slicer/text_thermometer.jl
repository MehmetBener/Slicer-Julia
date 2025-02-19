module text_thermometer

using Printf

mutable struct TextThermometer
    value::Float64
    target::Float64
    last_time::Float64
    update_period::Float64
    spincnt::Int
    spinchars::String
end

"""
    TextThermometer(; target=100.0, value=0.0, update_period=0.5)

Create a new TextThermometer with the given target, initial value, and update period.
"""
function TextThermometer(; target=100.0, value=0.0, update_period=0.5)
    return TextThermometer(value, target, time(), update_period, 0, "/-\\|")
end

"""
    set_target!(tt::TextThermometer, target)

Set the target value for the thermometer, reset the last update time and spinner counter.
"""
function set_target!(tt::TextThermometer, target)
    tt.target = target
    tt.last_time = time()
    tt.spincnt = 0
end

"""
    update!(tt::TextThermometer, value)

Update the thermometer’s current value. If the time elapsed since the last update is at least
`update_period`, it prints an updated progress bar (with a spinner) to standard output.
"""
function update!(tt::TextThermometer, value)
    tt.value = value
    now = time()
    if now - tt.last_time >= tt.update_period
        tt.last_time = now
        pct = 100.0 * tt.value / tt.target
        # Update spinner: in Python spincnt is 0-indexed; here we store 0-indexed value and add 1 when indexing.
        tt.spincnt = mod(tt.spincnt + 1, length(tt.spinchars))
        spinchar = pct >= 100.0 ? "" : string(tt.spinchars[tt.spincnt+1])
        # Build a progress bar of width 50: using '=' characters and appending the spinner character.
        bar = rpad(repeat("=", Int(floor(pct/2))) * spinchar, 50)
        # Print the progress bar with a carriage return so it overwrites the same line.
        print(@sprintf("\r  [%s] %.1f%%", bar, pct))
        flush(stdout)
    end
end

"""
    clear!(tt::TextThermometer)

Clear the current progress output from the terminal.
"""
function clear!(tt::TextThermometer)
    print(@sprintf("\r%78s\r", ""))
end

end  # module TextThermometer
