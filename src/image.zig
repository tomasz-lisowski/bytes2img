const std = @import("std");
const assert = std.debug.assert;
const ArgError = @import("main.zig").ArgError;

pub const ImageFormat = enum(u8) {
    Pbm = 0,
    Pgm = 1,
    Ppm = 2,

    pub fn parse(fmt_str_user: []const u8) ArgError!ImageFormat {
        const fmts = [_][]const u8{ "pbm", "pgm", "ppm" };
        var fmt_idx: u8 = 0;
        for (fmts) |fmt_str| {
            if (std.mem.eql(u8, fmt_str, fmt_str_user)) {
                return @intToEnum(ImageFormat, fmt_idx);
            }
            fmt_idx += 1;
        }
        return ArgError.FormatInvalid;
    }
};

fn savePbm(bytes: []const u8, file: *const std.fs.File, width: u16, height: u16) !void {
    const signaure = "P1\n";
    try file.writeAll(signaure);
    try file.writer().print("{d} {d}\n", .{ width, height });

    var line_width: u16 = 0;
    for (bytes) |byte, byte_idx| {
        if (line_width + 2 + 1 >= 70) {
            try file.writer().writeByte('\n');
            line_width = 0;
        }
        _ = try file.writer().write(&.{'0' + byte});
        line_width += 1;
    }
}

fn savePgm(bytes: []const u8, file: *const std.fs.File, width: u16, height: u16) !void {
    const signaure = "P2\n";
    try file.writeAll(signaure);
    try file.writer().print("{d} {d}\n255\n", .{ width, height });

    var line_width: u16 = 0;

    for (bytes) |byte, byte_idx| {
        if (line_width + 2 + 1 >= 70) {
            try file.writer().writeByte('\n');
            line_width = 0;
        }
        const pos_pre = try file.getPos();
        try file.writer().print("{d} ", .{byte});
        const pos_post = try file.getPos();
        line_width += @intCast(u16, pos_post - pos_pre);
    }
}

fn savePpm(bytes: []const u8, file: *const std.fs.File, width: u16, height: u16) !void {
    const signaure = "P3\n";
    try file.writeAll(signaure);
    try file.writer().print("{d} {d}\n255\n", .{ width, height });

    var line_width: u16 = 0;
    for (bytes) |byte, byte_idx| {
        if (line_width + 2 + 1 >= 70) {
            try file.writer().writeByte('\n');
            line_width = 0;
        }
        const pos_pre = try file.getPos();
        try file.writer().print("{d} ", .{byte});
        const pos_post = try file.getPos();
        line_width += @intCast(u16, pos_post - pos_pre);
    }
}

pub fn saveFile(file: *const std.fs.File, bytes: []const u8, format: ImageFormat, width: u16, height: u16) !void {
    return switch (format) {
        ImageFormat.Pbm => savePbm(bytes, file, width, height),
        ImageFormat.Pgm => savePgm(bytes, file, width, height),
        ImageFormat.Ppm => savePpm(bytes, file, width, height),
    };
}
