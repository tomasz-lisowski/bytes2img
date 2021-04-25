const std = @import("std");
const assert = std.debug.assert;
const image = @import("image.zig");

var alloctr: *std.mem.Allocator = undefined;

pub const ArgError = error{
    OpInvalid,
    NotEnoughArgs,
    BytesInvalid,
    FormatInvalid,
};

const Op = enum(u8) {
    Help = 0,
    HelpLong = 1,
    File = 2,
    FileLong = 3,
    Text = 4,
    TextLong = 5,

    fn parse(op_str_user: []const u8) ArgError!Op {
        const ops = [_][]const u8{ "-h", "--help", "-f", "--file", "-t", "--text" };
        var op_idx: u8 = 0;
        for (ops) |op_str| {
            if (std.mem.eql(u8, op_str, op_str_user)) {
                return @intToEnum(Op, op_idx);
            }
            op_idx += 1;
        }
        return ArgError.OpInvalid;
    }
};

fn usage() void {
    std.log.info(
        \\Usage: bytes2img <[-h | -f | -t] width height img_format byte_src>
        \\
        \\-h,--help: Displays a help message.
        \\-f,--file: Reads bytes from a file.
        \\-t,--text: Reads bytes from the string that has been passed in.
        \\
        \\Note: The output will be saved inside the current working directory as 'out.[img_format]'.
        \\Note: The 'img_format' is the extension name like 'pbm'.
        \\Note: The byte string is assumed to be a lowercase string of hex digits like '1badb002'. Placing any symbol that is not in the hex alphabet will lead to immediate exit.
    , .{});
}

fn fileReadAll(path: []const u8) ![]u8 {
    var path_absolute: []const u8 = undefined;
    if (std.fs.path.isAbsolute(path) == true) {
        path_absolute = path;
    } else {
        path_absolute = try std.fs.path.resolve(alloctr, &[_][]const u8{path});
    }
    std.log.info("Parsed path to absolute path: '{s}'", .{path_absolute});
    const file: std.fs.File = try std.fs.openFileAbsolute(path_absolute, std.fs.File.OpenFlags{ .read = true, .write = false });
    const buf: []u8 = try file.readToEndAllocOptions(alloctr, std.math.maxInt(u64), null, @alignOf(u32), null);
    std.log.info("Read {d} bytes from file", .{buf.len});
    return buf;
}

// Check if all characters in a buffer are a hex digits (0-9,a-f)
fn validateHexChars(buffer: []const u8) bool {
    for (buffer) |char| {
        switch (char) {
            '0', '1', '2', '3', '4', '5', '6', '7', '8', '9', 'a', 'b', 'c', 'd', 'e', 'f' => continue,
            else => return false,
        }
    }
    return true;
}

pub fn main() !void {
    errdefer usage();
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    alloctr = &arena.allocator;

    var argv = std.process.args();

    // Skip exe name
    assert(argv.skip() == true);

    // Read byte source type
    const src_op_str = try argv.next(alloctr) orelse return ArgError.NotEnoughArgs;
    const src_op = Op.parse(src_op_str) catch |err| {
        std.log.emerg("Failed to parse operation string, got: {s}", .{err});
        return err;
    };

    // Read width and height
    const width_str = try argv.next(alloctr) orelse return ArgError.NotEnoughArgs;
    const height_str = try argv.next(alloctr) orelse return ArgError.NotEnoughArgs;
    const width: u16 = try std.fmt.parseUnsigned(u16, width_str, 10);
    const height: u16 = try std.fmt.parseUnsigned(u16, height_str, 10);

    // Read image format
    const format_str = try argv.next(alloctr) orelse return ArgError.NotEnoughArgs;
    const format: image.ImageFormat = image.ImageFormat.parse(format_str) catch |err| {
        switch (err) {
            ArgError.FormatInvalid => std.log.emerg("The provided file format is not supported", .{}),
            else => unreachable,
        }
        return err;
    };
    var file_name: [16]u8 = undefined;
    _ = try std.fmt.bufPrint(&file_name, "out.{s}", .{format_str});
    // The output file is created and opened here
    const file_save = try std.fs.cwd().createFile(file_name[0..(4 + format_str.len)], std.fs.File.CreateFlags{});
    defer file_save.close();

    // Get a buffer hex digit characters
    var hex_digits: []u8 = undefined;
    switch (src_op) {
        Op.Help, Op.HelpLong => {
            usage();
            return;
        },
        Op.File, Op.FileLong => {
            const file_path = try (argv.next(alloctr) orelse {
                std.log.emerg("Expected third argument to be a path to file with bytes", .{});
                return error.InvalidArgs;
            });
            const hex_digits_raw: []u8 = try fileReadAll(file_path);
            if (validateHexChars(hex_digits_raw) == true) {
                hex_digits = hex_digits_raw;
            } else {
                return ArgError.BytesInvalid;
            }
        },
        Op.Text, Op.TextLong => {
            const hex_digits_raw = try (argv.next(alloctr) orelse {
                std.log.emerg("Expected third argument to be a string of bytes", .{});
                return error.InvalidArgs;
            });
            if (validateHexChars(hex_digits_raw) == true) {
                hex_digits = hex_digits_raw;
            } else {
                return ArgError.BytesInvalid;
            }
        },
    }

    // Combine 2 characters together into a pixel/color value
    var hex_digit_idx: u32 = 0;
    while (hex_digit_idx < (hex_digits.len / 2)) : (hex_digit_idx += 1) {
        var byte_a = hex_digits[(hex_digit_idx) * 2];
        if (byte_a >= '0' and byte_a <= '9') {
            byte_a = byte_a - '0';
        } else {
            byte_a = 10 + (byte_a - 'a');
        }
        var byte_b = hex_digits[(hex_digit_idx * 2) + 1];
        if (byte_b >= '0' and byte_b <= '9') {
            byte_b = byte_b - '0';
        } else {
            byte_b = 10 + (byte_b - 'a');
        }
        hex_digits[hex_digit_idx] = (byte_a * 16) + byte_b;
    }
    // This slice contains a byte per pixel/color channel
    const bytes = hex_digits[0..(hex_digits.len / 2)];

    try image.saveFile(&file_save, bytes, format, width, height);
}
