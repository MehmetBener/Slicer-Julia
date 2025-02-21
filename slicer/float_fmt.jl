module float_fmt

using Printf

export float_fmt

if !@isdefined(float_fmt)
    function float_fmt(val::Real)
        s = @sprintf("%.6f", val)
        s = rstrip(s, '0')
        s = rstrip(s, '.')
        return s == "-0" ? "0" : s
    end
end

end # module float_fmt
