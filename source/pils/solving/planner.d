module pils.solving.planner;

public
{
    import pils.solving.layout;
    import pils.solving.solver;
    import pils.entity;
}

private
{
    import std.exception : enforce;
    import painlessjson;
    import std.json;
    import std.conv : to;
    import std.typecons : Nullable;
    import std.algorithm.iteration;
    import std.array : array;
    import std.range.primitives;
    import std.traits : isSomeString;
}

/++
 + Submits objects to the solver to perform high-level placement logic over the
 + more lower-level Solver.
 +
 + The Planner provides more abstract control, e.g. place 12 desks, add
 + wardrobes until there is 3 cubic meters of space for clothes or add as much
 + tables as possible.
 +/
class Planner
{
public:
    Solver solver;
    Catalog lib;
    Layout layout;

    this(Catalog lib)
    {
        layout = new Layout();
        solver = new Solver(layout);
        this.lib = lib;
    }

    /++
     + Instantiates a new entity constructed off the blueprint stored in
     + the catalog under the given id. The new entity will be placed at the
     + specified position.
     +
     + Note that no checks whatsoever are performed to ensure the placement is
     + valid. This should only be used for purposely unchecked placements, e.g.
     + to build the starting layout or to gain performance for some insertions
     + that the user can guarantee are safe.
     +/
    void instantiate(string id, vec3d position)
    {
        auto blueprint = lib.findByID(id);

        enforce(blueprint !is null, "Cannot instantiate id " ~ id ~ " because it could not be found");

        layout ~= blueprint.build(position);
    }

    /++
     + Places a new instance of the blueprint stored in the catalog under
     + the given ID in the current layout. The algorithm will find a suitable
     + location for the object. If no space is available for a new instance, the
     + call will silently fail and not add anything.
     +
     + Params:
     +          id = Catalog ID of the blueprint to place, e.g. krachzack.tv
     +          groundTags = Single tag string or range of tag strings where the object can be placed on
     +          count = How many objects of the same type to create
     +/
    void place(S)(string id, S groundTags, size_t count=1) if(isSomeString!S || isForwardRange!S && isSomeString!(ElementType!S))
    in
    {
        assert(count >= 0);
    }
    body
    {
        auto blueprint = lib.findByID(id);

        enforce(blueprint !is null, "Cannot place id " ~ id ~ " because it could not be found");
        enforce(count >= 0);

        foreach(i; 0..count)
        {
            bool placed = solver.place(blueprint, groundTags);

            // If there is no more space available, there is no use to try and
            // add more of the same kind
            if(!placed)
            {
                break;
            }
        }
    }

    /++
     + Carries out the given planning step.
     +
     + If the contained command is null, does nothing.
     +/
    void submit(A...)(A steps) if(A.length >= 1)
    {
        foreach(step; steps)
        {
            alias S = typeof(step);

            static if(is(S == PlanningStep))
            {
                auto params = step.params;

                // If parameter is an actual planning step, do it
                final switch(step.cmd)
                {
                    case PlanningCmd.none:
                        break;

                    case PlanningCmd.place:
                        size_t count = params.count.isNull ? 1 : params.count.get();
                        place(params.id.get(), params.habitatTags, count);
                        break;

                    case PlanningCmd.instantiate:
                        instantiate(params.id.get(), params.position.get());
                        break;
                }
            }
            else static if(isInputRange!S && is(ElementType!S == PlanningStep))
            {
                // If is a range, recurse, effectively flattening the parameters
                foreach(substep; step)
                {
                    submit(substep);
                }
            }
            else
            {
                // If is neither a planning step, nor a range of planning steps,
                // obviously there is a wrong parameter
                static assert(false);
            }
        }
    }

    unittest
    {
        auto planner = new Planner(new Catalog("dustsucker"));

        // Submitting nothing should fail instantiation
        assert(! __traits( compiles, planner.submit() ));

        assert(__traits( compiles, planner.submit(PlanningStep()) ),
             "Submitting a single planning step should compile");

        // These are nop commands, this should just not crash
        planner.submit(PlanningStep(), [PlanningStep(), PlanningStep()]);
    }
}

enum PlanningCmd
{
    none,
    place,
    instantiate
}

