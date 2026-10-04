#include "pch.h"
#include "ZoneSplitter.h"

#include <algorithm>

namespace ZoneSplitter
{
    namespace
    {
        RECT RectOf(const Geometry& zones, ZoneIndex id)
        {
            const auto it = zones.find(id);
            return it == zones.end() ? RECT{} : it->second;
        }

        // "Start"/"end" run along the axis the seam moves on; "from"/"to" along the one it covers.
        long StartOf(const RECT& r, bool vertical) { return vertical ? r.left : r.top; }
        long EndOf(const RECT& r, bool vertical) { return vertical ? r.right : r.bottom; }
        long FromOf(const RECT& r, bool vertical) { return vertical ? r.top : r.left; }
        long ToOf(const RECT& r, bool vertical) { return vertical ? r.bottom : r.right; }

        bool Overlaps(const RECT& a, const RECT& b, bool vertical)
        {
            return (std::max)(FromOf(a, vertical), FromOf(b, vertical)) < (std::min)(ToOf(a, vertical), ToOf(b, vertical));
        }

        void AddOnce(std::vector<ZoneIndex>& list, ZoneIndex id)
        {
            if (std::find(list.begin(), list.end(), id) == list.end())
            {
                list.push_back(id);
            }
        }

        // A border with nothing on one side is the edge of the desktop, not a splitter.
        bool Usable(const Seam& seam)
        {
            return !seam.nearSide.empty() && !seam.farSide.empty();
        }
    }

    long Seam::GroupStart(const Geometry& zones) const noexcept
    {
        long value = at;
        for (ZoneIndex id : nearSide)
        {
            value = (std::min)(value, StartOf(RectOf(zones, id), vertical));
        }
        return value;
    }

    long Seam::GroupEnd(const Geometry& zones) const noexcept
    {
        long value = at;
        for (ZoneIndex id : farSide)
        {
            value = (std::max)(value, EndOf(RectOf(zones, id), vertical));
        }
        return value;
    }

    std::vector<Seam> CollectSeams(const Geometry& zones)
    {
        std::vector<Seam> seams;

        for (const auto& [aId, aZone] : zones)
        {
            for (const auto& [bId, bZone] : zones)
            {
                if (bId <= aId)
                {
                    continue;
                }

                for (int axis = 0; axis < 2; ++axis)
                {
                    const bool vertical = axis == 0;
                    // Either order is the same border: a's right meeting b's left is b's left
                    // meeting a's right, and both sides of it have to end up on one seam.
                    for (int flip = 0; flip < 2; ++flip)
                    {
                        const RECT nearRect = flip == 0 ? aZone : bZone;
                        const RECT farRect = flip == 0 ? bZone : aZone;
                        const ZoneIndex nearId = flip == 0 ? aId : bId;
                        const ZoneIndex farId = flip == 0 ? bId : aId;

                        if (std::abs(EndOf(nearRect, vertical) - StartOf(farRect, vertical)) > TouchTolerance)
                        {
                            continue;
                        }
                        if (!Overlaps(nearRect, farRect, vertical))
                        {
                            continue;
                        }

                        Seam candidate;
                        candidate.vertical = vertical;
                        candidate.at = (EndOf(nearRect, vertical) + StartOf(farRect, vertical)) / 2;
                        candidate.spanFrom = (std::max)(FromOf(nearRect, vertical), FromOf(farRect, vertical));
                        candidate.spanTo = (std::min)(ToOf(nearRect, vertical), ToOf(farRect, vertical));
                        candidate.nearSide.push_back(nearId);
                        candidate.farSide.push_back(farId);

                        const auto existing = std::find_if(seams.begin(), seams.end(), [&candidate](const Seam& seam) {
                            return seam.vertical == candidate.vertical && std::abs(seam.at - candidate.at) <= TouchTolerance;
                        });
                        if (existing == seams.end())
                        {
                            seams.push_back(candidate);
                        }
                        else
                        {
                            // "One left, two right" is one seam whose far side holds both of them.
                            // `at` stays where the first pair put it: moving the seam drags every
                            // edge on it to the same number, which closes a sub-pixel disagreement.
                            AddOnce(existing->nearSide, nearId);
                            AddOnce(existing->farSide, farId);
                            existing->spanFrom = (std::min)(existing->spanFrom, candidate.spanFrom);
                            existing->spanTo = (std::max)(existing->spanTo, candidate.spanTo);
                        }
                    }
                }
            }
        }

        std::erase_if(seams, [](const Seam& seam) { return !Usable(seam); });
        return seams;
    }

    const Seam* FindSeam(const std::vector<Seam>& seams, POINT pt) noexcept
    {
        for (const Seam& seam : seams)
        {
            const long across = seam.vertical ? pt.x : pt.y;
            const long along = seam.vertical ? pt.y : pt.x;
            if (std::abs(across - seam.at) <= HitBand && along >= seam.spanFrom && along <= seam.spanTo)
            {
                return &seam;
            }
        }
        return nullptr;
    }

    long EqualisedAt(const Geometry& zones, const Seam& seam) noexcept
    {
        return (seam.GroupStart(zones) + seam.GroupEnd(zones)) / 2;
    }

    std::map<ZoneIndex, RECT> ShiftedZones(const Geometry& zones, const Seam& seam, long to, long minSide)
    {
        std::map<ZoneIndex, RECT> result;
        const long at = seam.at;
        if (at == to)
        {
            return result;
        }

        // The two sides trade space, so each of them caps how far the border may travel: no zone on
        // either side may end up thinner than minSide.
        long lo = (std::min)(at, to);
        long hi = (std::max)(at, to);
        for (ZoneIndex id : seam.nearSide)
        {
            lo = (std::max)(lo, StartOf(RectOf(zones, id), seam.vertical) + minSide);
        }
        for (ZoneIndex id : seam.farSide)
        {
            hi = (std::min)(hi, EndOf(RectOf(zones, id), seam.vertical) - minSide);
        }
        if (lo > hi)
        {
            // Already as tight as it is allowed to be on one side; the drag goes nowhere.
            return result;
        }
        to = std::clamp(to, lo, hi);
        if (to == at)
        {
            return result;
        }

        for (ZoneIndex id : seam.nearSide)
        {
            RECT r = RectOf(zones, id);
            if (seam.vertical)
            {
                r.right = to;
            }
            else
            {
                r.bottom = to;
            }
            result[id] = r;
        }
        for (ZoneIndex id : seam.farSide)
        {
            RECT r = RectOf(zones, id);
            if (seam.vertical)
            {
                r.left = to;
            }
            else
            {
                r.top = to;
            }
            result[id] = r;
        }
        return result;
    }
}
