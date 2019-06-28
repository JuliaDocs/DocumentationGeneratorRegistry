using Pkg

Pkg.instantiate()

using Test, UUIDs, HTTP

const REGISTRY_PATH = joinpath(@__DIR__, "..", "Registry.toml")
const VALID_METHODS = ("hosted", "git-repo", "vendored")

isurlish(url) = occursin(r"(http|https|git)\://.*", url)

function testkeyvalidity(registry, key)
    uuid = UUID(key)

    entry = registry[key]

    if !haskey(entry, "name")
        @error("`name` entry missing for `$(uuid)`.")
        return false
    end
    name = entry["name"]

    method = ""
    if haskey(entry, "method")
        method = entry["method"]
        if !(method in VALID_METHODS)
            @error("Invalid method `$(method)` specified for `$(name)` ($(uuid)).")
            return false
        end
    else
        @error("No `method` specified for `$(name)` ($(uuid)).")
        return false
    end

    if haskey(entry, "location")
        uri = entry["location"]
        if method in ("git-repo", "hosted")
            if isurlish(uri)
                req = try
                    HTTP.request("GET", uri)
                    if req.status > 400
                        @error("""
                              `$(uri)` returned `$(req.status)` for `$(name)` ($(uuid)).
                              Please double check the URL.
                              """)
                        return false
                    end
                catch err
                    @error("""
                          `$(uri)` request failed for `$(name)` ($(uuid)).
                          Please double check the URL.
                          """)
                    return false
                end
            else
                @error("Invalid URL `$(uri)` for `$(name)` ($(uuid)).")
                return false
            end
        elseif method == "vendored"
            if isurlish(uri)
                @error("`location` should not be a URL for vendored docs in `$(name)` ($(uuid)).")
                return false
            end
        end
    else
        @error("No `location` specified for `$(name)` ($(uuid)).")
        return false
    end

    return true
end


@testset "Registry Validity" begin
    @test isfile(REGISTRY_PATH)
    toml = Pkg.TOML.parsefile(REGISTRY_PATH)
    @test collect(unique(keys(toml))) == collect(keys(toml))
    @testset "Package: $(key)" for key in keys(toml)
        isvalid = testkeyvalidity(toml, key)
        @test isvalid
    end
end