struct PlanningStep
{
    struct Params {
        Nullable!string id;
        Nullable!vec3d position;
        Nullable!size_t count;
        string[] habitatTags;
    }

    PlanningCmd cmd;
    Params params;

    static PlanningStep _fromJSON(JSONValue stepJson)
    {
        double doublify(const(JSONValue) v)
        {
            if(v.type() == JSON_TYPE.INTEGER)
            {
                return cast(double) v.integer;
            }
            else if(v.type() == JSON_TYPE.FLOAT)
            {
                return cast(double) v.floating;
            }

            return double.nan;
        }

        PlanningCmd cmdFromJson()
        {
            const(JSONValue)* cmdJson = "do" in stepJson;
            enforce(cmdJson, "No command (\"do\":) in planning step");
            enforce(cmdJson.type() == JSON_TYPE.STRING, "Command is not a string");

            switch(cmdJson.str)
            {
            case "instantiate":
                return PlanningCmd.instantiate;
            case "place":
                return PlanningCmd.place;
            default:
                throw new Exception("Unknown command " ~ cmdJson.str);
            }
        }

        Params paramsFromJson()
        {
            Params params;

            const(JSONValue)* paramJson = "with" in stepJson;
            enforce(paramJson, "No parameters (\"with\":) in planning step");
            enforce(paramJson.type() == JSON_TYPE.OBJECT, "\"with\": can only contain an object");

            const(JSONValue)* idJson = "id" in *paramJson;
            if(idJson)
            {
                enforce(idJson.type() == JSON_TYPE.STRING, "ID is not a string");
                params.id = idJson.str;
            }

            const(JSONValue)* positionJson = "position" in *paramJson;
            if(positionJson)
            {
                enforce(positionJson.type == JSON_TYPE.ARRAY, "Position is not an array");
                auto vals = positionJson.array;
                enforce(vals.length == 3, "Position does not have three components");
                double[] arr = vals.map!doublify().array;

                params.position = vec3d(arr[0], arr[1], arr[2]);
            }

            const(JSONValue)* countJson = "count" in *paramJson;
            if(countJson)
            {
                enforce(countJson.type() == JSON_TYPE.INTEGER ||
                        countJson.type() == JSON_TYPE.UINTEGER);

                params.count = countJson.integer;
            }

            const(JSONValue)* habitatJson = "habitat" in *paramJson;
            if(habitatJson)
            {
                enforce(habitatJson.type() == JSON_TYPE.OBJECT, "\"habitat\": can only contain an object");

                const(JSONValue)* habitatTagJson = "tag" in *habitatJson;
                if(habitatTagJson)
                {
                    params.habitatTags ~= habitatTagJson.str;
                }
            }

            return params;
        }

        return PlanningStep(cmdFromJson(), paramsFromJson());
    }

    unittest
    {
        string instantiation = q{{ "do": "instantiate", "with": { "id": "dustsucker.room", "position": [1, 2, 3] } }};
        PlanningStep instantiationStep = fromJSON!PlanningStep(parseJSON(instantiation));
        assert(instantiationStep.cmd == PlanningCmd.instantiate);
        assert(instantiationStep.params.id == "dustsucker.room");
        assert(instantiationStep.params.position == vec3d(1.0, 2.0, 3.0));
    }

    unittest
    {
        string placement = q{
            [
                {
                    "do": "place",
                    "with": {
                        "id": "dustsucker.couch",
                        "count": 3,
                        "habitat": {
                            "tag": "Ground"
                        },
                        "constraints": [
                            {
                                "constrain": "rotation",
                                "with": {
                                    "randomize": "y",
                                    "discrete": 8
                                }
                            },
                            {
                                "constrain": "proximity",
                                "with": {
                                    "tag": "Wall",
                                    "min": 0,
                                    "max": 0.1
                                }
                            }
                        ]
                    }
                }
            ]
        };

        PlanningStep placementStep = fromJSON!(PlanningStep[])(parseJSON(placement))[0];
        assert(placementStep.cmd ==  PlanningCmd.place);
        assert(placementStep.params.id == "dustsucker.couch");
        assert(placementStep.params.count == 3);
        assert(placementStep.params.habitatTags == ["Ground"]);
        // TODO constraints
    }
}
