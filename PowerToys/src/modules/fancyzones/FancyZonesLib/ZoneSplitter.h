#pragma once

#include <FancyZonesLib/Zone.h>

#include <map>

// The border between two laid-out windows is a seam both sides share: moving it hands one side
// exactly what it takes from the other, which is what makes it a splitter rather than a resize of
// one window. Everything here is pure geometry over the zones of one work area, so it can be
// reasoned about - and checked - without a desktop in front of it.
namespace ZoneSplitter
{
    // Which rectangles the borders are computed from - keyed by zone index, in the work area
    // overlay's coordinates. Deliberately not the layout's own zones: the layout keeps describing
    // the proportions it was designed with, while the point a person is trying to grab is where
    // two windows actually touch, which is a different place as soon as one of them has been
    // dragged. FancyZones.cpp builds this from the windows' visible frames.
    using Geometry = std::map<ZoneIndex, RECT>;

    // How close to a boundary the pointer has to be to count as grabbing it, and how far apart two
    // zone edges may sit and still be the same seam. Both in physical screen pixels.
    constexpr long HitBand = 6;
    constexpr long TouchTolerance = 2;

    // Never make a zone thinner than this along the axis being moved; the windows' own minimum
    // track size is respected on top of it.
    constexpr long MinZoneSide = 80;

    struct Seam
    {
        bool vertical{};
        long at{}; // x when vertical, y when horizontal
        long spanFrom{}; // the run the seam actually covers, at right angles to itself
        long spanTo{};
        std::vector<ZoneIndex> nearSide; // zones that END on the seam
        std::vector<ZoneIndex> farSide;  // zones that START on the seam

        // The whole span the two sides occupy together, along the axis being moved.
        long GroupStart(const Geometry& zones) const noexcept;
        long GroupEnd(const Geometry& zones) const noexcept;
    };

    // Every place two zones sit on each other. Zones that merely share a coordinate are not seams:
    // they have to overlap along it, or the border between them is not a border.
    std::vector<Seam> CollectSeams(const Geometry& zones);

    // The seam under pt, or nullptr. The pointer has to be inside the band and inside the run.
    const Seam* FindSeam(const std::vector<Seam>& seams, POINT pt) noexcept;

    // Where the seam would have to be to split the space both sides occupy evenly.
    long EqualisedAt(const Geometry& zones, const Seam& seam) noexcept;

    // The new rect of every zone touching the seam, when the seam is moved to `to`. Stops short at
    // the tightest zone, so a drag that cannot finish moves as far as it may and no further. Zones
    // that end up unchanged are left out.
    std::map<ZoneIndex, RECT> ShiftedZones(const Geometry& zones, const Seam& seam, long to, long minSide);
}
