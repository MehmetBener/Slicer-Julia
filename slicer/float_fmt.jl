module FloatFmt

using Printf

export float_fmt

function float_fmt(val)
    s = @sprintf("%.6f", val)
    s = rstrip(s, "0")
    s = rstrip(s, ".")
    return s == "-0" ? "0" : s
end

end
