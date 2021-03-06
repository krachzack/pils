module pils.solving.solver;

public
{
    import pils.solving.layout;
    import pils.geom.types;
}

private
{
    import pils.geom.sets;
    import pils.geom.tesselate;
    import pils.geom.dump;
    import pils.geom.minkowski;
    import pils.geom.basis;
    import pils.geom.transform;
    import pils.geom.random;
    import pils.entity.catalog;

    import std.conv : to;
    import std.stdio;
    import std.random;
    import std.array;
    import std.exception : enforce;
    import std.algorithm.searching : all, canFind;
    import std.algorithm.iteration : map, joiner, filter, fold;
    import std.random;
    import std.traits;
    import std.range.primitives;
    import std.typecons : tuple;
}

/++
 + Provides the core placement logic that applies constraints to find possible
 + locations of an object and randomly choosing one of those.
 +/
class Solver
{
    /++
     + Creates a new solver with the given starting layout.
     +/
    this(Layout layout)
    {
        this.layout = layout;
    }

    bool cannotOverlap(Feature f1, Feature f2)
    {
        return f1.tags.canFind("OffLimits") && f2.tags.canFind("OffLimits");
    }

    bool place(H)(Blueprint blueprint, H habitatTagsRange) if(isForwardRange!H && isSomeString!(ElementType!H))
    {
        enforceHabitatFeatureAssumptions(layout.findFeaturesByTags(habitatTagsRange), habitatTagsRange);

        auto habitatEnts = findEntities(habitatTagsRange);
        auto firstHabitatEnt = habitatEnts.front[0];
        auto firstHabitatEntFeature = habitatEnts.front[1].front;

        // The layout calculations will be performed in the pose of the first
        // habitat feature containing entity
        // and then transformed back into world space at the end of the method
        auto layoutPose = combine(firstHabitatEnt.pose, firstHabitatEntFeature.pose);

        // Get all entities with features containing any of the given tags
        auto worldHabitatPolygons = habitatEnts.map!((e) {
            auto ent = e[0];
            auto habitatFeatures = e[1];
            return habitatFeatures.map!(f => combine(ent.pose, f.pose).transform(f.polygon));
        }).joiner;

        Polygon habitat = worldHabitatPolygons.map!(p => layoutPose.untransform(p))
                                              .fold!merge();

        // For now, OffLimits is incompatible to everything else and thats it
        // In the future, it should be based on some blueprint feature setting
        string[] incompatibleTags = [ "OffLimits" ];
        habitat = conserveOccuppiedHabitat(habitat, layoutPose, blueprint, incompatibleTags);

        // TODO recover original elevation from globalHabitat

        bool habitatAvailable = habitat.contours.length > 0;

        if(habitatAvailable)
        {
            vec2d placementHabitatPoint = selectRandomLocation(habitat);
            vec3d worldPlacementPoint = layoutPose.transform(placementHabitatPoint);
            layout ~= blueprint.build(worldPlacementPoint);
        }

        return habitatAvailable;
    }

    bool place(S)(Blueprint blueprint, S habitatTag) if(isSomeString!S)
    {
        return place(blueprint, [ habitatTag ]);
    }

private:
    Layout layout;

    /++
     + Returns a new polygon that is created by merging all polygons of the
     + given features transformed into the given targetPose. The features are
     + assumed to share the same Z axis.
     +/
    Polygon combineFeatures(F)(Pose targetPose, F features) if(isForwardRange!F && is(ElementType!F == Feature))
    {
        // Range of polygons in the space of the first pose
        auto targetPosePolygons = features.map!(f => f.polygon.convert(f.pose, targetPose));
        return targetPosePolygons.fold!merge();
    }

    auto findEntities(T)(T tagRange) if(isForwardRange!T && isSomeString!(ElementType!T))
    {
        return layout.entities.map!(
            e => tuple(
                e,
                e.features.filter!(f => f.tags.any!(t => tagRange.canFind(t)))
            )
        )().filter!((e) => !e[1].empty);
    }

    Polygon conserveOccuppiedHabitat(T)(Polygon baseHabitat, Pose layoutPose, Blueprint blueprint, T incompatibleTags) if(isForwardRange!T && isSomeString!(ElementType!T))
    {
        auto requiredHabitat = blueprint.features.map!(
            f => layoutPose.untransform(
                    f.pose.transform(f.polygon)
                 )
        ).fold!merge;

        auto occuppiedHabitat = findEntities(incompatibleTags).map!(
            e => e[1].map!(
                f => layoutPose.untransform(
                        combine(f.pose, e[0].pose).transform(f.polygon)
                     )
            )
        ).joiner;

        auto offsetOccuppiedHabitat = occuppiedHabitat.map!(
            p => minkowskiSum(p, requiredHabitat)
        );

        auto remainingHabitat = offsetOccuppiedHabitat.fold!difference(baseHabitat);

        return remainingHabitat;
    }

    vec2d selectRandomLocation(Polygon poly)
    {
        auto allTriangles     = poly.triangles.array;
        auto allAreas         = allTriangles.map!((t) => t.area)();
        auto anyTriangleIndex = dice(allAreas);

        auto anyTriangle = allTriangles[anyTriangleIndex];

        return anyTriangle.randomPoint;
    }

    void enforceHabitatFeatureAssumptions(T, H)(T globalHabitat, H habitatTagsRange) if(is(ElementType!T == Feature) && isForwardRange!H && isSomeString!(ElementType!H))
    {
        enforce(!globalHabitat.empty, "No habitat with tags  " ~ to!string(habitatTagsRange) ~ " could not be found");

        auto scales = globalHabitat.map!(f => f.pose.scale);
        auto firstScale = scales.front;
        bool isUniformScale = scales.all!(s => s == firstScale);
        // Actually, non-uniform scales might even work, but right now, it is complicated enough without thinking about it
        enforce(isUniformScale, "Sorry all potential habitat features need to have the same scale in order for this thing to work");

        auto ups = globalHabitat.map!(f => f.pose.unitY);
        auto firstUp = ups.front;
        bool isUniformUp = ups.all!(u => u == firstUp);
        enforce(isUniformUp, "Sorry, we use 2D algorithms here, which means that all habitat features need to have the same up direction");
    }
}
