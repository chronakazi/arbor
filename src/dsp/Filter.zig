//! Trying to reinvent the filter for all time
//! (1 year later: ^ Not sure what I meant by that. I think just that these
//! should be the "default" IIRs instead of RBJ Cookbook)
//! Derived from "Matched Second Order Filters" by Martin Vicanek (2016)

const std = @import("std");

const Filter = @This();

pub const Coeffs = struct {
    a1: f32,
    a2: f32,
    b0: f32,
    b1: f32,
    b2: f32,
};

pub const Type = enum {
    Lowpass,
    Highpass,
    Bandpass,
};

cutoff: f32,
reso: f32,
coeffs: Coeffs,
filter_type: Type = .Lowpass,

xn: [][]f32,
yn: [][]f32,

allocator: std.mem.Allocator,

/// Create the filter and allocate its underlying memory
pub fn init(
    allocator: std.mem.Allocator,
    num_channels: u32,
    filter_type: Type,
    cutoff: f32,
    reso: f32,
) !Filter {
    const self: Filter = .{
        .allocator = allocator,
        .filter_type = filter_type,
        .reso = reso,
        .cutoff = cutoff,
        .coeffs = std.mem.zeroes(Coeffs),
        .xn = try allocator.alloc([]f32, num_channels),
        .yn = try allocator.alloc([]f32, num_channels),
    };

    for (self.xn) |*xn|
        xn.* = try allocator.alloc(f32, 2);
    for (self.yn) |*yn|
        yn.* = try allocator.alloc(f32, 2);

    return self;
}

/// deallocate filter state
pub fn deinit(self: *Filter) void {
    for (self.xn, 0..) |_, i|
        self.allocator.free(self.xn[i]);
    for (self.yn, 0..) |_, i|
        self.allocator.free(self.yn[i]);
    self.allocator.free(self.xn);
    self.allocator.free(self.yn);
}

pub fn reset(self: *Filter) void {
    for (self.xn, 0..) |_, i|
        self.xn[i] = [2]f32{ 0.0, 0.0 };

    for (self.yn, 0..) |_, i|
        self.yn[i] = [2]f32{ 0.0, 0.0 };
}

/// Must call this before processing or coefficients won't be initialized
pub fn setSampleRate(self: *Filter, sample_rate: f32) void {
    self.setCoeffs(sample_rate);
}

pub fn setCutoff(self: *Filter, cutoff: f32, sample_rate: f32) void {
    self.cutoff = cutoff;
    self.setCoeffs(sample_rate);
}

pub fn setReso(self: *Filter, reso: f32, sample_rate: f32) void {
    self.reso = reso;
    self.setCoeffs(sample_rate);
}

fn setCoeffs(self: *Filter, sr: f32) void {
    const w0 = 2.0 * std.math.pi * self.cutoff / sr;
    const q = 1.0 / (2.0 * self.reso);
    const tmp = @exp(-q * w0);
    self.coeffs.a1 = -2.0 * tmp;
    if (q <= 1.0)
        self.coeffs.a1 *= @cos(@sqrt(1.0 - q * q) * w0)
    else
        self.coeffs.a1 *= std.math.cosh(@sqrt(q * q - 1.0) * w0);
    self.coeffs.a2 = tmp * tmp;

    const f0 = self.cutoff / (sr * 0.5);
    const freq2 = f0 * f0;
    const fac = (1.0 - freq2) * (1.0 - freq2);

    switch (self.filter_type) {
        .Lowpass => {
            const r0 = 1.0 + self.coeffs.a1 + self.coeffs.a2;
            const r1_num = (1.0 - self.coeffs.a1 + self.coeffs.a2) * freq2;
            const r1_denom = @sqrt(fac + freq2 / (self.reso * self.reso));
            const r1 = r1_num / r1_denom;

            self.coeffs.b0 = (r0 + r1) / 2.0;
            self.coeffs.b1 = r0 - self.coeffs.b0;
            self.coeffs.b2 = 0.0;
        },
        .Highpass => {
            const r1_num = 1.0 - self.coeffs.a1 + self.coeffs.a2;
            const r1_denom = @sqrt(fac + freq2 / (self.reso * self.reso));
            const r1 = r1_num / r1_denom;

            self.coeffs.b0 = r1 / 4.0;
            self.coeffs.b1 = -2.0 * self.coeffs.b0;
            self.coeffs.b2 = self.coeffs.b0;
        },
        .Bandpass => {
            const r0 = (1.0 + self.coeffs.a1 + self.coeffs.a2) / (std.math.pi * f0 * self.reso);
            const r1_num = (1.0 - self.coeffs.a1 + self.coeffs.a2) * (f0 / self.reso);
            const r1_denom = @sqrt(fac + freq2 / (self.reso * self.reso));
            const r1 = r1_num / r1_denom;

            self.coeffs.b1 = -r1 / 2.0;
            self.coeffs.b0 = (r0 - self.coeffs.b1) / 2.0;
            self.coeffs.b2 = -self.coeffs.b0 - self.coeffs.b1;
        },
    }
}

pub fn process(self: *Filter, in: []const []const f32, out: []const []f32) void {
    for (in, 0..) |ch, ch_idx| {
        for (ch, 0..) |samp, i| {
            out[ch_idx][i] = self.processSample(ch_idx, samp);
        }
    }
}

pub fn processSample(self: *Filter, ch: usize, in: f32) f32 {
    std.debug.assert(ch < self.xn.len and ch < self.yn.len);
    const b = self.coeffs.b0 * in + self.coeffs.b1 * self.xn[ch][0] + self.coeffs.b2 * self.xn[ch][1];
    const a = -self.coeffs.a1 * self.yn[ch][0] - self.coeffs.a2 * self.yn[ch][1];
    const out = a + b;
    self.xn[ch][1] = self.xn[ch][0];
    self.xn[ch][0] = in;
    self.yn[ch][1] = self.yn[ch][0];
    self.yn[ch][0] = out;
    return out;
}