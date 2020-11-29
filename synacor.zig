const std = @import("std");

// First command-line argument: memory dump (defaults to `challenge.bin`)
// Second command-line argument: command
//   - If `history`, writes a history file
//   - If `explain`, writes commands to stderr
//
// Memory dump is written when stdin ends (C-d or redirect stdin from history
// file)

const Stack = struct {
    head: usize = 0,
    values: [65536]u16 = undefined,

    pub fn push(self: *Stack, value: u16) void {
        self.head += 1;
        self.values[self.head] = value;
    }

    pub fn peek(self: Stack) u16 {
        return self.values[self.head];
    }

    pub fn pop(self: *Stack) u16 {
        const value = self.peek();

        self.values[self.head] = undefined;
        self.head -= 1;

        return value;
    }
};

fn arg(memory: anytype, registers: anytype, index: usize) u16 {
    const value = memory[index];

    if (value < 32768) {
        return value;
    } else {
        return registers[value - 32768];
    }
}

fn explainArg(memory: anytype, registers: anytype, index: usize) []u8 {
    const value = memory[index];

    if (value < 32768) {
        return std.fmt.allocPrint(std.heap.page_allocator, "{}", .{value}) catch unreachable;
    } else {
        return std.fmt.allocPrint(std.heap.page_allocator, "R{}", .{value - 32768}) catch unreachable;
    }
}

fn printExplain(cmd: anytype, explain: bool, stream: anytype, memory: anytype, registers: anytype, i: usize, args: usize) !void {
    if (!explain) {
        return;
    }

    if (args == 0) {
        try stream.print("{}\n", .{cmd});
    } else if (args == 1) {
        try stream.print("{} {}\n", .{ cmd, explainArg(memory, registers, i + 1) });
    } else if (args == 2) {
        try stream.print("{} {} {}\n", .{ cmd, explainArg(memory, registers, i + 1), explainArg(memory, registers, i + 2) });
    } else if (args == 3) {
        try stream.print("{} {} {} {}\n", .{ cmd, explainArg(memory, registers, i + 1), explainArg(memory, registers, i + 2), explainArg(memory, registers, i + 3) });
    }
}

fn mod(value: u16) u16 {
    return value % 32768;
}

fn argv(i: u8) []u8 {
    var args = std.process.args();
    var j: u8 = 0;

    while (j <= i) : (j += 1) {
        _ = args.skip();
    }

    const flag = (args.next(std.heap.page_allocator) orelse "") catch "";

    return flag;
}

fn historyFile(flag: []u8) ?std.fs.File {
    if (std.mem.eql(u8, flag, "history")) {
        var history_filename: [21]u8 = undefined;
        _ = std.fmt.bufPrint(history_filename[0..], "{}.{}", .{ "history", std.time.milliTimestamp() }) catch unreachable;

        return std.fs.cwd().createFile(&history_filename, .{}) catch unreachable;
    } else {
        return undefined;
    }
}

fn sourceFile(flag: []u8) !std.fs.File {
    if (std.mem.eql(u8, flag, "")) {
        return std.fs.cwd().openFile("challenge.bin", .{});
    } else {
        return std.fs.cwd().openFile(flag, .{});
    }
}

fn dump(memory: [32768]u16, registers: [8]u16, stack: Stack, pointer: usize) !void {
    var memory_filename: [20]u8 = undefined;
    _ = try std.fmt.bufPrint(memory_filename[0..], "{}.{}", .{ "memory", std.time.milliTimestamp() });

    const file = try std.fs.cwd().createFile(&memory_filename, .{});
    defer file.close();

    var bytes: [2]u8 = undefined;
    var pointer_bytes: [8]u8 = undefined;

    for (memory) |item| {
        std.mem.writeIntSliceLittle(u16, bytes[0..], item);
        _ = try file.write(&bytes);
    }

    for (registers) |item| {
        std.mem.writeIntSliceLittle(u16, bytes[0..], item);
        _ = try file.write(&bytes);
    }

    for (stack.values) |item| {
        std.mem.writeIntSliceLittle(u16, bytes[0..], item);
        _ = try file.write(&bytes);
    }

    std.mem.writeIntSliceLittle(usize, pointer_bytes[0..], stack.head);
    _ = try file.write(&pointer_bytes);

    std.mem.writeIntSliceLittle(usize, pointer_bytes[0..], pointer);
    _ = try file.write(&pointer_bytes);
}

fn load(flag: []u8, memory: *[32768]u16, registers: *[8]u16, stack: *Stack) !usize {
    // Memory + registers + stack + stack head + pointer
    var raw: [196640]u8 = undefined;

    const source = try sourceFile(flag);
    defer source.close();

    const source_size = try source.getEndPos();
    _ = try source.read(raw[0..source_size]);

    var i: usize = 0;

    while (i < std.math.min(source_size, 65536)) : (i += 2) {
        memory[i / 2] = std.mem.readIntSliceLittle(u16, raw[i .. i + 2]);
    }

    if (source_size > 65536) {
        // Dump
        while (i < std.math.min(source_size, 65536 + 16)) : (i += 2) {
            registers[(i - 65536) / 2] = std.mem.readIntSliceLittle(u16, raw[i .. i + 2]);
        }

        while (i < std.math.min(source_size, (65536 * 3) + 16)) : (i += 2) {
            stack.values[(i - 65536 - 16) / 2] = std.mem.readIntSliceLittle(u16, raw[i .. i + 2]);
        }

        stack.head = std.mem.readIntSliceLittle(usize, raw[i .. i + 8]);
        return std.mem.readIntSliceLittle(usize, raw[i + 8 .. i + 16]);
    } else {
        // Initial challenge
        return 0;
    }
}

