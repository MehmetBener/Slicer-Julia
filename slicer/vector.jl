module vector

using Printf
using LinearAlgebra

if !haskey(Base.loaded_modules, :float_fmt)
    include(joinpath(@__DIR__, "float_fmt.jl"))
end
using Main.float_fmt: float_fmt  # or using .float_fmt if float_fmt becomes a submodule

export Vector, dot, cross, length, normalize, angle

# A simple vector type wrapping a Vector{Float64}.
struct Vector
    values::Base.Vector{Float64}
end

# Constructor supports a single real, complex, or iterable.
function Vector(args...)
    if length(args) == 1
        val = args[1]
        if isa(val, Real)
            return Vector([float(val)])
        elseif isa(val, Complex)
            return Vector([float(real(val)), float(imag(val))])
        elseif isa(val, AbstractVector)
            return Vector([float(x) for x in val])
        else
            error("Unexpected argument type in Vector constructor.")
        end
    else
        return Vector([float(x) for x in args])
    end
end

Base.length(v::Vector) = length(v.values)

function Base.iterate(v::Vector, state=1)
    state > length(v.values) && return nothing
    return (v.values[state], state+1)
end

Base.getindex(v::Vector, i::Int) = v.values[i]
Base.hash(v::Vector, h::UInt) = hash(v.values, h)
Base.:(==)(v::Vector, w::Vector) = v.values == w.values

function Base.isless(v::Vector, w::Vector)
    m = max(length(v.values), length(w.values))
    for i in reverse(1:m)
        a = i <= length(v.values) ? v.values[i] : 0.0
        b = i <= length(w.values) ? w.values[i] : 0.0
        if a != b
            return a < b
        end
    end
    return false
end

# Subtraction
function Base.:-(v::Vector, w::AbstractVector)
    return Vector([v.values[i] - w[i] for i in 1:length(v.values)])
end

function Base.:-(w::AbstractVector, v::Vector)
    return Vector([w[i] - v.values[i] for i in 1:length(v.values)])
end

# Addition
function Base.:+(v::Vector, w::AbstractVector)
    return Vector([v.values[i] + w[i] for i in 1:length(v.values)])
end

function Base.:+(w::AbstractVector, v::Vector)
    return Vector([w[i] + v.values[i] for i in 1:length(v.values)])
end

# Division by scalar.
function Base.:/(v::Vector, s::Real)
    return Vector([x/s for x in v.values])
end

# Multiplication by scalar.
function Base.:*(v::Vector, s::Real)
    return Vector([x*s for x in v.values])
end

function Base.:*(s::Real, v::Vector)
    return Vector([s*x for x in v.values])
end

# Formatting support: define a local formatting function.
function my_format(v::Vector, fmt::AbstractString)
    vals = [float_fmt(x) for x in v.values]
    if occursin("a", fmt)
        return "[" * join(vals, ", ") * "]"
    elseif occursin("s", fmt)
        return join(vals, " ")
    elseif occursin("b", fmt)
        buf = IOBuffer()
        for x in v.values
            write(buf, Float32(x))
        end
        return String(take!(buf))
    else
        return "(" * join(vals, ", ") * ")"
    end
end

function Base.show(io::IO, v::Vector)
    print(io, "<Vector: ", my_format(v, "a"), ">")
end

# Dot product.
function dot(v::Vector, w::Vector)
    @assert length(v.values) == length(w.values)
    s = 0.0
    for i in 1:length(v.values)
        s += v.values[i] * w.values[i]
    end
    return s
end

# Cross product (only for 3D).
function cross(v::Vector, w::Vector)
    if length(v.values) != 3 || length(w.values) != 3
        error("Cross product is only defined for 3D vectors.")
    end
    return Vector(
        v.values[2]*w.values[3] - v.values[3]*w.values[2],
        v.values[3]*w.values[1] - v.values[1]*w.values[3],
        v.values[1]*w.values[2] - v.values[2]*w.values[1]
    )
end

# Euclidean length.
function length(v::Vector)
    return sqrt(sum(x -> x*x, v.values))
end

# Normalize vector.
function normalize(v::Vector)
    len = length(v)
    if len == 0
        error("Cannot normalize zero-length vector.")
    end
    return v / len
end

# Angle between two vectors (in radians).
function angle(v::Vector, w::Vector)
    l = length(v) * length(w)
    if l == 0
        return 0.0
    end
    return acos(dot(v, w) / l)
end

end # module vector
