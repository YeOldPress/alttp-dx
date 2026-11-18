//! The two fairy fountains' bottle prizes: a port of the VT randomizer's
//! app/Region/Standard/Fountains.php (github.com/sporchia/alttp_vt_randomizer,
//! MIT). VT gives them no rules.
const r = @import("../rules.zig");

pub const region = r.RegionRules{ .region = .fountains };
