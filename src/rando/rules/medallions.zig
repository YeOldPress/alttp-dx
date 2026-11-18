//! The medallion locations, which say what opens Turtle Rock and Misery
//! Mire: a port of the VT randomizer's app/Region/Standard/Medallions.php
//! (github.com/sporchia/alttp_vt_randomizer, MIT). VT gives them no rules.
const r = @import("../rules.zig");

pub const region = r.RegionRules{ .region = .medallions };
