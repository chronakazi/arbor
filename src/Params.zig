//! Params.zig
//! some delclarations for handling parameters & changes

const std = @import("std");
const Plugin = @import("Plugin.zig");
const ClapPlugin = @import("clap_plugin.zig");
pub const clap = @cImport({
    @cInclude("clap/clap.h");
});

const c_cast = std.zig.c_translation.cast;

const Self = @This();

/// clamp a float to a 0 - 1 range
pub fn FloatClamp01(x: anytype) @TypeOf(x) {
    return if (x >= 1.0) 1.0 else if (x <= 0) 0 else x;
}

values: Values = Values{},
pub const numParams: u32 = std.meta.fields(Values).len;
/// structure for plugin parameters
/// stored as named values
pub const Values = struct {
    mix: f64 = 0.5,
    feedback: f64 = 0.2,
    // delay: f64 = 300.0,
    // freq: f64 = 1500.0,
};

pub const ParamInfo = struct {
    id: u32,
    name: []const u8,
    minValue: f64,
    maxValue: f64,
    defaultValue: f64,
};

pub const list = [std.meta.fields(Values).len]ParamInfo{
    .{ .id = 0, .name = "Mix", .minValue = 0.0, .maxValue = 1.0, .defaultValue = 0.5 },
    .{ .id = 1, .name = "Feedback", .minValue = 0.001, .maxValue = 0.35, .defaultValue = 0.2 },
    // .{ .id = 1, .name = "Delay", .minValue = 20.0, .maxValue = 2000.0, .defaultValue = 300.0 },
    // .{ .id = 2, .name = "Feedback", .minValue = 0.0, .maxValue = 1.0, .defaultValue = 0.0 },
    // .{ .id = 3, .name = "Freq", .minValue = 20.0, .maxValue = 20000.0, .defaultValue = 1500.0 },
};

pub fn count(plugin: [*c]const clap.clap_plugin_t) callconv(.C) u32 {
    _ = plugin;
    return std.meta.fields(Values).len;
}

fn getInfo(plugin: [*c]const clap.clap_plugin_t, index: u32, info: [*c]clap.clap_param_info_t) callconv(.C) bool {
    _ = plugin;
    const params = std.meta.fields(Values);
    switch (index) {
        inline 0...(params.len - 1) => |comptime_index| {
            // const param = params[comptime_index];
            // _ = param;
            info.* = .{
                .name = undefined,
                .module = undefined,
                .id = list[comptime_index].id,
                .flags = clap.CLAP_PARAM_IS_AUTOMATABLE | clap.CLAP_PARAM_IS_MODULATABLE,
                .min_value = list[comptime_index].minValue,
                .max_value = list[comptime_index].maxValue,
                .default_value = list[comptime_index].defaultValue,
                .cookie = null,
            };
            if (list[index].name.len > 0) {
                _ = std.fmt.bufPrintZ(&info.*.name, "{s}", .{list[index].name}) catch unreachable;
            } else {
                _ = std.fmt.bufPrintZ(&info.*.name, "N/A", .{}) catch unreachable;
            }
            return true;
        },
        else => return false,
    }
}

pub fn getNormalizedValue(self: *Self, id: u32) !f64 {
    const val = try self.idToValue(id);
    const param = list[id];
    return val / (param.maxValue - param.minValue);
}

pub fn idToName(id: u32) ![]u8 {
    std.debug.assert(id < numParams);
    inline for (list) |info| {
        if (info.id == id)
            return @constCast(info.name);
    }
    return error.CantFindName;
}

pub fn idToValue(self: *Self, id: u32) !f64 {
    std.debug.assert(id < numParams);
    const values = std.meta.fields(Values);
    inline for (values, 0..) |v, i| {
        if (list[i].id == id) {
            return @field(self.values, v.name);
        }
    }
    return error.CantFindValue;
}

pub fn nameToValue(self: *Self, name: []const u8) !f64 {
    const values = std.meta.fields(Values);
    inline for (values, 0..) |v, i| {
        if (std.mem.eql(u8, v.name, name))
            return self.idToValue(i);
    }
    return error.CantFindValue;
}

pub fn nameToID(name: []const u8) !u32 {
    const values = std.meta.fields(Values);
    inline for (values, 0..) |v, i| {
        if (std.mem.eql(u8, v.name, name))
            return i;
    }
    return error.CantFindValue;
}

pub fn getValue(plugin: [*c]const clap.clap_plugin_t, id: clap.clap_id, value: [*c]f64) callconv(.C) bool {
    const plug = c_cast(*Plugin, plugin.*.plugin_data);
    const paramValues = std.meta.fields(Values);
    const i = c_cast(u32, id);
    if (i >= paramValues.len)
        return false;
    value.* = plug.params.idToValue(i) catch unreachable;
    return true;
}

pub fn setValue(self: *Self, param_id: u32, value: f64) void {
    const values = std.meta.fields(Values);
    var valuePtr: *f64 = undefined;
    inline for (values, 0..) |v, i| {
        if (list[i].id == param_id) {
            valuePtr = &@field(self.values, v.name);
            valuePtr.* = value;
        }
    }
}

fn valueToText(plugin: [*c]const clap.clap_plugin_t, id: clap.clap_id, value: f64, display: [*c]u8, size: u32) callconv(.C) bool {
    _ = plugin;
    const buf: []u8 = display[0..size];
    const i = c_cast(u32, id);
    if (i >= std.meta.fields(Values).len) return false;
    // std.log.info("{s}: {d}", .{ display, value });
    _ = std.fmt.bufPrintZ(buf, "{d:.2}", .{value}) catch unreachable;
    return true;
}

fn textToValue(plugin: [*c]const clap.clap_plugin_t, param_id: clap.clap_id, display: [*c]const u8, value: [*c]f64) callconv(.C) bool {
    _ = value;
    _ = display;
    _ = param_id;
    _ = plugin;
    return false;
}

fn flush(plugin: [*c]const clap.clap_plugin_t, in: [*c]const clap.clap_input_events_t, out: [*c]const clap.clap_output_events_t) callconv(.C) void {
    _ = out;
    var c_plugin = c_cast(*ClapPlugin, plugin.*.plugin_data);
    const eventCount = in.*.size.?(in);
    // plug.syncMainToAudio(out);

    var eventIndex: u32 = 0;
    while (eventIndex < eventCount) : (eventIndex += 1) {
        c_plugin.processEvent(in.*.get.?(in, eventIndex));
    }
}

pub const Data = clap.clap_plugin_params_t{
    .count = count,
    .get_info = getInfo,
    .get_value = getValue,
    .value_to_text = valueToText,
    .text_to_value = textToValue,
    .flush = flush,
};