pub fn main() !void {
    // 15-bit address space for memory.
    var memory: [32768]u16 = undefined;
    var registers = [_]u16{0} ** 8;
    var stack = Stack{};
    var i = try load(argv(0), &memory, &registers, &stack);

    const stdout = std.io.getStdOut().outStream();
    const stderr = std.io.getStdErr().outStream();
    const stdin = std.io.getStdIn().inStream();
    const cmd = argv(1);
    const explain = std.mem.eql(u8, cmd, "explain");

    const history = historyFile(cmd);
    defer if (history) |h| {
        h.close();
    };

    var opcode: u16 = 0;
    var a_: u16 = 0;
    var a: u16 = 0;
    var b: u16 = 0;
    var c: u16 = 0;

    while (true) {
        opcode = memory[i];
        a = arg(memory, registers, i + 1);
        b = arg(memory, registers, i + 2);
        c = arg(memory, registers, i + 3);

        if (memory[i + 1] >= 32768) {
            a_ = memory[i + 1] - 32768;
        }

        switch (opcode) {
            // halt
            0 => {
                try printExplain("halt", explain, stderr, memory, registers, i, 0);

                break;
            },
            // set
            1 => {
                try printExplain("set", explain, stderr, memory, registers, i, 2);

                registers[a_] = b;
                i += 3;
            },
            // push
            2 => {
                try printExplain("push", explain, stderr, memory, registers, i, 1);

                stack.push(a);
                i += 2;
            },
            // pop
            3 => {
                try printExplain("pop", explain, stderr, memory, registers, i, 1);

                registers[a_] = stack.pop();
                i += 2;
            },
            // eq
            4 => {
                try printExplain("eq", explain, stderr, memory, registers, i, 3);

                registers[a_] = @boolToInt(b == c);
                i += 4;
            },
            // gt
            5 => {
                try printExplain("gt", explain, stderr, memory, registers, i, 3);

                registers[a_] = @boolToInt(b > c);
                i += 4;
            },
            // jmp
            6 => {
                try printExplain("jmp", explain, stderr, memory, registers, i, 1);

                i = a;
            },
            // jt
            7 => {
                try printExplain("jt", explain, stderr, memory, registers, i, 2);

                if (a != 0) {
                    i = b;
                } else {
                    i += 3;
                }
            },
            // jf
            8 => {
                try printExplain("jf", explain, stderr, memory, registers, i, 2);

                if (a == 0) {
                    i = b;
                } else {
                    i += 3;
                }
            },
            // add
            9 => {
                try printExplain("add", explain, stderr, memory, registers, i, 3);

                registers[a_] = mod(b + c);
                i += 4;
            },
            // mult
            10 => {
                try printExplain("mult", explain, stderr, memory, registers, i, 3);

                registers[a_] = @intCast(u16, (@intCast(u32, b) * @intCast(u32, c)) % 32768);
                i += 4;
            },
            // mod
            11 => {
                try printExplain("mod", explain, stderr, memory, registers, i, 3);

                registers[a_] = mod(b % c);
                i += 4;
            },
            // and
            12 => {
                try printExplain("and", explain, stderr, memory, registers, i, 3);

                registers[a_] = b & c;
                i += 4;
            },
            // or
            13 => {
                try printExplain("or", explain, stderr, memory, registers, i, 3);

                registers[a_] = b | c;
                i += 4;
            },
            // not
            14 => {
                try printExplain("not", explain, stderr, memory, registers, i, 2);

                registers[a_] = mod(~b);
                i += 3;
            },
            // rmem
            15 => {
                try printExplain("rmem", explain, stderr, memory, registers, i, 2);

                registers[a_] = memory[b];
                i += 3;
            },
            // wmem
            16 => {
                try printExplain("wmem", explain, stderr, memory, registers, i, 2);

                memory[a] = b;
                i += 3;
            },
            // call
            17 => {
                try printExplain("call", explain, stderr, memory, registers, i, 1);

                stack.push(@intCast(u16, i + 2));
                i = a;
            },
            // ret
            18 => {
                try printExplain("ret", explain, stderr, memory, registers, i, 0);

                i = stack.pop();
            },
            // out
            19 => {
                try printExplain("out", explain, stderr, memory, registers, i, 1);

                _ = try std.fmt.formatAsciiChar(@intCast(u8, a), .{}, stdout);
                i += 2;
            },
            // in
            20 => {
                try printExplain("in", explain, stderr, memory, registers, i, 1);

                if (stdin.readByte()) |input| {
                    registers[a_] = input;

                    if (history) |h| {
                        _ = try h.write(&[1]u8{input});
                    }
                } else |err| {
                    try dump(memory, registers, stack, i);
                    return err;
                }

                i += 2;
            },
            // noop
            21 => {
                try printExplain("noop", explain, stderr, memory, registers, i, 0);

                i += 1;
            },
            else => {
                try stdout.print("unhandled opcode: {}\n", .{opcode});
                break;
            },
        }
    }
}
