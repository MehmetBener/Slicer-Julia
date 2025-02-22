module text_thermometer

using Printf
using Base: time_ns  # for current timestamp in nanoseconds

"""
    current_time_s()

Return the current time in seconds as a floating-point number.
"""
function current_time_s()
    return time_ns() / 1e9
end

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
    return TextThermometer(value, target, current_time_s(), update_period, 0, "/-\\|")
end

"""
    set_target!(tt::TextThermometer, target)

Set the target value for the thermometer, reset the last update time and spinner counter.
"""
function set_target!(tt::TextThermometer, target)
    tt.target = target
    tt.last_time = current_time_s()
    tt.spincnt = 0
end

"""
    update!(tt::TextThermometer, value)

Update the thermometer’s current value. If enough time elapsed since the last update,
it prints an updated progress bar (with a spinner).
"""
function update!(tt::TextThermometer, value)
    tt.value = value
    now = current_time_s()
    if now - tt.last_time >= tt.update_period
        tt.last_time = now
        pct = 100.0 * tt.value / tt.target
        # spinner:
        tt.spincnt = mod(tt.spincnt + 1, length(tt.spinchars))
        spinchar = pct >= 100.0 ? "" : string(tt.spinchars[tt.spincnt+1])
        # progress bar of width 50
        barlen = Int(floor(pct/2))
        bar = repeat("=", barlen)
        bar = rpad(bar * spinchar, 50)
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

end  # module text_thermometer
