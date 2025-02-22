module float_fmt

using Printf
export float_fmt

# Define an internal helper function.
function _float_fmt(val::Real)
    s = @sprintf("%.6f", val)
    s = rstrip(s, '0')
    s = rstrip(s, '.')
    return s == "-0" ? "0" : s
end

# Bind the helper function to the constant.
const float_fmt = _float_fmt

end # module float_fmt
