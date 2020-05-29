const std = @import("std");

pub fn main() !void {
    // 15-bit address space for memory.
    var raw: [65536]u8 = undefined;
    var memory: [32768]u16 = undefined;

    const stdout = std.io.getStdOut().outStream();
    const file = try std.fs.cwd().openFile("challenge.bin", .{});
    defer file.close();
    const file_size = try file.getEndPos();
    _ = try file.read(raw[0..file_size]);

    var i: usize = 0;

    while (i <= file_size) : (i += 2) {
        memory[i / 2] = (@intCast(u16, raw[i + 1]) << 8) | (raw[i] & 0xff);
    }

    i = 0;

    while (true) {
        switch (memory[i]) {
            0 => break,
            19 => blk: {
                _ = try std.fmt.formatAsciiChar(@intCast(u8, memory[i + 1]), .{}, stdout);
                i += 2;
            },
            21 => i += 1,
            else => blk: {
                try stdout.print("unhandled opcode: {}\n", .{memory[i]});
                break;
            },
        }
    }
}
