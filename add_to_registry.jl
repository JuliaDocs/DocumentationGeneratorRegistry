const REGISTRY_PATH = joinpath(@__DIR__, "Registry.toml")

using Pkg
using UUIDs
using REPL.TerminalMenus

function yesno(query)
    menu = RadioMenu(["Yes", "No"])
    return request(query, menu) == 1
end

if VERSION < v"1.7.0"
    function get_pkgs_in_general()
        registries = Pkg.Types.collect_registries()
        general = registries[findfirst(reg -> reg.uuid == UUID("23338594-aafe-5451-b93e-139f81909106"), registries)]

        return Pkg.Types.read_registry(joinpath(general.path, "Registry.toml"))["packages"]
    end
else
    function get_pkgs_in_general()
        registries = Pkg.Registry.reachable_registries()
        general = registries[findfirst(reg -> reg.uuid == UUID("23338594-aafe-5451-b93e-139f81909106"), registries)]

        return general.pkgs
    end
end

function valid_location(method, location)
    isempty(location) && return false

    if method == "vendored"
        if occursin(r"^(/|\\)", location)
            printstyled("\n`location` for `vendored` docs must be path relative to the package's root directory.\n", color=:red)
            return false
        end
    else
        if !occursin(r"^(http|https|git)\://", location)
            printstyled("\n`location` for `hosted` or `git-repo` docs must be a valid URL.\n", color=:red)
            return false
        end
    end
    return true
end

function get_config(pkg; novendor = false)
    methods = novendor ? ["hosted", "git-dir"] : ["vendored", "hosted", "git-dir"]
    menu = RadioMenu(methods)
    method = methods[request("Choose a `method` for $(pkg):", menu)]
    println()

    location = ""
    while !valid_location(method, location)
        println("Please choose a `location` for $(pkg):")
        location = strip(readline())
    end

    println()
    return Dict(
        "method" => method,
        "location" => location
    )
end

function add_by_uuid(uuid, pkg, config)
    if config == nothing
        config = get_config(pkg)
    end
    config["name"] = pkg

    toml = Pkg.TOML.parsefile(REGISTRY_PATH)
    if haskey(toml, uuid)
        println("UUID `$(uuid)` for package `$(pkg)` already in registry.")
        overwrite = yesno("Do you want to overwrite the existing entry?")
        println()
        if !overwrite
            return false
        end
    end
    toml[uuid] = config
    open(REGISTRY_PATH, "w") do io
        Pkg.TOML.print(io, toml)
    end
    return true
end

function add_to_registry(pkg, general_pkgs, config = config)
    pkgs_with_name = String[]
    for (uuid, _pkg) in general_pkgs
        name = VERSION < v"1.7.0" ? _pkg["name"] : _pkg.name
        name == pkg && push!(pkgs_with_name, string(uuid))
    end

    if length(pkgs_with_name) == 0
        printstyled("No package with name `$(pkg)` found in registry. Skipping.\n ", color=:red)
        return false
    elseif length(pkgs_with_name) > 1
        menu = MultiSelectMenu(pkgs_with_name)
        indices = request("Choose one or multiple UUIDs for which you want to add a documentation hosting method:", menu)
        pkgs_with_name = pkgs_with_name[indices]
    end

    for uuid in pkgs_with_name
        success = add_by_uuid(uuid, pkg, config)
    end
end

function main(pkgnames)
    general_pkgs = get_pkgs_in_general()

    config = nothing
    if length(pkgnames) > 1
        one_for_all = yesno("Will all packages have the same configuration?")
        println()

        if one_for_all
            config = get_config("all provided packages", novendor = one_for_all)
        end
    end

    for pkg in pkgnames
        success = add_to_registry(pkg, general_pkgs, config)
    end
end


if length(ARGS) == 0 || any(isempty.(ARGS))
    println("Please provide one or multiple package names as arguments.")
else
    try
        main(ARGS)
    catch err
        println("\n")
        printstyled("An error occured. Please revert any changes and try again.\n", color=:red)
        @error "internal error" exception=(err, catch_backtrace())
    end
    println("Please commit your changes and open a PR.")
end
