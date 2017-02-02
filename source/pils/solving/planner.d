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
}

/++
 + Submits objects to the solver, which in turn places them one by one.
 + The Planner provides some higher level control, e.g. place 12 desks or
 + add wardrobes until there is 3 cubic meters of space for clothes.
 +
 + The Planner works by executing a number of rules in order.
 +/
 // place X instances of class Y
 // place as many objects of class Z as possible
 // keep adding cupboards until the total amount of storage space exceeds 1.3 cubic meters
 // if context is “dinner” place 5 plates on a table in front of a chair and stack 10 plates in storage features, else stack 15 plates in storage features
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
     +/
    void place(string id, string groundTag, size_t count=1)
    {
        auto blueprint = lib.findByID(id);

        enforce(blueprint !is null, "Cannot place id " ~ id ~ " because it could not be found");

        foreach(i; 0..count)
        {
            solver.place(blueprint, groundTag);
        }
    }
}